import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../utils/v2_grad_adresa_validator.dart';
import 'realtime/v2_master_realtime_manager.dart';

/// Model za jedan red iz vozac_raspored tabele.
///
/// Čuva per-termin raspored: koji vozač vozi cijeli termin (dan+grad+vreme).
/// Per-V2Putnik individualna dodjela čuva se u vozac_putnik tabeli (VozacPutnikService).
class VozacRasporedEntry {
  final String dan;
  final String grad;
  final String vreme;

  /// UUID vozača iz tabele vozaci.id — primarni identifikator
  final String vozacId;

  const VozacRasporedEntry({
    required this.dan,
    required this.grad,
    required this.vreme,
    required this.vozacId,
  });

  factory VozacRasporedEntry.fromMap(Map<String, dynamic> map) {
    return VozacRasporedEntry(
      dan: map['dan']?.toString() ?? '',
      grad: map['grad']?.toString() ?? '',
      vreme: map['vreme']?.toString() ?? '',
      vozacId: map['vozac_id']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'dan': dan,
        'grad': grad,
        'vreme': vreme,
        'vozac_id': vozacId,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VozacRasporedEntry &&
          runtimeType == other.runtimeType &&
          dan == other.dan &&
          grad == other.grad &&
          vreme == other.vreme &&
          vozacId == other.vozacId;

  @override
  int get hashCode => Object.hash(dan, grad, vreme, vozacId);
}

/// Servis za učitavanje i upravljanje vozac_raspored tabelom
class V2VozacRasporedService {
  static final V2VozacRasporedService _instance = V2VozacRasporedService._internal();
  factory V2VozacRasporedService() => _instance;
  V2VozacRasporedService._internal();

  SupabaseClient get _supabase => supabase;
  V2MasterRealtimeManager get _rm => V2MasterRealtimeManager.instance;

  /// Učitaj sve unose iz rm cache-a (sync)
  List<VozacRasporedEntry> loadAll() {
    return _rm.rasporedCache.values.map((row) => VozacRasporedEntry.fromMap(row)).toList();
  }

  /// Dodaj ili zameni unos (upsert po dan+grad+vreme)
  Future<void> upsert(VozacRasporedEntry entry) async {
    try {
      await _supabase.from('v2_vozac_raspored').upsert(entry.toMap(), onConflict: 'dan,grad,vreme');
    } catch (e) {
      debugPrint('[V2VozacRasporedService] Greška u upsert(): $e');
    }
  }

  /// Obriši unos za termin (dan+grad+vreme+vozac_id)
  Future<void> deleteTermin({
    required String dan,
    required String grad,
    required String vreme,
    required String vozacId,
  }) async {
    try {
      await _supabase
          .from('v2_vozac_raspored')
          .delete()
          .eq('dan', dan)
          .eq('grad', grad)
          .eq('vreme', vreme)
          .eq('vozac_id', vozacId);
    } catch (e) {
      debugPrint('[V2VozacRasporedService] Greška u deleteTermin(): $e');
    }
  }

  /// Filter logika: koji putnici pripadaju vozaču?
  ///
  /// Filtrira putnike po per-termin rasporedu.
  ///
  /// Logika:
  /// - Ako nema unosa za termin → V2Putnik je vidljiv svima
  /// - Ako postoji unos → prikaži samo vozaču koji je dodeljen tom terminu
  ///
  /// [vozacId] = UUID vozača
  static List<T> filterPutniciZaVozaca<T>({
    required List<T> sviPutnici,
    required String vozacId,
    required String targetDan, // 'pon', 'uto', ...
    required List<VozacRasporedEntry> raspored,
    required String Function(T) getId,
    required String Function(T) getGrad,
    required String Function(T) getPolazak,
  }) {
    if (raspored.isEmpty) return sviPutnici;

    bool jeVozacov(VozacRasporedEntry r) => r.vozacId == vozacId;

    return sviPutnici.where((p) {
      final grad = getGrad(p).toUpperCase();
      final vreme = GradAdresaValidator.normalizeTime(getPolazak(p));

      final terminEntries = raspored
          .where((r) =>
              r.dan == targetDan && r.grad.toUpperCase() == grad && GradAdresaValidator.normalizeTime(r.vreme) == vreme)
          .toList();

      if (terminEntries.isEmpty) return true; // nema unosa → vidljivo svima

      return terminEntries.any(jeVozacov);
    }).toList();
  }
}
