import 'package:flutter/foundation.dart';

import '../../models/v3_dug.dart';
import '../../models/v3_finansije.dart';
import '../../utils/v3_date_utils.dart';
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
  static final Set<String> _naplataPoReferenciLocks = <String>{};

  static bool _isNaplataPrihod(Map<String, dynamic> row) {
    if (row['tip']?.toString() != 'prihod') return false;
    final kategorija = (row['kategorija']?.toString() ?? '').toLowerCase();
    return kategorija == 'operativna_naplata';
  }

  static bool _isRealizacijaPrihod(Map<String, dynamic> row) {
    if (row['tip']?.toString() != 'prihod') return false;
    final kategorija = (row['kategorija']?.toString() ?? '').toLowerCase();
    return kategorija == 'operativna_realizacija';
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

  static Iterable<Map<String, dynamic>> _naplataRows() {
    final cache = V3MasterRealtimeManager.instance.getCache('v3_finansije').values;
    return cache.where(_isNaplataPrihod);
  }

  static Iterable<Map<String, dynamic>> _realizacijaRows() {
    final cache = V3MasterRealtimeManager.instance.getCache('v3_finansije').values;
    return cache.where(_isRealizacijaPrihod);
  }

  static Iterable<Map<String, dynamic>> _naplataRowsForPutnikMesec({
    required String putnikId,
    required int godina,
    required int mesec,
  }) {
    return _naplataRows().where((row) {
      if ((row['putnik_v3_auth_id']?.toString() ?? '') != putnikId) return false;
      final rowGodina = (row['godina'] as num?)?.toInt();
      final rowMesec = (row['mesec'] as num?)?.toInt();
      return rowGodina == godina && rowMesec == mesec;
    });
  }

  static Iterable<Map<String, dynamic>> _naplataRowsForDan(DateTime day) {
    return _naplataRows().where((row) {
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
      final row = await _repo.insertReturning(trosak.toJson());
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_finansije', row);
    } catch (e) {
      debugPrint('[V3FinansijeService] addTrosak error: $e');
    }
  }

  static V3NaplataInfo? resolveNaplataInfo({
    required String putnikId,
    required DateTime datumRef,
    required bool isMesecniModel,
    String? referencaId,
  }) {
    if (!isMesecniModel) {
      final refId = (referencaId ?? '').trim();
      if (refId.isEmpty) return null;

      final candidates = _naplataRows().where((row) {
        return (row['operativna_id']?.toString() ?? '') == refId;
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

    final candidates = _naplataRowsForPutnikMesec(
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

    final candidates = _naplataRows().where((row) {
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

  static ({int brojVoznji, double ukupanIznos}) getNaplataSummaryForPutnik({
    required String putnikId,
    int? godina,
    int? mesec,
  }) {
    final putnik = putnikId.trim();
    if (putnik.isEmpty) return (brojVoznji: 0, ukupanIznos: 0.0);

    final naplataRows = _naplataRows().where((row) {
      if ((row['putnik_v3_auth_id']?.toString() ?? '') != putnik) return false;
      if (godina != null) {
        final rowGodina = (row['godina'] as num?)?.toInt();
        if (rowGodina != godina) return false;
      }
      if (mesec != null) {
        final rowMesec = (row['mesec'] as num?)?.toInt();
        if (rowMesec != mesec) return false;
      }
      return true;
    });

    final realizacijaRows = _realizacijaRows().where((row) {
      if ((row['putnik_v3_auth_id']?.toString() ?? '') != putnik) return false;
      if (godina != null) {
        final rowGodina = (row['godina'] as num?)?.toInt();
        if (rowGodina != godina) return false;
      }
      if (mesec != null) {
        final rowMesec = (row['mesec'] as num?)?.toInt();
        if (rowMesec != mesec) return false;
      }
      return true;
    });

    var brojVoznjiNaplata = 0;
    var brojVoznjiRealizacija = 0;
    var ukupanIznos = 0.0;

    for (final row in naplataRows) {
      final broj = (row['broj_voznji'] as num?)?.toInt() ?? 0;
      brojVoznjiNaplata += broj > 0 ? broj : 0;
      ukupanIznos += (row['iznos'] as num?)?.toDouble() ?? 0.0;
    }

    for (final row in realizacijaRows) {
      final broj = (row['broj_voznji'] as num?)?.toInt() ?? 0;
      brojVoznjiRealizacija += broj > 0 ? broj : 0;
    }

    final brojVoznji = brojVoznjiRealizacija > 0 ? brojVoznjiRealizacija : brojVoznjiNaplata;

    return (brojVoznji: brojVoznji, ukupanIznos: ukupanIznos);
  }

  static Future<void> evidentirajRealizacijuPriPokupljanju({
    required String putnikId,
    required String tipPutnika,
    required DateTime datum,
    String? referencaId,
    String? evidentiraoBy,
  }) async {
    final safePutnikId = putnikId.trim();
    if (safePutnikId.isEmpty) return;

    final tip = tipPutnika.trim().toLowerCase();
    final isPoDanu = tip == 'radnik' || tip == 'ucenik';
    final dayKey = V3DateUtils.parseIsoDatePart(datum.toIso8601String());

    final cache = V3MasterRealtimeManager.instance.getCache('v3_finansije').values;

    if (isPoDanu) {
      final naziv = 'Realizacija prevoza (dan) $dayKey';
      final exists = cache.any((row) {
        if (!_isRealizacijaPrihod(row)) return false;
        if ((row['putnik_v3_auth_id']?.toString() ?? '') != safePutnikId) return false;
        if ((row['godina'] as num?)?.toInt() != datum.year) return false;
        if ((row['mesec'] as num?)?.toInt() != datum.month) return false;
        return (row['naziv']?.toString() ?? '') == naziv;
      });
      if (exists) return;

      final row1 = await _repo.insertReturning({
        'naziv': naziv,
        'kategorija': 'operativna_realizacija',
        'tip': 'prihod',
        'iznos': 0,
        'putnik_v3_auth_id': safePutnikId,
        'naplaceno_by': (evidentiraoBy ?? '').trim().isEmpty ? null : evidentiraoBy,
        'broj_voznji': 1,
        'mesec': datum.month,
        'godina': datum.year,
      });
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_finansije', row1);
      return;
    }

    final safeReferencaId = (referencaId ?? '').trim();
    if (safeReferencaId.isNotEmpty) {
      final exists = cache.any((row) {
        if (!_isRealizacijaPrihod(row)) return false;
        return (row['operativna_id']?.toString() ?? '') == safeReferencaId;
      });
      if (exists) return;
    }

    final row2 = await _repo.insertReturning({
      'naziv': safeReferencaId.isNotEmpty ? 'Realizacija prevoza (vožnja)' : 'Realizacija prevoza (vožnja) $dayKey',
      'kategorija': 'operativna_realizacija',
      'tip': 'prihod',
      'iznos': 0,
      'putnik_v3_auth_id': safePutnikId,
      if (safeReferencaId.isNotEmpty) 'operativna_id': safeReferencaId,
      'naplaceno_by': (evidentiraoBy ?? '').trim().isEmpty ? null : evidentiraoBy,
      'broj_voznji': 1,
      'mesec': datum.month,
      'godina': datum.year,
    });
    V3MasterRealtimeManager.instance.v3UpsertToCache('v3_finansije', row2);
  }

  static Set<(int, int)> getNaplataMeseciForPutnik(String putnikId) {
    final putnik = putnikId.trim();
    if (putnik.isEmpty) return <(int, int)>{};

    final meseci = <(int, int)>{};
    final rows = <Map<String, dynamic>>[
      ..._naplataRows(),
      ..._realizacijaRows(),
    ];

    for (final row in rows) {
      if ((row['putnik_v3_auth_id']?.toString() ?? '') != putnik) continue;
      final godina = (row['godina'] as num?)?.toInt();
      final mesec = (row['mesec'] as num?)?.toInt();
      if (godina == null || mesec == null) continue;
      if (mesec < 1 || mesec > 12) continue;
      meseci.add((godina, mesec));
    }

    return meseci;
  }

  static List<Map<String, dynamic>> getNaplataRowsZaVozacaDan({
    required String vozacId,
    required DateTime dan,
  }) {
    final id = vozacId.trim();
    if (id.isEmpty) return <Map<String, dynamic>>[];

    final targetDay = DateTime(dan.year, dan.month, dan.day);
    final rows = _naplataRowsForDan(targetDay)
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

    for (final row in _naplataRowsForDan(targetDay)) {
      final naplatioBy = row['naplaceno_by']?.toString().trim() ?? '';
      if (naplatioBy.isEmpty) continue;

      final iznos = (row['iznos'] as num?)?.toDouble() ?? 0.0;
      result[naplatioBy] = (result[naplatioBy] ?? 0.0) + iznos;
    }

    return result;
  }

  static String _dugMatchKey(Map<String, dynamic> row) {
    final referencaId = row['operativna_id']?.toString().trim() ?? '';
    if (referencaId.isNotEmpty) return referencaId;
    return row['id']?.toString().trim() ?? '';
  }

  static List<V3Dug> getDugovi() {
    final rm = V3MasterRealtimeManager.instance;
    final realizacije = _realizacijaRows().toList(growable: false);
    final naplate = _naplataRows().toList(growable: false);

    final latestNaplataByKey = <String, Map<String, dynamic>>{};
    for (final naplata in naplate) {
      final key = _dugMatchKey(naplata);
      if (key.isEmpty) continue;
      final existing = latestNaplataByKey[key];
      if (existing == null || _createdAtOrEpoch(naplata).isAfter(_createdAtOrEpoch(existing))) {
        latestNaplataByKey[key] = naplata;
      }
    }

    final dugovi = <V3Dug>[];
    for (final row in realizacije) {
      final putnikId = row['putnik_v3_auth_id']?.toString().trim() ?? '';
      if (putnikId.isEmpty) continue;

      final putnikData = rm.putniciCache[putnikId];
      if (putnikData == null) continue;

      final tip = putnikData['tip_putnika'] as String? ?? 'dnevni';
      if (tip != 'dnevni' && tip != 'posiljka') continue;

      final key = _dugMatchKey(row);
      if (key.isEmpty) continue;
      final naplata = latestNaplataByKey[key];
      if (naplata != null) continue;

      try {
        final pickupVozacId = row['naplaceno_by']?.toString() ?? '';
        final vozacData = pickupVozacId.isNotEmpty ? rm.vozaciCache[pickupVozacId] : null;
        final createdAt = V3DateUtils.parseTs(row['created_at']?.toString());
        final cenaPoPokupljenju = (putnikData['cena_po_pokupljenju'] as num?)?.toDouble() ?? 0.0;

        dugovi.add(
          V3Dug(
            id: key,
            putnikId: putnikId,
            imePrezime: putnikData['ime_prezime'] as String? ?? 'Nepoznato',
            tipPutnika: tip,
            vozacId: pickupVozacId,
            vozacIme: vozacData?['ime_prezime'] as String? ?? '',
            datum: createdAt ?? DateTime.now(),
            pokupljenAt: createdAt,
            iznos: cenaPoPokupljenju,
            placeno: false,
            createdAt: createdAt,
          ),
        );
      } catch (_) {}
    }

    dugovi.sort((a, b) => b.datum.compareTo(a.datum));
    return dugovi;
  }

  static Stream<List<V3Dug>> streamDugovi() => V3MasterRealtimeManager.instance.v3StreamFromRevisions(
        tables: ['v3_auth', 'v3_finansije'],
        build: () => getDugovi(),
      );

  static Future<void> sacuvajMesecnuNaplatu({
    required String putnikId,
    required String naplacenoBy,
    required double iznos,
    required int mesec,
    required int godina,
  }) async {
    final lockKey = '$putnikId:$mesec:$godina';
    if (_mesecnaNaplataLocks.contains(lockKey)) {
      debugPrint('[V3FinansijeService] sacuvajMesecnuNaplatu skipped (lock): $lockKey');
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

      final row = await _repo.insertReturning(payload);
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_finansije', row);
    } catch (e) {
      debugPrint('[V3FinansijeService] sacuvajMesecnuNaplatu error: $e');
      rethrow;
    } finally {
      _mesecnaNaplataLocks.remove(lockKey);
    }
  }

  static Future<void> sacuvajNaplatuPoReferenci({
    required String referencaId,
    required String putnikId,
    required String naplacenoBy,
    required double iznos,
    required DateTime datum,
  }) async {
    if (referencaId.trim().isEmpty) {
      throw ArgumentError('referencaId je obavezan.');
    }
    if (putnikId.trim().isEmpty) {
      throw ArgumentError('putnikId je obavezan.');
    }
    if (iznos <= 0) {
      throw ArgumentError('Iznos naplate mora biti veći od nule.');
    }

    final lockKey = 'ref:$referencaId';
    if (_naplataPoReferenciLocks.contains(lockKey)) {
      debugPrint('[V3FinansijeService] sacuvajNaplatuPoReferenci skipped (lock): $lockKey');
      return;
    }
    _naplataPoReferenciLocks.add(lockKey);

    try {
      final payload = {
        'naziv': 'Naplata prevoza',
        'kategorija': 'operativna_naplata',
        'tip': 'prihod',
        'iznos': iznos,
        'putnik_v3_auth_id': putnikId,
        'operativna_id': referencaId,
        'naplaceno_by': naplacenoBy,
        'broj_voznji': 1,
        'mesec': datum.month,
        'godina': datum.year,
      };

      final existing = await _repo.findNaplataByReferencaId(referencaId);
      if (existing != null && existing['id'] != null) {
        final row = await _repo.updateByIdReturning(existing['id'] as String, payload);
        V3MasterRealtimeManager.instance.v3UpsertToCache('v3_finansije', row);
      } else {
        final row = await _repo.insertReturning(payload);
        V3MasterRealtimeManager.instance.v3UpsertToCache('v3_finansije', row);
      }
    } catch (e) {
      debugPrint('[V3FinansijeService] sacuvajNaplatuPoReferenci error: $e');
      rethrow;
    } finally {
      _naplataPoReferenciLocks.remove(lockKey);
    }
  }
}
