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
  final DateTime? updatedAt;
  final String? updatedBy;

  const V3NaplataInfo({
    required this.isPaid,
    required this.iznos,
    this.paidAt,
    this.paidBy,
    this.updatedAt,
    this.updatedBy,
  });
}

class V3FinansijeService {
  V3FinansijeService._();
  static final V3FinansijeRepository _repo = V3FinansijeRepository();
  static final Set<String> _mesecnaNaplataLocks = <String>{};
  static final Set<String> _naplataPoReferenciLocks = <String>{};

  static bool _isPoDanuTip(String tip) {
    final normalized = tip.trim().toLowerCase();
    return normalized == 'radnik' || normalized == 'ucenik' || normalized == 'vozac';
  }

  static double _cenaZaTip({
    required String tip,
    required double cenaPoDanu,
    required double cenaPoPokupljenju,
  }) {
    return _isPoDanuTip(tip) ? cenaPoDanu : cenaPoPokupljenju;
  }

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

  static DateTime? _naplacenoAt(Map<String, dynamic> row) {
    return V3DateUtils.parseTs(row['created_at']?.toString());
  }

  static void _sortByCreatedAtDesc(List<Map<String, dynamic>> rows) {
    rows.sort((a, b) => _createdAtOrEpoch(b).compareTo(_createdAtOrEpoch(a)));
  }

  static bool _isSameDay(DateTime dt, DateTime day) {
    return dt.year == day.year && dt.month == day.month && dt.day == day.day;
  }

  static String _realizacijaVoznjaNazivZaDan(DateTime datum) {
    final dayKey = V3DateUtils.parseIsoDatePart(datum.toIso8601String());
    return 'Realizacija prevoza (vožnja) $dayKey';
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
  }) {
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
      paidAt: _naplacenoAt(latest),
      paidBy: latest['naplaceno_by']?.toString(),
      updatedAt: V3DateUtils.parseTs(latest['updated_at']?.toString()),
      updatedBy: latest['updated_by']?.toString(),
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
      paidAt: _naplacenoAt(latest),
      paidBy: latest['naplaceno_by']?.toString(),
      updatedAt: V3DateUtils.parseTs(latest['updated_at']?.toString()),
      updatedBy: latest['updated_by']?.toString(),
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

    var brojVoznjiRealizacija = 0;
    var ukupanIznos = 0.0;

    for (final row in naplataRows) {
      ukupanIznos += (row['iznos'] as num?)?.toDouble() ?? 0.0;
    }

    for (final row in realizacijaRows) {
      final broj = (row['broj_voznji'] as num?)?.toInt() ?? 0;
      brojVoznjiRealizacija += broj > 0 ? broj : 0;
    }

    final brojVoznji = brojVoznjiRealizacija;

    return (brojVoznji: brojVoznji, ukupanIznos: ukupanIznos);
  }

  static Future<void> evidentirajRealizacijuPriPokupljanju({
    required String putnikId,
    required String tipPutnika,
    required DateTime datum,
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

    final nazivVoznja = _realizacijaVoznjaNazivZaDan(datum);
    final existsVoznja = cache.any((row) {
      if (!_isRealizacijaPrihod(row)) return false;
      if ((row['putnik_v3_auth_id']?.toString() ?? '') != safePutnikId) return false;
      if ((row['godina'] as num?)?.toInt() != datum.year) return false;
      if ((row['mesec'] as num?)?.toInt() != datum.month) return false;
      return (row['naziv']?.toString() ?? '') == nazivVoznja;
    });
    if (existsVoznja) return;

    final row2 = await _repo.insertReturning({
      'naziv': nazivVoznja,
      'kategorija': 'operativna_realizacija',
      'tip': 'prihod',
      'iznos': 0,
      'putnik_v3_auth_id': safePutnikId,
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

  static List<V3Dug> getDugovi() {
    final rm = V3MasterRealtimeManager.instance;
    final dugovi = <V3Dug>[];
    final now = DateTime.now();

    for (final putnikData in rm.putniciCache.values) {
      final putnikId = putnikData['id']?.toString().trim() ?? '';
      if (putnikId.isEmpty) continue;

      final tip = (putnikData['tip_putnika'] as String? ?? 'dnevni').toLowerCase();
      final cenaPoDanu = (putnikData['cena_po_danu'] as num?)?.toDouble() ?? 0.0;
      final cenaPoPokupljenju = (putnikData['cena_po_pokupljenju'] as num?)?.toDouble() ?? 0.0;
      final cena = _cenaZaTip(
        tip: tip,
        cenaPoDanu: cenaPoDanu,
        cenaPoPokupljenju: cenaPoPokupljenju,
      );

      final meseci = getNaplataMeseciForPutnik(putnikId)..add((now.year, now.month));
      if (meseci.isEmpty) continue;

      for (final (godina, mesec) in meseci) {
        final summary = getNaplataSummaryForPutnik(
          putnikId: putnikId,
          godina: godina,
          mesec: mesec,
        );
        final naplateRows = _naplataRowsForPutnikMesec(
          putnikId: putnikId,
          godina: godina,
          mesec: mesec,
        ).toList()
          ..sort((a, b) => _createdAtOrEpoch(b).compareTo(_createdAtOrEpoch(a)));
        final latestNaplata = naplateRows.isNotEmpty ? naplateRows.first : null;
        final naplatioById = latestNaplata?['naplaceno_by']?.toString().trim();
        final updatedById = latestNaplata?['updated_by']?.toString().trim();

        final brojVoznji = summary.brojVoznji;
        if (brojVoznji <= 0) continue;

        final ukupnaObaveza = brojVoznji * cena;
        final uplaceno = summary.ukupanIznos;
        final dugIznos = ukupnaObaveza - uplaceno;
        if (dugIznos <= 0) continue;

        dugovi.add(
          V3Dug(
            id: '$putnikId:$godina:$mesec',
            putnikId: putnikId,
            imePrezime: putnikData['ime_prezime'] as String? ?? 'Nepoznato',
            tipPutnika: tip,
            godina: godina,
            mesec: mesec,
            brojVoznji: brojVoznji,
            cena: cena,
            ukupnaObaveza: ukupnaObaveza,
            uplaceno: uplaceno,
            vozacId: '',
            vozacIme: naplatioById ?? '',
            datum: DateTime(godina, mesec, 1),
            pokupljenAt: null,
            iznos: dugIznos,
            placeno: false,
            createdAt: V3DateUtils.parseTs(latestNaplata?['created_at']?.toString()),
            naplacenoAt: _naplacenoAt(latestNaplata ?? const {}),
            naplacenoBy: (naplatioById != null && naplatioById.isNotEmpty) ? naplatioById : null,
            updatedAt: V3DateUtils.parseTs(latestNaplata?['updated_at']?.toString()),
            updatedBy: (updatedById != null && updatedById.isNotEmpty) ? updatedById : null,
            finansijeNaziv: latestNaplata?['naziv']?.toString(),
            finansijeKategorija: latestNaplata?['kategorija']?.toString(),
          ),
        );
      }
    }

    dugovi.sort((a, b) {
      final byDate = b.datum.compareTo(a.datum);
      if (byDate != 0) return byDate;
      return b.iznos.compareTo(a.iznos);
    });
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
    int brojVoznji = 1,
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
        'broj_voznji': brojVoznji,
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

  static Future<void> sacuvajNaplatuZaMesec({
    required String putnikId,
    required String naplacenoBy,
    required double iznos,
    required DateTime datum,
  }) async {
    if (putnikId.trim().isEmpty) {
      throw ArgumentError('putnikId je obavezan.');
    }
    if (iznos <= 0) {
      throw ArgumentError('Iznos naplate mora biti veći od nule.');
    }

    final lockKey = 'ref:${putnikId.trim()}:${datum.month}:${datum.year}';
    if (_naplataPoReferenciLocks.contains(lockKey)) {
      debugPrint('[V3FinansijeService] sacuvajNaplatuZaMesec skipped (lock): $lockKey');
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
        'naplaceno_by': naplacenoBy,
        'broj_voznji': 1,
        'mesec': datum.month,
        'godina': datum.year,
      };

      final existing = await _repo.findMesecnuNaplatu(
        putnikId: putnikId,
        mesec: datum.month,
        godina: datum.year,
      );
      Map<String, dynamic> row;
      if (existing != null && existing['id'] != null) {
        row = await _repo.updateByIdReturning(existing['id'] as String, payload);
      } else {
        try {
          row = await _repo.insertReturning(payload);
        } on Object catch (insertErr) {
          final isConflict = insertErr.toString().contains('23505') || insertErr.toString().contains('duplicate key');
          if (!isConflict) rethrow;
          // Race condition — zapis se pojavio između find i insert, pokušaj update
          debugPrint('[V3FinansijeService] sacuvajNaplatuZaMesec: insert conflict, retry find+update');
          final retry = await _repo.findMesecnuNaplatu(
            putnikId: putnikId,
            mesec: datum.month,
            godina: datum.year,
          );
          if (retry != null && retry['id'] != null) {
            row = await _repo.updateByIdReturning(retry['id'] as String, payload);
          } else {
            rethrow;
          }
        }
      }
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_finansije', row);
    } catch (e) {
      debugPrint('[V3FinansijeService] sacuvajNaplatuZaMesec error: $e');
      rethrow;
    } finally {
      _naplataPoReferenciLocks.remove(lockKey);
    }
  }
}
