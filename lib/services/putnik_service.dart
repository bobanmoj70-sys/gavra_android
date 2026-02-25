import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart' as globals_file;
import '../models/putnik.dart';
import '../utils/grad_adresa_validator.dart';
import '../utils/vozac_cache.dart';
import 'realtime/realtime_manager.dart';
import 'seat_request_service.dart';
import 'vozac_putnik_service.dart';
import 'voznje_log_service.dart';

class _StreamParams {
  _StreamParams({this.isoDate, this.grad, this.vreme, this.vozacId});
  final String? isoDate;
  final String? grad;
  final String? vreme;
  final String? vozacId; // 📉 EGRESS OPT: UUID vozača za server-side filter
}

class PutnikService {
  SupabaseClient get supabase => globals_file.supabase;

  // 📉 EGRESS OPT: Samo kolone koje Putnik/RegistrovaniPutnik.fromMap() zaista koristi
  static const String registrovaniFields =
      'id, putnik_ime, broj_telefona, broj_telefona_2, broj_telefona_oca, broj_telefona_majke, '
      'tip, tip_skole, adresa_bela_crkva_id, adresa_vrsac_id, '
      'datum_pocetka_meseca, datum_kraja_meseca, created_at, updated_at, '
      'aktivan, status, obrisan, is_duplicate, tip_prikazivanja, '
      'pin, email, cena_po_danu, treba_racun, '
      'firma_naziv, firma_pib, firma_mb, firma_ziro, firma_adresa, broj_mesta, '
      'adresa_bc:adresa_bela_crkva_id(naziv), '
      'adresa_vs:adresa_vrsac_id(naziv)';

  static final Map<String, StreamController<List<Putnik>>> _streams = {};
  static final Map<String, List<Putnik>> _lastValues = {};
  static final Map<String, _StreamParams> _streamParams = {};

  // 🌐 GLOBALNI SHARED LISTENER-I (jedan po tabeli, ne po stream key-u)
  static StreamSubscription? _globalSeatRequestsListener;
  static StreamSubscription? _globalVoznjeLogListener;
  static StreamSubscription? _globalRegistrovaniListener;
  static StreamSubscription? _globalVozacPutnikListener;
  static StreamSubscription? _globalVozacRasporedListener;

  // 📉 EGRESS OPT: Debounce timer — sprječava seriju fetch-ova na burst realtime evente
  static Timer? _refreshDebounceTimer;

  String _streamKey({String? isoDate, String? grad, String? vreme, String? vozacId}) =>
      '${isoDate ?? ''}|${grad ?? ''}|${vreme ?? ''}|${vozacId ?? ''}';

  Stream<List<Putnik>> streamKombinovaniPutniciFiltered(
      {String? isoDate, String? grad, String? vreme, String? vozacId}) {
    final key = _streamKey(isoDate: isoDate, grad: grad, vreme: vreme, vozacId: vozacId);
    if (_streams.containsKey(key) && !_streams[key]!.isClosed) {
      final controller = _streams[key]!;
      if (_lastValues.containsKey(key)) {
        Future.microtask(() {
          if (!controller.isClosed) controller.add(_lastValues[key]!);
        });
      } else {
        _doFetchForStream(key, isoDate, grad, vreme, controller, vozacId: vozacId);
      }
      return controller.stream;
    }
    final controller = StreamController<List<Putnik>>.broadcast();
    _streams[key] = controller;
    _streamParams[key] = _StreamParams(isoDate: isoDate, grad: grad, vreme: vreme, vozacId: vozacId);
    _doFetchForStream(key, isoDate, grad, vreme, controller, vozacId: vozacId);
    controller.onCancel = () {
      _streams.remove(key);
      _lastValues.remove(key);
      _streamParams.remove(key);

      // ✅ Zatvori globalne listener-e ako nema više aktivnih streamova
      if (_streams.isEmpty) {
        _globalSeatRequestsListener?.cancel();
        _globalVoznjeLogListener?.cancel();
        _globalRegistrovaniListener?.cancel();
        _globalVozacPutnikListener?.cancel();
        _globalVozacRasporedListener?.cancel();
        _globalSeatRequestsListener = null;
        _globalVoznjeLogListener = null;
        _globalRegistrovaniListener = null;
        _globalVozacPutnikListener = null;
        _globalVozacRasporedListener = null;
        debugPrint('🛑 [PutnikService] Svi streamovi zatvoreni - globalni listener-i otkazani');
      }
    };
    return controller.stream;
  }

  Stream<List<Putnik>> streamPutnici() {
    // 🆕 REDIREKCIJA NA IZVOR ISTINE (seat_requests)
    final todayDate = DateTime.now().toIso8601String().split('T')[0];
    return streamKombinovaniPutniciFiltered(isoDate: todayDate);
  }

  Future<List<Putnik>> getPutniciByDayIso(String isoDate) async {
    try {
      final todayDate = isoDate.split('T')[0];
      final rm = RealtimeManager.instance;
      // Ako je traženi datum jednak cache datumu, čitaj iz cache-a
      if (rm.loadedDate == todayDate && rm.isInitialized) {
        return rm.srCache.values
            .map((sr) {
              final putnikId = sr['putnik_id']?.toString();
              final vlRows = putnikId != null
                  ? rm.vlCache.values.where((vl) => vl['putnik_id']?.toString() == putnikId).toList()
                  : <Map<String, dynamic>>[];
              final rp = putnikId != null ? rm.rpCache[putnikId] : null;
              return _buildPutnik(sr, vlRows, rp, todayDate);
            })
            .where((p) => p.status != 'bez_polaska' && p.status != 'cancelled')
            .toList();
      }
      // Fallback: direktni upit za drugi datum (ne danas)
      final dan = _isoToDanKratica(todayDate);
      final srRows = await supabase
          .from('seat_requests')
          .select('id, putnik_id, grad, zeljeno_vreme, dodeljeno_vreme, status, '
              'created_at, updated_at, processed_at, priority, broj_mesta, '
              'custom_adresa_id, alternative_vreme_1, alternative_vreme_2, '
              'cancelled_by, pokupljeno_by, dan, tip_putnika')
          .eq('dan', dan)
          .inFilter('status',
              ['pending', 'manual', 'approved', 'confirmed', 'otkazano', 'cancelled', 'bez_polaska', 'pokupljen']);
      final vlRows = await supabase
          .from('voznje_log')
          .select('id, putnik_id, datum, tip, iznos, vozac_id, vozac_ime, grad, vreme_polaska, created_at')
          .eq('datum', todayDate);
      final vlByPutnik = <String, List<Map<String, dynamic>>>{};
      for (final vl in vlRows) {
        final pid = vl['putnik_id']?.toString() ?? '';
        vlByPutnik.putIfAbsent(pid, () => []).add(Map<String, dynamic>.from(vl));
      }
      return srRows
          .map((sr) {
            final pid = sr['putnik_id']?.toString();
            final rp = pid != null ? rm.rpCache[pid] : null;
            final vls = pid != null ? (vlByPutnik[pid] ?? []) : <Map<String, dynamic>>[];
            return _buildPutnik(Map<String, dynamic>.from(sr), vls, rp, todayDate);
          })
          .where((p) => p.status != 'bez_polaska' && p.status != 'cancelled')
          .toList();
    } catch (e) {
      debugPrint('⚠️ [PutnikService] Error fetching by day: $e');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // 🔧 CACHE-BASED JOIN — replicira RPC logiku u Dart-u (0 DB upita)
  // ---------------------------------------------------------------------------

  /// Gradi Putnik objekat iz 3 cache redova — zamjena za RPC `get_putnoci_sa_statusom`.
  /// Prima:
  ///   [srRow]   — red iz seat_requests cache-a
  ///   [vlRows]  — svi voznje_log redovi za ovog putnika za taj dan
  ///   [rp]      — red iz registrovani_putnici cache-a (null ako nije pronađen)
  ///   [isoDate] — datum za koji gradimo putnika ('yyyy-MM-dd')
  static Putnik _buildPutnik(
    Map<String, dynamic> srRow,
    List<Map<String, dynamic>> vlRows,
    Map<String, dynamic>? rp,
    String isoDate,
  ) {
    final srGrad = (srRow['grad'] ?? '').toString().toUpperCase();
    final srVreme = (srRow['dodeljeno_vreme'] ?? srRow['zeljeno_vreme'])?.toString();

    // Filtriraj voznje_log samo za isti grad i vreme (replicira RPC WHERE logiku)
    List<Map<String, dynamic>> matchedVl = vlRows.where((vl) {
      final vlGrad = (vl['grad'] ?? '').toString().toUpperCase();
      final vlVreme = vl['vreme_polaska']?.toString();
      final gradOk = vlGrad.isEmpty || vlGrad == srGrad;
      final vremeOk = vlVreme == null || srVreme == null || vlVreme == srVreme;
      return gradOk && vremeOk;
    }).toList();

    // je_pokupljen — direktno iz statusa
    final bool jePokupljen = srRow['status'] == 'pokupljen';

    // je_otkazan_iz_loga — direktno iz statusa
    final bool jeOtkazan = srRow['status'] == 'otkazano' || srRow['status'] == 'cancelled';

    // je_placen — postoji uplata/uplata_dnevna u voznje_log
    final uplataRows = matchedVl.where((vl) => vl['tip'] == 'uplata' || vl['tip'] == 'uplata_dnevna').toList();
    final bool jePlacen = uplataRows.isNotEmpty;

    // iznos_placanja — iz prve uplata/uplata_dnevna
    final double? iznos = uplataRows.isNotEmpty ? (uplataRows.first['iznos'] as num?)?.toDouble() : null;

    // vozac_id + vozac_ime — prefer uplata, zatim voznja
    final tipPriority = ['uplata', 'uplata_dnevna', 'voznja'];
    Map<String, dynamic>? mainVl;
    for (final tip in tipPriority) {
      mainVl = matchedVl.where((vl) => vl['tip'] == tip).firstOrNull;
      if (mainVl != null) break;
    }
    final String? vozacId = mainVl?['vozac_id']?.toString();
    final String? vozacIme = mainVl?['vozac_ime']?.toString();

    // log_created_at — najnoviji log event
    final logRows = matchedVl
        .where((vl) => ['voznja', 'otkazivanje', 'uplata', 'uplata_dnevna'].contains(vl['tip']))
        .toList()
      ..sort((a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));
    final String? logCreatedAt = logRows.isNotEmpty ? logRows.first['created_at']?.toString() : null;

    // pokupioVozac — direktno iz seat_requests.pokupljeno_by
    final String? pokupioVozac = srRow['pokupljeno_by']?.toString();

    // naplatioVozac — vozac_ime iz uplata reda
    final String? naplatioVozac = uplataRows.isNotEmpty ? uplataRows.first['vozac_ime']?.toString() : null;
    final String? naplatioVozacId = uplataRows.isNotEmpty ? uplataRows.first['vozac_id']?.toString() : null;

    // otkazaoVozac — vozac_ime iz otkazivanje reda
    final otkazRows = matchedVl.where((vl) => vl['tip'] == 'otkazivanje').toList();
    final String? otkazaoVozac = otkazRows.isNotEmpty ? otkazRows.first['vozac_ime']?.toString() : null;
    final String? otkazaoVozacId = otkazRows.isNotEmpty ? otkazRows.first['vozac_id']?.toString() : null;

    // pokupioVozacId — lookup po imenu u vozaciCache
    String? pokupioVozacId;
    if (pokupioVozac != null && pokupioVozac.isNotEmpty) {
      pokupioVozacId = RealtimeManager.instance.vozaciCache.values
          .where((v) => v['ime']?.toString() == pokupioVozac)
          .firstOrNull?['id']
          ?.toString();
    }

    // naziv_adrese — lookup u adreseCache
    String? nazivAdrese;
    final adresaId = srRow['custom_adresa_id']?.toString();
    if (adresaId != null && adresaId.isNotEmpty) {
      nazivAdrese = RealtimeManager.instance.adreseCache[adresaId]?['naziv']?.toString();
    }

    // Gradi mapu kompatibilnu sa Putnik.fromSeatRequest()
    final map = Map<String, dynamic>.from(srRow);
    map['datum'] = isoDate;
    map['pokupljen_iz_loga'] = jePokupljen;
    map['otkazano_iz_loga'] = jeOtkazan;
    map['placeno_iz_loga'] = jePlacen;
    if (iznos != null) map['cena'] = iznos;
    if (iznos != null) map['iznos_placanja'] = iznos;
    if (vozacId != null) map['vozac_id'] = vozacId;
    if (vozacIme != null) map['vozac_ime'] = vozacIme;
    if (logCreatedAt != null) map['log_created_at'] = logCreatedAt;
    if (pokupioVozac != null) map['pokupioVozac'] = pokupioVozac;
    if (pokupioVozacId != null) map['pokupioVozacId'] = pokupioVozacId;
    if (naplatioVozac != null) map['naplatioVozac'] = naplatioVozac;
    if (naplatioVozacId != null) map['naplatioVozacId'] = naplatioVozacId;
    if (otkazaoVozac != null) map['otkazaoVozac'] = otkazaoVozac;
    if (otkazaoVozacId != null) map['otkazaoVozacId'] = otkazaoVozacId;
    if (nazivAdrese != null) map['adrese'] = {'naziv': nazivAdrese};
    if (map['status'] == 'cancelled') map['status'] = 'otkazano';
    if (rp != null) map['registrovani_putnici'] = rp;
    return Putnik.fromSeatRequest(map);
  }

  Future<void> _doFetchForStream(
      String key, String? isoDate, String? grad, String? vreme, StreamController<List<Putnik>> controller,
      {String? vozacId}) async {
    try {
      final todayDate = (isoDate ?? DateTime.now().toIso8601String()).split('T')[0];
      final rm = RealtimeManager.instance;

      // Čekaj cache ako nije još inicijalizovan (race condition pri startu)
      if (!rm.isInitialized) {
        await Future.delayed(const Duration(milliseconds: 300));
      }

      // 📥 Učitaj sve putnike za traženi datum (cache za danas, DB za ostale)
      final sviPutnici = await getPutniciByDayIso(todayDate);

      final gradNorm = grad == null ? null : GradAdresaValidator.normalizeGrad(grad).toUpperCase();
      final vremeNorm = vreme != null ? GradAdresaValidator.normalizeTime(vreme) : null;
      final danKratica = _isoToDanKratica(todayDate);

      // Filtriraj po grad/vreme/vozacId
      final results = sviPutnici.where((p) {
        // Grad filter
        if (gradNorm != null) {
          final pGrad = GradAdresaValidator.normalizeGrad(p.grad).toUpperCase();
          if (pGrad != gradNorm) return false;
        }
        // Vreme filter
        if (vremeNorm != null) {
          final pVreme = GradAdresaValidator.normalizeTime(p.polazak);
          if (pVreme != vremeNorm) return false;
        }
        // vozacId filter — per-putnik override + per-termin raspored
        if (vozacId != null) {
          final putnikId = p.id?.toString() ?? '';
          // 1. Per-putnik override
          final override = rm.vozacPutnikCache.values
              .where((vp) => vp['putnik_id']?.toString() == putnikId)
              .firstOrNull;
          if (override != null) {
            return override['vozac_id']?.toString() == vozacId;
          }
          // 2. Per-termin raspored
          final rasporedZaTermin = rm.rasporedCache.values
              .where((vr) =>
                  vr['dan']?.toString() == danKratica &&
                  vr['grad']?.toString().toUpperCase() ==
                      GradAdresaValidator.normalizeGrad(p.grad).toUpperCase() &&
                  vr['vreme']?.toString() ==
                      GradAdresaValidator.normalizeTime(p.polazak))
              .toList();
          if (rasporedZaTermin.isEmpty) return true; // nema termina → vidljivo svima
          return rasporedZaTermin.any((vr) => vr['vozac_id']?.toString() == vozacId);
        }
        return true;
      }).toList();

      debugPrint(
          '🔍 [_doFetchForStream] key=$key, datum=$todayDate, grad=$gradNorm, vreme=$vremeNorm → ${results.length} putnika');

      _lastValues[key] = results;
      if (!controller.isClosed) controller.add(results);
      _setupRealtimeRefresh(key, isoDate, grad, vreme, controller);
    } catch (e) {
      debugPrint('⚠️ [PutnikService] Error in stream fetch: $e');
      if (!controller.isClosed) controller.add([]);
    }
  }

  /// Konvertuje ISO datum u kraticu dana ('pon', 'uto', ...)
  static String _isoToDanKratica(String iso) {
    const map = {1: 'pon', 2: 'uto', 3: 'sre', 4: 'cet', 5: 'pet', 6: 'sub', 7: 'ned'};
    return map[DateTime.tryParse(iso)?.weekday ?? 1]!;
  }

  void _setupRealtimeRefresh(
      String key, String? isoDate, String? grad, String? vreme, StreamController<List<Putnik>> controller) {
    // 🌐 SETUP GLOBALNIH SHARED LISTENER-A (samo ako već nisu kreirani)

    // Listener za seat_requests — ⚡ ažuriraj cache + patch putnika (0 DB upita)
    if (_globalSeatRequestsListener == null) {
      _globalSeatRequestsListener = RealtimeManager.instance.subscribe('seat_requests').listen((payload) {
        final record = payload.newRecord;
        final putnikId = record['putnik_id']?.toString();
        final recGrad = record['grad']?.toString();
        final recDan = record['dan']?.toString();
        final recVreme = (record['dodeljeno_vreme'] ?? record['zeljeno_vreme'])?.toString();

        debugPrint(
            '⚡ [PutnikService] seat_requests event: putnik=$putnikId, grad=$recGrad, dan=$recDan, vreme=$recVreme');

        // 1. Ažuriraj srCache direktno iz payloada
        RealtimeManager.instance.updateSrCache(record);

        if (putnikId != null && recGrad != null && recDan != null) {
          _patchPutnikInMatchingStreams(
            putnikId: putnikId,
            grad: recGrad,
            dan: recDan,
            vreme: recVreme,
          );
        } else {
          debugPrint('⚠️ [PutnikService] seat_requests payload nepotpun, fallback na full refresh');
          _debouncedRefreshAllStreams();
        }
      });
      debugPrint('✅ [PutnikService] Globalni seat_requests listener kreiran (cache+patch mode)');
    }

    // Listener za voznje_log — ⚡ ažuriraj cache + patch putnika (0 DB upita)
    if (_globalVoznjeLogListener == null) {
      _globalVoznjeLogListener = RealtimeManager.instance.subscribe('voznje_log').listen((payload) {
        final record = payload.newRecord;
        final putnikId = record['putnik_id']?.toString();
        final recDatum = record['datum']?.toString();
        final recGrad = record['grad']?.toString();
        final recVreme = record['vreme_polaska']?.toString();

        debugPrint(
            '⚡ [PutnikService] voznje_log event: putnik=$putnikId, datum=$recDatum, grad=$recGrad, vreme=$recVreme');

        // 1. Ažuriraj vlCache direktno iz payloada
        RealtimeManager.instance.updateVlCache(record);

        if (putnikId != null && recDatum != null) {
          _patchPutnikByIdInStreams(
            putnikId: putnikId,
            isoDate: recDatum.split('T')[0],
            grad: recGrad,
            vreme: recVreme,
          );
        } else {
          debugPrint('⚠️ [PutnikService] voznje_log payload nepotpun, fallback na full refresh');
          _debouncedRefreshAllStreams();
        }
      });
      debugPrint('✅ [PutnikService] Globalni voznje_log listener kreiran (cache+patch mode)');
    }

    // Listener za registrovani_putnici — ažuriraj rpCache + patch stream
    if (_globalRegistrovaniListener == null) {
      _globalRegistrovaniListener = RealtimeManager.instance.subscribe('registrovani_putnici').listen((payload) {
        final record = payload.newRecord;
        debugPrint('🔄 [PutnikService] registrovani_putnici event: ${payload.eventType}');
        // 1. Ažuriraj rpCache direktno iz payloada
        RealtimeManager.instance.updateRpCache(record);
        // 2. Refresh streamova za ovog putnika
        final putnikId = record['id']?.toString();
        if (putnikId != null) {
          final today = DateTime.now().toIso8601String().split('T')[0];
          _patchPutnikByIdInStreams(putnikId: putnikId, isoDate: today);
        } else {
          _debouncedRefreshAllStreams();
        }
      });
      debugPrint('✅ [PutnikService] Globalni registrovani_putnici listener kreiran (cache+patch mode)');
    }

    // Listener za vozac_putnik — kada se doda/promijeni/briše override, refresh svih streamova
    if (_globalVozacPutnikListener == null) {
      _globalVozacPutnikListener = RealtimeManager.instance.subscribe('vozac_putnik').listen((_) {
        debugPrint('🔄 [PutnikService] vozac_putnik promijenjen — full stream refresh');
        _debouncedRefreshAllStreams();
      });
      debugPrint('✅ [PutnikService] Globalni vozac_putnik listener kreiran');
    }

    // Listener za vozac_raspored — kada se doda/promijeni/briše termin, refresh svih streamova
    if (_globalVozacRasporedListener == null) {
      _globalVozacRasporedListener = RealtimeManager.instance.subscribe('vozac_raspored').listen((_) {
        debugPrint('🔄 [PutnikService] vozac_raspored promijenjen — full stream refresh');
        _debouncedRefreshAllStreams();
      });
      debugPrint('✅ [PutnikService] Globalni vozac_raspored listener kreiran');
    }
  }

  // ---------------------------------------------------------------------------
  // ⚡ PATCH METODE — osvježavaju samo jednog putnika u cache-u
  // ---------------------------------------------------------------------------

  /// Konvertuje tekstualni naziv dana u ISO datum (na osnovu najbližeg dana u
  /// aktivnim streamovima koji odgovaraju tom danu u sedmici).
  /// Ako `dan` već izgleda kao ISO datum (yyyy-mm-dd), vraća ga direktno.
  static String? _danToIsoDate(String dan, Iterable<String?> activeIsoDates) {
    // Ako je već ISO datum format
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dan)) return dan;

    // Mapa naziva dana na weekday broj (Dart: Mon=1, Sun=7)
    // Podržava i kratice (pon/uto...) koje baza/realtime koristi I pune nazive
    const danMap = {
      // Kratice iz seat_requests.dan kolone (realtime payload)
      'pon': 1, 'uto': 2, 'sre': 3, 'cet': 4, 'pet': 5, 'sub': 6, 'ned': 7,
      // Puni nazivi (fallback)
      'ponedeljak': 1, 'utorak': 2, 'sreda': 3, 'cetvrtak': 4,
      'petak': 5, 'subota': 6, 'nedelja': 7,
    };
    final targetWeekday = danMap[dan.toLowerCase()];
    if (targetWeekday == null) return null;

    // Traži u aktivnim stream datumima koji odgovara ovom danu
    for (final iso in activeIsoDates) {
      if (iso == null || iso.isEmpty) continue;
      try {
        final dt = DateTime.parse(iso);
        if (dt.weekday == targetWeekday) return iso;
      } catch (_) {}
    }
    return null;
  }

  /// ⚡ Fetcha jednog putnika i patchi ga u svim matchujućim streamovima.
  /// Koristi se za `seat_requests` realtime evente.
  Future<void> _patchPutnikInMatchingStreams({
    required String putnikId,
    required String grad,
    required String dan,
    String? vreme,
  }) async {
    // Pronađi ISO datum na osnovu 'dan' polja i aktivnih streamova
    final activeIsoDates = _streamParams.values.map((p) => p.isoDate);
    final isoDate = _danToIsoDate(dan, activeIsoDates);

    if (isoDate == null) {
      debugPrint('⚠️ [PutnikService] Ne mogu konvertovati dan="$dan" u ISO datum, fallback full refresh');
      _debouncedRefreshAllStreams();
      return;
    }

    await _patchPutnikByIdInStreams(putnikId: putnikId, isoDate: isoDate, grad: grad, vreme: vreme);
  }

  /// ⚡ Patchi jednog putnika u svim streamovima direktno iz cache-a (0 DB upita).
  /// Koristi se za seat_requests i voznje_log realtime evente.
  Future<void> _patchPutnikByIdInStreams({
    required String putnikId,
    required String isoDate,
    String? grad,
    String? vreme,
  }) async {
    // Pronađi seat_request iz cache-a za ovog putnika
    Putnik? svjezPutnik;
    try {
      final rm = RealtimeManager.instance;

      // Nađi seat_request red za ovog putnika iz srCache
      final srRow = rm.srCache.values.where((r) => r['putnik_id']?.toString() == putnikId).firstOrNull;

      if (srRow != null) {
        // Sve voznje_log redove za ovog putnika (za tekući dan)
        final vlRows = rm.vlCache.values.where((r) => r['putnik_id']?.toString() == putnikId).toList();

        // Profil iz rpCache
        final rp = rm.rpCache[putnikId];

        // JOIN u Dart-u — 0 DB upita
        svjezPutnik = _buildPutnik(srRow, vlRows, rp, isoDate);
      }
    } catch (e) {
      debugPrint('⚠️ [PutnikService] Patch cache error za putnik=$putnikId: $e, fallback full refresh');
      _debouncedRefreshAllStreams();
      return;
    }

    // Patchi u svim matchujućim aktivnim streamovima
    int patchedCount = 0;
    for (final entry in _streams.entries) {
      final key = entry.key;
      final controller = entry.value;
      if (controller.isClosed) continue;

      final params = _streamParams[key];
      if (params == null) continue;

      // Match kriteriji: isti datum i grad (ako je grad zadan)
      final keyDate = (params.isoDate ?? '').split('T')[0];
      if (keyDate != isoDate) continue;
      if (grad != null) {
        final gradNorm = GradAdresaValidator.normalizeGrad(grad).toLowerCase();
        final paramsGrad = params.grad != null ? GradAdresaValidator.normalizeGrad(params.grad!).toLowerCase() : null;
        if (paramsGrad != null && paramsGrad != gradNorm) continue;
      }
      // vreme filter: ako stream ima specifičan vreme, provjeri matchuje li
      if (vreme != null && params.vreme != null) {
        final vremeNorm = '${GradAdresaValidator.normalizeTime(vreme)}:00';
        final paramsVremeNorm = '${GradAdresaValidator.normalizeTime(params.vreme!)}:00';
        if (vremeNorm != paramsVremeNorm) continue;
      }

      final current = List<Putnik>.from(_lastValues[key] ?? []);

      if (svjezPutnik == null ||
          svjezPutnik.status == 'bez_polaska' ||
          svjezPutnik.status == 'cancelled' ||
          svjezPutnik.status == 'otkazano') {
        // Putnik treba biti uklonjen iz liste
        final before = current.length;
        current.removeWhere((p) => p.id?.toString() == putnikId);
        if (current.length != before) {
          _lastValues[key] = current;
          controller.add(current);
          debugPrint('⚡ [PutnikService] PATCH uklonjen putnik=$putnikId iz stream=$key');
          patchedCount++;
        }
      } else {
        // Dodaj ili zamijeni putnika
        final idx = current.indexWhere((p) => p.id?.toString() == putnikId);
        if (idx >= 0) {
          current[idx] = svjezPutnik;
          debugPrint(
              '⚡ [PutnikService] PATCH zamijenjen putnik=$putnikId u stream=$key (status=${svjezPutnik.status})');
        } else {
          current.add(svjezPutnik);
          debugPrint(
              '⚡ [PutnikService] PATCH dodan novi putnik=$putnikId u stream=$key (status=${svjezPutnik.status})');
        }
        _lastValues[key] = current;
        controller.add(current);
        patchedCount++;
      }
    }

    if (patchedCount == 0) {
      debugPrint('⚡ [PutnikService] PATCH putnik=$putnikId nije našao matching stream (datum=$isoDate, grad=$grad)');
    }
  }

  /// 📉 EGRESS OPT: Debounce — čeka 600ms od zadnjeg eventa pa tek onda refreshuje
  /// Sprječava N×fetch kad korisnik brzo označi više putnika ili dođe burst eventa
  void _debouncedRefreshAllStreams() {
    _refreshDebounceTimer?.cancel();
    _refreshDebounceTimer = Timer(const Duration(milliseconds: 600), () {
      _refreshAllActiveStreams();
    });
  }

  /// 🔄 Refreshuje SVE aktivne streamove
  void _refreshAllActiveStreams() {
    debugPrint('🔄 [PutnikService] _refreshAllActiveStreams: ${_streams.length} aktivnih streamova');
    for (final entry in _streams.entries) {
      final key = entry.key;
      final controller = entry.value;
      final params = _streamParams[key];
      if (params != null && !controller.isClosed) {
        debugPrint(
            '🔄 [PutnikService] Refreshujem stream: isoDate=${params.isoDate}, grad=${params.grad}, vreme=${params.vreme}, vozacId=${params.vozacId}');
        _doFetchForStream(key, params.isoDate, params.grad, params.vreme, controller, vozacId: params.vozacId);
      }
    }
  }

  /// 🔄 PUBLIC metoda za eksplicitno refresh-ovanje streamova (npr. posle dodavanja putnika)
  void refreshAllActiveStreams() {
    debugPrint('🔄 [PutnikService] Eksplicitan refresh svih aktivnih streamova');
    _refreshAllActiveStreams();
  }

  static final Map<String, DateTime> _lastActionTime = {};
  static bool _isDuplicateAction(String key) {
    final now = DateTime.now();
    if (_lastActionTime.containsKey(key) && now.difference(_lastActionTime[key]!) < const Duration(milliseconds: 500)) {
      return true;
    }
    _lastActionTime[key] = now;
    return false;
  }

  Future<Putnik?> getPutnikByName(String ime, {String? grad}) async {
    final todayStr = DateTime.now().toIso8601String().split('T')[0];
    final rm = RealtimeManager.instance;

    // Nađi putnik_id po imenu iz rpCache
    final rpEntry = rm.rpCache.values.where((r) => r['putnik_ime']?.toString() == ime).firstOrNull;
    if (rpEntry == null) return null;
    final putnikId = rpEntry['id']?.toString();
    if (putnikId == null) return null;

    // Nađi seat_request za ovog putnika iz srCache
    final srRow = rm.srCache.values.where((r) => r['putnik_id']?.toString() == putnikId).firstOrNull;
    if (srRow != null) {
      final vlRows = rm.vlCache.values.where((vl) => vl['putnik_id']?.toString() == putnikId).toList();
      return _buildPutnik(srRow, vlRows, rpEntry, todayStr);
    }

    // Fallback na profil ako nema današnjeg seat_request-a
    return Putnik.fromRegistrovaniPutnici(rpEntry);
  }

  Future<Putnik?> getPutnikFromAnyTable(dynamic id) async {
    try {
      final todayStr = DateTime.now().toIso8601String().split('T')[0];
      final idStr = id.toString();
      final rm = RealtimeManager.instance;

      final srRow = rm.srCache.values.where((r) => r['putnik_id']?.toString() == idStr).firstOrNull;
      final rp = rm.rpCache[idStr];

      if (srRow != null) {
        final vlRows = rm.vlCache.values.where((vl) => vl['putnik_id']?.toString() == idStr).toList();
        return _buildPutnik(srRow, vlRows, rp, todayStr);
      }
      if (rp != null) return Putnik.fromRegistrovaniPutnici(rp);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<Putnik>> getPutniciByIds(List<dynamic> ids, {String? targetDan, String? isoDate}) async {
    if (ids.isEmpty) return [];
    try {
      final String danasStr = (isoDate ?? DateTime.now().toIso8601String()).split('T')[0];
      final idStrings = ids.map((id) => id.toString()).toSet();
      final rm = RealtimeManager.instance;

      return rm.srCache.values
          .where((sr) => idStrings.contains(sr['putnik_id']?.toString()))
          .map((sr) {
            final putnikId = sr['putnik_id']?.toString();
            final vlRows = putnikId != null
                ? rm.vlCache.values.where((vl) => vl['putnik_id']?.toString() == putnikId).toList()
                : <Map<String, dynamic>>[];
            final rp = putnikId != null ? rm.rpCache[putnikId] : null;
            return _buildPutnik(sr, vlRows, rp, danasStr);
          })
          .where((p) => p.status != 'bez_polaska' && p.status != 'cancelled')
          .toList();
    } catch (e) {
      debugPrint('⚠️ [PutnikService] Error in getPutniciByIds: $e');
      return [];
    }
  }

  Future<List<Putnik>> getAllPutnici({String? targetDay, String? isoDate}) async {
    try {
      final String danasStr = (isoDate ?? DateTime.now().toIso8601String()).split('T')[0];
      final rm = RealtimeManager.instance;

      return rm.srCache.values
          .map((sr) {
            final putnikId = sr['putnik_id']?.toString();
            final vlRows = putnikId != null
                ? rm.vlCache.values.where((vl) => vl['putnik_id']?.toString() == putnikId).toList()
                : <Map<String, dynamic>>[];
            final rp = putnikId != null ? rm.rpCache[putnikId] : null;
            return _buildPutnik(sr, vlRows, rp, danasStr);
          })
          .where((p) => p.status != 'bez_polaska' && p.status != 'cancelled')
          .toList();
    } catch (e) {
      debugPrint('⚠️ [PutnikService] Error in getAllPutnici: $e');
      return [];
    }
  }

  Future<void> dodajPutnika(Putnik putnik, {bool skipKapacitetCheck = false}) async {
    debugPrint('🔍 [PutnikService] dodajPutnika: ime="${putnik.ime}"');

    final res = await supabase
        .from('registrovani_putnici')
        .select('id, tip')
        .eq('putnik_ime', putnik.ime)
        .eq('aktivan', true)
        .eq('obrisan', false)
        .maybeSingle();

    debugPrint('🔍 [PutnikService] Query result: ${res != null ? "FOUND id=${res['id']}" : "NOT FOUND"}');

    if (res == null) {
      throw Exception('Putnik "${putnik.ime}" nije pronađen u bazi ili nije aktivan');
    }
    final putnikId = res['id'];

    final gradKey = GradAdresaValidator.normalizeGrad(putnik.grad);
    final normVreme = GradAdresaValidator.normalizeTime(putnik.polazak);
    final danKey = putnik.dan.toLowerCase();

    // ⛔ Postavi sve DRUGE aktivne termine za isti dan+grad na 'bez_polaska'
    // Putnik ide samo jednim terminom — poređenje po zeljeno_vreme (cekaonica/identifikator reda)
    // voznje_log se NE dira — nema uticaja na statistiku
    try {
      await supabase
          .from('seat_requests')
          .update({
            'status': 'bez_polaska',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('putnik_id', putnikId.toString())
          .eq('dan', danKey)
          .eq('grad', gradKey)
          .neq('zeljeno_vreme', '$normVreme:00')
          .inFilter('status', ['pending', 'manual', 'approved', 'confirmed']);
      debugPrint('🔄 [dodajPutnika] Stari termini ($gradKey/$danKey ≠ $normVreme) → bez_polaska');
    } catch (e) {
      debugPrint('⚠️ [dodajPutnika] Greška pri postavljanju starih termina na bez_polaska: $e');
    }

    await SeatRequestService.insertSeatRequest(
      putnikId: putnikId.toString(),
      dan: putnik.dan,
      vreme: putnik.polazak,
      grad: putnik.grad,
      brojMesta: putnik.brojMesta,
      status: 'confirmed', // Vozač ga je dodao ručno
      customAdresaId: putnik.adresaId,
    );
  }

  Future<void> oznaciPokupljen(dynamic id, bool value,
      {String? grad, String? vreme, String? driver, String? datum, String? requestId}) async {
    if (_isDuplicateAction('pickup_$id')) return;
    if (!value) {
      return; // 🚫 "Undo" funkcija uklonjena - ne dozvoljavamo poništavanje pokupljenja
    }

    final targetDatum = datum ?? DateTime.now().toIso8601String().split('T')[0];

    // ✅ DIREKTAN QUERY: Dohvati vozac_id iz baze umesto VozacMappingService
    String? vozacId;
    if (driver != null) {
      try {
        final vozacData = await supabase.from('vozaci').select('id').eq('ime', driver).maybeSingle();
        vozacId = vozacData?['id'] as String?;
      } catch (e) {
        debugPrint('⚠️ [oznaciPokupljen] Greška pri dohvatanju vozača "$driver": $e');
      }
    }

    // 1. Označi status='pokupljen' u seat_requests (operativno stanje)
    try {
      if (requestId != null && requestId.isNotEmpty) {
        await supabase.from('seat_requests').update({
          'status': 'pokupljen',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'processed_at': DateTime.now().toUtc().toIso8601String(),
          if (driver != null) 'pokupljeno_by': driver,
        }).eq('id', requestId);
        debugPrint('✅ [oznaciPokupljen] seat_requests status=pokupljen (requestId=$requestId)');
      } else {
        // Fallback: match po putnik_id + datum + grad + vreme (PRAVILO: DAN+GRAD+VREME)
        final gradKey = grad != null ? GradAdresaValidator.normalizeGrad(grad) : null;
        final vremeKey = vreme != null ? '${GradAdresaValidator.normalizeTime(vreme)}:00' : null;
        String? danKey;
        try {
          final dt = DateTime.parse(targetDatum);
          const dani = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
          danKey = dani[dt.weekday - 1];
        } catch (_) {}
        if (gradKey == null || vremeKey == null || danKey == null) {
          debugPrint('⛔ [oznaciPokupljen] Nedostaje grad, vreme ili dan — ne mogu da označim pokupljenim!');
        } else {
          await supabase
              .from('seat_requests')
              .update({
                'status': 'pokupljen',
                'updated_at': DateTime.now().toUtc().toIso8601String(),
                'processed_at': DateTime.now().toUtc().toIso8601String(),
                if (driver != null) 'pokupljeno_by': driver,
              })
              .eq('putnik_id', id.toString())
              .eq('dan', danKey)
              .eq('grad', gradKey)
              .eq('zeljeno_vreme', vremeKey);
          debugPrint(
              '✅ [oznaciPokupljen] seat_requests status=pokupljen (dan=$danKey, grad=$gradKey, vreme=$vremeKey)');
        }
      }
    } catch (e) {
      debugPrint('⚠️ [oznaciPokupljen] Greška pri update seat_requests: $e');
    }

    // 2. Upiši u voznje_log (TRAJNI ZAPIS ZA STATISTIKU - nikad se ne briše)
    final existing = await VoznjeLogService.getLogEntry(
      putnikId: id.toString(),
      datum: targetDatum,
      tip: 'voznja',
      grad: grad,
      vreme: vreme,
    );

    if (existing == null) {
      await VoznjeLogService.logGeneric(
        tip: 'voznja',
        putnikId: id.toString(),
        vozacId: vozacId,
        vozacImeOverride: vozacId == null ? driver : null,
        datum: targetDatum,
        grad: grad,
        vreme: vreme,
      );
    }
  }

  /// 🏖️ POSTAVLJA PUTNIKA NA BOLOVANJE ILI GODIŠNJI
  /// Takođe otkazuje njegove vožnje u seat_requests za taj dan ili period
  Future<void> oznaciBolovanjeGodisnji(String putnikId, String status, String actor) async {
    try {
      // 1. Ažuriraj status putnika
      await supabase.from('registrovani_putnici').update({
        'status': status,
        'updated_at': nowToString(),
      }).eq('id', putnikId);

      // 2. Ako je na bolovanju/godišnjem, otkaži sve pending seat_requests za DANAS i SUTRA
      if (status == 'bolovanje' || status == 'godisnji') {
        final danasDay = DateTime.now().weekday;
        final sutraDay = DateTime.now().add(const Duration(days: 1)).weekday;
        const dani = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
        final danasKratica = dani[danasDay - 1];
        final sutraKratica = dani[sutraDay - 1];

        await supabase
            .from('seat_requests')
            .update({'status': 'cancelled', 'updated_at': nowToString()})
            .eq('putnik_id', putnikId)
            .inFilter('dan', [danasKratica, sutraKratica])
            .inFilter('status', ['pending', 'manual', 'approved', 'confirmed']);

        debugPrint('🏖️ [PutnikService] Otkazane vožnje za putnika $putnikId (status: $status)');
      }
    } catch (e) {
      debugPrint('❌ [PutnikService] Error setting bolovanje/godisnji: $e');
      rethrow;
    }
  }

  String nowToString() => DateTime.now().toUtc().toIso8601String();

  Future<void> ukloniPolazak(
    dynamic id, {
    String? grad,
    String? vreme,
    String? selectedDan,
    String? selectedVreme,
    String? selectedGrad,
    String? datum,
    String? requestId,
  }) async {
    debugPrint('🗑️ [PutnikService] ukloniPolazak: id=$id, requestId=$requestId');

    // 1. PRIORITET: Match po requestId
    if (requestId != null && requestId.isNotEmpty) {
      try {
        final res = await supabase
            .from('seat_requests')
            .update({
              'status': 'bez_polaska',
              'processed_at': DateTime.now().toUtc().toIso8601String(),
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', requestId)
            .select();

        if (res.isNotEmpty) {
          debugPrint('🗑️ [PutnikService] ukloniPolazak SUCCESS (by requestId)');
          return;
        }
      } catch (e) {
        debugPrint('⚠️ [PutnikService] Error matching by requestId in ukloniPolazak: $e');
      }
    }

    // FALLBACK na stare parametre
    final finalDan = selectedDan;
    final finalVreme = selectedVreme ?? vreme;
    final finalGrad = selectedGrad ?? grad;

    String danKey;
    if (finalDan != null && finalDan.isNotEmpty) {
      danKey = finalDan.toLowerCase();
    } else if (datum != null) {
      try {
        final dt = DateTime.parse(datum);
        const dani = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
        danKey = dani[dt.weekday - 1];
      } catch (_) {
        const dani = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
        danKey = dani[DateTime.now().weekday - 1];
      }
    } else {
      const dani = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
      danKey = dani[DateTime.now().weekday - 1];
    }

    final gradKey = GradAdresaValidator.normalizeGrad(finalGrad);
    final normalizedTime = GradAdresaValidator.normalizeTime(finalVreme);
    debugPrint('🗑️ [PutnikService] ukloniPolazak (fallback): dan=$danKey, grad=$gradKey, time=$normalizedTime');
    debugPrint(
        '🔍 [PutnikService] ukloniPolazak query: putnik_id=$id, dan=$danKey, grad=$gradKey, zeljeno_vreme=$normalizedTime:00');

    try {
      if (normalizedTime.isNotEmpty) {
        var res = await supabase
            .from('seat_requests')
            .update({
              'status': 'bez_polaska',
              'processed_at': DateTime.now().toUtc().toIso8601String(),
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .match({'putnik_id': id.toString(), 'dan': danKey})
            .eq('grad', gradKey)
            .eq('zeljeno_vreme', '$normalizedTime:00')
            .select();

        if (res.isNotEmpty) {
          debugPrint('🗑️ [PutnikService] ukloniPolazak SUCCESS (zeljeno_vreme): ${res.length} rows');
          return;
        }

        debugPrint('⚠️ [PutnikService] No match by zeljeno_vreme, trying dodeljeno_vreme...');
        res = await supabase
            .from('seat_requests')
            .update({
              'status': 'bez_polaska',
              'processed_at': DateTime.now().toUtc().toIso8601String(),
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .match({'putnik_id': id.toString(), 'dan': danKey})
            .eq('grad', gradKey)
            .eq('dodeljeno_vreme', '$normalizedTime:00')
            .select();

        if (res.isNotEmpty) {
          debugPrint('🗑️ [PutnikService] ukloniPolazak SUCCESS (dodeljeno_vreme): ${res.length} rows');
          return;
        }
      }

      debugPrint('⚠️ [PutnikService] No match by vremena, trying without time filter...');
      final res = await supabase
          .from('seat_requests')
          .update({
            'status': 'bez_polaska',
            'processed_at': DateTime.now().toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .match({'putnik_id': id.toString(), 'dan': danKey})
          .eq('grad', gradKey)
          .select();

      debugPrint('🗑️ [PutnikService] ukloniPolazak (fallback): updated ${res.length} rows');
    } catch (e) {
      debugPrint('❌ [PutnikService] ukloniPolazak ERROR: $e');
      rethrow;
    }
  }

  Future<void> otkaziPutnika(
    dynamic id,
    String? driver, {
    String? grad,
    String? vreme,
    String? selectedDan,
    String? selectedVreme,
    String? selectedGrad,
    String? datum,
    String? requestId,
    String status = 'otkazano',
  }) async {
    debugPrint('🛑 [PutnikService] otkaziPutnika: id=$id, requestId=$requestId, status=$status');

    // ✅ LOGOVANJE AKCIJE (sa gradom i vremenom za preciznost)
    try {
      String? vozacUuid;
      if (driver != null) {
        vozacUuid = VozacCache.getUuidByIme(driver);
      }

      await VoznjeLogService.logGeneric(
        tip: 'otkazivanje',
        putnikId: id.toString(),
        vozacId: vozacUuid,
        vozacImeOverride: vozacUuid == null ? driver : null, // 'Putnik', 'Admin', itd.
        grad: selectedGrad ?? grad,
        vreme: selectedVreme ?? vreme,
        datum: datum,
      );
    } catch (e) {
      debugPrint('⚠️ [PutnikService] Greška pri logovanju otkazivanja: $e');
    }

    // 1. PRIORITET: Match po requestId
    if (requestId != null && requestId.isNotEmpty) {
      try {
        final res = await supabase
            .from('seat_requests')
            .update({
              'status': status,
              'processed_at': DateTime.now().toUtc().toIso8601String(),
              'updated_at': DateTime.now().toUtc().toIso8601String(),
              if (driver != null) 'cancelled_by': driver,
            })
            .eq('id', requestId)
            .select();

        if (res.isNotEmpty) {
          debugPrint('🛑 [PutnikService] otkaziPutnika SUCCESS (by requestId)');
          return;
        }
      } catch (e) {
        debugPrint('⚠️ [PutnikService] Error matching by requestId in otkaziPutnika: $e');
      }
    }

    final finalDan2 = selectedDan;
    final finalVreme2 = selectedVreme ?? vreme;
    final finalGrad2 = selectedGrad ?? grad;

    String danKey2;
    if (finalDan2 != null && finalDan2.isNotEmpty) {
      danKey2 = finalDan2.toLowerCase();
    } else if (datum != null) {
      try {
        final dt = DateTime.parse(datum);
        const dani = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
        danKey2 = dani[dt.weekday - 1];
      } catch (_) {
        const dani = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
        danKey2 = dani[DateTime.now().weekday - 1];
      }
    } else {
      const dani = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
      danKey2 = dani[DateTime.now().weekday - 1];
    }

    final gradKey = GradAdresaValidator.normalizeGrad(finalGrad2);
    final normalizedTime = GradAdresaValidator.normalizeTime(finalVreme2);
    debugPrint('🛑 [PutnikService] otkaziPutnika (fallback): dan=$danKey2, grad=$gradKey, time=$normalizedTime');

    try {
      if (normalizedTime.isNotEmpty) {
        var res = await supabase
            .from('seat_requests')
            .update({
              'status': status,
              'processed_at': DateTime.now().toUtc().toIso8601String(),
              'updated_at': DateTime.now().toUtc().toIso8601String(),
              if (driver != null) 'cancelled_by': driver,
            })
            .match({'putnik_id': id.toString(), 'dan': danKey2})
            .eq('grad', gradKey)
            .eq('zeljeno_vreme', '$normalizedTime:00')
            .select();

        if (res.isNotEmpty) {
          debugPrint('🛑 [PutnikService] otkaziPutnika SUCCESS (zeljeno_vreme)');
          return;
        }

        res = await supabase
            .from('seat_requests')
            .update({
              'status': status,
              'processed_at': DateTime.now().toUtc().toIso8601String(),
              'updated_at': DateTime.now().toUtc().toIso8601String(),
              if (driver != null) 'cancelled_by': driver,
            })
            .match({'putnik_id': id.toString(), 'dan': danKey2})
            .eq('grad', gradKey)
            .eq('dodeljeno_vreme', '$normalizedTime:00')
            .select();

        if (res.isNotEmpty) {
          debugPrint('🛑 [PutnikService] otkaziPutnika SUCCESS (dodeljeno_vreme)');
          return;
        }
      }

      // ⛔ ZABRANJENO: fallback bez vremena narušava DAN+GRAD+VREME pravilo
      // Ako nije pronađen termin po zeljeno_vreme ni dodeljeno_vreme — logujemo grešku, NE diramo ništa
      debugPrint(
          '⛔ [PutnikService] otkaziPutnika: nije pronađen termin za dan=$danKey2, grad=$gradKey, vreme=$normalizedTime — NE diram druge termine!');
    } catch (e) {
      debugPrint('❌ [PutnikService] otkaziPutnika ERROR: $e');
      rethrow;
    }
  }

  Future<void> oznaciPlaceno(
    dynamic id,
    num iznos,
    String? driver, {
    String? grad,
    String? selectedVreme,
    String? selectedDan,
    String? requestId, // 🆕 Dodato
  }) async {
    // ✅ Uvek koristi DANAŠNJI datum za uplatu — naplata se vrši u realnom vremenu,
    // ne za budući dan na koji se selectedDan odnosi u seat_requests
    final dateStr = DateTime.now().toIso8601String().split('T')[0];

    // ✅ DIREKTAN QUERY: Dohvati vozac_id iz baze umesto VozacMappingService
    String? vozacId;
    if (driver != null) {
      try {
        final vozacData = await supabase.from('vozaci').select('id').eq('ime', driver).maybeSingle();
        vozacId = vozacData?['id'] as String?;
        debugPrint('💰 [oznaciPlaceno] driver="$driver" → vozacId=$vozacId');
      } catch (e) {
        debugPrint('⚠️ [oznaciPlaceno] Greška pri dohvatanju vozača "$driver": $e');
      }
    } else {
      debugPrint('⚠️ [oznaciPlaceno] driver je NULL!');
    }

    // 💰 Plaćanje se evidentira SAMO u voznje_log (izvor istine za finansije)
    // seat_requests.status se NE mijenja - 'pokupljen' ostaje 'pokupljen', 'confirmed' ostaje 'confirmed'
    // Dodaj u voznje_log preko servisa (sa gradom i vremenom za preciznost)
    await VoznjeLogService.dodajUplatu(
      putnikId: id.toString(),
      datum: DateTime.parse(dateStr),
      iznos: iznos.toDouble(),
      vozacId: vozacId,
      vozacImeParam: driver, // ✅ fallback: direktno ime vozača ako UUID lookup ne uspe
      grad: grad,
      vreme: selectedVreme,
    );
  }

  /// 🚫 GLOBALNO UKLONI POLAZAK: Postavlja 'bez_polaska' status za sve putnike u datom terminu
  Future<int> globalniBezPolaska({
    required String dan,
    required String grad,
    required String vreme,
  }) async {
    try {
      final gradKey = GradAdresaValidator.normalizeGrad(grad);

      var query = supabase.from('seat_requests').update({
        'status': 'bez_polaska',
        'processed_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).match({
        'dan': dan.toLowerCase(),
      }).eq('grad', gradKey);

      if (vreme.isNotEmpty) {
        query = query.eq('zeljeno_vreme', '${GradAdresaValidator.normalizeTime(vreme)}:00');
      }

      final res = await query.select();
      debugPrint('🚫 [PutnikService] globalniBezPolaska: updated ${res.length} rows');
      return res.length;
    } catch (e) {
      debugPrint('❌ [PutnikService] globalniBezPolaska ERROR: $e');
      return 0;
    }
  }

  /// 👤 AŽURIRA DODELJENOG VOZAČA ZA PUTNIKA
  /// Delegira na VozacPutnikService (tabela vozac_putnik).
  /// Ako je vozacIme prazan string → briše override.
  Future<bool> updatePutnikVozac({
    required dynamic putnikId,
    required String vozacIme,
    required String dan,
    required String grad,
    required String vreme,
  }) async {
    try {
      final result = await VozacPutnikService().set(
        putnikId: putnikId.toString(),
        vozacIme: vozacIme,
        dan: dan,
        grad: grad,
        vreme: vreme,
      );
      if (result) {
        debugPrint('✅ [updatePutnikVozac] putnik=$putnikId → vozac="$vozacIme"');
      } else {
        debugPrint('❌ [updatePutnikVozac] Neuspješno za vozac="$vozacIme"');
      }
      return result;
    } catch (e) {
      debugPrint('❌ [updatePutnikVozac] Greška: $e');
      return false;
    }
  }
}
