import 'package:flutter/foundation.dart';

import '../globals.dart';
import '../utils/v2_grad_adresa_validator.dart';
import '../utils/v2_vozac_cache.dart';
import 'realtime/v2_master_realtime_manager.dart';
import 'v2_vozac_raspored_service.dart';

/// Model za jedan red iz vozac_putnik tabele.
///
/// Čuva per-V2Putnik raspored: koji vozač vozi određenog putnika
/// za određeni dan/grad/vreme.
///
/// Jedan V2Putnik može imati najviše jednu aktivnu individualnu dodjelu (UNIQUE putnik_id).
class V2VozacPutnikEntry {
  final String? id; // uuid PK, null prije inserata
  final String putnikId; // FK → registrovani_putnici.id
  final String vozacId; // FK → vozaci.id
  final String dan; // 'pon','uto','sre','cet','pet'
  final String grad; // 'BC' ili 'VS'
  final String vreme; // '07:00', '08:00', ...

  const V2VozacPutnikEntry({
    this.id,
    required this.putnikId,
    required this.vozacId,
    required this.dan,
    required this.grad,
    required this.vreme,
  });

  factory V2VozacPutnikEntry.fromMap(Map<String, dynamic> map) {
    final vremeRaw = map['vreme']?.toString() ?? '';
    final vreme = V2GradAdresaValidator.normalizeTime(vremeRaw);
    return V2VozacPutnikEntry(
      id: map['id']?.toString(),
      putnikId: map['putnik_id']?.toString() ?? '',
      vozacId: map['vozac_id']?.toString() ?? '',
      dan: map['dan']?.toString() ?? '',
      grad: map['grad']?.toString() ?? '',
      vreme: vreme,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'putnik_id': putnikId,
        'vozac_id': vozacId,
        'dan': dan,
        'grad': grad,
        'vreme': vreme,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is V2VozacPutnikEntry &&
          runtimeType == other.runtimeType &&
          putnikId == other.putnikId &&
          vozacId == other.vozacId &&
          dan == other.dan &&
          grad == other.grad &&
          vreme == other.vreme;

  @override
  int get hashCode => Object.hash(putnikId, vozacId, dan, grad, vreme);
}

/// Servis za upravljanje per-V2Putnik individualnom dodjelom vozača.
///
/// Jedan V2Putnik može imati više dodjela — jednu per (dan+grad+vreme).
///
/// Arhitektura:
/// vozac_putnik   — per-V2Putnik individualna dodjela (ovaj servis)
/// vozac_raspored — per-termin raspored (VozacRasporedService)
class V2VozacPutnikService {
  V2VozacPutnikService._();

  static V2MasterRealtimeManager get _rm => V2MasterRealtimeManager.instance;

  /// Učitaj sve individualne dodjele iz rm cache-a (sync)
  static List<V2VozacPutnikEntry> loadAll() {
    return _rm.vozacPutnikCache.values.map((row) => V2VozacPutnikEntry.fromMap(row)).toList();
  }

  /// Postavi (ili zamijeni) individualnu dodjelu za putnika.
  ///
  /// Ako [vozacIme] je prazan string → briše dodjelu (vidi [delete]).
  /// Vraća `true` ako uspješno.
  static Future<bool> set({
    required String putnikId,
    required String vozacIme,
    required String dan,
    required String grad,
    required String vreme,
  }) async {
    // Prazan vozacIme = brisi samo konkretni termin, ne sve dodjele za putnika
    if (vozacIme.isEmpty) return delete(putnikId: putnikId, dan: dan, grad: grad, vreme: vreme);

    final vozacId = V2VozacCache.getUuidByIme(vozacIme);
    if (vozacId == null) {
      return false; // vozač ne postoji u cache-u
    }

    try {
      final row = await supabase
          .from('v2_vozac_putnik')
          .upsert(
            {
              'putnik_id': putnikId,
              'vozac_id': vozacId,
              'dan': dan,
              'grad': grad,
              'vreme': vreme,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            onConflict: 'putnik_id,dan,grad,vreme', // UNIQUE (putnik_id, dan, grad, vreme)
          )
          .select()
          .single();
      _rm.v2UpsertToCache('v2_vozac_putnik', row);
      return true;
    } catch (e) {
      debugPrint('[V2VozacPutnikService] set greška: $e');
      return false;
    }
  }

  /// Briše individualnu dodjelu za putnika za konkretni dan+grad+vreme.
  static Future<bool> delete({required String putnikId, String? dan, String? grad, String? vreme}) async {
    try {
      var q = supabase.from('v2_vozac_putnik').delete().eq('putnik_id', putnikId);
      if (dan != null) q = q.eq('dan', dan);
      if (grad != null) q = q.eq('grad', grad);
      if (vreme != null) q = q.eq('vreme', vreme);
      await q;
      // Ukloni iz cache-a sve redove koji odgovaraju filteru
      final toRemove = _rm.vozacPutnikCache.entries
          .where((e) =>
              e.value['putnik_id']?.toString() == putnikId &&
              (dan == null || e.value['dan'] == dan) &&
              (grad == null || e.value['grad'] == grad) &&
              (vreme == null || e.value['vreme'] == vreme))
          .map((e) => e.key)
          .toList();
      for (final id in toRemove) {
        _rm.v2RemoveFromCache('v2_vozac_putnik', id);
      }
      return true;
    } catch (e) {
      debugPrint('[V2VozacPutnikService] delete greška: $e');
      return false;
    }
  }

  static Future<void> deleteForVozac({required String vozacId}) async {
    try {
      await supabase.from('v2_vozac_putnik').delete().eq('vozac_id', vozacId);
      final toRemove = _rm.vozacPutnikCache.entries
          .where((e) => e.value['vozac_id']?.toString() == vozacId)
          .map((e) => e.key)
          .toList();
      for (final id in toRemove) {
        _rm.v2RemoveFromCache('v2_vozac_putnik', id);
      }
    } catch (e) {
      debugPrint('[V2VozacPutnikService] deleteForVozac greška: $e');
    }
  }

  /// Kombinirani filter za VOZAČ ekran (strict mode — samo eksplicitno raspoređeni).
  ///
  /// Prioritet:
  /// 1. Per-V2Putnik individualna dodjela (vozac_putnik):
  ///    - dodeljen MENI   → prikaži
  ///    - dodeljen DRUGOM → sakrij
  /// 2. Nema individualne dodjele → provjeri termin-raspored (vozac_raspored):
  ///    - termin dodeljen MENI   → prikaži sve putnike tog termina
  ///    - termin dodeljen DRUGOM → sakrij
  ///    - termin NIJE raspoređen → sakrij (vozač vidi samo SVOJE termine)
  ///
  /// [vozacId] = UUID vozača
  static List<T> filterKombinovan<T>({
    required List<T> sviPutnici,
    required String vozacId,
    required String targetDan,
    required List<V2VozacPutnikEntry> individualneDodjele,
    required List<V2VozacRasporedEntry> raspored,
    required String Function(T) getId,
    required String Function(T) getGrad,
    required String Function(T) getPolazak,
  }) {
    return sviPutnici.where((p) {
      final id = getId(p);
      final grad = getGrad(p);
      // Normalizuj vreme za konzistentno poređenje ('07:00:00' → '07:00')
      final vreme = V2GradAdresaValidator.normalizeTime(getPolazak(p));

      // 1. Provjeri per-V2Putnik individualnu dodjelu
      // e.vreme je vec normalizovano u fromMap; grad je uvek 'BC'/'VS' iz normalizeGrad
      final putnikDodjele = individualneDodjele
          .where((e) => e.putnikId == id && e.dan == targetDan && e.grad == grad && e.vreme == vreme)
          .toList();
      if (putnikDodjele.isNotEmpty) {
        // Individualna dodjela postoji za ovaj dan+grad+vreme — prikaži samo ako je dodeljen MENI
        return putnikDodjele.any((e) => e.vozacId == vozacId);
      }

      // 2. Nema individualne dodjele → provjeri termin-raspored
      // r.vreme iz fromMap nije normalizovano — pozivamo normalizeTime
      final terminEntries = raspored
          .where((r) => r.dan == targetDan && r.grad == grad && V2GradAdresaValidator.normalizeTime(r.vreme) == vreme)
          .toList();
      // Nema rasporeda za termin → vozač ne vidi ove putnike (termin nije dodeljen njemu)
      if (terminEntries.isEmpty) return false;
      return terminEntries.any((r) => r.vozacId == vozacId);
    }).toList();
  }
}
