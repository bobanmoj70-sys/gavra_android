import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';

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
      dan: map['dan'] as String,
      grad: map['grad'] as String,
      vreme: map['vreme'] as String,
      vozacId: map['vozac_id'] as String,
    );
  }

  Map<String, dynamic> toMap() => {
        'dan': dan,
        'grad': grad,
        'vreme': vreme,
        'vozac_id': vozacId,
      };
}

/// Servis za učitavanje i upravljanje vozac_raspored tabelom
class V2VozacRasporedService {
  static final V2VozacRasporedService _instance = V2VozacRasporedService._internal();
  factory V2VozacRasporedService() => _instance;
  V2VozacRasporedService._internal();

  SupabaseClient get _supabase => supabase;

  /// Učitaj sve unose iz tabele
  Future<List<VozacRasporedEntry>> loadAll() async {
    try {
      final response = await _supabase.from('v2_vozac_raspored').select();
      return (response as List).map((row) => VozacRasporedEntry.fromMap(row as Map<String, dynamic>)).toList();
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return [];
    }
  }

  /// Dodaj ili zameni unos (upsert po dan+grad+vreme+vozac_id)
  Future<void> upsert(VozacRasporedEntry entry) async {
    await _supabase.from('v2_vozac_raspored').upsert(entry.toMap(), onConflict: 'dan,grad,vreme,vozac_id');
  }

  /// Obriši unos za termin (dan+grad+vreme+vozac_id)
  Future<void> deleteTermin({
    required String dan,
    required String grad,
    required String vreme,
    required String vozacId,
  }) async {
    await _supabase
        .from('v2_vozac_raspored')
        .delete()
        .eq('dan', dan)
        .eq('grad', grad)
        .eq('vreme', vreme)
        .eq('vozac_id', vozacId);
  }

  /// Filter logika: koji putnici pripadaju vozaču?
  ///
  /// Filtrira putnike po per-termin rasporedu.
  ///
  /// Logika:
  ///   - Ako nema unosa za termin → V2Putnik je vidljiv svima
  ///   - Ako postoji unos → prikaži samo vozaču koji je dodeljen tom terminu
  ///
  /// [vozacId] = UUID (preferiran), [vozac] = ime (fallback)
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

    // Helper: da li je unos za ovog vozača? Poredi po UUID
    bool jeVozacov(VozacRasporedEntry r) {
      return r.vozacId == vozacId;
    }

    return sviPutnici.where((p) {
      final grad = getGrad(p);
      final vreme = getPolazak(p);

      // Koji vozači su dodeljeni ovom terminu?
      final terminEntries = raspored.where((r) => r.dan == targetDan && r.grad == grad && r.vreme == vreme).toList();

      if (terminEntries.isEmpty) return true; // nema unosa → vidljivo svima

      return terminEntries.any(jeVozacov);
    }).toList();
  }
}
