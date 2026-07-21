import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../models/v3_dug.dart';
import '../../models/v3_finansije.dart';
import '../../utils/v3_date_utils.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_finansije_repository.dart';

class V3NaplataInfo {
  final bool isPaid;
  final double ukupanIznos;
  final double poslednjaDopuna;
  final DateTime? paidAt;
  final String? paidBy;
  final DateTime? updatedAt;
  final String? updatedBy;
  final DateTime? uplataAt;

  const V3NaplataInfo({
    required this.isPaid,
    required this.ukupanIznos,
    required this.poslednjaDopuna,
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
    return V3DateUtils.parseTs(row['created_at']?.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  static DateTime? _naplacenoAt(Map<String, dynamic> row) {
    // Koristimo updated_at za datum poslednje dopune
    final ts = row['updated_at'];
    return V3DateUtils.parseTs(ts?.toString());
  }

  static DateTime? _readLastUplata(Map<String, dynamic> row) {
    final uplate = _readUplate(row);
    if (uplate.isEmpty) return null;
    final last = uplate.last;
    return V3DateUtils.parseTs(last['datum']?.toString());
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

  /// Da li red ima bilo kakvu stvarnu uplatu u uplate_json.
  static bool _hasUplata(Map<String, dynamic> row) => _readUplate(row).isNotEmpty;

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
      final danIso = V3DateUtils.parseIsoDatePart(datum.toIso8601String());
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
      'datum': datum.toIso8601String(),
      'cena': cena,
    });
    updated.sort((a, b) => _parseNenaplacenaDatumOrEpoch(a).compareTo(_parseNenaplacenaDatumOrEpoch(b)));
    return updated;
  }

  static List<Map<String, dynamic>> _consumeNenaplaceneVoznje({
    required List<Map<String, dynamic>> stavke,
    required double uplacenIznos,
    required double defaultCena,
  }) {
    var preostalo = uplacenIznos;
    final queue = List<Map<String, dynamic>>.from(stavke)
      ..sort((a, b) => _parseNenaplacenaDatumOrEpoch(a).compareTo(_parseNenaplacenaDatumOrEpoch(b)));

    while (queue.isNotEmpty && preostalo > 0.009) {
      final first = queue.first;
      final cenaStavke =
          ((first['cena'] as num?)?.toDouble() ?? 0.0) > 0 ? (first['cena'] as num).toDouble() : defaultCena;
      if (cenaStavke <= 0) break;
      if (preostalo + 0.009 < cenaStavke) break;
      preostalo -= cenaStavke;
      queue.removeAt(0);
    }

    return queue;
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
      // Danas je pazar onoliko koliko je danas uplaceno.
      // Red se kreira prilikom pokupljanja (created_at), a azurira prilikom uplate (updated_at).
      final ts = row['updated_at'];
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

    // Ukupan iznos se izvodi isključivo iz uplate_json (jedini izvor istine).
    final ukupanIznos = _getUkupanIznosUplata(latest);
    final poslednjaDopuna = _readPosledjaDopuna(latest);

    return V3NaplataInfo(
      isPaid: ukupanIznos > 0,
      ukupanIznos: ukupanIznos,
      poslednjaDopuna: poslednjaDopuna,
      paidAt: _naplacenoAt(latest),
      paidBy: _getNaplatioBy(latest),
      updatedAt: V3DateUtils.parseTs(latest['updated_at']?.toString()),
      updatedBy: latest['updated_by']?.toString(),
      uplataAt: _readLastUplata(latest),
    );
  }

  static V3NaplataInfo? getLatestNaplataForPutnik(String putnikId) {
    final putnik = putnikId.trim();
    if (putnik.isEmpty) return null;

    final candidates = _naplataRows().where((row) {
      final rPutnikId = (row['putnik_v3_auth_id']?.toString() ?? '').trim().toLowerCase();
      if (rPutnikId != putnik.toLowerCase()) return false;
      // Jedini pouzdan izvor za postojanje uplate je uplate_json.
      return _hasUplata(row);
    }).toList();
    if (candidates.isEmpty) return null;

    // Sortiramo po updated_at da bismo dobili poslednju dopunu
    candidates.sort((a, b) {
      final aUpdatedAt = V3DateUtils.parseTs(a['updated_at']?.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bUpdatedAt = V3DateUtils.parseTs(b['updated_at']?.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bUpdatedAt.compareTo(aUpdatedAt);
    });
    final latest = candidates.first;

    // Ukupan iznos se izvodi isključivo iz uplate_json (jedini izvor istine).
    final ukupanIznos = _getUkupanIznosUplata(latest);
    final poslednjaDopuna = _readPosledjaDopuna(latest);

    return V3NaplataInfo(
      isPaid: ukupanIznos > 0,
      ukupanIznos: ukupanIznos,
      poslednjaDopuna: poslednjaDopuna,
      paidAt: _naplacenoAt(latest),
      paidBy: latest['naplaceno_by']?.toString(),
      updatedAt: V3DateUtils.parseTs(latest['updated_at']?.toString()),
      updatedBy: latest['updated_by']?.toString(),
      uplataAt: _readLastUplata(latest),
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

    final rm = V3MasterRealtimeManager.instance;
    final putnikData = rm.putniciCache[putnikId] ?? const <String, dynamic>{};
    final tipPutnika = (putnikData['tip_putnika'] as String? ?? '').toLowerCase();

    for (final row in naplataRows) {
      // Ukupan iznos se izvodi isključivo iz uplate_json (jedini izvor istine).
      ukupanIznos += _getUkupanIznosUplata(row);
      brojVoznjiRealizacija += _countRealizovaneVoznje(row, tipPutnika);
    }

    return (brojVoznji: brojVoznjiRealizacija, ukupanIznos: ukupanIznos);
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
          final danIso = V3DateUtils.parseIsoDatePart(datum.toIso8601String());
          final opCache = V3MasterRealtimeManager.instance.getCache('v3_operativna_nedelja');
          final vecVozioDanas = opCache.values.any((r) {
            final rPutnikId = (r['created_by']?.toString() ?? '').trim().toLowerCase();
            if (rPutnikId != safePutnikId.toLowerCase()) return false;

            final rDanIso = V3DateUtils.parseIsoDatePart(r['datum']?.toString() ?? '');
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
          final updatedNenaplacene = _appendNenaplacenaVoznja(
            stavke: currentNenaplacene,
            operativnaId: operativnaId,
            datum: datum,
            cena: cenaVoznje,
          );
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
            'updated_at': DateTime.now().toIso8601String(),
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
      final row = await _repo.insertReturning({
        'naziv': 'Evidencija prevoza ${datum.month}/${datum.year}',
        'kategorija': _masterKategorija(),
        'tip': 'prihod',
        'iznos': 0,
        'putnik_v3_auth_id': safePutnikId,
        _nenaplaceneVoznjeKey: [
          {
            'operativna_id': operativnaId,
            'datum': datum.toIso8601String(),
            'cena': cenaVoznje,
          }
        ],
        'mesec': datum.month,
        'godina': datum.year,
      });
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_finansije', row);
    } finally {
      _mesecnaNaplataLocks.remove(lockKey);
    }
  }

  /// Vraća sve vožnje koje je vozač pokupio na zadati dan iz arhive v3_finansije.
  static List<Map<String, dynamic>> getPokupljeniPutniciZaVozacaDan({
    required String vozacId,
    required DateTime dan,
  }) {
    final id = vozacId.trim();
    if (id.isEmpty) return <Map<String, dynamic>>[];

    final datumIso = V3DateUtils.parseIsoDatePart(dan.toIso8601String());
    final result = <Map<String, dynamic>>[];

    for (final row in _naplataRows()) {
      final realizovane = _readRealizovaneVoznje(row);
      for (final voznja in realizovane) {
        final voznjaDatumIso = V3DateUtils.parseIsoDatePart(voznja['datum']?.toString() ?? '');
        if (voznjaDatumIso != datumIso) continue;
        if ((voznja['pokupljen_by']?.toString() ?? '').trim() != id) continue;
        result.add({
          ...voznja,
          'putnik_v3_auth_id': row['putnik_v3_auth_id']?.toString(),
          'finansije_id': row['id']?.toString(),
        });
      }
    }

    return result;
  }

  /// Vraća sve vožnje koje je vozač uneo/azurirao na zadati dan iz arhive v3_finansije.
  static List<Map<String, dynamic>> getDodatiPutniciZaVozacaDan({
    required String vozacId,
    required DateTime dan,
  }) {
    final id = vozacId.trim();
    if (id.isEmpty) return <Map<String, dynamic>>[];

    final datumIso = V3DateUtils.parseIsoDatePart(dan.toIso8601String());
    final result = <Map<String, dynamic>>[];

    for (final row in _naplataRows()) {
      final realizovane = _readRealizovaneVoznje(row);
      for (final voznja in realizovane) {
        final voznjaDatumIso = V3DateUtils.parseIsoDatePart(voznja['datum']?.toString() ?? '');
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

  /// Vraća sve vožnje koje je vozač otkazao na zadati dan iz arhive v3_finansije.
  static List<Map<String, dynamic>> getOtkazaneVoznjeZaVozacaDan({
    required String vozacId,
    required DateTime dan,
  }) {
    final id = vozacId.trim();
    if (id.isEmpty) return <Map<String, dynamic>>[];

    final datumIso = V3DateUtils.parseIsoDatePart(dan.toIso8601String());
    final result = <Map<String, dynamic>>[];

    for (final row in _naplataRows()) {
      final otkazane = _readOtkazaneVoznje(row);
      for (final voznja in otkazane) {
        final voznjaDatumIso = V3DateUtils.parseIsoDatePart(voznja['datum']?.toString() ?? '');
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
          // Prikazujemo samo redove sa stvarnom uplatom istog dana od traženog vozača (u uplate_json).
          return _readUplate(row).any((u) {
            final dt = V3DateUtils.parseTs(u['datum']?.toString());
            if (dt == null) return false;
            if (dt.year != targetDay.year || dt.month != targetDay.month || dt.day != targetDay.day) return false;
            return (u['naplatio_by']?.toString() ?? '').trim().toLowerCase() == id.toLowerCase();
          });
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

    // Jedini pouzdan izvor je uplate_json: sumiramo SVE pojedinačne uplate
    // čiji datum pada na traženi dan, grupisano po tome ko je tu konkretnu
    // uplatu naplatio (naplatio_by iz same stavke, ne naplaceno_by sa reda,
    // jer red može imati više uplata od različitih vozača kroz vreme).
    for (final row in _naplataRows()) {
      for (final uplata in _readUplate(row)) {
        final dt = V3DateUtils.parseTs(uplata['datum']?.toString());
        if (dt == null) continue;
        if (dt.year != targetDay.year || dt.month != targetDay.month || dt.day != targetDay.day) continue;

        final naplatioBy = (uplata['naplatio_by']?.toString() ?? '').trim();
        if (naplatioBy.isEmpty) continue;

        final iznos = (uplata['iznos'] as num?)?.toDouble() ?? 0.0;
        if (iznos <= 0) continue;
        result[naplatioBy] = (result[naplatioBy] ?? 0.0) + iznos;
      }
    }

    return result;
  }

  /// Vraća ukupan iznos duga koji je nastao TAČNO na zadati dan (podrazumevano danas),
  /// za putnike tipa 'dnevni' i 'posiljka' (naplata po pokupljenju/danu).
  ///
  /// Ovo je analogno metodi [getPazarPoVozacuZaDan] koja prikazuje samo uplate
  /// izvršene tog dana - ovde se prikazuje samo dug (nenaplaćena vožnja)
  /// nastao tog dana, a ne kumulativni dug kroz ceo mesec.
  static double getDugZaDan(DateTime dan) {
    final rm = V3MasterRealtimeManager.instance;
    final targetDay = DateTime(dan.year, dan.month, dan.day);
    double total = 0.0;

    for (final row in _naplataRows()) {
      final putnikId = row['putnik_v3_auth_id']?.toString().trim() ?? '';
      if (putnikId.isEmpty) continue;

      final putnikData = rm.putniciCache[putnikId];
      final tip = (putnikData?['tip_putnika'] as String? ?? '').toLowerCase();
      if (tip != 'dnevni' && tip != 'posiljka') continue;

      for (final stavka in _readNenaplaceneVoznje(row)) {
        final datum = V3DateUtils.parseTs(stavka['datum']?.toString());
        if (datum == null) continue;
        if (datum.year == targetDay.year && datum.month == targetDay.month && datum.day == targetDay.day) {
          total += (stavka['cena'] as num?)?.toDouble() ?? 0.0;
        }
      }
    }

    return total;
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
        final naplatioById = _getNaplatioBy(latestNaplata ?? <String, dynamic>{});
        final updatedById = latestNaplata?['updated_by']?.toString().trim();

        final brojVoznji = summary.brojVoznji;
        if (brojVoznji <= 0) continue; // Samo oni koji su se vozili

        final vozacData = naplatioById != null ? rm.vozaciCache[naplatioById] : null;
        final vozacIme = vozacData?['ime_prezime']?.toString() ?? '';

        // Nađi vozača koji je pokupio putnika u ovom mesecu iz arhive realizovanih vožnji.
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
        // Fallback na operativnu nedelju ako arhiva nema podatak.
        if (pokupioVozacId.isEmpty) {
          for (final operRow in rm.operativnaNedeljaCache.values) {
            final rPutnikId = (operRow['created_by']?.toString() ?? '').trim().toLowerCase();
            if (rPutnikId != putnikId.toLowerCase()) continue;
            final pokupljenBy = operRow['pokupljen_by']?.toString().trim();
            if (pokupljenBy == null || pokupljenBy.isEmpty) continue;
            final datum = V3DateUtils.parseTs(operRow['datum']?.toString());
            if (datum == null) continue;
            if (datum.year == godina && datum.month == mesec) {
              pokupioVozacId = pokupljenBy;
              final pokupioVozacData = rm.vozaciCache[pokupioVozacId];
              pokupioVozacIme = pokupioVozacData?['ime_prezime']?.toString() ?? '';
              break;
            }
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
        'datum': now.toIso8601String(),
        'iznos': iznos,
        'naplatio_by': naplacenoBy,
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
        final updatedNenaplacene = _consumeNenaplaceneVoznje(
          stavke: currentNenaplacene,
          uplacenIznos: iznos,
          defaultCena: cenaVoznje,
        );
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
          'updated_at': now.toIso8601String(),
        });
      } else {
        // Skalarne kolone su izvedene iz uplate_json (jedini izvor istine).
        final initialUplate = [uplataStavka];
        final initialIznos = _getUkupanIznosUplata(<String, dynamic>{_uplateKey: initialUplate});
        final initialNaplatioBy = _getNaplatioBy(<String, dynamic>{_uplateKey: initialUplate});

        row = await _repo.insertReturning({
          'naziv': 'Evidencija prevoza $mesec/$godina',
          'kategorija': _masterKategorija(),
          'tip': 'prihod',
          'iznos': initialIznos,
          'putnik_v3_auth_id': safePutnikId,
          'naplaceno_by': initialNaplatioBy,
          _nenaplaceneVoznjeKey: <Map<String, dynamic>>[],
          _uplateKey: initialUplate,
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
        if (operativnaId.isEmpty || datum == null || datum.isEmpty) continue;
        result.add({
          'operativna_id': operativnaId,
          'datum': datum,
          'pokupljen_by': item['pokupljen_by']?.toString(),
          'pokupljen_at': item['pokupljen_at']?.toString(),
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
    final dt = V3DateUtils.parseTs(stavka['datum']?.toString());
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
        final datum = V3DateUtils.parseTs(uplataMap['datum']?.toString()) ??
            DateTime.tryParse(uplataMap['datum']?.toString() ?? '');
        if (datum == null) continue;
        result.add(V3Uplata(
          uplataId: uplataMap['uplata_id']?.toString() ?? '',
          datum: datum,
          iznos: (uplataMap['iznos'] as num?)?.toDouble() ?? 0,
          naplatioBy: uplataMap['naplatio_by']?.toString(),
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
      if (rG != godina || rM != mesec) continue;

      final voznje = _readRealizovaneVoznje(row);
      for (final v in voznje) {
        final datum = V3DateUtils.parseTs(v['datum']?.toString()) ?? DateTime.tryParse(v['datum']?.toString() ?? '');
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

  /// Broji realizovane vožnje iz arhivske JSON kolone.
  /// Za putnike tipa 'radnik'/'ucenik' naplata je po danu, pa se broje
  /// unikatni dani. Za sve ostale tipove broje se pojedinačne vožnje.
  static int _countRealizovaneVoznje(Map<String, dynamic> row, String tipPutnika) {
    final voznje = _readRealizovaneVoznje(row);
    if (_isPoDanuTip(tipPutnika)) {
      final dani = voznje
          .map((v) => V3DateUtils.parseIsoDatePart(v['datum']?.toString() ?? ''))
          .where((d) => d.isNotEmpty)
          .toSet();
      return dani.length;
    }
    return voznje.length;
  }
}
