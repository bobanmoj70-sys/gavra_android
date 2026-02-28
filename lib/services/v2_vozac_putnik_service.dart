import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../utils/v2_grad_adresa_validator.dart';
import '../utils/v2_vozac_cache.dart';
import 'v2_vozac_raspored_service.dart';

/// Model za jedan red iz vozac_putnik tabele.
///
/// Čuva per-V2Putnik raspored: koji vozač vozi određenog putnika
/// za određeni dan/grad/vreme.
///
/// Jedan V2Putnik može imati najviše jednu aktivnu individualnu dodjelu (UNIQUE putnik_id).
class VozacPutnikEntry {
  final String? id; // uuid PK, null prije inserata
  final String putnikId; // FK → registrovani_putnici.id
  final String vozacId; // FK → vozaci.id
  final String dan; // 'pon','uto','sre','cet','pet'
  final String grad; // 'BC' ili 'VS'
  final String vreme; // '07:00', '08:00', ...

  const VozacPutnikEntry({
    this.id,
    required this.putnikId,
    required this.vozacId,
    required this.dan,
    required this.grad,
    required this.vreme,
  });

  factory VozacPutnikEntry.fromMap(Map<String, dynamic> map) {
    return VozacPutnikEntry(
      id: map['id'] as String?,
      putnikId: map['putnik_id'] as String,
      vozacId: map['vozac_id'] as String,
      dan: map['dan'] as String,
      grad: map['grad'] as String,
      vreme: map['vreme'] as String,
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
}

/// Servis za upravljanje per-V2Putnik individualnom dodjelom vozača.
///
/// Jedan V2Putnik → jedna individualna dodjela vozača (UNIQUE putnik_id u tabeli).
///
/// Arhitektura:
///   vozac_putnik   — per-V2Putnik individualna dodjela (ovaj servis)
///   vozac_raspored — per-termin raspored (VozacRasporedService)
class V2VozacPutnikService {
  static final V2VozacPutnikService _instance = V2VozacPutnikService._internal();
  factory V2VozacPutnikService() => _instance;
  V2VozacPutnikService._internal();

  SupabaseClient get _supabase => supabase;

  /// Učitaj sve individualne dodjele
  Future<List<VozacPutnikEntry>> loadAll() async {
    try {
      final response = await _supabase.from('v2_vozac_putnik').select();
      return (response as List).map((row) => VozacPutnikEntry.fromMap(row as Map<String, dynamic>)).toList();
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return [];
    }
  }

  /// Postavi (ili zamijeni) individualnu dodjelu za putnika.
  ///
  /// Ako [vozacIme] je prazan string → briše dodjelu (vidi [delete]).
  /// Vraća `true` ako uspješno.
  Future<bool> set({
    required String putnikId,
    required String vozacIme,
    required String dan,
    required String grad,
    required String vreme,
  }) async {
    if (vozacIme.isEmpty) return delete(putnikId: putnikId);

    final vozacId = VozacCache.getUuidByIme(vozacIme);
    if (vozacId == null) {
      return false; // vozač ne postoji u cache-u
    }

    try {
      await _supabase.from('v2_vozac_putnik').upsert(
        {
          'putnik_id': putnikId,
          'vozac_id': vozacId,
          'dan': dan,
          'grad': grad,
          'vreme': vreme,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'putnik_id', // UNIQUE constraint
      );
      return true;
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return false;
    }
  }

  /// Briše individualnu dodjelu za putnika (V2Putnik se vraća na termin-level vozača).
  Future<bool> delete({required String putnikId}) async {
    try {
      await _supabase.from('v2_vozac_putnik').delete().eq('putnik_id', putnikId);
      return true;
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return false;
    }
  }

  /// Briše sve individualne dodjele za datog vozača.
  Future<void> deleteForVozac({required String vozacId}) async {
    await _supabase.from('v2_vozac_putnik').delete().eq('vozac_id', vozacId);
  }

  /// Kombinirani filter: per-V2Putnik individualna dodjela + per-termin raspored.
  ///
  /// Tačan prioritet:
  ///   1. Per-V2Putnik individualna dodjela postoji:
  ///      - dodeljen MENI   → prikaži (ignoriši termin-raspored)
  ///      - dodeljen DRUGOM → sakrij  (ignoriši termin-raspored)
  ///   2. Nema individualne dodjele → provjeri termin-raspored:
  ///      - nema unosa za termin → vidljivo svima ✅
  ///      - postoji unos → prikaži samo vozaču koji je dodeljen terminu
  ///
  /// Filtrira putnike za datog vozača na osnovu termin rasporeda (vozac_raspored).
  /// V2Putnik je vidljiv vozaču samo ako postoji unos u rasporedu koji ga dodjeljuje tom vozaču.
  ///
  /// [vozacId] = UUID vozača
  static List<T> filterKombinovan<T>({
    required List<T> sviPutnici,
    required String vozacId,
    required String targetDan,
    required List<VozacPutnikEntry> individualneDodjele,
    required List<VozacRasporedEntry> raspored,
    required String Function(T) getId,
    required String Function(T) getGrad,
    required String Function(T) getPolazak,
  }) {
    // Helper: da li je termin-unos za ovog vozača?
    bool jeTerminVozacov(VozacRasporedEntry r) {
      return r.vozacId == vozacId;
    }

    // Helper: da li je individualna dodjela za ovog vozača?
    bool jeDodjelajeVozacova(VozacPutnikEntry e) {
      return e.vozacId == vozacId;
    }

    return sviPutnici.where((p) {
      final id = getId(p);
      final grad = getGrad(p);
      // Normalizuj vreme za konzistentno poređenje ('07:00:00' → '07:00')
      final vreme = GradAdresaValidator.normalizeTime(getPolazak(p));

      // 1. Provjeri per-V2Putnik individualnu dodjelu
      final putnikDodjele = individualneDodjele
          .where((e) =>
              e.putnikId == id &&
              e.dan == targetDan &&
              e.grad.toUpperCase() == grad.toUpperCase() &&
              GradAdresaValidator.normalizeTime(e.vreme) == vreme)
          .toList();
      if (putnikDodjele.isNotEmpty) {
        // Individualna dodjela postoji za ovaj dan+grad+vreme — prikaži samo ako je dodeljen MENI
        return putnikDodjele.any(jeDodjelajeVozacova);
      }

      // 2. Nema individualne dodjele → provjeri termin-raspored
      final terminEntries = raspored
          .where((r) =>
              r.dan == targetDan &&
              r.grad.toUpperCase() == grad.toUpperCase() &&
              GradAdresaValidator.normalizeTime(r.vreme) == vreme)
          .toList();
      if (terminEntries.isEmpty) return false; // nema raspodele → V2Putnik nije vidljiv
      return terminEntries.any(jeTerminVozacov);
    }).toList();
  }
}
