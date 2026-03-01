import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/v2_day_constants.dart';
import '../globals.dart' as globals_file;
import '../models/v2_putnik.dart';
import '../utils/v2_grad_adresa_validator.dart';
import '../utils/v2_vozac_cache.dart';
import 'realtime/v2_master_realtime_manager.dart';
import 'v2_polasci_service.dart';
import 'v2_statistika_istorija_service.dart';

/// Servis za putnike — read metode čitaju iz V2MasterRealtimeManager cache-a,
/// write metode pišu direktno u bazu.
class V2PutnikStreamService {
  SupabaseClient get supabase => globals_file.supabase;

  // ──────────────────────────────────────────────────────────────────────────
  // 📡 STREAM METODE — emituju direktno iz RM cache-a
  // ──────────────────────────────────────────────────────────────────────────

  /// Stream kombinovanih putnika sa opcionim filterima (isoDate, grad, vreme, vozacId).
  /// Emituje pri svakoj promjeni v2_polasci, v2_statistika_istorija,
  /// v2_vozac_raspored ili v2_vozac_putnik u RM-u.
  Stream<List<V2Putnik>> streamKombinovaniPutniciFiltered(
      {String? isoDate, String? grad, String? vreme, String? vozacId}) {
    final controller = StreamController<List<V2Putnik>>.broadcast();

    Future<void> emit() async {
      if (controller.isClosed) return;
      try {
        final result = await _fetchPutnici(isoDate: isoDate, grad: grad, vreme: vreme, vozacId: vozacId);
        if (!controller.isClosed) controller.add(result);
      } catch (e) {
        if (!controller.isClosed) controller.add([]);
      }
    }

    // Inicijalna emisija
    emit();

    // Osvježi na svaku promjenu relevantnih tabela
    final rm = V2MasterRealtimeManager.instance;
    final subs = <StreamSubscription>[
      rm.subscribe('v2_polasci').listen((_) => emit()),
      rm.subscribe('v2_statistika_istorija').listen((_) => emit()),
      rm.subscribe('v2_vozac_raspored').listen((_) => emit()),
      rm.subscribe('v2_vozac_putnik').listen((_) => emit()),
    ];

    controller.onCancel = () {
      for (final s in subs) {
        s.cancel();
      }
    };

    return controller.stream;
  }

  /// Stream svih putnika za danas.
  Stream<List<V2Putnik>> streamPutnici() {
    final todayDate = DateTime.now().toIso8601String().split('T')[0];
    return streamKombinovaniPutniciFiltered(isoDate: todayDate);
  }

  /// Eksplicitan refresh — no-op jer stream automatski reaguje na RM promjene.
  void refreshAllActiveStreams() {
    debugPrint('🔄 [V2PutnikStreamService] refreshAllActiveStreams — RM stream se sam ažurira');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 🔍 READ METODE — čitanje iz RM cache-a ili DB za drugi datum
  // ──────────────────────────────────────────────────────────────────────────

  Future<List<V2Putnik>> getPutniciByDayIso(String isoDate) async {
    try {
      final todayDate = isoDate.split('T')[0];
      final rm = V2MasterRealtimeManager.instance;

      // Cache: koristi se samo za današnji datum
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
            .where((p) => p.status != 'bez_polaska')
            .toList();
      }

      // Fallback: direktni DB upit za drugi datum
      final dan = _isoToDanKratica(todayDate);
      final srRows = await supabase
          .from('v2_polasci')
          .select('id, putnik_id, putnik_tabela, grad, zeljeno_vreme, dodeljeno_vreme, status, '
              'created_at, updated_at, processed_at, broj_mesta, '
              'adresa_id, alternative_vreme_1, alternative_vreme_2, '
              'cancelled_by, pokupljeno_by, dan')
          .eq('dan', dan)
          .inFilter('status', ['obrada', 'odobreno', 'otkazano', 'odbijeno', 'bez_polaska', 'pokupljen']);
      final vlRows = await supabase
          .from('v2_statistika_istorija')
          .select('id, putnik_id, datum, tip, iznos, vozac_id, vozac_ime, grad, vreme, created_at')
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
          .where((p) => p.status != 'bez_polaska')
          .toList();
    } catch (e) {
      debugPrint('⚠️ [PutnikService] Error fetching by day: $e');
      return [];
    }
  }

  Future<V2Putnik?> getPutnikByName(String ime, {String? grad}) async {
    final String todayStr = DateTime.now().toIso8601String().split('T')[0];
    final rm = V2MasterRealtimeManager.instance;

    final rpEntry = rm.getAllPutnici().where((r) => r['ime']?.toString() == ime).firstOrNull;
    if (rpEntry == null) return null;
    final putnikId = rpEntry['id']?.toString();
    if (putnikId == null) return null;

    final srRow = rm.polasciCache.values.where((r) => r['putnik_id']?.toString() == putnikId).firstOrNull;
    if (srRow != null) {
      final vlRows = rm.statistikaCache.values.where((vl) => vl['putnik_id']?.toString() == putnikId).toList();
      return _buildPutnik(srRow, vlRows, rpEntry, todayStr);
    }
    return V2Putnik.v2FromProfil(rpEntry);
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
      if (rp != null) return V2Putnik.v2FromProfil(rp);
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

  // ──────────────────────────────────────────────────────────────────────────
  // 🔧 INTERNI HELPERI
  // ──────────────────────────────────────────────────────────────────────────

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
        final individualnaDodjela = rm.vozacPutnikCache.values
            .where((vp) =>
                vp['putnik_id']?.toString() == putnikIdStr &&
                vp['dan']?.toString() == danKratica &&
                vp['grad']?.toString().toUpperCase() == GradAdresaValidator.normalizeGrad(p.grad).toUpperCase() &&
                GradAdresaValidator.normalizeTime(vp['vreme']?.toString()) ==
                    GradAdresaValidator.normalizeTime(p.polazak))
            .toList();
        if (individualnaDodjela.isNotEmpty) {
          return individualnaDodjela.any((vp) => vp['vozac_id']?.toString() == vozacId);
        }
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

  static String _isoToDanKratica(String iso) {
    const map = {1: 'pon', 2: 'uto', 3: 'sre', 4: 'cet', 5: 'pet', 6: 'sub', 7: 'ned'};
    return map[DateTime.tryParse(iso)?.weekday ?? 1]!;
  }

  static V2Putnik _buildPutnik(
    Map<String, dynamic> srRow,
    List<Map<String, dynamic>> vlRows,
    Map<String, dynamic>? rp,
    String isoDate,
  ) {
    final srGrad = (srRow['grad'] ?? '').toString().toUpperCase();
    final srVreme = (srRow['dodeljeno_vreme'] ?? srRow['zeljeno_vreme'])?.toString();

    final matchedVl = vlRows.where((vl) {
      final vlGrad = (vl['grad'] ?? '').toString().toUpperCase();
      final vlVreme = vl['vreme']?.toString();
      final gradOk = vlGrad.isEmpty || vlGrad == srGrad;
      final vremeOk = vlVreme == null || srVreme == null || vlVreme == srVreme;
      return gradOk && vremeOk;
    }).toList();

    final bool jePokupljen = srRow['status'] == 'pokupljen';
    final bool jeOtkazan = srRow['status'] == 'otkazano';

    final uplataRows = matchedVl.where((vl) => vl['tip'] == 'uplata' || vl['tip'] == 'uplata_dnevna').toList();
    final bool jePlacen = uplataRows.isNotEmpty;
    final double? iznos = uplataRows.isNotEmpty ? (uplataRows.first['iznos'] as num?)?.toDouble() : null;

    final tipPriority = ['uplata', 'uplata_dnevna', 'voznja'];
    Map<String, dynamic>? mainVl;
    for (final tip in tipPriority) {
      mainVl = matchedVl.where((vl) => vl['tip'] == tip).firstOrNull;
      if (mainVl != null) break;
    }
    final String? vozacId = mainVl?['vozac_id']?.toString();
    final String? vozacIme = mainVl?['vozac_ime']?.toString();

    final logRows = matchedVl
        .where((vl) => ['voznja', 'otkazivanje', 'uplata', 'uplata_dnevna'].contains(vl['tip']))
        .toList()
      ..sort((a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));
    final String? logCreatedAt = logRows.isNotEmpty ? logRows.first['created_at']?.toString() : null;

    final String? pokupioVozac = srRow['pokupljeno_by']?.toString();
    final String? naplatioVozac = uplataRows.isNotEmpty ? uplataRows.first['vozac_ime']?.toString() : null;
    final String? naplatioVozacId = uplataRows.isNotEmpty ? uplataRows.first['vozac_id']?.toString() : null;
    final String? vremeUplate = uplataRows.isNotEmpty ? uplataRows.first['created_at']?.toString() : null;

    final otkazRows = matchedVl.where((vl) => vl['tip'] == 'otkazivanje').toList();
    final String? otkazaoVozac = otkazRows.isNotEmpty ? otkazRows.first['vozac_ime']?.toString() : null;
    final String? otkazaoVozacId = otkazRows.isNotEmpty ? otkazRows.first['vozac_id']?.toString() : null;
    final String? vremeOtkazivanja = otkazRows.isNotEmpty ? otkazRows.first['created_at']?.toString() : null;

    String? pokupioVozacId;
    if (pokupioVozac != null && pokupioVozac.isNotEmpty) {
      pokupioVozacId = V2MasterRealtimeManager.instance.vozaciCache.values
          .where((v) => v['ime']?.toString() == pokupioVozac)
          .firstOrNull?['id']
          ?.toString();
    }

    String? nazivAdrese;
    final adresaId = srRow['adresa_id']?.toString();
    if (adresaId != null && adresaId.isNotEmpty) {
      nazivAdrese = V2MasterRealtimeManager.instance.adreseCache[adresaId]?['naziv']?.toString();
    }
    if (nazivAdrese == null && rp != null) {
      final fallbackAdresaId = srGrad == 'VS' ? rp['adresa_vs_id']?.toString() : rp['adresa_bc_id']?.toString();
      if (fallbackAdresaId != null && fallbackAdresaId.isNotEmpty) {
        nazivAdrese = V2MasterRealtimeManager.instance.adreseCache[fallbackAdresaId]?['naziv']?.toString();
      }
    }

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
    if (rp != null) map['registrovani_putnici'] = rp;
    return V2Putnik.v2FromPolazak(map);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ✏️ WRITE METODE
  // ──────────────────────────────────────────────────────────────────────────

  final Map<String, DateTime> _lastActionTime = {};

  bool _isDuplicateAction(String key) {
    final now = DateTime.now();
    if (_lastActionTime.containsKey(key) && now.difference(_lastActionTime[key]!) < const Duration(milliseconds: 500)) {
      return true;
    }
    _lastActionTime[key] = now;
    return false;
  }

  String nowToString() => DateTime.now().toUtc().toIso8601String();

  Future<void> v2DodajPutnika(V2Putnik putnik) async {
    debugPrint('🔍 [PutnikService] v2DodajPutnika: ime="${putnik.ime}"');

    final allPutnici = V2MasterRealtimeManager.instance.getAllPutnici();
    final found = allPutnici.where((r) => r['ime']?.toString() == putnik.ime).firstOrNull;

    debugPrint('🔍 [PutnikService] Cache lookup: ${found != null ? 'FOUND id=${found['id']}' : 'NOT FOUND'}');

    if (found == null) {
      throw Exception('Putnik "${putnik.ime}" nije pronađen u bazi ili nije aktivan');
    }
    final putnikId = found['id'].toString();

    await V2PolasciService.v2PoSaljiZahtev(
      putnikId: putnikId,
      dan: putnik.dan,
      grad: putnik.grad,
      vreme: putnik.polazak,
      brojMesta: putnik.brojMesta,
      isAdmin: true,
      customAdresaId: putnik.adresaId,
      putnikTabela: found['_tabela']?.toString(),
    );
  }

  Future<void> v2OznaciPokupljen(dynamic id, bool value,
      {String? grad, String? vreme, String? driver, String? datum, String? requestId}) async {
    if (_isDuplicateAction('pickup_$id')) return;
    if (!value) return; // 🚫 Undo nije podržan

    final targetDatum = datum ?? DateTime.now().toIso8601String().split('T')[0];

    String? vozacId;
    if (driver != null) {
      try {
        final vozacData = await supabase.from('v2_vozaci').select('id').eq('ime', driver).maybeSingle();
        vozacId = vozacData?['id'] as String?;
      } catch (e) {
        debugPrint('⚠️ [PutnikService] v2OznaciPokupljen: Greška pri dohvatanju vozača "$driver": $e');
      }
    }

    try {
      if (requestId != null && requestId.isNotEmpty) {
        await supabase.from('v2_polasci').update({
          'status': 'pokupljen',
          'updated_at': nowToString(),
          'processed_at': nowToString(),
          if (driver != null) 'pokupljeno_by': driver,
        }).eq('id', requestId);
        debugPrint('✅ [PutnikService] v2OznaciPokupljen: status=pokupljen (requestId=$requestId)');
      } else {
        final gradKey = grad != null ? GradAdresaValidator.normalizeGrad(grad) : null;
        final vremeKey = vreme != null ? '${GradAdresaValidator.normalizeTime(vreme)}:00' : null;
        String? danKey;
        try {
          final dt = DateTime.parse(targetDatum);
          const dani = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
          danKey = dani[dt.weekday - 1];
        } catch (_) {}
        if (gradKey == null || vremeKey == null || danKey == null) {
          debugPrint('⛔ [PutnikService] v2OznaciPokupljen: Nedostaje grad, vreme ili dan!');
        } else {
          await supabase
              .from('v2_polasci')
              .update({
                'status': 'pokupljen',
                'updated_at': nowToString(),
                'processed_at': nowToString(),
                if (driver != null) 'pokupljeno_by': driver,
              })
              .eq('putnik_id', id.toString())
              .eq('dan', danKey)
              .eq('grad', gradKey)
              .eq('zeljeno_vreme', vremeKey);
          debugPrint(
              '✅ [PutnikService] v2OznaciPokupljen: status=pokupljen (dan=$danKey, grad=$gradKey, vreme=$vremeKey)');
        }
      }
    } catch (e) {
      debugPrint('⚠️ [PutnikService] v2OznaciPokupljen: Greška pri update v2_polasci: $e');
    }

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

  /// 🏖️ Postavlja putnika na bolovanje ili godišnji i otkazuje vožnje
  Future<void> v2OznaciStatus(String putnikId, String status, String actor) async {
    try {
      final putnikData = V2MasterRealtimeManager.instance.getPutnikById(putnikId);
      final tabela = putnikData?['_tabela'] as String?;
      if (tabela != null) {
        await supabase.from(tabela).update({
          'status': status,
          'updated_at': nowToString(),
        }).eq('id', putnikId);
      } else {
        debugPrint('⚠️ [PutnikService] v2OznaciStatus: Putnik $putnikId nije u v2_ cache-u!');
      }

      if (status == 'bolovanje' || status == 'godisnji') {
        final danasDay = DateTime.now().weekday;
        final sutraDay = DateTime.now().add(const Duration(days: 1)).weekday;
        const dani = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
        final danasKratica = dani[danasDay - 1];
        final sutraKratica = dani[sutraDay - 1];

        await supabase
            .from('v2_polasci')
            .update({'status': 'otkazano', 'updated_at': nowToString()})
            .eq('putnik_id', putnikId)
            .inFilter('dan', [danasKratica, sutraKratica])
            .inFilter('status', ['obrada', 'odobreno']);

        debugPrint('🏖️ [PutnikService] Otkazane vožnje za putnika $putnikId (status: $status)');
      }
    } catch (e) {
      debugPrint('❌ [PutnikService] Error setting bolovanje/godisnji: $e');
      rethrow;
    }
  }

  Future<void> v2OtkaziPutnika(
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
    debugPrint('🛑 [PutnikService] v2OtkaziPutnika: id=$id, requestId=$requestId, status=$status');

    try {
      String? vozacUuid;
      if (driver != null) {
        vozacUuid = VozacCache.getUuidByIme(driver);
      }
      await V2StatistikaIstorijaService.logGeneric(
        tip: 'otkazivanje',
        putnikId: id.toString(),
        vozacId: vozacUuid,
        vozacImeOverride: vozacUuid == null ? driver : null,
        grad: selectedGrad ?? grad,
        vreme: selectedVreme ?? vreme,
        datum: datum,
      );
    } catch (e) {
      debugPrint('⚠️ [PutnikService] Greška pri logovanju otkazivanja: $e');
    }

    if (requestId != null && requestId.isNotEmpty) {
      try {
        final res = await supabase
            .from('v2_polasci')
            .update({
              'status': status,
              'processed_at': nowToString(),
              'updated_at': nowToString(),
              if (driver != null) 'cancelled_by': driver,
            })
            .eq('id', requestId)
            .select();
        if (res.isNotEmpty) {
          debugPrint('🛑 [PutnikService] v2OtkaziPutnika SUCCESS (by requestId)');
          return;
        }
      } catch (e) {
        debugPrint('⚠️ [PutnikService] v2OtkaziPutnika: Error matching by requestId: $e');
      }
    }

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
    debugPrint('🛑 [PutnikService] v2OtkaziPutnika (fallback): dan=$danKey, grad=$gradKey, time=$normalizedTime');

    try {
      if (normalizedTime.isNotEmpty) {
        var res = await supabase
            .from('v2_polasci')
            .update({
              'status': status,
              'processed_at': nowToString(),
              'updated_at': nowToString(),
              if (driver != null) 'cancelled_by': driver,
            })
            .match({'putnik_id': id.toString(), 'dan': danKey})
            .eq('grad', gradKey)
            .eq('zeljeno_vreme', '$normalizedTime:00')
            .select();

        if (res.isNotEmpty) {
          debugPrint('🛑 [PutnikService] v2OtkaziPutnika SUCCESS (zeljeno_vreme)');
          return;
        }

        res = await supabase
            .from('v2_polasci')
            .update({
              'status': status,
              'processed_at': nowToString(),
              'updated_at': nowToString(),
              if (driver != null) 'cancelled_by': driver,
            })
            .match({'putnik_id': id.toString(), 'dan': danKey})
            .eq('grad', gradKey)
            .eq('dodeljeno_vreme', '$normalizedTime:00')
            .select();

        if (res.isNotEmpty) {
          debugPrint('🛑 [PutnikService] v2OtkaziPutnika SUCCESS (dodeljeno_vreme)');
          return;
        }
      }

      debugPrint(
          '⛔ [PutnikService] v2OtkaziPutnika: nije pronađen termin za dan=$danKey, grad=$gradKey, vreme=$normalizedTime — NE diram druge termine!');
    } catch (e) {
      debugPrint('❌ [PutnikService] v2OtkaziPutnika ERROR: $e');
      rethrow;
    }
  }

  Future<void> v2OznaciPlaceno(
    dynamic id,
    num iznos,
    String? driver, {
    String? grad,
    String? selectedVreme,
    String? selectedDan,
    String? requestId,
  }) async {
    final dateStr = DateTime.now().toIso8601String().split('T')[0];

    String? vozacId;
    if (driver != null) {
      try {
        final vozacData = await supabase.from('v2_vozaci').select('id').eq('ime', driver).maybeSingle();
        vozacId = vozacData?['id'] as String?;
        debugPrint('💰 [PutnikService] v2OznaciPlaceno: driver="$driver" → vozacId=$vozacId');
      } catch (e) {
        debugPrint('⚠️ [PutnikService] v2OznaciPlaceno: Greška pri dohvatanju vozača "$driver": $e');
      }
    } else {
      debugPrint('⚠️ [PutnikService] v2OznaciPlaceno: driver je NULL!');
    }

    await V2StatistikaIstorijaService.dodajUplatu(
      putnikId: id.toString(),
      datum: DateTime.parse(dateStr),
      iznos: iznos.toDouble(),
      vozacId: vozacId,
      vozacImeParam: driver,
      grad: grad,
      vreme: selectedVreme,
    );
  }

  /// 🚫 Postavlja 'bez_polaska' status za sve putnike u datom terminu
  Future<int> v2GlobalniBezPolaska({
    required String dan,
    required String grad,
    required String vreme,
  }) async {
    try {
      final gradKey = GradAdresaValidator.normalizeGrad(grad);
      final danKey = DayConstants.getAbbreviationByIndex(DayConstants.getIndexByName(dan));

      var query = supabase.from('v2_polasci').update({
        'status': 'bez_polaska',
        'dodeljeno_vreme': null,
        'pokupljeno_by': null,
        'cancelled_by': null,
        'processed_at': null,
        'updated_at': nowToString(),
      }).match({'dan': danKey}).inFilter('status', ['odobreno', 'obrada', 'pokupljen', 'otkazano']).eq('grad', gradKey);

      if (vreme.isNotEmpty && vreme != 'Sva vremena') {
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
