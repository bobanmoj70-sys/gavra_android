import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart' as globals_file;
import '../models/v2_putnik.dart';
import '../utils/v2_grad_adresa_validator.dart';
import '../utils/v2_vozac_cache.dart';
import 'realtime/v2_master_realtime_manager.dart';
import 'v2_polasci_service.dart';
import 'v2_statistika_istorija_service.dart';

class _StreamParams {
  _StreamParams({this.isoDate, this.grad, this.vreme, this.vozacId});
  final String? isoDate;
  final String? grad;
  final String? vreme;
  final String? vozacId;
}

class V2PutnikStreamService {
  SupabaseClient get supabase => globals_file.supabase;

  static final Map<String, StreamController<List<V2Putnik>>> _streams = {};
  static final Map<String, List<V2Putnik>> _lastValues = {};
  static final Map<String, _StreamParams> _streamParams = {};

  // 🌐 GLOBALNI SHARED LISTENER-I (jedan po tabeli, ne po stream key-u)
  static StreamSubscription? _globalSeatRequestsListener;
  static StreamSubscription? _globalVoznjeLogListener;
  static StreamSubscription? _globalRegistrovaniListener;
  static StreamSubscription? _globalVozacRasporedListener;
  static StreamSubscription? _globalVozacPutnikListener;

  static Timer? _refreshDebounceTimer;

  String _streamKey({String? isoDate, String? grad, String? vreme, String? vozacId}) =>
      '${isoDate ?? ''}|${grad ?? ''}|${vreme ?? ''}|${vozacId ?? ''}';

  Stream<List<V2Putnik>> streamKombinovaniPutniciFiltered(
      {String? isoDate, String? grad, String? vreme, String? vozacId}) {
    final key = _streamKey(isoDate: isoDate, grad: grad, vreme: vreme, vozacId: vozacId);
    if (_streams.containsKey(key) && !_streams[key]!.isClosed) {
      final controller = _streams[key]!;
      if (_lastValues.containsKey(key)) {
        Future.microtask(() {
          if (!controller.isClosed) controller.add(_lastValues[key]!);
        });
      } else {
        _fetchAndEmit(key, isoDate, grad, vreme, controller, vozacId: vozacId);
      }
      return controller.stream;
    }
    final controller = StreamController<List<V2Putnik>>.broadcast();
    _streams[key] = controller;
    _streamParams[key] = _StreamParams(isoDate: isoDate, grad: grad, vreme: vreme, vozacId: vozacId);
    _fetchAndEmit(key, isoDate, grad, vreme, controller, vozacId: vozacId);
    controller.onCancel = () {
      _streams.remove(key);
      _lastValues.remove(key);
      _streamParams.remove(key);

      // ✅ Zatvori globalne listener-e ako nema više aktivnih streamova
      if (_streams.isEmpty) {
        _globalSeatRequestsListener?.cancel();
        _globalVoznjeLogListener?.cancel();
        _globalRegistrovaniListener?.cancel();
        _globalVozacRasporedListener?.cancel();
        _globalVozacPutnikListener?.cancel();
        _globalSeatRequestsListener = null;
        _globalVoznjeLogListener = null;
        _globalRegistrovaniListener = null;
        _globalVozacRasporedListener = null;
        _globalVozacPutnikListener = null;
        debugPrint('🛑 [V2PutnikStreamService] Svi streamovi zatvoreni - globalni listener-i otkazani');
      }
    };
    return controller.stream;
  }

  Stream<List<V2Putnik>> streamPutnici() {
    // 🆕 REDIREKCIJA NA IZVOR ISTINE (seat_requests)
    final todayDate = DateTime.now().toIso8601String().split('T')[0];
    return streamKombinovaniPutniciFiltered(isoDate: todayDate);
  }

  Future<List<V2Putnik>> getPutniciByDayIso(String isoDate) async {
    try {
      final todayDate = isoDate.split('T')[0];
      final rm = V2MasterRealtimeManager.instance;
      // Ako je traženi datum jednak cache datumu, čitaj iz cache-a
      if (rm.loadedDate == todayDate && rm.isInitialized) {
        return rm.polasciCache.values
            .map((sr) {
              final putnikId = sr['putnik_id']?.toString();
              final vlRows = putnikId != null
                  ? rm.statistikaCache.values.where((vl) => vl['putnik_id']?.toString() == putnikId).toList()
                  : <Map<String, dynamic>>[];
              final rp = putnikId != null ? rm.getPutnikById(putnikId) : null;
              return _buildPutnik(sr, vlRows, rp, todayDate);
            })
            .where((p) => p.status != 'bez_polaska' && p.status != 'cancelled')
            .toList();
      }
      // Fallback: direktni upit za drugi datum (ne danas)
      final dan = _isoToDanKratica(todayDate);
      final srRows = await supabase
          .from('v2_polasci')
          .select('id, putnik_id, grad, zeljeno_vreme, dodeljeno_vreme, status, '
              'created_at, updated_at, processed_at, priority, broj_mesta, '
              'custom_adresa_id, alternative_vreme_1, alternative_vreme_2, '
              'cancelled_by, pokupljeno_by, dan, tip_putnika')
          .eq('dan', dan)
          .inFilter('status',
              ['pending', 'manual', 'approved', 'confirmed', 'otkazano', 'cancelled', 'bez_polaska', 'pokupljen']);
      final vlRows = await supabase
          .from('v2_statistika_istorija')
          .select('id, putnik_id, datum, tip, iznos, vozac_id, vozac_ime, grad, vreme as vreme_polaska, created_at')
          .eq('datum', todayDate);
      final vlByPutnik = <String, List<Map<String, dynamic>>>{};
      for (final vl in vlRows) {
        final pid = vl['putnik_id']?.toString() ?? '';
        vlByPutnik.putIfAbsent(pid, () => []).add(Map<String, dynamic>.from(vl));
      }
      return srRows
          .map((sr) {
            final pid = sr['putnik_id']?.toString();
            final rp = pid != null ? V2MasterRealtimeManager.instance.getPutnikById(pid) : null;
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

  /// Gradi V2Putnik objekat iz cache redova.
  static V2Putnik _buildPutnik(
    Map<String, dynamic> srRow,
    List<Map<String, dynamic>> vlRows,
    Map<String, dynamic>? rp,
    String isoDate,
  ) {
    final srGrad = (srRow['grad'] ?? '').toString().toUpperCase();
    final srVreme = (srRow['dodeljeno_vreme'] ?? srRow['zeljeno_vreme'])?.toString();

    // Filtriraj voznje_log samo za isti grad i vreme
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

    // vreme_placanja — created_at iz prve uplata/uplata_dnevna
    final String? vremeUplate = uplataRows.isNotEmpty ? uplataRows.first['created_at']?.toString() : null;

    // otkazaoVozac — vozac_ime iz otkazivanje reda
    final otkazRows = matchedVl.where((vl) => vl['tip'] == 'otkazivanje').toList();
    final String? otkazaoVozac = otkazRows.isNotEmpty ? otkazRows.first['vozac_ime']?.toString() : null;
    final String? otkazaoVozacId = otkazRows.isNotEmpty ? otkazRows.first['vozac_id']?.toString() : null;
    final String? vremeOtkazivanja = otkazRows.isNotEmpty ? otkazRows.first['created_at']?.toString() : null;

    // pokupioVozacId — lookup po imenu u vozaciCache
    String? pokupioVozacId;
    if (pokupioVozac != null && pokupioVozac.isNotEmpty) {
      pokupioVozacId = V2MasterRealtimeManager.instance.vozaciCache.values
          .where((v) => v['ime']?.toString() == pokupioVozac)
          .firstOrNull?['id']
          ?.toString();
    }

    // naziv_adrese — lookup u adreseCache
    // 1. custom_adresa_id iz seat_requests (prioritet)
    // 2. fallback: adresa putnika iz registrovani_putnici (BC ili VS)
    String? nazivAdrese;
    final adresaId = srRow['custom_adresa_id']?.toString();
    if (adresaId != null && adresaId.isNotEmpty) {
      nazivAdrese = V2MasterRealtimeManager.instance.adreseCache[adresaId]?['naziv']?.toString();
    }
    if (nazivAdrese == null && rp != null) {
      final fallbackAdresaId =
          srGrad == 'VS' ? rp['adresa_vrsac_id']?.toString() : rp['adresa_bela_crkva_id']?.toString();
      if (fallbackAdresaId != null && fallbackAdresaId.isNotEmpty) {
        nazivAdrese = V2MasterRealtimeManager.instance.adreseCache[fallbackAdresaId]?['naziv']?.toString();
      }
    }

    // Gradi mapu kompatibilnu sa V2Putnik.fromSeatRequest()
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
    if (vremeOtkazivanja != null) map['vreme_otkazivanja'] = vremeOtkazivanja;
    if (vremeUplate != null) map['vreme_placanja'] = vremeUplate;
    if (nazivAdrese != null) map['adrese'] = {'naziv': nazivAdrese};
    if (map['status'] == 'cancelled') map['status'] = 'otkazano';
    if (rp != null) map['registrovani_putnici'] = rp;
    return V2Putnik.fromSeatRequest(map);
  }

  /// Fetcha putnike i emituje u controller. Jezgro stream logike.
  Future<void> _fetchAndEmit(
      String key, String? isoDate, String? grad, String? vreme, StreamController<List<V2Putnik>> controller,
      {String? vozacId}) async {
    try {
      final results = await _fetchPutnici(isoDate: isoDate, grad: grad, vreme: vreme, vozacId: vozacId);
      _lastValues[key] = results;
      if (!controller.isClosed) controller.add(results);
      _setupRealtimeRefresh(key, isoDate, grad, vreme, controller);
    } catch (e) {
      debugPrint('\u26a0\ufe0f [PutnikService] Error in stream fetch: $e');
      if (!controller.isClosed) controller.add([]);
    }
  }

  /// Fetcha i filtrira putnike za zadani datum/grad/vreme/vozacId.
  /// Koristi cache za danas, DB upit za ostale datume.
  Future<List<V2Putnik>> _fetchPutnici({String? isoDate, String? grad, String? vreme, String? vozacId}) async {
    final todayDate = (isoDate ?? DateTime.now().toIso8601String()).split('T')[0];
    final rm = V2MasterRealtimeManager.instance;

    if (!rm.isInitialized) {
      await Future.delayed(const Duration(milliseconds: 300));
    }

    final sviPutnici = await getPutniciByDayIso(todayDate);

    final gradNorm = grad == null ? null : GradAdresaValidator.normalizeGrad(grad).toUpperCase();
    final vremeNorm = vreme != null ? GradAdresaValidator.normalizeTime(vreme) : null;
    final danKratica = _isoToDanKratica(todayDate);

    return sviPutnici.where((p) {
      if (gradNorm != null) {
        if (GradAdresaValidator.normalizeGrad(p.grad).toUpperCase() != gradNorm) return false;
      }
      if (vremeNorm != null) {
        if (GradAdresaValidator.normalizeTime(p.polazak) != vremeNorm) return false;
      }
      if (vozacId != null) {
        final putnikIdStr = p.id?.toString() ?? '';
        // 1. Provjeri per-V2Putnik individualnu dodjelu (vozac_putnik) — klč: putnik_id + dan + grad + vreme
        final individualnaDodjela = rm.vozacPutnikCache.values
            .where((vp) =>
                vp['putnik_id']?.toString() == putnikIdStr &&
                vp['dan']?.toString() == danKratica &&
                vp['grad']?.toString().toUpperCase() == GradAdresaValidator.normalizeGrad(p.grad).toUpperCase() &&
                GradAdresaValidator.normalizeTime(vp['vreme']?.toString()) ==
                    GradAdresaValidator.normalizeTime(p.polazak))
            .toList();
        if (individualnaDodjela.isNotEmpty) {
          // Individualna dodjela postoji za ovaj dan+grad+vreme — prikaži samo ako je dodeljen OVOM vozaču
          return individualnaDodjela.any((vp) => vp['vozac_id']?.toString() == vozacId);
        }
        // 2. Nema individualne dodjele → provjeri termin raspored (vozac_raspored)
        final rasporedZaTermin = rm.rasporedCache.values
            .where((vr) =>
                vr['dan']?.toString() == danKratica &&
                vr['grad']?.toString().toUpperCase() == GradAdresaValidator.normalizeGrad(p.grad).toUpperCase() &&
                vr['vreme']?.toString() == GradAdresaValidator.normalizeTime(p.polazak))
            .toList();
        if (rasporedZaTermin.isEmpty) return false;
        return rasporedZaTermin.any((vr) => vr['vozac_id']?.toString() == vozacId);
      }
      return true;
    }).toList();
  }

  /// Konvertuje ISO datum u kraticu dana ('pon', 'uto', ...)
  static String _isoToDanKratica(String iso) {
    const map = {1: 'pon', 2: 'uto', 3: 'sre', 4: 'cet', 5: 'pet', 6: 'sub', 7: 'ned'};
    return map[DateTime.tryParse(iso)?.weekday ?? 1]!;
  }

  void _setupRealtimeRefresh(
      String key, String? isoDate, String? grad, String? vreme, StreamController<List<V2Putnik>> controller) {
    // 🌐 SETUP GLOBALNIH SHARED LISTENER-A (samo ako već nisu kreirani)

    // Listener za v2_polasci — ažuriraj cache + debounce refresh
    if (_globalSeatRequestsListener == null) {
      _globalSeatRequestsListener = V2MasterRealtimeManager.instance.subscribe('v2_polasci').listen((payload) {
        final record = payload.newRecord;
        debugPrint('⚡ [PutnikService] v2_polasci event: V2Putnik=${record["putnik_id"]}');
        V2MasterRealtimeManager.instance.upsertToCache('v2_polasci', record);
        _debouncedRefreshAllStreams();
      });
      debugPrint('✅ [PutnikService] Globalni v2_polasci listener kreiran');
    }

    // Listener za v2_statistika_istorija — ažuriraj cache + debounce refresh
    if (_globalVoznjeLogListener == null) {
      _globalVoznjeLogListener = V2MasterRealtimeManager.instance.subscribe('v2_statistika_istorija').listen((payload) {
        final record = payload.newRecord;
        debugPrint('⚡ [PutnikService] v2_statistika_istorija event: V2Putnik=${record["putnik_id"]}');
        V2MasterRealtimeManager.instance.upsertToCache('v2_statistika_istorija', record);
        _debouncedRefreshAllStreams();
      });
      debugPrint('✅ [PutnikService] Globalni v2_statistika_istorija listener kreiran');
    }

    // Listener za v2_ V2Putnik tabele — refresh kada se neko V2Putnik promeni
    if (_globalRegistrovaniListener == null) {
      _globalRegistrovaniListener = V2MasterRealtimeManager.instance.subscribe('v2_radnici').listen((_) {
        debugPrint('🔄 [PutnikService] v2_radnici promenjeni — debounce refresh');
        _debouncedRefreshAllStreams();
      });
      debugPrint('✅ [PutnikService] Globalni v2_radnici listener kreiran');
    }

    // Listener za v2_vozac_raspored — kada se doda/promijeni/briše termin, refresh svih streamova
    if (_globalVozacRasporedListener == null) {
      _globalVozacRasporedListener = V2MasterRealtimeManager.instance.subscribe('v2_vozac_raspored').listen((_) {
        debugPrint('🔄 [PutnikService] v2_vozac_raspored promijenjen — full stream refresh');
        _debouncedRefreshAllStreams();
      });
      debugPrint('✅ [PutnikService] Globalni v2_vozac_raspored listener kreiran');
    }

    // Listener za v2_vozac_putnik — individualna dodjela promijenjena, refresh svih streamova
    if (_globalVozacPutnikListener == null) {
      _globalVozacPutnikListener = V2MasterRealtimeManager.instance.subscribe('v2_vozac_putnik').listen((_) {
        debugPrint('🔄 [PutnikService] v2_vozac_putnik promijenjen — full stream refresh');
        _debouncedRefreshAllStreams();
      });
      debugPrint('✅ [PutnikService] Globalni v2_vozac_putnik listener kreiran');
    }
  }

  /// Debounce — čeka 600ms od zadnjeg eventa pa refreshuje sve aktivne streamove
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
        _fetchAndEmit(key, params.isoDate, params.grad, params.vreme, controller, vozacId: params.vozacId);
      }
    }
  }

  /// 🔄 PUBLIC metoda za eksplicitno refresh-ovanje streamova (npr. posle dodavanja putnika)
  void refreshAllActiveStreams() {
    debugPrint('🔄 [PutnikService] Eksplicitan refresh svih aktivnih streamova');
    _refreshAllActiveStreams();
  }

  final Map<String, DateTime> _lastActionTime = {};
  bool _isDuplicateAction(String key) {
    final now = DateTime.now();
    if (_lastActionTime.containsKey(key) && now.difference(_lastActionTime[key]!) < const Duration(milliseconds: 500)) {
      return true;
    }
    _lastActionTime[key] = now;
    return false;
  }

  Future<V2Putnik?> getPutnikByName(String ime, {String? grad}) async {
    final String todayStr = DateTime.now().toIso8601String().split('T')[0];
    final rm = V2MasterRealtimeManager.instance;

    // Nađi putnik_id po imenu iz V2MasterRealtimeManager cache-a (v2_ tabele koriste kolonu 'ime')
    final rpEntry = rm.getAllPutnici().where((r) => r['ime']?.toString() == ime).firstOrNull;
    if (rpEntry == null) return null;
    final putnikId = rpEntry['id']?.toString();
    if (putnikId == null) return null;

    // Nađi seat_request za ovog putnika iz polasciCache
    final srRow = rm.polasciCache.values.where((r) => r['putnik_id']?.toString() == putnikId).firstOrNull;
    if (srRow != null) {
      final vlRows = rm.statistikaCache.values.where((vl) => vl['putnik_id']?.toString() == putnikId).toList();
      return _buildPutnik(srRow, vlRows, rpEntry, todayStr);
    }

    // Fallback na profil ako nema današnjeg seat_request-a
    return V2Putnik.fromRegistrovaniPutnici(rpEntry);
  }

  Future<V2Putnik?> getPutnikFromAnyTable(dynamic id) async {
    try {
      final todayStr = DateTime.now().toIso8601String().split('T')[0];
      final String idStr = id.toString();
      final rm = V2MasterRealtimeManager.instance;

      final srRow = rm.polasciCache.values.where((r) => r['putnik_id']?.toString() == idStr).firstOrNull;
      final rp = rm.getPutnikById(idStr);

      if (srRow != null) {
        final vlRows = rm.statistikaCache.values.where((vl) => vl['putnik_id']?.toString() == idStr).toList();
        return _buildPutnik(srRow, vlRows, rp, todayStr);
      }
      if (rp != null) return V2Putnik.fromRegistrovaniPutnici(rp);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<V2Putnik>> getPutniciByIds(List<dynamic> ids, {String? targetDan, String? isoDate}) async {
    if (ids.isEmpty) return [];
    try {
      final String danasStr = (isoDate ?? DateTime.now().toIso8601String()).split('T')[0];
      final idStrings = ids.map((id) => id.toString()).toSet();
      final svi = await getPutniciByDayIso(danasStr);
      return svi.where((p) => idStrings.contains(p.id?.toString())).toList();
    } catch (e) {
      debugPrint('⚠️ [PutnikService] Error in getPutniciByIds: $e');
      return [];
    }
  }

  Future<List<V2Putnik>> getAllPutnici({String? targetDay, String? isoDate}) async {
    try {
      final String danasStr = (isoDate ?? DateTime.now().toIso8601String()).split('T')[0];
      return await getPutniciByDayIso(danasStr);
    } catch (e) {
      debugPrint('⚠️ [PutnikService] Error in getAllPutnici: $e');
      return [];
    }
  }

  Future<void> dodajPutnika(V2Putnik putnik) async {
    debugPrint('🔍 [PutnikService] dodajPutnika: ime="${putnik.ime}"');

    // Traži putnika po imenu u v2_ cache-u (sve 4 tabele)
    final allPutnici = V2MasterRealtimeManager.instance.getAllPutnici();
    final found = allPutnici.where((r) => r['ime']?.toString() == putnik.ime).firstOrNull;

    debugPrint('🔍 [PutnikService] Cache lookup: ${found != null ? 'FOUND id=${found['id']}' : 'NOT FOUND'}');

    if (found == null) {
      throw Exception('Putnik "${putnik.ime}" nije pronađen u bazi ili nije aktivan');
    }
    final putnikId = found['id'].toString();

    // Voza\u010d/admin ru\u010dno dodaje \u2192 isAdmin=true \u2192 confirmed + dodeljeno_vreme odmah
    await V2PolasciService.submitPolazak(
      putnikId: putnikId,
      dan: putnik.dan,
      grad: putnik.grad,
      vreme: putnik.polazak,
      brojMesta: putnik.brojMesta,
      isAdmin: true,
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
        final vozacData = await supabase.from('v2_vozaci').select('id').eq('ime', driver).maybeSingle();
        vozacId = vozacData?['id'] as String?;
      } catch (e) {
        debugPrint('⚠️ [oznaciPokupljen] Greška pri dohvatanju vozača "$driver": $e');
      }
    }

    // 1. Označi status='pokupljen' u seat_requests (operativno stanje)
    try {
      if (requestId != null && requestId.isNotEmpty) {
        await supabase.from('v2_polasci').update({
          'status': 'pokupljen',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'processed_at': DateTime.now().toUtc().toIso8601String(),
          if (driver != null) 'pokupljeno_by': driver,
        }).eq('id', requestId);
        debugPrint('✅ [oznaciPokupljen] v2_polasci status=pokupljen (requestId=$requestId)');
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
              .from('v2_polasci')
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
          debugPrint('✅ [oznaciPokupljen] v2_polasci status=pokupljen (dan=$danKey, grad=$gradKey, vreme=$vremeKey)');
        }
      }
    } catch (e) {
      debugPrint('⚠️ [oznaciPokupljen] Greška pri update v2_polasci: $e');
    }

    // 2. Upiši u v2_statistika_istorija (TRAJNI ZAPIS ZA STATISTIKU - nikad se ne briše)
    final existing = await V2StatistikaIstorijaService.getLogEntry(
      putnikId: id.toString(),
      datum: targetDatum,
      tip: 'voznja',
      grad: grad,
      vreme: vreme,
    );

    if (existing == null) {
      await V2StatistikaIstorijaService.logGeneric(
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
      // 1. Ažuriraj status putnika u odgovarajućoj v2_ tabeli
      final putnikData = V2MasterRealtimeManager.instance.getPutnikById(putnikId);
      final tabela = putnikData?['_tabela'] as String?;
      if (tabela != null) {
        await supabase.from(tabela).update({
          'status': status,
          'updated_at': nowToString(),
        }).eq('id', putnikId);
      } else {
        debugPrint('⚠️ [oznaciBolovanjeGodisnji] V2Putnik $putnikId nije u v2_ cache-u!');
      }

      // 2. Ako je na bolovanju/godišnjem, otkaži sve pending v2_polasci za DANAS i SUTRA
      if (status == 'bolovanje' || status == 'godisnji') {
        final danasDay = DateTime.now().weekday;
        final sutraDay = DateTime.now().add(const Duration(days: 1)).weekday;
        const dani = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
        final danasKratica = dani[danasDay - 1];
        final sutraKratica = dani[sutraDay - 1];

        await supabase
            .from('v2_polasci')
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
            .from('v2_polasci')
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
            .from('v2_polasci')
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
            .from('v2_polasci')
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
          .from('v2_polasci')
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

      await V2StatistikaIstorijaService.logGeneric(
        tip: 'otkazivanje',
        putnikId: id.toString(),
        vozacId: vozacUuid,
        vozacImeOverride: vozacUuid == null ? driver : null, // 'V2Putnik', 'Admin', itd.
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
            .from('v2_polasci')
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
            .from('v2_polasci')
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
            .from('v2_polasci')
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
        final vozacData = await supabase.from('v2_vozaci').select('id').eq('ime', driver).maybeSingle();
        vozacId = vozacData?['id'] as String?;
        debugPrint('💰 [oznaciPlaceno] driver="$driver" → vozacId=$vozacId');
      } catch (e) {
        debugPrint('⚠️ [oznaciPlaceno] Greška pri dohvatanju vozača "$driver": $e');
      }
    } else {
      debugPrint('⚠️ [oznaciPlaceno] driver je NULL!');
    }

    // 💰 Plaćanje se evidentira SAMO u v2_statistika_istorija (izvor istine za finansije)
    // v2_polasci.status se NE mijenja - 'pokupljen' ostaje 'pokupljen', 'confirmed' ostaje 'confirmed'
    await V2StatistikaIstorijaService.dodajUplatu(
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

      var query = supabase.from('v2_polasci').update({
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
}
