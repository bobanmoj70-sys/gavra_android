import 'package:flutter/foundation.dart';

import '../../models/v3_finansije.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_finansije_repository.dart';

class V3FinansijeService {
  V3FinansijeService._();
  static final V3FinansijeRepository _repo = V3FinansijeRepository();
  static final Set<String> _mesecnaNaplataLocks = <String>{};

  /// Vraca sve troškove za trenutni mesec iz cache-a (v3_finansije)
  static List<V3Trosak> getTroskoviMesec({int? mesec, int? godina}) {
    final now = DateTime.now();
    final m = mesec ?? now.month;
    final g = godina ?? now.year;
    final cache = V3MasterRealtimeManager.instance.getCache('v3_finansije');
    return cache.values
        .where((r) => r['tip'] == 'rashod' && r['mesec'] == m && r['godina'] == g)
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
      await _repo.deleteById(id);
    } catch (e) {
      debugPrint('[V3FinansijeService] deleteTrosak error: $e');
      rethrow;
    }
  }

  static Future<void> sacuvajMesecnuOperativnuNaplatu({
    required String putnikId,
    required String naplacenoBy,
    required double iznos,
    required int mesec,
    required int godina,
  }) async {
    final lockKey = '$putnikId:$mesec:$godina';
    if (_mesecnaNaplataLocks.contains(lockKey)) {
      debugPrint('[V3FinansijeService] sacuvajMesecnuOperativnuNaplatu skipped (lock): $lockKey');
      return;
    }
    _mesecnaNaplataLocks.add(lockKey);

    try {
      final payload = {
        'naziv': 'Naplata prevoza',
        'kategorija': 'operativna_naplata',
        'tip': 'prihod',
        'iznos': iznos,
        'putnik_v3_auth_id': putnikId,
        'naplaceno_by': naplacenoBy,
        'broj_voznji': 1,
        'mesec': mesec,
        'godina': godina,
      };

      await _repo.insert(payload);
    } catch (e) {
      debugPrint('[V3FinansijeService] sacuvajMesecnuOperativnuNaplatu error: $e');
      rethrow;
    } finally {
      _mesecnaNaplataLocks.remove(lockKey);
    }
  }
}
