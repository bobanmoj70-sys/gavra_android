import 'package:flutter/foundation.dart';

import '../../models/v3_dug.dart';
import '../../models/v3_finansije.dart';
import '../../utils/v3_date_utils.dart';
import '../../utils/v3_status_policy.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_finansije_repository.dart';

class V3NaplataInfo {
  final bool isPaid;
  final double iznos;
  final DateTime? paidAt;
  final String? paidBy;

  const V3NaplataInfo({
    required this.isPaid,
    required this.iznos,
    this.paidAt,
    this.paidBy,
  });
}

class V3FinansijeService {
  V3FinansijeService._();
  static final V3FinansijeRepository _repo = V3FinansijeRepository();
  static final Set<String> _mesecnaNaplataLocks = <String>{};
  static final Set<String> _operativnaNaplataLocks = <String>{};

  static bool _isOperativnaNaplataPrihod(Map<String, dynamic> row) {
    if (row['tip']?.toString() != 'prihod') return false;
    final kategorija = (row['kategorija']?.toString() ?? '').toLowerCase();
    return kategorija == 'operativna_naplata';
  }

  static DateTime _createdAtOrEpoch(Map<String, dynamic> row) {
    return V3DateUtils.parseTs(row['created_at']?.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  static void _sortByCreatedAtDesc(List<Map<String, dynamic>> rows) {
    rows.sort((a, b) => _createdAtOrEpoch(b).compareTo(_createdAtOrEpoch(a)));
  }

  static bool _isSameDay(DateTime dt, DateTime day) {
    return dt.year == day.year && dt.month == day.month && dt.day == day.day;
  }

  static Iterable<Map<String, dynamic>> _operativnaNaplataRows() {
    final cache = V3MasterRealtimeManager.instance.getCache('v3_finansije').values;
    return cache.where(_isOperativnaNaplataPrihod);
  }

  static Iterable<Map<String, dynamic>> _operativnaNaplataRowsForPutnikMesec({
    required String putnikId,
    required int godina,
    required int mesec,
  }) {
    return _operativnaNaplataRows().where((row) {
      if ((row['putnik_v3_auth_id']?.toString() ?? '') != putnikId) return false;
      final rowGodina = (row['godina'] as num?)?.toInt();
      final rowMesec = (row['mesec'] as num?)?.toInt();
      return rowGodina == godina && rowMesec == mesec;
    });
  }

  static Iterable<Map<String, dynamic>> _operativnaNaplataRowsForDan(DateTime day) {
    return _operativnaNaplataRows().where((row) {
      final dt = V3DateUtils.parseTs(row['created_at']?.toString());
      return dt != null && _isSameDay(dt, day);
    });
  }

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

  static V3NaplataInfo? resolveNaplataInfo({
    required String putnikId,
    required DateTime datumRef,
    required bool isMesecniModel,
    String? operativnaId,
  }) {
    if (!isMesecniModel) {
      final opId = (operativnaId ?? '').trim();
      if (opId.isEmpty) return null;

      final candidates = _operativnaNaplataRows().where((row) {
        return (row['operativna_id']?.toString() ?? '') == opId;
      }).toList();
      if (candidates.isEmpty) return null;

      _sortByCreatedAtDesc(candidates);
      final row = candidates.first;
      final iznos = (row['iznos'] as num?)?.toDouble() ?? 0;
      final paidAt = V3DateUtils.parseTs(row['created_at']?.toString());
      final paidBy = row['naplaceno_by']?.toString();
      return V3NaplataInfo(isPaid: iznos > 0, iznos: iznos, paidAt: paidAt, paidBy: paidBy);
    }

    final putnik = putnikId.trim();
    if (putnik.isEmpty) return null;

    final mesec = datumRef.month;
    final godina = datumRef.year;

    final candidates = _operativnaNaplataRowsForPutnikMesec(
      putnikId: putnik,
      godina: godina,
      mesec: mesec,
    ).toList();
    if (candidates.isEmpty) return null;

    _sortByCreatedAtDesc(candidates);
    final latest = candidates.first;

    final ukupno = candidates.fold<double>(0, (sum, row) => sum + ((row['iznos'] as num?)?.toDouble() ?? 0));
    return V3NaplataInfo(
      isPaid: ukupno > 0,
      iznos: ukupno,
      paidAt: V3DateUtils.parseTs(latest['created_at']?.toString()),
      paidBy: latest['naplaceno_by']?.toString(),
    );
  }

  static V3NaplataInfo? getLatestNaplataForPutnik(String putnikId) {
    final putnik = putnikId.trim();
    if (putnik.isEmpty) return null;

    final candidates = _operativnaNaplataRows().where((row) {
      if ((row['putnik_v3_auth_id']?.toString() ?? '') != putnik) return false;
      final createdAt = row['created_at']?.toString() ?? '';
      return createdAt.isNotEmpty;
    }).toList();
    if (candidates.isEmpty) return null;

    _sortByCreatedAtDesc(candidates);
    final latest = candidates.first;

    final iznos = (latest['iznos'] as num?)?.toDouble() ?? 0;
    return V3NaplataInfo(
      isPaid: iznos > 0,
      iznos: iznos,
      paidAt: V3DateUtils.parseTs(latest['created_at']?.toString()),
      paidBy: latest['naplaceno_by']?.toString(),
    );
  }

  static Map<String, Map<String, dynamic>> getLatestNaplataByOperativnaForPutnikMesec({
    required String putnikId,
    required int godina,
    required int mesec,
  }) {
    final putnik = putnikId.trim();
    if (putnik.isEmpty) return <String, Map<String, dynamic>>{};

    final byOperativna = <String, Map<String, dynamic>>{};
    for (final row in _operativnaNaplataRowsForPutnikMesec(putnikId: putnik, godina: godina, mesec: mesec)) {
      final operativnaId = row['operativna_id']?.toString().trim() ?? '';
      if (operativnaId.isEmpty) continue;

      final existing = byOperativna[operativnaId];
      if (existing == null || _createdAtOrEpoch(row).isAfter(_createdAtOrEpoch(existing))) {
        byOperativna[operativnaId] = row;
      }
    }

    return byOperativna;
  }

  static double sumOperativnaUplateZaPutnikMesec({
    required String putnikId,
    required int godina,
    required int mesec,
  }) {
    final putnik = putnikId.trim();
    if (putnik.isEmpty) return 0;

    return _operativnaNaplataRowsForPutnikMesec(
      putnikId: putnik,
      godina: godina,
      mesec: mesec,
    ).fold<double>(0, (sum, row) => sum + ((row['iznos'] as num?)?.toDouble() ?? 0));
  }

  static List<Map<String, dynamic>> getOperativnaNaplateZaVozacaDan({
    required String vozacId,
    required DateTime dan,
  }) {
    final id = vozacId.trim();
    if (id.isEmpty) return <Map<String, dynamic>>[];

    final targetDay = DateTime(dan.year, dan.month, dan.day);
    final rows = _operativnaNaplataRowsForDan(targetDay)
        .where((row) {
          final naplatioBy = row['naplaceno_by']?.toString() ?? '';
          return naplatioBy == id;
        })
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);

    rows.sort((a, b) {
      final aDt = _createdAtOrEpoch(a);
      final bDt = _createdAtOrEpoch(b);
      return aDt.compareTo(bDt);
    });
    return rows;
  }

  static Map<String, double> getPazarPoVozacuZaDan(DateTime dan) {
    final targetDay = DateTime(dan.year, dan.month, dan.day);
    final result = <String, double>{};

    for (final row in _operativnaNaplataRowsForDan(targetDay)) {
      final naplatioBy = row['naplaceno_by']?.toString().trim() ?? '';
      if (naplatioBy.isEmpty) continue;

      final iznos = (row['iznos'] as num?)?.toDouble() ?? 0.0;
      result[naplatioBy] = (result[naplatioBy] ?? 0.0) + iznos;
    }

    return result;
  }

  static List<V3Dug> getDugovi() {
    final rm = V3MasterRealtimeManager.instance;
    final cache = rm.operativnaNedeljaCache;
    final latestNaplataByOperativna = getLatestNaplataByOperativnaIds(
      cache.values.map((row) => row['id']?.toString() ?? ''),
    );
    final dugovi = <V3Dug>[];
    for (final row in cache.values) {
      final operativnaId = row['id']?.toString() ?? '';
      final naplata = operativnaId.isEmpty ? null : latestNaplataByOperativna[operativnaId];
      final isPlaceno = naplata != null;
      if (isPlaceno) continue;
      final isPokupljen = V3StatusPolicy.isTimestampSet(row['pokupljen_at']);
      if (!isPokupljen) continue;
      final putnikId = row['created_by'] as String? ?? '';
      final putnikData = rm.putniciCache[putnikId];
      if (putnikData == null) continue;
      final tip = putnikData['tip_putnika'] as String? ?? 'dnevni';
      if (tip != 'dnevni' && tip != 'posiljka') continue;
      try {
        final pickupVozacId = row['pokupljen_by'] as String? ?? '';
        final vozacData = pickupVozacId.isNotEmpty ? rm.vozaciCache[pickupVozacId] : null;
        final rowWithDriver = Map<String, dynamic>.from(row);
        rowWithDriver['pokupljen_by'] = pickupVozacId;
        rowWithDriver['vozac_ime'] = vozacData?['ime_prezime'] as String? ?? '';
        rowWithDriver['placeno_finansije'] = naplata != null;
        dugovi.add(V3Dug.fromOperacija(rowWithDriver, putnikData: putnikData));
      } catch (_) {}
    }
    dugovi.sort((a, b) => b.datum.compareTo(a.datum));
    return dugovi;
  }

  static Stream<List<V3Dug>> streamDugovi() => V3MasterRealtimeManager.instance.v3StreamFromRevisions(
        tables: ['v3_operativna_nedelja', 'v3_auth', 'v3_finansije'],
        build: () => getDugovi(),
      );

  static Map<String, Map<String, dynamic>> getLatestNaplataByOperativnaIds(Iterable<String> operativnaIds) {
    final ids = operativnaIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return <String, Map<String, dynamic>>{};

    final byOperativna = <String, Map<String, dynamic>>{};

    for (final row in _operativnaNaplataRows()) {
      final operativnaId = row['operativna_id']?.toString().trim() ?? '';
      if (!ids.contains(operativnaId)) continue;

      final existing = byOperativna[operativnaId];
      if (existing == null || _createdAtOrEpoch(row).isAfter(_createdAtOrEpoch(existing))) {
        byOperativna[operativnaId] = row;
      }
    }

    return byOperativna;
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

  static Future<void> sacuvajOperativnuNaplatu({
    required String operativnaId,
    required String putnikId,
    required String naplacenoBy,
    required double iznos,
    required DateTime datum,
  }) async {
    if (operativnaId.trim().isEmpty) {
      throw ArgumentError('operativnaId je obavezan.');
    }
    if (putnikId.trim().isEmpty) {
      throw ArgumentError('putnikId je obavezan.');
    }
    if (iznos <= 0) {
      throw ArgumentError('Iznos naplate mora biti veći od nule.');
    }

    final lockKey = 'op:$operativnaId';
    if (_operativnaNaplataLocks.contains(lockKey)) {
      debugPrint('[V3FinansijeService] sacuvajOperativnuNaplatu skipped (lock): $lockKey');
      return;
    }
    _operativnaNaplataLocks.add(lockKey);

    try {
      final payload = {
        'naziv': 'Naplata prevoza',
        'kategorija': 'operativna_naplata',
        'tip': 'prihod',
        'iznos': iznos,
        'putnik_v3_auth_id': putnikId,
        'operativna_id': operativnaId,
        'naplaceno_by': naplacenoBy,
        'broj_voznji': 1,
        'mesec': datum.month,
        'godina': datum.year,
      };

      final existing = await _repo.findOperativnaNaplataByOperativnaId(operativnaId);
      if (existing != null && existing['id'] != null) {
        await _repo.updateById(existing['id'] as String, payload);
      } else {
        await _repo.insert(payload);
      }
    } catch (e) {
      debugPrint('[V3FinansijeService] sacuvajOperativnuNaplatu error: $e');
      rethrow;
    } finally {
      _operativnaNaplataLocks.remove(lockKey);
    }
  }
}
