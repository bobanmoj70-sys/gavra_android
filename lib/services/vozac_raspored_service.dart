import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';

/// Model za jedan red iz vozac_raspored tabele
class VozacRasporedEntry {
  final String dan;
  final String grad;
  final String vreme;
  final String vozac;
  final String? putnikId; // null = ceo termin, uuid = pojedinacni putnik

  const VozacRasporedEntry({
    required this.dan,
    required this.grad,
    required this.vreme,
    required this.vozac,
    this.putnikId,
  });

  factory VozacRasporedEntry.fromMap(Map<String, dynamic> map) {
    return VozacRasporedEntry(
      dan: map['dan'] as String,
      grad: map['grad'] as String,
      vreme: map['vreme'] as String,
      vozac: map['vozac'] as String,
      putnikId: map['putnik_id'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'dan': dan,
        'grad': grad,
        'vreme': vreme,
        'vozac': vozac,
        'putnik_id': putnikId,
      };
}

/// Servis za učitavanje i upravljanje vozac_raspored tabelom
class VozacRasporedService {
  static final VozacRasporedService _instance = VozacRasporedService._internal();
  factory VozacRasporedService() => _instance;
  VozacRasporedService._internal();

  SupabaseClient get _supabase => supabase;

  /// Učitaj sve unose iz tabele
  Future<List<VozacRasporedEntry>> loadAll() async {
    try {
      final response = await _supabase.from('vozac_raspored').select();
      return (response as List).map((row) => VozacRasporedEntry.fromMap(row as Map<String, dynamic>)).toList();
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return [];
    }
  }

  /// Dodaj ili zameni unos (upsert po svim poljima)
  Future<void> upsert(VozacRasporedEntry entry) async {
    await _supabase.from('vozac_raspored').upsert(entry.toMap());
  }

  /// Obriši unos za termin (dan+grad+vreme+vozac, putnik_id=null)
  Future<void> deleteTermin({
    required String dan,
    required String grad,
    required String vreme,
    required String vozac,
  }) async {
    await _supabase
        .from('vozac_raspored')
        .delete()
        .eq('dan', dan)
        .eq('grad', grad)
        .eq('vreme', vreme)
        .eq('vozac', vozac)
        .isFilter('putnik_id', null);
  }

  /// Obriši override za pojedinačnog putnika
  Future<void> deletePutnikOverride({
    required String putnikId,
    required String vozac,
  }) async {
    await _supabase.from('vozac_raspored').delete().eq('putnik_id', putnikId).eq('vozac', vozac);
  }

  /// Filter logika: koji putnici pripadaju vozaču?
  ///
  /// Prioritet:
  /// 1. Per-putnik override (putnik_id != null) — direktno pridruživanje
  /// 2. Per-termin (putnik_id == null, dan+grad+vreme) — ceo termin vozaču
  /// 3. Nema unosa za termin → svi vozači vide sve putnike (staro ponašanje)
  static List<T> filterPutniciZaVozaca<T>({
    required List<T> sviPutnici,
    required String vozac,
    required String targetDan, // 'pon', 'uto', ...
    required List<VozacRasporedEntry> raspored,
    required String Function(T) getId,
    required String Function(T) getGrad,
    required String Function(T) getPolazak,
  }) {
    if (raspored.isEmpty) return sviPutnici; // nema rasporeda = sve vidljivo

    return sviPutnici.where((p) {
      final id = getId(p);
      final grad = getGrad(p);
      final vreme = getPolazak(p);

      // 1. Per-putnik override: da li je ovaj putnik EKSPLICITNO dodeljen DRUGOM vozaču?
      final assignedToOther = raspored.any((r) => r.putnikId != null && r.putnikId == id && r.vozac != vozac);
      if (assignedToOther) return false;

      // 2. Per-putnik override: da li je ovaj putnik EKSPLICITNO dodeljen MENI?
      final assignedToMe = raspored.any((r) => r.putnikId != null && r.putnikId == id && r.vozac == vozac);
      if (assignedToMe) return true;

      // 3. Per-termin: koji vozači su dodeljeni ovom terminu?
      final terminVozaci = raspored
          .where((r) => r.putnikId == null && r.dan == targetDan && r.grad == grad && r.vreme == vreme)
          .map((r) => r.vozac)
          .toSet();

      // Ako nema unosa za termin → sve vidljivo
      if (terminVozaci.isEmpty) return true;

      // Inače: prikaži samo ako je ovaj vozač u terminu
      return terminVozaci.contains(vozac);
    }).toList();
  }
}
