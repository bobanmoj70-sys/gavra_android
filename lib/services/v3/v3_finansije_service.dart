import 'package:flutter/foundation.dart';

import '../../models/v3_finansije.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_finansije_repository.dart';

class V3FinansijeService {
  V3FinansijeService._();
  static final V3FinansijeRepository _repo = V3FinansijeRepository();

  /// Vraca sve troškove za trenutni mesec iz cache-a (v3_finansije)
  static List<V3Trosak> getTroskoviMesec({int? mesec, int? godina}) {
    final now = DateTime.now();
    final m = mesec ?? now.month;
    final g = godina ?? now.year;
    final cache = V3MasterRealtimeManager.instance.getCache('v3_finansije');
    return cache.values
        .where((r) => r['aktivno'] != false && r['tip'] == 'rashod' && r['mesec'] == m && r['godina'] == g)
        .map((r) => V3Trosak.fromJson(r))
        .toList()
      ..sort((a, b) => (b.createdAt ?? DateTime.now()).compareTo(a.createdAt ?? DateTime.now()));
  }

  /// Dodaje novi trošak u bazu (Fire and Forget)
  static Future<void> addTrosak(V3Trosak trosak) async {
    try {
      await _repo.insert(trosak.toJson());
    } catch (e) {
      debugPrint('[V3FinansijeService] addTrosak error: $e');
    }
  }

  /// Briše trošak (Fire and Forget)
  static Future<void> deleteTrosak(String id) async {
    try {
      await _repo.updateById(id, {'aktivno': false});
    } catch (e) {
      debugPrint('[V3FinansijeService] deleteTrosak error: $e');
      rethrow;
    }
  }

  // --- Backward compat (stari kod koji koristi V3FinansijskiIzvestaj) ---
  static Stream<V3FinansijskiIzvestaj> streamIzvestaj() {
    return V3MasterRealtimeManager.instance.v3StreamFromRevisions(
        tables: ['v3_finansije'],
        build: () {
          final now = DateTime.now();
          final troskovi = getTroskoviMesec(mesec: now.month, godina: now.year);
          double trosakMesec = 0;
          final Map<String, double> poKategoriji = {};
          for (final t in troskovi) {
            trosakMesec += t.iznos;
            poKategoriji[t.kategorija ?? 'ostalo'] = (poKategoriji[t.kategorija ?? 'ostalo'] ?? 0) + t.iznos;
          }
          return V3FinansijskiIzvestaj(
            trosakMesec: trosakMesec,
            troskoviPoKategoriji: poKategoriji,
          );
        });
  }

  /// @deprecated Koristi addTrosak umesto addUnos
  static Future<void> addUnos(V3FinansijskiUnos unos) async {
    final now = DateTime.now();
    final trosak = V3Trosak(
      id: '',
      tip: unos.tip == 'prihod' ? 'prihod' : 'rashod',
      naziv: unos.opis,
      kategorija: unos.kategorija,
      iznos: unos.iznos,
      isplataIz: 'pazar',
      ponavljajMesecno: false,
      mesec: unos.datum.month,
      godina: unos.datum.year,
      vozacId: unos.vozacId,
    );
    await addTrosak(trosak);
  }
}
