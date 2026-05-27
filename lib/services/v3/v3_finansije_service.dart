import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../models/v3_dug.dart';
import '../../models/v3_finansije.dart';
import '../../utils/v3_date_utils.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_finansije_repository.dart';
import 'v3_vozac_akcije_service.dart';

class V3NaplataInfo {
  final bool isPaid;
  final double ukupanIznos;
  final double poslednjaDopuna;
  final DateTime? paidAt;
  final String? paidBy;
  final DateTime? updatedAt;
  final String? updatedBy;

  const V3NaplataInfo({
    required this.isPaid,
    required this.ukupanIznos,
    required this.poslednjaDopuna,
    this.paidAt,
    this.paidBy,
    this.updatedAt,
    this.updatedBy,
  });
}

class V3FinansijeService {
  V3FinansijeService._();
  static const Uuid _uuid = Uuid();
  static final V3FinansijeRepository _repo = V3FinansijeRepository();
  static final Set<String> _mesecnaNaplataLocks = <String>{};

  static bool _isPoDanuTip(String tip) {
    final normalized = tip.trim().toLowerCase();
    return normalized == 'radnik' || normalized == 'ucenik';
  }

  static double _cenaZaTip({
    required String tip,
    required double cenaPoDanu,
    required double cenaPoPokupljenju,
  }) {
    return _isPoDanuTip(tip) ? cenaPoDanu : cenaPoPokupljenju;
  }

  static int? _parseInternalInt(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val);
    return null;
  }

  static String _masterKategorija() => 'operativna_naplata';

  static String _getLockKey(String putnikId, int mesec, int godina) =>
      'finansije_master:${putnikId.trim().toLowerCase()}:$mesec:$godina';

  static bool _isMesecnaEvidencija(Map<String, dynamic> row) {
    final tip = (row['tip']?.toString() ?? '').toLowerCase();
    if (tip != 'prihod') return false;
    final kategorija = (row['kategorija']?.toString() ?? '').toLowerCase();
    return kategorija == _masterKategorija() || kategorija == 'operativna_realizacija';
  }

  static DateTime _createdAtOrEpoch(Map<String, dynamic> row) {
    return V3DateUtils.parseTs(row['created_at']?.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  static DateTime? _naplacenoAt(Map<String, dynamic> row) {
    // Koristimo created_at za stvarni datum uplate, ne updated_at
    final ts = row['created_at'];
    return V3DateUtils.parseTs(ts?.toString());
  }

  static void _sortByCreatedAtDesc(List<Map<String, dynamic>> rows) {
    rows.sort((a, b) => _createdAtOrEpoch(b).compareTo(_createdAtOrEpoch(a)));
  }

  static Iterable<Map<String, dynamic>> _naplataRows() {
    final cache = V3MasterRealtimeManager.instance.getCache('v3_finansije').values;
    return cache.where(_isMesecnaEvidencija);
  }

  static Iterable<Map<String, dynamic>> _naplataRowsForPutnikMesec({
    required String putnikId,
    required int godina,
    required int mesec,
  }) {
    return _naplataRows().where((row) {
      final rPutnikId = (row['putnik_v3_auth_id']?.toString() ?? '').trim().toLowerCase();
      if (rPutnikId != putnikId.trim().toLowerCase()) return false;
      final rowGodina = _parseInternalInt(row['godina']);
      final rowMesec = _parseInternalInt(row['mesec']);
      return rowGodina == godina && rowMesec == mesec;
    });
  }

  static Iterable<Map<String, dynamic>> _naplataRowsForDan(DateTime day) {
    return _naplataRows().where((row) {
      // Koristimo created_at jer nas zanima datum kada je naplata stvarno izvršena
      final ts = row['created_at'];
      final dt = V3DateUtils.parseTs(ts?.toString());
      if (dt == null) return false;
      return dt.year == day.year && dt.month == day.month && dt.day == day.day;
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
    
    // Ukupan iznos je ukupna suma uplaćena
    final ukupanIznos = (latest['iznos'] as num?)?.toDouble() ?? 0;
    
    // Poslednja dopuna se čuva u posebnoj koloni
    final poslednjaDopuna = (latest['poslednja_dopuna'] as num?)?.toDouble() ?? 0;
    
    return V3NaplataInfo(
      isPaid: ukupanIznos > 0,
      ukupanIznos: ukupanIznos,
      poslednjaDopuna: poslednjaDopuna,
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
      final rPutnikId = (row['putnik_v3_auth_id']?.toString() ?? '').trim().toLowerCase();
      if (rPutnikId != putnik.toLowerCase()) return false;
      final createdAt = row['created_at']?.toString() ?? '';
      return createdAt.isNotEmpty;
    }).toList();
    if (candidates.isEmpty) return null;

    _sortByCreatedAtDesc(candidates);
    final latest = candidates.first;

    final ukupanIznos = (latest['iznos'] as num?)?.toDouble() ?? 0;
    final poslednjaDopuna = (latest['poslednja_dopuna'] as num?)?.toDouble() ?? 0;
    
    return V3NaplataInfo(
      isPaid: ukupanIznos > 0,
      ukupanIznos: ukupanIznos,
      poslednjaDopuna: poslednjaDopuna,
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
      final rPutnikId = (row['putnik_v3_auth_id']?.toString() ?? '').trim().toLowerCase();
      if (rPutnikId != putnik.toLowerCase()) return false;
      if (godina != null) {
        final rowGodina = _parseInternalInt(row['godina']);
        if (rowGodina != godina) return false;
      }
      if (mesec != null) {
        final rowMesec = _parseInternalInt(row['mesec']);
        if (rowMesec != mesec) return false;
      }
      return true;
    });

    var brojVoznjiRealizacija = 0;
    var ukupanIznos = 0.0;

    for (final row in naplataRows) {
      ukupanIznos += (row['iznos'] as num?)?.toDouble() ?? 0.0;
      brojVoznjiRealizacija += (row['broj_voznji'] as num?)?.toInt() ?? 0;
    }

    return (brojVoznji: brojVoznjiRealizacija, ukupanIznos: ukupanIznos);
  }

  static Future<void> evidentirajRealizacijuPriPokupljanju({
    required String putnikId,
    required String tipPutnika,
    required DateTime datum,
    String? dogadjajId,
    String? evidentiraoBy,
  }) async {
    final safePutnikId = putnikId.trim();
    if (safePutnikId.isEmpty) return;

    final tip = tipPutnika.trim().toLowerCase();
    if (tip == 'vozac') return;

    final isPoDanu = _isPoDanuTip(tip);
    final safeDogadjajId = (dogadjajId ?? '').trim();

    final lockKey = _getLockKey(safePutnikId, datum.month, datum.year);
    if (_mesecnaNaplataLocks.contains(lockKey)) return;
    _mesecnaNaplataLocks.add(lockKey);

    final cache = V3MasterRealtimeManager.instance.getCache('v3_finansije').values;

    try {
      // 1. Pronađi postojeći master red za ovaj mesec
      final existingMesecna = cache.where((row) {
        final rPutnikId = (row['putnik_v3_auth_id']?.toString() ?? '').trim().toLowerCase();
        if (rPutnikId != safePutnikId.toLowerCase()) return false;
        final rG = _parseInternalInt(row['godina']);
        final rM = _parseInternalInt(row['mesec']);
        if (rG != datum.year || rM != datum.month) return false;
        // Smatramo ga master redom ako se podudaraju putnik i mesec/godina
        return (row['tip']?.toString().toLowerCase() ?? '') == 'prihod';
      }).toList();

      if (existingMesecna.isNotEmpty) {
        _sortByCreatedAtDesc(existingMesecna);
        final latest = existingMesecna.first;
        final latestId = (latest['id'] ?? '').toString();

        if (isPoDanu) {
          final danIso = V3DateUtils.parseIsoDatePart(datum.toIso8601String());
          final opCache = V3MasterRealtimeManager.instance.getCache('v3_operativna_nedelja');
          final vecVozioDanas = opCache.values.any((r) =>
              (r['created_by']?.toString() ?? '') == safePutnikId &&
              V3DateUtils.parseIsoDatePart(r['datum']?.toString() ?? '') ==
                  danIso && // Proveravamo da li je putnik već pokupljen danas
              // Uklonjena provera za operativnaId jer se više ne prosleđuje
              r['pokupljen_at'] != null);
          if (vecVozioDanas) return;
        }

        if (latestId.isNotEmpty) {
          final currentBroj = (latest['broj_voznji'] as num?)?.toInt() ?? 0;
          final updated = await _repo.updateByIdReturning(latestId, {
            'broj_voznji': currentBroj + 1,
            'updated_at': DateTime.now().toIso8601String(),
          });
          V3MasterRealtimeManager.instance.v3UpsertToCache('v3_finansije', updated);
          return;
        }
      }

      // 2. Ako ne postoji red, kreiraj novi master red
      final row = await _repo.insertReturning({
        'naziv': 'Evidencija prevoza ${datum.month}/${datum.year}',
        'kategorija': _masterKategorija(),
        'tip': 'prihod',
        'iznos': 0,
        'putnik_v3_auth_id': safePutnikId,
        'naplaceno_by': (evidentiraoBy ?? '').trim().isEmpty ? null : evidentiraoBy,
        'dogadjaj_id': safeDogadjajId.isEmpty ? null : safeDogadjajId,
        'broj_voznji': 1,
        'mesec': datum.month,
        'godina': datum.year,
      });
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_finansije', row);
      
      // Dodaj evidenciju u v3_vozac_akcije tabelu
      if (evidentiraoBy != null && evidentiraoBy.isNotEmpty) {
        try {
          final rm = V3MasterRealtimeManager.instance;
          final vozacData = rm.vozaciCache[evidentiraoBy];
          final vozacIme = vozacData?['ime_prezime']?.toString() ?? 'Nepoznat vozač';
          final putnikData = rm.putniciCache[safePutnikId];
          final putnikIme = putnikData?['ime_prezime']?.toString() ?? 'Nepoznat putnik';
          
          await V3VozacAkcijeService.evidentirajPokupio(
            vozacId: evidentiraoBy,
            vozacIme: vozacIme,
            putnikId: safePutnikId,
            putnikIme: putnikIme,
            datum: datum,
            evidentiraoBy: evidentiraoBy,
          );
        } catch (e) {
          debugPrint('[V3FinansijeService] Greška pri evidentiranju pokupio u v3_vozac_akcije: $e');
        }
      }
    } finally {
      _mesecnaNaplataLocks.remove(lockKey);
    }
  }

  static Set<(int, int)> getNaplataMeseciForPutnik(String putnikId) {
    final putnik = putnikId.trim();
    if (putnik.isEmpty) return <(int, int)>{};

    final meseci = <(int, int)>{};
    final rows = _naplataRows();

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
        if (brojVoznji <= 0) continue; // Samo oni koji su se vozili

        final vozacData = naplatioById != null ? rm.vozaciCache[naplatioById] : null;
        final vozacIme = vozacData?['ime_prezime']?.toString() ?? '';

        // Nađi vozača koji je pokupio putnika u ovom mesecu
        String pokupioVozacId = '';
        String pokupioVozacIme = '';
        for (final operRow in rm.operativnaNedeljaCache.values) {
          final rPutnikId = (operRow['created_by']?.toString() ?? '').trim().toLowerCase();
          if (rPutnikId != putnikId.toLowerCase()) continue;
          final pokupljenBy = operRow['pokupljen_by']?.toString().trim();
          if (pokupljenBy == null || pokupljenBy.isEmpty) continue;
          final datum = V3DateUtils.parseTs(operRow['datum']?.toString());
          if (datum == null) continue;
          if (datum.year == godina && datum.month == mesec) {
            pokupioVozacId = pokupljenBy;
            final pokupioVozacData = rm.vozaciCache[pokupljenBy];
            pokupioVozacIme = pokupioVozacData?['ime_prezime']?.toString() ?? '';
            break;
          }
        }

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
            vozacId: naplatioById ?? '',
            vozacIme: vozacIme,
            pokupioVozacId: pokupioVozacId,
            pokupioVozacIme: pokupioVozacIme,
            datum: DateTime(godina, mesec, 1),
            pokupljenAt: null,
            iznos: dugIznos,
            placeno: dugIznos <= 0,
            createdAt: V3DateUtils.parseTs(latestNaplata?['created_at']?.toString()),
            naplacenoAt: _naplacenoAt(latestNaplata ?? <String, dynamic>{}),
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
    int brojVoznji = 0,
  }) async {
    final safePutnikId = putnikId.trim();
    if (safePutnikId.isEmpty) {
      throw ArgumentError('putnikId je obavezan.');
    }
    if (iznos <= 0) {
      throw ArgumentError('Iznos naplate mora biti veći od nule.');
    }

    final lockKey = _getLockKey(safePutnikId, mesec, godina);
    if (_mesecnaNaplataLocks.contains(lockKey)) {
      debugPrint('[V3FinansijeService] sacuvajMesecnuNaplatu skipped (lock): $lockKey');
      return;
    }
    _mesecnaNaplataLocks.add(lockKey);

    try {
      final cache = V3MasterRealtimeManager.instance.getCache('v3_finansije').values;
      final existing = cache.where((row) {
        final rPutnikId = (row['putnik_v3_auth_id']?.toString() ?? '').trim().toLowerCase();
        if (rPutnikId != safePutnikId.toLowerCase()) return false;
        final rG = _parseInternalInt(row['godina']);
        final rM = _parseInternalInt(row['mesec']);
        if (rG != godina || rM != mesec) return false;
        // Širimo pretragu na bilo koji prihodni red za ovog putnika/mesec
        return (row['tip']?.toString().toLowerCase() ?? '') == 'prihod';
      }).toList();

      Map<String, dynamic> row;
      if (existing.isNotEmpty) {
        _sortByCreatedAtDesc(existing);
        final latest = existing.first;
        final existingId = (latest['id']?.toString() ?? '').trim();
        if (existingId.isEmpty) {
          throw StateError('Master red za finansije nema validan ID');
        }

        final currentIznos = (latest['iznos'] as num?)?.toDouble() ?? 0.0;
        final currentBrojVoznji = (latest['broj_voznji'] as num?)?.toInt() ?? 0;
        // Broj vožnji se ne menja pri plaćanju - samo pri pokupljanju (evidentirajRealizacijuPriPokupljanju)
        // Zadržavamo trenutnu vrednost da ne bi smanjili broj vožnji ako se u međuvremenu povećao
        final finalBrojVoznji = currentBrojVoznji;

        row = await _repo.updateByIdReturning(existingId, {
          'iznos': currentIznos + iznos,
          'poslednja_dopuna': iznos, // Čuvamo iznos poslednje dopune
          'naplaceno_by': naplacenoBy,
          'broj_voznji': finalBrojVoznji,
          'updated_at': DateTime.now().toIso8601String(),
          'dogadjaj_id': _uuid.v4(),
        });
      } else {
        row = await _repo.insertReturning({
          'naziv': 'Evidencija prevoza $mesec/$godina',
          'kategorija': _masterKategorija(),
          'tip': 'prihod',
          'iznos': iznos,
          'poslednja_dopuna': iznos, // Prva uplata je ujedno i poslednja dopuna
          'putnik_v3_auth_id': safePutnikId,
          'dogadjaj_id': _uuid.v4(),
          'naplaceno_by': naplacenoBy,
          'broj_voznji': brojVoznji,
          'mesec': mesec,
          'godina': godina,
        });
      }

      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_finansije', row);
      
      // Dodaj evidenciju u v3_vozac_akcije tabelu
      try {
        final rm = V3MasterRealtimeManager.instance;
        final vozacData = rm.vozaciCache[naplacenoBy];
        final vozacIme = vozacData?['ime_prezime']?.toString() ?? 'Nepoznat vozač';
        final putnikData = rm.putniciCache[safePutnikId];
        final putnikIme = putnikData?['ime_prezime']?.toString() ?? 'Nepoznat putnik';
        
        await V3VozacAkcijeService.evidentirajNaplata(
          vozacId: naplacenoBy,
          vozacIme: vozacIme,
          putnikId: safePutnikId,
          putnikIme: putnikIme,
          iznos: iznos,
          datum: DateTime.now(), // Datum naplate
          evidentiraoBy: naplacenoBy,
        );
      } catch (e) {
        debugPrint('[V3FinansijeService] Greška pri evidentiranju naplata u v3_vozac_akcije: $e');
      }
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
    return sacuvajMesecnuNaplatu(
      putnikId: putnikId,
      naplacenoBy: naplacenoBy,
      iznos: iznos,
      mesec: datum.month,
      godina: datum.year,
      brojVoznji: 0,
    );
  }
}
