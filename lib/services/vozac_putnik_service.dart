import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../utils/vozac_cache.dart';
import 'vozac_raspored_service.dart';

/// Model za jedan red iz vozac_putnik tabele.
///
/// Čuva per-putnik raspored: koji vozač vozi određenog putnika
/// za određeni dan/grad/vreme.
///
/// Jedan putnik može imati najviše jedan aktivan override (UNIQUE putnik_id).
class VozacPutnikEntry {
  final String? id; // uuid PK, null prije inserata
  final String putnikId; // FK → registrovani_putnici.id
  final String vozacId; // FK → vozaci.id
  final String vozac; // ime vozača (denormalizovano za display)
  final String dan; // 'pon','uto','sre','cet','pet'
  final String grad; // 'BC' ili 'VS'
  final String vreme; // '07:00', '08:00', ...

  const VozacPutnikEntry({
    this.id,
    required this.putnikId,
    required this.vozacId,
    required this.vozac,
    required this.dan,
    required this.grad,
    required this.vreme,
  });

  factory VozacPutnikEntry.fromMap(Map<String, dynamic> map) {
    return VozacPutnikEntry(
      id: map['id'] as String?,
      putnikId: map['putnik_id'] as String,
      vozacId: map['vozac_id'] as String,
      vozac: map['vozac'] as String,
      dan: map['dan'] as String,
      grad: map['grad'] as String,
      vreme: map['vreme'] as String,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'putnik_id': putnikId,
        'vozac_id': vozacId,
        'vozac': vozac,
        'dan': dan,
        'grad': grad,
        'vreme': vreme,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
}

/// Servis za upravljanje per-putnik vozač overrideom.
///
/// Jedan putnik → jedan vozač override (UNIQUE putnik_id u tabeli).
///
/// Arhitektura:
///   vozac_putnik   — per-putnik override (ovaj servis)
///   vozac_raspored — per-termin raspored (VozacRasporedService)
class VozacPutnikService {
  static final VozacPutnikService _instance = VozacPutnikService._internal();
  factory VozacPutnikService() => _instance;
  VozacPutnikService._internal();

  SupabaseClient get _supabase => supabase;

  /// Učitaj sve override-e
  Future<List<VozacPutnikEntry>> loadAll() async {
    try {
      final response = await _supabase.from('vozac_putnik').select();
      return (response as List).map((row) => VozacPutnikEntry.fromMap(row as Map<String, dynamic>)).toList();
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return [];
    }
  }

  /// Postavi (ili zamijeni) override za putnika.
  ///
  /// Ako [vozacIme] je prazan string → briše override (vidi [delete]).
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
      await _supabase.from('vozac_putnik').upsert(
        {
          'putnik_id': putnikId,
          'vozac_id': vozacId,
          'vozac': vozacIme,
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

  /// Briše override za putnika (putnik se vraća na termin-level vozača).
  Future<bool> delete({required String putnikId}) async {
    try {
      await _supabase.from('vozac_putnik').delete().eq('putnik_id', putnikId);
      return true;
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return false;
    }
  }

  /// Briše sve override-e za datog vozača.
  Future<void> deleteForVozac({required String vozacId}) async {
    await _supabase.from('vozac_putnik').delete().eq('vozac_id', vozacId);
  }

  /// Kombinirani filter: per-putnik override + per-termin raspored.
  ///
  /// Tačan prioritet:
  ///   1. Per-putnik override postoji:
  ///      - dodeljen MENI   → prikaži (ignoriši termin-raspored)
  ///      - dodeljen DRUGOM → sakrij  (ignoriši termin-raspored)
  ///   2. Nema override-a → provjeri termin-raspored:
  ///      - nema unosa za termin → vidljivo svima ✅
  ///      - postoji unos → prikaži samo vozaču koji je dodeljen terminu
  ///
  /// Filtrira putnike za datog vozača na osnovu termin rasporeda (vozac_raspored).
  /// Putnik je vidljiv vozaču samo ako postoji unos u rasporedu koji ga dodjeljuje tom vozaču.
  ///
  /// [vozacId] = UUID (preferiran), [vozac] = ime (fallback)
  static List<T> filterKombinovan<T>({
    required List<T> sviPutnici,
    required String vozac,
    required String? vozacId,
    required String targetDan,
    required List<VozacPutnikEntry> overrides, // zadržano radi compat, nije u upotrebi
    required List<VozacRasporedEntry> raspored,
    required String Function(T) getId,
    required String Function(T) getGrad,
    required String Function(T) getPolazak,
  }) {
    // Helper: da li je termin-unos za ovog vozača?
    bool jeTerminVozacov(VozacRasporedEntry r) {
      if (vozacId != null) return r.vozacId == vozacId;
      return r.vozac == vozac;
    }

    return sviPutnici.where((p) {
      final grad = getGrad(p);
      final vreme = getPolazak(p);
      final terminEntries = raspored.where((r) => r.dan == targetDan && r.grad == grad && r.vreme == vreme).toList();

      if (terminEntries.isEmpty) return false; // nema raspodele → putnik nije vidljiv

      return terminEntries.any(jeTerminVozacov);
    }).toList();
  }
}
