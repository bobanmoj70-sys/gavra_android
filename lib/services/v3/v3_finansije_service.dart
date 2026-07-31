import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../models/v3_dug.dart';
import '../../models/v3_finansije.dart';
import '../../utils/v3_belgrade_time.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_finansije_repository.dart';

/// Status naplate putnika za konkretnu vožnju/mesec.
enum V3NaplataStatus {
  nemaUplate,
  potpunoPlacen,
}

class V3NaplataInfo {
  final V3NaplataStatus status;
  final double ukupanIznos;
  final double poslednjaDopuna;
  final double dug;
  final DateTime? paidAt;
  final String? paidBy;
  final DateTime? updatedAt;
  final String? updatedBy;
  final DateTime? uplataAt;

  /// Da li postoji bilo kakva uplata.
  bool get imaUplatu => ukupanIznos > 0.009;

  /// Da li je dug u potpunosti izmiren.
  bool get isPaid => status == V3NaplataStatus.potpunoPlacen;

  const V3NaplataInfo({
    required this.status,
    required this.ukupanIznos,
    required this.poslednjaDopuna,
    this.dug = 0.0,
    this.paidAt,
    this.paidBy,
    this.updatedAt,
    this.updatedBy,
    this.uplataAt,
  });
}

class V3FinansijeService {
  V3FinansijeService._();
  static const Uuid _uuid = Uuid();
  static const String _nenaplaceneVoznjeKey = 'nenaplacene_voznje_json';
  static const String _realizovaneVoznjeKey = 'realizovane_voznje_json';
  static const String _otkazaneVoznjeKey = 'otkazane_voznje_json';
  static const String _uplateKey = 'uplate_json';
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
    return V3BelgradeTime.parseTs(row['created_at']?.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  static DateTime? _naplacenoAt(Map<String, dynamic> row) {
    // Koristimo updated_at za datum poslednje dopune
    final ts = row['updated_at'];
    return V3BelgradeTime.parseTs(ts?.toString());
  }

  static DateTime? _readLastUplata(Map<String, dynamic> row) {
    final uplate = _readUplate(row);
    if (uplate.isEmpty) return null;
    final last = uplate.last;
    return V3BelgradeTime.parseTs(last['datum']?.toString());
  }

  /// Iznos poslednje pojedinačne uplate, izveden isključivo iz uplate_json.
  static double _readPosledjaDopuna(Map<String, dynamic> row) {
    final uplate = _readUplate(row);
    if (uplate.isEmpty) return 0.0;
    return (uplate.last['iznos'] as num?)?.toDouble() ?? 0.0;
  }

  /// Ukupan iznos svih uplata iz uplate_json (jedini izvor istine).
  static double _getUkupanIznosUplata(Map<String, dynamic> row) {
    final uplate = _readUplate(row);
    if (uplate.isEmpty) return 0.0;
    return uplate.fold<double>(0.0, (sum, u) => sum + ((u['iznos'] as num?)?.toDouble() ?? 0.0));
  }

  /// Ko je poslednji uplatio, izvedeno isključivo iz uplate_json.
  static String? _getNaplatioBy(Map<String, dynamic> row) {
    final uplate = _readUplate(row);
    if (uplate.isEmpty) return null;
    final last = uplate.last;
    final naplatioBy = last['naplatio_by']?.toString().trim();
    return naplatioBy?.isEmpty ?? true ? null : naplatioBy;
  }

  static void _sortByCreatedAtDesc(List<Map<String, dynamic>> rows) {
    rows.sort((a, b) => _createdAtOrEpoch(b).compareTo(_createdAtOrEpoch(a)));
  }

  static double _resolveCenaZaPutnik(String putnikId, {String? fallbackTip}) {
    final rm = V3MasterRealtimeManager.instance;
    final putnik = rm.putniciCache[putnikId];
    final tip =
        (putnik?['tip_putnika']?.toString() ?? putnik?['tip']?.toString() ?? fallbackTip ?? '').trim().toLowerCase();
    final cenaPoDanu = (putnik?['cena_po_danu'] as num?)?.toDouble() ?? 0.0;
    final cenaPoPokupljenju = (putnik?['cena_po_pokupljenju'] as num?)?.toDouble() ?? 0.0;
    return _cenaZaTip(
      tip: tip,
      cenaPoDanu: cenaPoDanu,
      cenaPoPokupljenju: cenaPoPokupljenju,
    );
  }

  static String _resolveOperativnaStavkaId({
    required String putnikId,
    required DateTime datum,
    required String operativnaId,
    required bool isPoDanu,
  }) {
    final safeOperativnaId = operativnaId.trim();
    if (safeOperativnaId.isNotEmpty) return safeOperativnaId;
    if (isPoDanu) {
      final danIso = V3BelgradeTime.toIsoDate(datum);
      return 'auto:${putnikId.trim().toLowerCase()}:$danIso';
    }
    return 'auto:${_uuid.v4()}';
  }

  static List<Map<String, dynamic>> _readNenaplaceneVoznje(Map<String, dynamic> row) {
    final raw = row[_nenaplaceneVoznjeKey];
    final result = <Map<String, dynamic>>[];

    try {
      Iterable<dynamic> src;
      if (raw is List) {
        src = raw;
      } else if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is! List) return result;
        src = decoded;
      } else {
        return result;
      }

      for (final item in src) {
        if (item is! Map) continue;
        final operativnaId = (item['operativna_id']?.toString() ?? '').trim();
        final datum = item['datum']?.toString();
        final cena = (item['cena'] as num?)?.toDouble() ?? 0.0;
        if (operativnaId.isEmpty || datum == null || datum.isEmpty) continue;
        result.add({
          'operativna_id': operativnaId,
          'datum': datum,
          'cena': cena,
        });
      }
    } catch (_) {
      return result;
    }

    result.sort((a, b) => _parseNenaplacenaDatumOrEpoch(a).compareTo(_parseNenaplacenaDatumOrEpoch(b)));
    return result;
  }

  static List<Map<String, dynamic>> _appendNenaplacenaVoznja({
    required List<Map<String, dynamic>> stavke,
    required String operativnaId,
    required DateTime datum,
    required double cena,
  }) {
    final safeOperativnaId = operativnaId.trim();
    if (safeOperativnaId.isEmpty) return stavke;
    if (stavke.any((s) => (s['operativna_id']?.toString() ?? '').trim() == safeOperativnaId)) {
      return stavke;
    }

    final updated = List<Map<String, dynamic>>.from(stavke);
    updated.add({
      'operativna_id': safeOperativnaId,
      'datum': V3BelgradeTime.toIsoDate(datum),
      'cena': cena,
    });
    updated.sort((a, b) => _parseNenaplacenaDatumOrEpoch(a).compareTo(_parseNenaplacenaDatumOrEpoch(b)));
    return updated;
  }

  static bool _containsNenaplacenaForDay({
    required List<Map<String, dynamic>> stavke,
    required DateTime datum,
  }) {
    final targetDay = V3BelgradeTime.toIsoDate(datum);
    if (targetDay.isEmpty) return false;
    return stavke.any((stavka) {
      final stavkaDay = V3BelgradeTime.parseIsoDatePart(stavka['datum']?.toString() ?? '');
      return stavkaDay == targetDay;
    });
  }

  /// Iznos trenutnog "viška" (kredita/preplate) na master redu, koji se troši
  /// pre nego što se generiše nova stavka duga za narednu vožnju.
  static double _readVisak(Map<String, dynamic> row) => (row['visak_iznos'] as num?)?.toDouble() ?? 0.0;

  /// Rezultat trošenja nenaplaćenih stavki nakon uplate: preostale nenaplaćene
  /// stavke i eventualan "preostatak" uplate koji nije mogao da se iskoristi
  /// (jer je iznos veći od svih nenaplaćenih vožnji) — taj preostatak postaje
  /// višak/kredit, umesto da se izgubi.
  ///
  /// Delimična uplata (manja od cene prve stavke) umanjuje cenu te stavke;
  /// ne odbacuje se novac dok dug postoji.
  static ({List<Map<String, dynamic>> stavke, double preostalo}) _consumeNenaplaceneVoznje({
    required List<Map<String, dynamic>> stavke,
    required double uplacenIznos,
    required double defaultCena,
  }) {
    var preostalo = uplacenIznos;
    final queue = List<Map<String, dynamic>>.from(stavke)
      ..sort((a, b) => _parseNenaplacenaDatumOrEpoch(a).compareTo(_parseNenaplacenaDatumOrEpoch(b)));

    while (queue.isNotEmpty && preostalo > 0.009) {
      final first = Map<String, dynamic>.from(queue.first);
      final rawCena = (first['cena'] as num?)?.toDouble() ?? 0.0;
      final cenaStavke = rawCena > 0.009 ? rawCena : defaultCena;
      if (cenaStavke <= 0.009) break;

      if (preostalo + 0.009 >= cenaStavke) {
        // Puna otplata stavke
        preostalo -= cenaStavke;
        queue.removeAt(0);
        continue;
      }

      // Delimična uplata: smanji preostalu cenu stavke, ne gubi novac.
      first['cena'] = cenaStavke - preostalo;
      queue[0] = first;
      preostalo = 0;
      break;
    }

    // preostalo > 0 samo kada su sve stavke pokrivene → postaje visak_iznos.
    return (stavke: queue, preostalo: preostalo);
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

  /// Vraca sve troškove za trenutni mesec iz cache-a (v3_finansije)
  static List<V3Trosak> getTroskoviMesec({int? mesec, int? godina}) {
    final now = V3BelgradeTime.now();
    final m = mesec ?? now.month;
    final g = godina ?? now.year;
    final cache = V3MasterRealtimeManager.instance.getCache('v3_finansije');
    return cache.values
        .where((r) => r['tip'] == 'rashod' && r['mesec'] == m && r['godina'] == g)
        .map((r) => V3Trosak.fromJson(r))
        .toList()
      ..sort((a, b) => (b.createdAt ?? V3BelgradeTime.now()).compareTo(a.createdAt ?? V3BelgradeTime.now()));
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

    // Ukupan iznos se izvodi isključivo iz uplate_json (jedini izvor istine).
    final ukupanIznos = _getUkupanIznosUplata(latest);
    final poslednjaDopuna = _readPosledjaDopuna(latest);

    return V3NaplataInfo(
      status: _resolveNaplataStatus(latest),
      ukupanIznos: ukupanIznos,
      poslednjaDopuna: poslednjaDopuna,
      paidAt: _naplacenoAt(latest),
      paidBy: _getNaplatioBy(latest),
      updatedAt: V3BelgradeTime.parseTs(latest['updated_at']?.toString()),
      updatedBy: latest['updated_by']?.toString(),
      uplataAt: _readLastUplata(latest),
    );
  }

  static V3NaplataInfo? getLatestNaplataForPutnik(String putnikId) {
    final putnik = putnikId.trim();
    if (putnik.isEmpty) return null;

    DateTime? latestUplataDatum;
    Map<String, dynamic>? latestUplata;
    Map<String, dynamic>? latestRow;

    for (final row in _naplataRows()) {
      final rPutnikId = (row['putnik_v3_auth_id']?.toString() ?? '').trim().toLowerCase();
      if (rPutnikId != putnik.toLowerCase()) continue;

      final uplate = _readUplate(row);
      if (uplate.isEmpty) continue;

      for (final uplata in uplate) {
        final datum = V3BelgradeTime.parseTs(uplata['datum']?.toString());
        if (datum == null) continue;
        if (latestUplataDatum == null || datum.isAfter(latestUplataDatum)) {
          latestUplataDatum = datum;
          latestUplata = uplata;
          latestRow = row;
        }
      }
    }

    if (latestUplata == null || latestRow == null) return null;

    final ukupanIznos = _getUkupanIznosUplata(latestRow);
    final poslednjaDopuna = (latestUplata['iznos'] as num?)?.toDouble() ?? 0.0;

    return V3NaplataInfo(
      status: _resolveNaplataStatus(latestRow),
      ukupanIznos: ukupanIznos,
      poslednjaDopuna: poslednjaDopuna,
      paidAt: latestUplataDatum,
      paidBy: latestUplata['naplatio_by']?.toString(),
      updatedAt: V3BelgradeTime.parseTs(latestRow['updated_at']?.toString()),
      updatedBy: latestRow['updated_by']?.toString(),
      uplataAt: latestUplataDatum,
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

    var ukupanIznos = 0.0;

    final rm = V3MasterRealtimeManager.instance;
    // Case-insensitive lookup — keš ključ je id iz auth, ali filter redova
    // poredi lower-case; tip mora biti pouzdan radi po-danu brojanja.
    final putnikData = rm.putniciCache[putnik] ??
        rm.putniciCache[putnik.toLowerCase()] ??
        rm.putniciCache.entries
            .where((e) => e.key.toLowerCase() == putnik.toLowerCase())
            .map((e) => e.value)
            .firstOrNull ??
        const <String, dynamic>{};
    final tipPutnika = (putnikData['tip_putnika'] as String? ?? putnikData['tip'] as String? ?? '').toLowerCase();
    final isPoDanu = _isPoDanuTip(tipPutnika);

    // Brojanje preko SVIH redova meseca (ne po redu pa zbir): race trigger/app
    // često pravi 2 reda.
    // Faza 1 JSON-only: skalar broj_voznji se više ne čita (legacy deprecated).
    final uniqueDani = <String>{};
    final uniqueOperativna = <String>{};
    var brojBezId = 0;
    var brojNenaplacenihStavki = 0;

    for (final row in naplataRows) {
      ukupanIznos += _getUkupanIznosUplata(row);
      brojNenaplacenihStavki += _readNenaplaceneVoznje(row).length;

      final voznje = _readRealizovaneVoznje(row);
      for (final v in voznje) {
        if (isPoDanu) {
          final dan = V3BelgradeTime.parseIsoDatePart(v['datum']?.toString() ?? '');
          if (dan.isNotEmpty) uniqueDani.add(dan);
        } else {
          final id = (v['operativna_id']?.toString() ?? '').trim();
          if (id.isNotEmpty) {
            uniqueOperativna.add(id);
          } else {
            brojBezId++;
          }
        }
      }
    }

    final brojVoznjiRealizacija = isPoDanu ? uniqueDani.length : uniqueOperativna.length + brojBezId;

    // Izvor istine isključivo JSON kolone:
    // 1) nenaplacene_voznje_json — preostale naplative jedinice (dug)
    // 2) realizovane_voznje_json — arhiva unique dan / operativna_id
    // max: nepotpuna arhiva ne sme spustiti broj ispod nena stavki
    // (npr. 2 nena isti dan → 2 jedinice; ili plaćeno pa nena prazna → real).
    final brojVoznji = brojVoznjiRealizacija > brojNenaplacenihStavki ? brojVoznjiRealizacija : brojNenaplacenihStavki;

    return (brojVoznji: brojVoznji, ukupanIznos: ukupanIznos);
  }

  /// Vraća stvarni nenaplaćeni iznos (dug) za putnika u zadatom periodu,
  /// izveden iz istorijskih cena po vožnji sačuvanih u nenaplacene_voznje_json.
  ///
  /// Ovo je precizniji izvor za dug od "brojVoznji * trenutnaCena", јер свакa
  /// ставка чува цену која је била важећа у тренутку пokuplјања те воžње.
  /// Ако се цена путника промени током месеца, овај обрачун остаје исправан.
  static double getNenaplacenIznosForPutnik({
    required String putnikId,
    int? godina,
    int? mesec,
  }) {
    final putnik = putnikId.trim();
    if (putnik.isEmpty) return 0.0;

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

    var ukupno = 0.0;
    for (final row in naplataRows) {
      for (final stavka in _readNenaplaceneVoznje(row)) {
        ukupno += (stavka['cena'] as num?)?.toDouble() ?? 0.0;
      }
    }
    return ukupno;
  }

  /// Vraća број преосталих ненаплаћених воžњи (ставки) за путника у периоду.
  /// Свакa ставка у ненaplacене_voznje_json одговара једној воžњи (или једном
  /// дану за тип радник/ученик, поšto се за тај модел додаје само једна
  /// ставка по дану). Ово је прецизнији броjaч од "бројВожњи - уплаћено/цена",
  /// јер се не ослања на просечну/тренутну цену.
  static int getNenaplacenBrojVoznjiForPutnik({
    required String putnikId,
    int? godina,
    int? mesec,
  }) {
    final putnik = putnikId.trim();
    if (putnik.isEmpty) return 0;

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

    var ukupno = 0;
    for (final row in naplataRows) {
      ukupno += _readNenaplaceneVoznje(row).length;
    }
    return ukupno;
  }

  /// Vraća укпан "вишак" (кредит/преплату) за путника у задатом периоду —
  /// новац који је уплаћен унапред, а још није искоришћен на ниједну воžњу.
  static double getVisakIznosForPutnik({
    required String putnikId,
    int? godina,
    int? mesec,
  }) {
    final putnik = putnikId.trim();
    if (putnik.isEmpty) return 0.0;

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

    var ukupno = 0.0;
    for (final row in naplataRows) {
      ukupno += _readVisak(row);
    }
    return ukupno;
  }

  /// Pronalazi hronološki poslednji master red za putnika STROGO pre
  /// zadatog (godina, mesec) — koristi se za prenos viška u novi mesec.
  static Map<String, dynamic>? _findPrethodniRed({
    required String putnikId,
    required int godina,
    required int mesec,
  }) {
    final target = godina * 12 + mesec;
    Map<String, dynamic>? best;
    var bestKey = -1;
    for (final row in _naplataRows()) {
      final rPutnikId = (row['putnik_v3_auth_id']?.toString() ?? '').trim().toLowerCase();
      if (rPutnikId != putnikId.trim().toLowerCase()) continue;
      final rG = _parseInternalInt(row['godina']);
      final rM = _parseInternalInt(row['mesec']);
      if (rG == null || rM == null) continue;
      final key = rG * 12 + rM;
      if (key >= target) continue;
      if (key > bestKey) {
        bestKey = key;
        best = row;
      }
    }
    return best;
  }

  static Future<void> evidentirajRealizacijuPriPokupljanju({
    required String putnikId,
    required String tipPutnika,
    required DateTime datum,
    String? operativnaId,
    String? evidentiraoBy,
    String? pokupljenAt,
    String? dodaoBy,
    String? azuriraoBy,
    String? grad,
    String? vreme,
  }) async {
    final safePutnikId = putnikId.trim();
    if (safePutnikId.isEmpty) return;

    final tip = tipPutnika.trim().toLowerCase();
    if (tip == 'vozac') return;

    final isPoDanu = _isPoDanuTip(tip);
    final safeOperativnaId = (operativnaId ?? '').trim();

    final lockKey = '${_getLockKey(safePutnikId, datum.month, datum.year)}:pokupljanje';
    if (_mesecnaNaplataLocks.contains(lockKey)) {
      debugPrint('[V3FinansijeService] evidentirajRealizacijuPriPokupljanju skipped (lock): $lockKey');
      throw StateError('Evidencija pokupljanja je već u toku, sačekajte trenutak.');
    }
    _mesecnaNaplataLocks.add(lockKey);

    final cache = V3MasterRealtimeManager.instance.getCache('v3_finansije').values;
    final cenaVoznje = _resolveCenaZaPutnik(safePutnikId, fallbackTip: tip);

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
          final danIso = V3BelgradeTime.toIsoDate(datum);
          final opCache = V3MasterRealtimeManager.instance.getCache('v3_operativna_nedelja');
          final vecVozioDanas = opCache.values.any((r) {
            final rPutnikId = (r['created_by']?.toString() ?? '').trim().toLowerCase();
            if (rPutnikId != safePutnikId.toLowerCase()) return false;

            final rDanIso = V3BelgradeTime.parseIsoDatePart(r['datum']?.toString() ?? '');
            if (rDanIso != danIso) return false;

            if (r['pokupljen_at'] == null) return false;

            // Trenutna operativna stavka ne tretira se kao "već vozio danas",
            // inače bi prvo pokupljanje dana bilo preskočeno.
            if (safeOperativnaId.isNotEmpty) {
              final rOperativnaId = (r['id']?.toString() ?? '').trim();
              if (rOperativnaId == safeOperativnaId) return false;
            }

            return true;
          });
          if (vecVozioDanas) return;
        }

        if (latestId.isNotEmpty) {
          final operativnaId = _resolveOperativnaStavkaId(
            putnikId: safePutnikId,
            datum: datum,
            operativnaId: safeOperativnaId,
            isPoDanu: isPoDanu,
          );
          final currentNenaplacene = _readNenaplaceneVoznje(latest);
          if (isPoDanu && _containsNenaplacenaForDay(stavke: currentNenaplacene, datum: datum)) {
            return;
          }
          // Prvo pokušaj da pokriješ cenu ove vožnje iz postojećeg viška
          // (kredita/preplate) pre nego što se doda nova stavka duga. Ako je
          // putnik već platio unapred, nova vožnja se ne tretira kao dug dok
          // god ima pokrića u višku.
          final trenutniVisak = _readVisak(latest);
          final preostalaCena = (cenaVoznje - trenutniVisak) > 0.009 ? cenaVoznje - trenutniVisak : 0.0;
          final noviVisak = (trenutniVisak - cenaVoznje) > 0.009 ? trenutniVisak - cenaVoznje : 0.0;

          final updatedNenaplacene = preostalaCena > 0.009
              ? _appendNenaplacenaVoznja(
                  stavke: currentNenaplacene,
                  operativnaId: operativnaId,
                  datum: datum,
                  cena: preostalaCena,
                )
              : currentNenaplacene;
          // NAPOMENA: Ovde se NE dodaje lažna "uplata" u uplate_json — vožnja se
          // evidentira kao NENAPLAĆENA (currentNenaplacene/updatedNenaplacene) i
          // stvarni zapis o uplati se pravi tek kada putnik zaista plati
          // (vidi sacuvajMesecnuNaplatu). Ranije se ovde dodavao lažni uplata
          // zapis sa vremenom pokupljanja, zbog čega je "vreme naplate" u UI-u
          // pogrešno prikazivalo isto vreme kao pokupljanje.
          //
          // realizovane_voznje_json se više ne popunjava ovde — održava je
          // database trigger v3_sync_realizovane_voznje_to_finansije.
          final updatePayload = <String, dynamic>{
            _nenaplaceneVoznjeKey: updatedNenaplacene,
            'visak_iznos': noviVisak,
            'updated_at': V3BelgradeTime.nowIsoUtc(),
          };
          final updated = await _repo.updateByIdReturning(latestId, updatePayload);
          V3MasterRealtimeManager.instance.v3UpsertToCache('v3_finansije', updated);
          return;
        }
      }

      // 2. Ako ne postoji red, kreiraj novi master red
      final operativnaId = _resolveOperativnaStavkaId(
        putnikId: safePutnikId,
        datum: datum,
        operativnaId: safeOperativnaId,
        isPoDanu: isPoDanu,
      );

      // Prenesi eventualni višak (kredit) iz prethodnog meseca — ako je
      // putnik preplatio prošli mesec, taj višak prvo pokriva ovu (prvu)
      // vožnju novog meseca pre nego što se ona upiše kao dug.
      final prethodniRed = _findPrethodniRed(
        putnikId: safePutnikId,
        godina: datum.year,
        mesec: datum.month,
      );
      final prenetiVisak = prethodniRed != null ? _readVisak(prethodniRed) : 0.0;
      final preostalaCenaNoviMesec = (cenaVoznje - prenetiVisak) > 0.009 ? cenaVoznje - prenetiVisak : 0.0;
      final noviVisakNoviMesec = (prenetiVisak - cenaVoznje) > 0.009 ? prenetiVisak - cenaVoznje : 0.0;

      if (prethodniRed != null && prenetiVisak > 0.009) {
        final prethodniId = (prethodniRed['id'] ?? '').toString();
        if (prethodniId.isNotEmpty) {
          final updatedPrethodni = await _repo.updateByIdReturning(prethodniId, {
            'visak_iznos': 0,
            'updated_at': V3BelgradeTime.nowIsoUtc(),
          });
          V3MasterRealtimeManager.instance.v3UpsertToCache('v3_finansije', updatedPrethodni);
        }
      }

      final row = await _repo.insertReturning({
        'naziv': 'Evidencija prevoza ${datum.month}/${datum.year}',
        'kategorija': _masterKategorija(),
        'tip': 'prihod',
        'iznos': 0,
        'putnik_v3_auth_id': safePutnikId,
        _nenaplaceneVoznjeKey: preostalaCenaNoviMesec > 0.009
            ? [
                {
                  'operativna_id': operativnaId,
                  'datum': V3BelgradeTime.toIsoDate(datum),
                  'cena': preostalaCenaNoviMesec,
                }
              ]
            : <Map<String, dynamic>>[],
        'visak_iznos': noviVisakNoviMesec,
        'mesec': datum.month,
        'godina': datum.year,
      });
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_finansije', row);
    } finally {
      _mesecnaNaplataLocks.remove(lockKey);
    }
  }

  /// Vraća ukupan pazar (naplaćeno) po vozaču za zadati dan, na osnovu
  /// uplate_json stavki čiji dan naplate (naplatio_at, ili datum ako
  /// naplatio_at nedostaje) odgovara zadatom danu. Ključ mape je vozacId
  /// (naplatio_by), vrednost je ukupan naplaćen iznos tog dana.
  static Map<String, double> getPazarPoVozacuZaDan(DateTime dan) {
    final result = <String, double>{};
    final datumIso = V3BelgradeTime.toIsoDate(dan);

    for (final row in _naplataRows()) {
      for (final uplata in _readUplate(row)) {
        final naplatioAtRaw = (uplata['naplatio_at']?.toString() ?? '').trim();
        final dayIso = naplatioAtRaw.isNotEmpty
            ? V3BelgradeTime.parseIsoDatePart(naplatioAtRaw)
            : V3BelgradeTime.parseIsoDatePart(uplata['datum']?.toString() ?? '');
        if (dayIso != datumIso) continue;

        final naplatioBy = (uplata['naplatio_by']?.toString() ?? '').trim();
        if (naplatioBy.isEmpty) continue;

        final iznos = (uplata['iznos'] as num?)?.toDouble() ?? 0.0;
        result[naplatioBy] = (result[naplatioBy] ?? 0.0) + iznos;
      }
    }

    return result;
  }

  /// Vraća ukupan dug za zadati dan — zbir nenaplaćenih vožnji (cena) čiji
  /// je datum jednak zadatom danu, samo za putnike tipa "dnevni" i
  /// "posiljka" (naplata po pokupljenju, pa dug postoji odmah istog dana).
  static double getDugZaDan(DateTime dan) {
    final rm = V3MasterRealtimeManager.instance;
    final datumIso = V3BelgradeTime.toIsoDate(dan);
    var ukupno = 0.0;

    for (final row in _naplataRows()) {
      final putnikId = (row['putnik_v3_auth_id']?.toString() ?? '').trim();
      if (putnikId.isEmpty) continue;

      final putnikData = rm.putniciCache[putnikId] ??
          rm.putniciCache.entries
              .where((e) => e.key.toLowerCase() == putnikId.toLowerCase())
              .map((e) => e.value)
              .firstOrNull;
      final tip = (putnikData?['tip_putnika'] as String? ?? '').toLowerCase();
      if (tip != 'dnevni' && tip != 'posiljka') continue;

      for (final stavka in _readNenaplaceneVoznje(row)) {
        final stavkaDan = V3BelgradeTime.parseIsoDatePart(stavka['datum']?.toString() ?? '');
        if (stavkaDan != datumIso) continue;
        ukupno += (stavka['cena'] as num?)?.toDouble() ?? 0.0;
      }
    }

    return ukupno;
  }

  /// Vraća sve naplate (uplate) koje je vozač naplatio na zadati dan, iz
  /// arhive v3_finansije (uplate_json). Svaka stavka sadrži: iznos,
  /// naplatio_at, putnik_v3_auth_id, naziv (fallback ime iz master reda).
  static List<Map<String, dynamic>> getNaplataRowsZaVozacaDan({
    required String vozacId,
    required DateTime dan,
  }) {
    final id = vozacId.trim();
    if (id.isEmpty) return <Map<String, dynamic>>[];
    final idLower = id.toLowerCase();
    final datumIso = V3BelgradeTime.toIsoDate(dan);

    final result = <Map<String, dynamic>>[];
    for (final row in _naplataRows()) {
      for (final uplata in _readUplate(row)) {
        final naplatioBy = (uplata['naplatio_by']?.toString() ?? '').trim().toLowerCase();
        if (naplatioBy != idLower) continue;

        final naplatioAtRaw = (uplata['naplatio_at']?.toString() ?? '').trim();
        final dayIso = naplatioAtRaw.isNotEmpty
            ? V3BelgradeTime.parseIsoDatePart(naplatioAtRaw)
            : V3BelgradeTime.parseIsoDatePart(uplata['datum']?.toString() ?? '');
        if (dayIso != datumIso) continue;

        result.add({
          ...uplata,
          'putnik_v3_auth_id': row['putnik_v3_auth_id']?.toString(),
          'naziv': row['naziv']?.toString(),
          'uplata_datum': uplata['datum']?.toString(),
          'updated_at': row['updated_at']?.toString(),
          'finansije_id': row['id']?.toString(),
        });
      }
    }

    result.sort((a, b) {
      final aDt = V3BelgradeTime.parseTs(a['naplatio_at']?.toString()) ?? V3BelgradeTime.now();
      final bDt = V3BelgradeTime.parseTs(b['naplatio_at']?.toString()) ?? V3BelgradeTime.now();
      return aDt.compareTo(bDt);
    });

    return result;
  }

  /// Vraća sve vožnje koje je vozač pokupio na zadati dan iz arhive v3_finansije.
  static List<Map<String, dynamic>> getPokupljeniPutniciZaVozacaDan({
    required String vozacId,
    required DateTime dan,
  }) {
    final id = vozacId.trim();
    if (id.isEmpty) return <Map<String, dynamic>>[];
    final idLower = id.toLowerCase();

    final datumIso = V3BelgradeTime.toIsoDate(dan);
    final result = <Map<String, dynamic>>[];
    final seenOperativnaIds = <String>{};

    for (final row in _naplataRows()) {
      final realizovane = _readRealizovaneVoznje(row);
      for (final voznja in realizovane) {
        final voznjaDatumIso = V3BelgradeTime.parseIsoDatePart(voznja['datum']?.toString() ?? '');
        final pokupljenAtIso = V3BelgradeTime.parseIsoDatePart(voznja['pokupljen_at']?.toString() ?? '');
        if (pokupljenAtIso != datumIso && voznjaDatumIso != datumIso) continue;
        final pokupljenBy = (voznja['pokupljen_by']?.toString() ?? '').trim().toLowerCase();
        if (pokupljenBy != idLower) continue;

        final operativnaId = (voznja['operativna_id']?.toString() ?? '').trim();
        if (operativnaId.isNotEmpty && !seenOperativnaIds.add(operativnaId)) continue;

        result.add({
          ...voznja,
          'putnik_v3_auth_id': row['putnik_v3_auth_id']?.toString(),
          'finansije_id': row['id']?.toString(),
        });
      }
    }

    // Fallback: ako arhiva realizovanih vožnji kasni/ne sadrži stavke,
    // preuzmi pokupljene vožnje direktno iz operativne cache za isti dan.
    final operCache = V3MasterRealtimeManager.instance.operativnaNedeljaCache.values;
    for (final operRow in operCache) {
      final pokupljenBy = (operRow['pokupljen_by']?.toString() ?? '').trim().toLowerCase();
      if (pokupljenBy != idLower) continue;

      final pokupljenAtIso = V3BelgradeTime.parseIsoDatePart(operRow['pokupljen_at']?.toString() ?? '');
      final operDatumIso = V3BelgradeTime.parseIsoDatePart(operRow['datum']?.toString() ?? '');
      if (pokupljenAtIso != datumIso && operDatumIso != datumIso) continue;

      final operativnaId = (operRow['id']?.toString() ?? '').trim();
      if (operativnaId.isNotEmpty && !seenOperativnaIds.add(operativnaId)) continue;

      result.add({
        'operativna_id': operativnaId,
        'datum': operRow['datum']?.toString(),
        'pokupljen_by': operRow['pokupljen_by']?.toString(),
        'pokupljen_at': operRow['pokupljen_at']?.toString(),
        'dodao_by': operRow['dodao_by']?.toString(),
        'azurirao_by': operRow['azurirao_by']?.toString(),
        'grad': operRow['grad']?.toString(),
        'vreme': operRow['vreme']?.toString(),
        'putnik_v3_auth_id': operRow['created_by']?.toString(),
        'finansije_id': null,
      });
    }

    result.sort((a, b) {
      final aDt = V3BelgradeTime.parseTs(a['pokupljen_at']?.toString()) ?? _parseNenaplacenaDatumOrEpoch(a);
      final bDt = V3BelgradeTime.parseTs(b['pokupljen_at']?.toString()) ?? _parseNenaplacenaDatumOrEpoch(b);
      return aDt.compareTo(bDt);
    });

    return result;
  }

  /// Vraća све vožnje које је возаč uneо/azurirao на задати дан из arhive v3_finansije.
  static List<Map<String, dynamic>> getDodatiPutniciZaVozacaDan({
    required String vozacId,
    required DateTime dan,
  }) {
    final id = vozacId.trim();
    if (id.isEmpty) return <Map<String, dynamic>>[];

    final datumIso = V3BelgradeTime.toIsoDate(dan);
    final result = <Map<String, dynamic>>[];

    for (final row in _naplataRows()) {
      final realizovane = _readRealizovaneVoznje(row);
      for (final voznja in realizovane) {
        final voznjaDatumIso = V3BelgradeTime.parseIsoDatePart(voznja['datum']?.toString() ?? '');
        if (voznjaDatumIso != datumIso) continue;
        final dodaoBy = (voznja['dodao_by']?.toString() ?? '').trim();
        final azuriraoBy = (voznja['azurirao_by']?.toString() ?? '').trim();
        if (dodaoBy != id && azuriraoBy != id) continue;
        result.add({
          ...voznja,
          'putnik_v3_auth_id': row['putnik_v3_auth_id']?.toString(),
          'finansije_id': row['id']?.toString(),
        });
      }
    }

    return result;
  }

  /// Vraća све воžње које је возаč otkazao на задати дан из архиве v3_finansije.
  static List<Map<String, dynamic>> getOtkazaneVoznjeZaVozacaDan({
    required String vozacId,
    required DateTime dan,
  }) {
    final id = vozacId.trim();
    if (id.isEmpty) return <Map<String, dynamic>>[];

    final datumIso = V3BelgradeTime.toIsoDate(dan);
    final result = <Map<String, dynamic>>[];

    for (final row in _naplataRows()) {
      final otkazane = _readOtkazaneVoznje(row);
      for (final voznja in otkazane) {
        final voznjaDatumIso = V3BelgradeTime.parseIsoDatePart(voznja['datum']?.toString() ?? '');
        if (voznjaDatumIso != datumIso) continue;
        if ((voznja['otkazao_by']?.toString() ?? '').trim() != id) continue;
        result.add({
          ...voznja,
          'putnik_v3_auth_id': row['putnik_v3_auth_id']?.toString(),
          'finansije_id': row['id']?.toString(),
        });
      }
    }

    return result;
  }

  static Set<(int, int)> getNaplataMeseciForPutnik(String putnikId) {
    final putnik = putnikId.trim();
    if (putnik.isEmpty) return <(int, int)>{};
    final putnikLower = putnik.toLowerCase();

    final meseci = <(int, int)>{};
    final rows = _naplataRows();

    for (final row in rows) {
      final rPutnikId = (row['putnik_v3_auth_id']?.toString() ?? '').trim().toLowerCase();
      if (rPutnikId != putnikLower) continue;
      final godina = _parseInternalInt(row['godina']);
      final mesec = _parseInternalInt(row['mesec']);
      if (godina == null || mesec == null) continue;
      if (mesec < 1 || mesec > 12) continue;
      meseci.add((godina, mesec));
    }

    return meseci;
  }

  static List<V3Dug> getDugovi() {
    final rm = V3MasterRealtimeManager.instance;
    final dugovi = <V3Dug>[];
    final now = V3BelgradeTime.now();

    // Ključ: putnikId(lower) + godina + mesec → kanonski putnikId iz keša/reda.
    // Izvor 1: svi meseci sa mesečnom evidencijom (da ne propadnu stari dugovi).
    // Izvor 2: svi putnici za tekući mesec (Beograd).
    final periodKeys = <String, String>{}; // "lowerId:g:m" -> putnikId

    void addPeriod(String putnikId, int godina, int mesec) {
      final safeId = putnikId.trim();
      if (safeId.isEmpty) return;
      if (mesec < 1 || mesec > 12) return;
      final key = '${safeId.toLowerCase()}:$godina:$mesec';
      periodKeys.putIfAbsent(key, () => safeId);
    }

    for (final row in _naplataRows()) {
      final pid = row['putnik_v3_auth_id']?.toString().trim() ?? '';
      final godina = _parseInternalInt(row['godina']);
      final mesec = _parseInternalInt(row['mesec']);
      if (pid.isEmpty || godina == null || mesec == null) continue;
      addPeriod(pid, godina, mesec);
    }

    for (final putnikData in rm.putniciCache.values) {
      final putnikId = putnikData['id']?.toString().trim() ?? '';
      if (putnikId.isEmpty) continue;
      addPeriod(putnikId, now.year, now.month);
      for (final (godina, mesec) in getNaplataMeseciForPutnik(putnikId)) {
        addPeriod(putnikId, godina, mesec);
      }
    }

    for (final entry in periodKeys.entries) {
      final parts = entry.key.split(':');
      if (parts.length != 3) continue;
      final putnikLower = parts[0];
      final godina = int.tryParse(parts[1]);
      final mesec = int.tryParse(parts[2]);
      if (godina == null || mesec == null) continue;

      var putnikId = entry.value;
      var putnikData = rm.putniciCache[putnikId] ??
          rm.putniciCache[putnikLower] ??
          rm.putniciCache.entries.where((e) => e.key.toLowerCase() == putnikLower).map((e) => e.value).firstOrNull;

      if (putnikData != null) {
        final cachedId = putnikData['id']?.toString().trim();
        if (cachedId != null && cachedId.isNotEmpty) putnikId = cachedId;
      }

      final tip = (putnikData?['tip_putnika'] as String? ?? 'dnevni').toLowerCase();
      final cenaPoDanu = (putnikData?['cena_po_danu'] as num?)?.toDouble() ?? 0.0;
      final cenaPoPokupljenju = (putnikData?['cena_po_pokupljenju'] as num?)?.toDouble() ?? 0.0;
      final cena = _cenaZaTip(
        tip: tip,
        cenaPoDanu: cenaPoDanu,
        cenaPoPokupljenju: cenaPoPokupljenju,
      );

      // Dug se računa isključivo iz nenaplacene_voznje_json (istorijske cene).
      final dugIznos = getNenaplacenIznosForPutnik(
        putnikId: putnikId,
        godina: godina,
        mesec: mesec,
      );
      if (dugIznos <= 0) continue;

      final summary = getNaplataSummaryForPutnik(
        putnikId: putnikId,
        godina: godina,
        mesec: mesec,
      );
      // Ne filtriramo po brojVoznji iz realizovanih — dug može postojati i kada
      // je arhiva realizovanih prazna/nepotpuna; tada koristimo broj nenaplaćenih.
      final brojVoznji = summary.brojVoznji > 0
          ? summary.brojVoznji
          : getNenaplacenBrojVoznjiForPutnik(
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
      final naplatioById = _getNaplatioBy(latestNaplata ?? <String, dynamic>{});
      final updatedById = latestNaplata?['updated_by']?.toString().trim();

      final vozacData = naplatioById != null ? rm.vozaciCache[naplatioById] : null;
      final vozacIme = vozacData?['ime_prezime']?.toString() ?? '';

      String pokupioVozacId = '';
      String pokupioVozacIme = '';
      if (latestNaplata != null) {
        final realizovane = _readRealizovaneVoznje(latestNaplata);
        for (final voznja in realizovane.reversed) {
          final pokupljenBy = voznja['pokupljen_by']?.toString().trim();
          if (pokupljenBy != null && pokupljenBy.isNotEmpty) {
            pokupioVozacId = pokupljenBy;
            final pokupioVozacData = rm.vozaciCache[pokupioVozacId];
            pokupioVozacIme = pokupioVozacData?['ime_prezime']?.toString() ?? '';
            break;
          }
        }
      }
      if (pokupioVozacId.isEmpty) {
        for (final operRow in rm.operativnaNedeljaCache.values) {
          final rPutnikId = (operRow['created_by']?.toString() ?? '').trim().toLowerCase();
          if (rPutnikId != putnikId.toLowerCase()) continue;
          final pokupljenBy = operRow['pokupljen_by']?.toString().trim();
          if (pokupljenBy == null || pokupljenBy.isEmpty) continue;
          final datum = V3BelgradeTime.parseTs(operRow['datum']?.toString());
          if (datum == null) continue;
          if (datum.year == godina && datum.month == mesec) {
            pokupioVozacId = pokupljenBy;
            final pokupioVozacData = rm.vozaciCache[pokupioVozacId];
            pokupioVozacIme = pokupioVozacData?['ime_prezime']?.toString() ?? '';
            break;
          }
        }
      }

      final uplaceno = summary.ukupanIznos;
      final visak = getVisakIznosForPutnik(
        putnikId: putnikId,
        godina: godina,
        mesec: mesec,
      );
      // Ista formula kao u getMesecniObracun: obaveza = stvarna vrednost vožnji
      // (uplaćeno što je potrošeno na vožnje + preostali dug).
      final ukupnaObaveza = (uplaceno - visak + dugIznos).clamp(0.0, double.infinity);

      dugovi.add(
        V3Dug(
          id: '$putnikId:$godina:$mesec',
          putnikId: putnikId,
          imePrezime: putnikData?['ime_prezime'] as String? ?? 'Nepoznato',
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
          createdAt: V3BelgradeTime.parseTs(latestNaplata?['created_at']?.toString()),
          naplacenoAt: _naplacenoAt(latestNaplata ?? <String, dynamic>{}),
          naplacenoBy: (naplatioById != null && naplatioById.isNotEmpty) ? naplatioById : null,
          updatedAt: V3BelgradeTime.parseTs(latestNaplata?['updated_at']?.toString()),
          updatedBy: (updatedById != null && updatedById.isNotEmpty) ? updatedById : null,
          finansijeNaziv: latestNaplata?['naziv']?.toString(),
          finansijeKategorija: latestNaplata?['kategorija']?.toString(),
        ),
      );
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
  }) async {
    final safePutnikId = putnikId.trim();
    if (safePutnikId.isEmpty) {
      throw ArgumentError('putnikId je obavezan.');
    }
    if (iznos <= 0) {
      throw ArgumentError('Iznos naplate mora biti veći od nule.');
    }

    final lockKey = '${_getLockKey(safePutnikId, mesec, godina)}:naplata';
    if (_mesecnaNaplataLocks.contains(lockKey)) {
      debugPrint('[V3FinansijeService] sacuvajMesecnuNaplatu skipped (lock): $lockKey');
      throw StateError('Naplata za ovog putnika je već u toku, sačekajte trenutak i pokušajte ponovo.');
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

      final now = DateTime.now();
      final uplataStavka = <String, dynamic>{
        'uplata_id': 'upl:${_uuid.v4()}',
        'datum': V3BelgradeTime.toIsoUtc(now),
        'iznos': iznos,
        'naplatio_by': naplacenoBy,
        'naplatio_at': V3BelgradeTime.toIsoUtc(now),
      };

      Map<String, dynamic> row;
      if (existing.isNotEmpty) {
        _sortByCreatedAtDesc(existing);
        final latest = existing.first;
        final existingId = (latest['id']?.toString() ?? '').trim();
        if (existingId.isEmpty) {
          throw StateError('Master red za finansije nema validan ID');
        }

        final currentNenaplacene = _readNenaplaceneVoznje(latest);
        final cenaVoznje = _resolveCenaZaPutnik(safePutnikId);
        final consumeResult = _consumeNenaplaceneVoznje(
          stavke: currentNenaplacene,
          uplacenIznos: iznos,
          defaultCena: cenaVoznje,
        );
        final updatedNenaplacene = consumeResult.stavke;
        // Iznos uplate koji je premašio sve tekuće nenaplaćene vožnje se ne
        // gubi — postaje višak (kredit) koji će pokriti naredne vožnje pre
        // nego što se one uopšte upišu kao dug.
        final updatedVisak = _readVisak(latest) + consumeResult.preostalo;
        // Broj vožnji se izvodi isključivo iz realizovane_voznje_json, ne iz
        // skalarne kolone. Pri plaćanju se broj vožnji ne menja.
        final currentUplate = _readUplate(latest);
        final updatedUplate = _appendUplata(currentUplate, uplataStavka);
        // Skalarne kolone su izvedene iz uplate_json (jedini izvor istine).
        final updatedIznos = _getUkupanIznosUplata(<String, dynamic>{_uplateKey: updatedUplate});
        final updatedNaplatioBy = _getNaplatioBy(<String, dynamic>{_uplateKey: updatedUplate});

        row = await _repo.updateByIdReturning(existingId, {
          'iznos': updatedIznos,
          'naplaceno_by': updatedNaplatioBy,
          _nenaplaceneVoznjeKey: updatedNenaplacene,
          _uplateKey: updatedUplate,
          'visak_iznos': updatedVisak,
          'updated_at': V3BelgradeTime.toIsoUtc(now),
        });
      } else {
        // Skalarne kolone su izvedene iz uplate_json (jedini izvor istine).
        final initialUplate = [uplataStavka];
        final initialIznos = _getUkupanIznosUplata(<String, dynamic>{_uplateKey: initialUplate});
        final initialNaplatioBy = _getNaplatioBy(<String, dynamic>{_uplateKey: initialUplate});

        // Prenesi eventualni višak iz prethodnog meseca, ako postoji —
        // uplata se prvo primenjuje na taj preneti višak.
        final prethodniRed = _findPrethodniRed(putnikId: safePutnikId, godina: godina, mesec: mesec);
        final prenetiVisak = prethodniRed != null ? _readVisak(prethodniRed) : 0.0;
        if (prethodniRed != null && prenetiVisak > 0.009) {
          final prethodniId = (prethodniRed['id'] ?? '').toString();
          if (prethodniId.isNotEmpty) {
            final updatedPrethodni = await _repo.updateByIdReturning(prethodniId, {
              'visak_iznos': 0,
              'updated_at': V3BelgradeTime.toIsoUtc(now),
            });
            V3MasterRealtimeManager.instance.v3UpsertToCache('v3_finansije', updatedPrethodni);
          }
        }

        row = await _repo.insertReturning({
          'naziv': 'Evidencija prevoza $mesec/$godina',
          'kategorija': _masterKategorija(),
          'tip': 'prihod',
          'iznos': initialIznos,
          'putnik_v3_auth_id': safePutnikId,
          'naplaceno_by': initialNaplatioBy,
          _nenaplaceneVoznjeKey: <Map<String, dynamic>>[],
          _uplateKey: initialUplate,
          'visak_iznos': prenetiVisak + iznos,
          'mesec': mesec,
          'godina': godina,
        });
      }

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
    return sacuvajMesecnuNaplatu(
      putnikId: putnikId,
      naplacenoBy: naplacenoBy,
      iznos: iznos,
      mesec: datum.month,
      godina: datum.year,
    );
  }

  static List<Map<String, dynamic>> _readRealizovaneVoznje(Map<String, dynamic> row) {
    final raw = row[_realizovaneVoznjeKey];
    final result = <Map<String, dynamic>>[];

    try {
      Iterable<dynamic> src;
      if (raw is List) {
        src = raw;
      } else if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is! List) return result;
        src = decoded;
      } else {
        return result;
      }

      for (final item in src) {
        if (item is! Map) continue;
        final operativnaId = (item['operativna_id']?.toString() ?? '').trim();
        final datum = item['datum']?.toString();
        // Ghost stavke (bez stvarnog pokupljanja) ne ulaze u arhivsku
        // evidenciju za brojanje/prikaz — operativna se briše nedeljno, pa
        // pokupljen_at u JSON-u mora biti jedini dokaz da je vožnja realizovana.
        final pokupljenAt = (item['pokupljen_at']?.toString() ?? '').trim();
        if (operativnaId.isEmpty || datum == null || datum.isEmpty) continue;
        if (pokupljenAt.isEmpty || pokupljenAt.toLowerCase() == 'null') continue;
        result.add({
          'operativna_id': operativnaId,
          'datum': datum,
          'pokupljen_by': item['pokupljen_by']?.toString(),
          'pokupljen_at': pokupljenAt,
          'dodao_by': item['dodao_by']?.toString(),
          'azurirao_by': item['azurirao_by']?.toString(),
          'grad': item['grad']?.toString(),
          'vreme': item['vreme']?.toString(),
        });
      }
    } catch (_) {
      return result;
    }

    result.sort((a, b) => _parseNenaplacenaDatumOrEpoch(a).compareTo(_parseNenaplacenaDatumOrEpoch(b)));
    return result;
  }

  static DateTime _parseNenaplacenaDatumOrEpoch(Map<String, dynamic> stavka) {
    final dt = V3BelgradeTime.parseTs(stavka['datum']?.toString());
    return dt ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  static List<Map<String, dynamic>> _readOtkazaneVoznje(Map<String, dynamic> row) {
    final raw = row[_otkazaneVoznjeKey];
    final result = <Map<String, dynamic>>[];

    try {
      Iterable<dynamic> src;
      if (raw is List) {
        src = raw;
      } else if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is! List) return result;
        src = decoded;
      } else {
        return result;
      }

      for (final item in src) {
        if (item is! Map) continue;
        final operativnaId = (item['operativna_id']?.toString() ?? '').trim();
        final datum = item['datum']?.toString();
        if (operativnaId.isEmpty || datum == null || datum.isEmpty) continue;
        result.add({
          'operativna_id': operativnaId,
          'datum': datum,
          'otkazao_by': item['otkazao_by']?.toString(),
          'otkazano_at': item['otkazano_at']?.toString(),
          'tip_otkazivanja': item['tip_otkazivanja']?.toString(),
          'grad': item['grad']?.toString(),
          'vreme': item['vreme']?.toString(),
        });
      }
    } catch (_) {
      return result;
    }

    result.sort((a, b) => _parseNenaplacenaDatumOrEpoch(a).compareTo(_parseNenaplacenaDatumOrEpoch(b)));
    return result;
  }

  static List<Map<String, dynamic>> _readUplate(Map<String, dynamic> row) {
    final raw = row[_uplateKey];
    final result = <Map<String, dynamic>>[];

    try {
      Iterable<dynamic> src;
      if (raw is List) {
        src = raw;
      } else if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is! List) return result;
        src = decoded;
      } else {
        return result;
      }

      for (final item in src) {
        if (item is! Map) continue;
        final uplataId = (item['uplata_id']?.toString() ?? '').trim();
        final datum = item['datum']?.toString();
        final iznos = (item['iznos'] as num?)?.toDouble();
        if (uplataId.isEmpty || datum == null || datum.isEmpty || iznos == null) continue;
        result.add({
          'uplata_id': uplataId,
          'datum': datum,
          'iznos': iznos,
          'naplatio_by': item['naplatio_by']?.toString(),
          'naplatio_at': item['naplatio_at']?.toString(),
        });
      }
    } catch (_) {
      return result;
    }

    result.sort((a, b) => _parseNenaplacenaDatumOrEpoch(a).compareTo(_parseNenaplacenaDatumOrEpoch(b)));
    return result;
  }

  static List<Map<String, dynamic>> _appendUplata(
    List<Map<String, dynamic>> stavke,
    Map<String, dynamic> novaStavka,
  ) {
    final uplataId = (novaStavka['uplata_id']?.toString() ?? '').trim();
    if (uplataId.isEmpty) return stavke;

    final updated = List<Map<String, dynamic>>.from(stavke);
    updated.add(novaStavka);
    updated.sort((a, b) => _parseNenaplacenaDatumOrEpoch(a).compareTo(_parseNenaplacenaDatumOrEpoch(b)));
    return updated;
  }

  static List<V3Uplata> getUplateZaMesec({
    required String putnikId,
    required int godina,
    required int mesec,
  }) {
    final safePutnikId = putnikId.trim();
    if (safePutnikId.isEmpty) return const <V3Uplata>[];

    final cache = V3MasterRealtimeManager.instance.getCache('v3_finansije').values;
    final result = <V3Uplata>[];

    for (final row in cache) {
      final rPutnikId = (row['putnik_v3_auth_id']?.toString() ?? '').trim().toLowerCase();
      if (rPutnikId != safePutnikId.toLowerCase()) continue;
      final rG = _parseInternalInt(row['godina']);
      final rM = _parseInternalInt(row['mesec']);
      if (rG != godina || rM != mesec) continue;

      final uplate = _readUplate(row);
      for (final uplataMap in uplate) {
        final datum = V3BelgradeTime.parseTs(uplataMap['datum']?.toString()) ??
            V3BelgradeTime.parseDatum(uplataMap['datum']?.toString());
        if (datum == null) continue;
        result.add(V3Uplata(
          uplataId: uplataMap['uplata_id']?.toString() ?? '',
          datum: datum,
          iznos: (uplataMap['iznos'] as num?)?.toDouble() ?? 0,
          naplatioBy: uplataMap['naplatio_by']?.toString(),
          naplatioAt: V3BelgradeTime.parseTs(uplataMap['naplatio_at']?.toString()),
        ));
      }
    }

    result.sort((a, b) => a.datum.compareTo(b.datum));
    return result;
  }

  static List<Map<String, dynamic>> getRealizovaneVoznjeZaMesec({
    required String putnikId,
    required int godina,
    required int mesec,
  }) {
    final safePutnikId = putnikId.trim();
    if (safePutnikId.isEmpty) return const <Map<String, dynamic>>[];

    final cache = V3MasterRealtimeManager.instance.getCache('v3_finansije').values;
    final result = <Map<String, dynamic>>[];

    for (final row in cache) {
      final rPutnikId = (row['putnik_v3_auth_id']?.toString() ?? '').trim().toLowerCase();
      if (rPutnikId != safePutnikId.toLowerCase()) continue;
      final rG = _parseInternalInt(row['godina']);
      final rM = _parseInternalInt(row['mesec']);
      // Samo preskoči drugi mesec — NE prekidaj celu petlju (inače prazan UI).
      if (rG != godina || rM != mesec) continue;

      final voznje = _readRealizovaneVoznje(row);
      for (final v in voznje) {
        final datum =
            V3BelgradeTime.parseTs(v['datum']?.toString()) ?? V3BelgradeTime.parseDatum(v['datum']?.toString());
        if (datum == null) continue;
        result.add({
          ...v,
          '_datum_parsed': datum,
        });
      }
    }

    result.sort((a, b) {
      final aDt = a['_datum_parsed'] as DateTime;
      final bDt = b['_datum_parsed'] as DateTime;
      return aDt.compareTo(bDt);
    });
    return result;
  }

  /// Nenaplaćene stavke za putnika/mesec (sa parsiranim datumom).
  static List<Map<String, dynamic>> getNenaplaceneVoznjeZaMesec({
    required String putnikId,
    required int godina,
    required int mesec,
  }) {
    final safePutnikId = putnikId.trim();
    if (safePutnikId.isEmpty) return const <Map<String, dynamic>>[];

    final result = <Map<String, dynamic>>[];
    for (final row in _naplataRowsForPutnikMesec(
      putnikId: safePutnikId,
      godina: godina,
      mesec: mesec,
    )) {
      for (final stavka in _readNenaplaceneVoznje(row)) {
        final datum = V3BelgradeTime.parseTs(stavka['datum']?.toString()) ??
            V3BelgradeTime.parseDatum(stavka['datum']?.toString());
        if (datum == null) continue;
        if (datum.year != godina || datum.month != mesec) continue;
        result.add({
          ...stavka,
          '_datum_parsed': datum,
        });
      }
    }

    result.sort((a, b) {
      final aDt = a['_datum_parsed'] as DateTime;
      final bDt = b['_datum_parsed'] as DateTime;
      return aDt.compareTo(bDt);
    });
    return result;
  }

  /// Vraća sve otkazane vožnje за путника у задатом месецу, са парсираним датумом.
  static List<Map<String, dynamic>> getOtkazaneVoznjeZaMesec({
    required String putnikId,
    required int godina,
    required int mesec,
  }) {
    final safePutnikId = putnikId.trim();
    if (safePutnikId.isEmpty) return const <Map<String, dynamic>>[];

    final cache = V3MasterRealtimeManager.instance.getCache('v3_finansije').values;
    final result = <Map<String, dynamic>>[];

    for (final row in cache) {
      final rPutnikId = (row['putnik_v3_auth_id']?.toString() ?? '').trim().toLowerCase();
      if (rPutnikId != safePutnikId.toLowerCase()) continue;
      final rG = _parseInternalInt(row['godina']);
      final rM = _parseInternalInt(row['mesec']);
      if (rG != godina || rM != mesec) continue;

      final otkazane = _readOtkazaneVoznje(row);
      for (final o in otkazane) {
        final datum = V3BelgradeTime.parseTs(o['datum']?.toString()) ?? DateTime.tryParse(o['datum']?.toString() ?? '');
        if (datum == null) continue;
        if (datum.year != godina || datum.month != mesec) continue;
        result.add({
          ...o,
          '_datum_parsed': datum,
        });
      }
    }

    result.sort((a, b) {
      final aDt = a['_datum_parsed'] as DateTime;
      final bDt = b['_datum_parsed'] as DateTime;
      return aDt.compareTo(bDt);
    });
    return result;
  }

  /// Vraća све појединачне уплате из једног финансијског реда као V3Uplata објекте.
  static List<V3Uplata> getUplateFromRow(Map<String, dynamic> row) {
    final uplate = _readUplate(row);
    final result = <V3Uplata>[];
    for (final uplataMap in uplate) {
      final datum = V3BelgradeTime.parseTs(uplataMap['datum']?.toString()) ??
          V3BelgradeTime.parseDatum(uplataMap['datum']?.toString());
      if (datum == null) continue;
      result.add(V3Uplata(
        uplataId: uplataMap['uplata_id']?.toString() ?? '',
        datum: datum,
        iznos: (uplataMap['iznos'] as num?)?.toDouble() ?? 0,
        naplatioBy: uplataMap['naplatio_by']?.toString(),
        naplatioAt: V3BelgradeTime.parseTs(uplataMap['naplatio_at']?.toString()),
      ));
    }
    return result;
  }

  /// Vraća све реализоване воžње из једног финансијског реда са парсираним датумом.
  static List<({DateTime datum, String? pokupljenBy, String? grad, String? vreme})> getRealizovaneVoznjeFromRow(
      Map<String, dynamic> row) {
    final voznje = _readRealizovaneVoznje(row);
    final result = <({DateTime datum, String? pokupljenBy, String? grad, String? vreme})>[];
    for (final v in voznje) {
      final datum = V3BelgradeTime.parseTs(v['datum']?.toString()) ?? V3BelgradeTime.parseDatum(v['datum']?.toString());
      if (datum == null) continue;
      result.add((
        datum: datum,
        pokupljenBy: v['pokupljen_by']?.toString(),
        grad: v['grad']?.toString(),
        vreme: v['vreme']?.toString(),
      ));
    }
    return result;
  }

  static V3NaplataStatus _resolveNaplataStatus(Map<String, dynamic> row) {
    final uplate = _readUplate(row);
    final ukupnoUplaceno = uplate.fold<double>(0.0, (sum, u) => sum + ((u['iznos'] as num?)?.toDouble() ?? 0.0));
    if (ukupnoUplaceno <= 0.009) return V3NaplataStatus.nemaUplate;

    // Dug se računa iz preostalih nenaplaćenih stavki sa istorijskim cenama.
    final dug = _readNenaplaceneVoznje(row).fold<double>(
      0.0,
      (sum, stavka) => sum + ((stavka['cena'] as num?)?.toDouble() ?? 0.0),
    );

    if (dug <= 0.009) return V3NaplataStatus.potpunoPlacen;
    return V3NaplataStatus.nemaUplate;
  }
}
