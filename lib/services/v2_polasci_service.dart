import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart' as globals_file;
import '../globals.dart';
import '../models/v2_polazak.dart';
import '../models/v2_putnik.dart';
import '../utils/v2_dan_utils.dart';
import '../utils/v2_grad_adresa_validator.dart';
import '../utils/v2_vozac_cache.dart';
import 'realtime/v2_master_realtime_manager.dart';
import 'v2_audit_log_service.dart';
import 'v2_statistika_istorija_service.dart';

/// Servis za upravljanje aktivnim zahtevima za sedišta (v2_polasci tabela)
class V2PolasciService {
  V2PolasciService._();

  static SupabaseClient get _supabase => supabase;

  /// UNIFIKOVANA ULAZNA TAČKA — koriste je svi akteri (V2Putnik, admin, vozač)
  ///
  /// Model: dan + grad + zeljeno_vreme → upsert u v2_polasci
  ///
  /// - [isAdmin] = true → status='odobreno', dodeljeno_vreme=vreme odmah (vozač/admin ručno dodaje)
  /// - [isAdmin] = false → status='obrada' (V2Putnik šalje zahtev, backend obrađuje)
  ///
  /// Nema datuma, nema sedmice, nema predviđanja.
  static Future<void> v2PoSaljiZahtev({
    required String putnikId,
    required String dan,
    required String grad,
    required String vreme,
    int brojMesta = 1,
    bool isAdmin = false,
    String? customAdresaId,
    String? putnikTabela, // v2_radnici / v2_ucenici / v2_dnevni / v2_posiljke
  }) async {
    try {
      final gradKey = V2GradAdresaValidator.normalizeGrad(grad);
      final normVreme = V2GradAdresaValidator.normalizeTime(vreme);
      final danKey = dan.toLowerCase();
      final nowStr = DateTime.now().toUtc().toIso8601String();
      final status = isAdmin ? 'odobreno' : 'obrada';

      final rm = V2MasterRealtimeManager.instance;

      // 1. Ukloni sve ostale aktivne zahtjeve za isti grad+dan (drugačije vreme)
      // Putnik može imati samo jedan aktivan zahtjev po grad+dan.
      // isAdmin=true → 'bez_polaska': SOFT RESET, zapis ostaje u bazi (ne briše se!).
      //   Null/brisanje bi uklonilo putnika iz cache-a i slomilo prikaz u profilu i vozačevom ekranu.
      //   'bez_polaska' ima prioritet 0 → automatski se pregazi kad putnik pošalje nov zahtev.
      // isAdmin=false → 'cancelled': putnik sam menja zahtev na drugo vreme
      final cancelledStatus = isAdmin ? 'bez_polaska' : 'cancelled';
      final cancelledRows = await _supabase
          .from('v2_polasci')
          .update({'status': cancelledStatus, 'updated_at': nowStr})
          .eq('putnik_id', putnikId)
          .eq('grad', gradKey)
          .eq('dan', danKey)
          .neq('zeljeno_vreme', normVreme)
          .inFilter('status', ['obrada', 'odobreno', 'odbijeno', 'pokupljen', 'otkazano'])
          .select('id');
      for (final row in cancelledRows) {
        rm.v2PatchCache('v2_polasci', row['id'].toString(), {'status': cancelledStatus, 'updated_at': nowStr});
      }

      // 2. Upsert po (putnik_id, grad, dan, zeljeno_vreme) — uvijek ide ispočetka kroz obradu
      final existing = await _supabase
          .from('v2_polasci')
          .select('id')
          .eq('putnik_id', putnikId)
          .eq('grad', gradKey)
          .eq('dan', danKey)
          .eq('zeljeno_vreme', normVreme)
          .maybeSingle();

      if (existing != null) {
        final updatePayload = {
          'status': status,
          'broj_mesta': brojMesta,
          if (isAdmin) 'zeljeno_vreme': normVreme,
          'dodeljeno_vreme': isAdmin ? normVreme : null,
          'processed_at': null,
          'alternativno_vreme_1': null,
          'alternativno_vreme_2': null,
          if (putnikTabela != null) 'putnik_tabela': putnikTabela,
          if (customAdresaId != null) 'adresa_id': customAdresaId,
          'updated_at': nowStr,
        };
        final updated =
            await _supabase.from('v2_polasci').update(updatePayload).eq('id', existing['id']).select().single();
        rm.v2UpsertToCache('v2_polasci', updated);
      } else {
        final inserted = await _supabase
            .from('v2_polasci')
            .insert({
              'putnik_id': putnikId,
              'grad': gradKey,
              'dan': danKey,
              'zeljeno_vreme': normVreme,
              if (isAdmin) 'dodeljeno_vreme': normVreme,
              'status': status,
              'broj_mesta': brojMesta,
              if (putnikTabela != null) 'putnik_tabela': putnikTabela,
              if (customAdresaId != null) 'adresa_id': customAdresaId,
              'created_at': nowStr,
              'updated_at': nowStr,
            })
            .select()
            .single();
        rm.v2UpsertToCache('v2_polasci', inserted);
      }
      // Audit: log zahteva samo kad putnik sam šalje (isAdmin=false)
      if (!isAdmin) {
        try {
          await V2StatistikaIstorijaService.logGeneric(
            tip: 'zahtev_poslan',
            putnikId: putnikId,
            detalji: 'Zahtev za vožnju: $danKey $gradKey $normVreme',
            grad: grad,
            vreme: vreme,
          );
        } catch (_) {}

        // Audit log — putnik šalje zahtev za vožnju
        V2AuditLogService.log(
          tip: 'zahtev_poslan',
          aktorId: putnikId,
          aktorTip: 'putnik',
          putnikId: putnikId,
          putnikTabela: putnikTabela,
          dan: danKey,
          grad: gradKey,
          vreme: normVreme,
          novo: {'status': status, 'broj_mesta': brojMesta},
          detalji: 'Zahtev za vožnju: $danKey $gradKey $normVreme',
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Ažurira broj_mesta za postojeći polazak (vozač označava da putnik povede više osoba)
  static Future<bool> v2SetBrojMesta({
    required String putnikId,
    required String grad,
    required String vreme,
    required String dan,
    required int brojMesta,
  }) async {
    try {
      final gradKey = V2GradAdresaValidator.normalizeGrad(grad);
      final normVreme = V2GradAdresaValidator.normalizeTime(vreme);
      final danKey = dan.toLowerCase();
      final nowStr = DateTime.now().toUtc().toIso8601String();

      final res = await _supabase
          .from('v2_polasci')
          .update({'broj_mesta': brojMesta, 'updated_at': nowStr})
          .eq('putnik_id', putnikId)
          .eq('grad', gradKey)
          .eq('dan', danKey)
          .eq('zeljeno_vreme', normVreme)
          .inFilter('status', ['obrada', 'odobreno'])
          .select('id');

      return res.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Odobrava zahtev — kopira zeljeno_vreme u dodeljeno_vreme
  static Future<bool> v2OdobriZahtev(String id, {String? approvedBy}) async {
    try {
      final nowStr = DateTime.now().toUtc().toIso8601String();

      // Dohvati zeljeno_vreme iz cache-a — 0 DB querija
      // Fallback: DB upit ako iz nekog razloga nije u cache-u
      final cachedRow = V2MasterRealtimeManager.instance.polasciCache[id];
      final zeljenoVreme = cachedRow?['zeljeno_vreme'] ??
          (await _supabase.from('v2_polasci').select('zeljeno_vreme').eq('id', id).single())['zeljeno_vreme'];

      // 2. Odobri i upisi dodeljeno_vreme = zeljeno_vreme
      final approvePayload = {
        'status': 'odobreno',
        'dodeljeno_vreme': zeljenoVreme, // kopira zeljeno_vreme u dodeljeno_vreme
        'updated_at': nowStr,
        'processed_at': nowStr,
        if (approvedBy != null) 'odobrio': approvedBy,
      };
      await _supabase.from('v2_polasci').update(approvePayload).eq('id', id);
      V2MasterRealtimeManager.instance.v2PatchCache('v2_polasci', id, approvePayload);

      // Audit log
      final r = cachedRow;
      V2AuditLogService.log(
        tip: 'odobren_zahtev',
        aktorIme: approvedBy,
        aktorTip: 'vozac',
        putnikId: r?['putnik_id']?.toString(),
        putnikTabela: r?['putnik_tabela']?.toString(),
        dan: r?['dan']?.toString(),
        grad: r?['grad']?.toString(),
        vreme: zeljenoVreme?.toString(),
        polazakId: id,
        staro: {'status': r?['status'] ?? 'obrada'},
        novo: {'status': 'odobreno'},
        detalji: 'Zahtev odobren${approvedBy != null ? " od: $approvedBy" : ""}',
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Odbija zahtev
  static Future<bool> v2OdbijZahtev(String id, {String? rejectedBy}) async {
    try {
      final nowStr = DateTime.now().toUtc().toIso8601String();
      final rejectPayload = {
        'status': 'odbijeno',
        'updated_at': nowStr,
        'processed_at': nowStr,
        if (rejectedBy != null) 'otkazao': rejectedBy,
      };
      await _supabase.from('v2_polasci').update(rejectPayload).eq('id', id);
      V2MasterRealtimeManager.instance.v2PatchCache('v2_polasci', id, rejectPayload);

      // Audit log
      final r = V2MasterRealtimeManager.instance.polasciCache[id];
      V2AuditLogService.log(
        tip: 'odbijen_zahtev',
        aktorIme: rejectedBy,
        aktorTip: 'vozac',
        putnikId: r?['putnik_id']?.toString(),
        putnikTabela: r?['putnik_tabela']?.toString(),
        dan: r?['dan']?.toString(),
        grad: r?['grad']?.toString(),
        vreme: r?['zeljeno_vreme']?.toString(),
        polazakId: id,
        staro: {'status': r?['status'] ?? 'obrada'},
        novo: {'status': 'odbijeno'},
        detalji: 'Zahtev odbijen${rejectedBy != null ? " od: $rejectedBy" : ""}',
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------

  /// Čita polasciCache iz mastera, enrichuje iz putnici cacheova — 0 DB upita.
  ///
  /// - [statusFilter] = null → samo `'obrada'`; lista → filtriraj po tim statusima
  /// - [gradFilter] = opcioni filter po gradu (`'BC'` / `'VS'`)
  static Stream<List<V2Polazak>> v2StreamZahteviObrada({
    List<String>? statusFilter,
    String? gradFilter,
  }) {
    final rm = V2MasterRealtimeManager.instance;
    final controller = StreamController<List<V2Polazak>>.broadcast();

    // Čita iz cache-a i emituje — bez ijednog DB upita
    void emit() {
      if (controller.isClosed) return;
      final statusi = statusFilter != null && statusFilter.isNotEmpty ? statusFilter : const ['obrada'];

      final result = rm.polasciCache.values.where((row) {
        if (!statusi.contains(row['status'])) return false;
        if (gradFilter != null && row['grad'] != gradFilter) return false;
        return true;
      }).map((row) {
        final putnikId = row['putnik_id']?.toString();
        final putnikTabela = row['putnik_tabela']?.toString();

        // Enrichuj iz putnici cache-a — sve u memoriji
        final putnikRow = putnikId == null
            ? null
            : switch (putnikTabela) {
                'v2_radnici' => rm.radniciCache[putnikId],
                'v2_ucenici' => rm.uceniciCache[putnikId],
                'v2_dnevni' => rm.dnevniCache[putnikId],
                'v2_posiljke' => rm.posiljkeCache[putnikId],
                _ => null,
              };

        final enriched = putnikRow == null
            ? row
            : {
                ...row,
                'putnik_ime': putnikRow['ime'],
                'broj_telefona': putnikRow['telefon'], // DB kolona je 'telefon', ne 'broj_telefona'
              };

        return V2Polazak.fromJson(enriched);
      }).toList()
        ..sort((a, b) {
          final ca = a.createdAt ?? DateTime(0);
          final cb = b.createdAt ?? DateTime(0);
          return cb.compareTo(ca); // najnoviji prvi
        });

      controller.add(result);
    }

    // Emituj odmah (cache je već popunjen pri initialize())
    Future.microtask(emit);

    // Debounce 150ms — skuplja brze uzastopne v2_polasci evente u jedan emit
    Timer? debounce;
    final cacheSub = rm.onCacheChanged.where((t) => t == 'v2_polasci').listen((_) {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 150), emit);
    });
    controller.onCancel = () {
      debounce?.cancel();
      cacheSub.cancel();
      controller.close();
    };
    return controller.stream;
  }

  /// Broj zahteva u statusu `'obrada'` za dnevne putnike — za bedž na Home ekranu.
  /// Usklađeno sa screen filterom koji prikazuje samo tip 'dnevni'.
  static Stream<int> v2StreamBrojZahteva() => v2StreamZahteviObrada()
      .map((list) => list.where((z) => (z.tipPutnika ?? 'dnevni').toLowerCase() == 'dnevni').length);

  /// Prihvata alternativni termin - ODMAH ODOBRAVA
  static Future<bool> v2PrihvatiAlternativu({
    String? requestId,
    required String putnikId,
    required String novoVreme,
    required String grad,
    required String dan,
  }) async {
    try {
      final gradKey = V2GradAdresaValidator.normalizeGrad(grad);
      final danKey = dan.toLowerCase();
      final nowStr = DateTime.now().toUtc().toIso8601String();

      final rm = V2MasterRealtimeManager.instance;
      // Atomski UPDATE — direktno postavi novo vreme bez međukoraka 'cancelled'
      if (requestId != null && requestId.isNotEmpty) {
        final altPayload = {
          'zeljeno_vreme': novoVreme, // cekaonica → premestamo na novi termin
          'dodeljeno_vreme': novoVreme, // stvarni termin putovanja → novi termin
          'status': 'odobreno',
          'processed_at': nowStr,
          'updated_at': nowStr,
        };
        await _supabase.from('v2_polasci').update(altPayload).eq('id', requestId);
        rm.v2PatchCache('v2_polasci', requestId, altPayload);
      } else {
        // Ako nema requestId, kreiraj novi zahtev (fallback)
        final inserted = await _supabase
            .from('v2_polasci')
            .insert({
              'putnik_id': putnikId,
              'grad': gradKey,
              'dan': danKey,
              'zeljeno_vreme': novoVreme, // cekaonica
              'dodeljeno_vreme': novoVreme, // stvarni termin putovanja
              'status': 'odobreno',
              'processed_at': nowStr,
            })
            .select()
            .single();
        rm.v2UpsertToCache('v2_polasci', inserted);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // STATIČKI WRAPPERI — delegiraju na _svc instancu
  // ---------------------------------------------------------------------------

  static final V2PutnikStreamService _svc = V2PutnikStreamService();

  static Stream<List<V2Putnik>> v2StreamPutnici() => _svc.v2StreamPutnici();

  static Stream<List<V2Putnik>> streamKombinovaniPutniciFiltered({
    String? isoDate,
    String? dan,
    String? grad,
    String? vreme,
    String? selectedVreme,
    String? selectedDan,
    String? datum,
    String? requestId,
    String? status,
  }) =>
      _svc.streamKombinovaniPutniciFiltered(
        isoDate: isoDate,
        dan: dan,
        grad: grad,
        vreme: vreme ?? selectedVreme,
      );

  static void v2RefreshStreams() => _svc.v2RefreshStreams();

  static Future<int> v2GlobalniBezPolaska({
    String? dan,
    String? grad,
    String? vreme,
  }) =>
      _svc.v2GlobalniBezPolaska(
        dan: dan ?? '',
        grad: grad ?? '',
        vreme: vreme ?? '',
      );

  static Future<void> v2DodajPutnika({
    String? putnikId,
    String? dan,
    String? grad,
    String? vreme,
    String? putnikTabela,
    String? adresaId,
    int brojMesta = 1,
  }) async {
    if (putnikId == null) return;
    final rm = V2MasterRealtimeManager.instance;
    final tabela = putnikTabela ?? rm.v2GetPutnikById(putnikId)?['_tabela']?.toString();
    await v2PoSaljiZahtev(
      putnikId: putnikId,
      dan: dan ?? '',
      grad: grad ?? '',
      vreme: vreme ?? '',
      isAdmin: true,
      putnikTabela: tabela,
      customAdresaId: adresaId,
      brojMesta: brojMesta,
    );
  }

  static Future<void> v2OznaciPlaceno({
    String? putnikId,
    double? iznos,
    String? vozacId,
    String? grad,
    String? selectedVreme,
    String? selectedDan,
    String? tipPutnika,
    String? putnikIme,
    String? putnikTabela,
  }) async {
    if (putnikId == null) return;
    await _svc.v2OznaciPlaceno(
      putnikId,
      iznos ?? 0,
      vozacId,
      grad: grad,
      selectedVreme: selectedVreme,
      selectedDan: selectedDan,
      tipPutnika: tipPutnika,
      putnikIme: putnikIme,
      putnikTabela: putnikTabela,
    );
  }

  static Future<void> v2OznaciPokupljen({
    String? putnikId,
    bool? pokupljen,
    String? grad,
    String? vreme,
    String? driver,
    String? datum,
    String? requestId,
  }) async {
    if (putnikId == null) return;
    await _svc.v2OznaciPokupljen(
      putnikId,
      pokupljen ?? true,
      grad: grad,
      vreme: vreme,
      driver: driver,
      datum: datum,
      requestId: requestId,
    );
  }

  static Future<void> v2OtkaziPutnika({
    String? putnikId,
    String? vozacId,
    String? otkazao,
    String? grad,
    String? vreme,
    String? selectedDan,
    String? datum,
    String? requestId,
    String? status,
  }) async {
    if (putnikId == null) return;
    await _svc.v2OtkaziPutnika(
      putnikId,
      otkazao,
      grad: grad,
      vreme: vreme,
      selectedDan: selectedDan,
      datum: datum,
      requestId: requestId,
      status: status ?? 'otkazano',
    );
  }
}

// =============================================================================
// V2PutnikStreamService — instance klasa za stream i write operacije
// =============================================================================

/// Servis za putnike — read metode čitaju iz V2MasterRealtimeManager cache-a,
/// write metode pišu direktno u bazu.
class V2PutnikStreamService {
  SupabaseClient get supabase => globals_file.supabase;

  // ──────────────────────────────────────────────────────────────────────────
  // ──────────────────────────────────────────────────────────────────────────

  /// Stream kombinovanih putnika sa opcionim filterima (isoDate, grad, vreme, vozacId).
  Stream<List<V2Putnik>> streamKombinovaniPutniciFiltered(
      {String? isoDate, String? dan, String? grad, String? vreme, String? vozacId}) {
    final controller = StreamController<List<V2Putnik>>.broadcast();
    bool isEmitting = false;
    bool pendingEmit = false;
    Timer? _debounce;

    Future<void> emit() async {
      if (isEmitting) {
        pendingEmit = true; // zabilježi da treba još jedan emit kad završi
        return;
      }
      isEmitting = true;
      pendingEmit = false;
      try {
        if (controller.isClosed) return;
        final result = await _fetchPutnici(isoDate: isoDate, dan: dan, grad: grad, vreme: vreme, vozacId: vozacId);
        if (!controller.isClosed) controller.add(result);
      } catch (e) {
        if (!controller.isClosed) controller.add([]);
      } finally {
        isEmitting = false;
        if (pendingEmit) unawaited(emit()); // ako je stigla nova promjena, odmah emituj
      }
    }

    void scheduleEmit() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 150), emit);
    }

    final rm = V2MasterRealtimeManager.instance;

    // Inicijalna emisija — ako RM nije gotov, čeka pa emituje
    Future(() async {
      if (!rm.isInitialized) {
        for (int i = 0; i < 50 && !rm.isInitialized; i++) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
      await emit();
    });

    // Sve relevantne tabele — polasci + raspored + putnik tabele (status promjena)
    // Debounce 150ms — skuplja brze uzastopne evente u jedan emit (sprečava treperenje)
    final cacheSub = rm.onCacheChanged
        .where((t) =>
            t == 'v2_polasci' ||
            t == 'v2_vozac_raspored' ||
            t == 'v2_vozac_putnik' ||
            t == 'v2_dnevni' ||
            t == 'v2_radnici' ||
            t == 'v2_ucenici' ||
            t == 'v2_posiljke')
        .listen((_) => scheduleEmit());

    controller.onCancel = () {
      _debounce?.cancel();
      cacheSub.cancel();
      controller.close();
    };

    return controller.stream;
  }

  /// Stream svih putnika za danas.
  Stream<List<V2Putnik>> v2StreamPutnici() {
    final todayDate = DateTime.now().toIso8601String().split('T')[0];
    return streamKombinovaniPutniciFiltered(isoDate: todayDate);
  }

  /// Eksplicitan refresh — no-op jer stream automatski reaguje na RM promjene.
  void v2RefreshStreams() {
    V2MasterRealtimeManager.instance.v2RefreshPolasciCache();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // READ METODE
  // ──────────────────────────────────────────────────────────────────────────

  Future<List<V2Putnik>> getPutniciByDayIso(String isoDate) async {
    try {
      final todayDate = isoDate.split('T')[0];
      final targetDan = V2DanUtils.odIso(todayDate);
      final rm = V2MasterRealtimeManager.instance;

      return rm.polasciCache.values
          .where((sr) => sr['dan']?.toString() == targetDan)
          .map((sr) {
            final putnikId = sr['putnik_id']?.toString();
            final rp = putnikId != null ? rm.v2GetPutnikById(putnikId) : null;
            return _buildPutnik(sr, rp, todayDate);
          })
          .where((p) => p.status != 'bez_polaska')
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<V2Putnik?> getPutnikByName(String ime, {String? grad}) async {
    final String todayStr = DateTime.now().toIso8601String().split('T')[0];
    final rm = V2MasterRealtimeManager.instance;

    final rpEntry = rm.v2GetAllPutnici().where((r) => r['ime']?.toString() == ime).firstOrNull;
    if (rpEntry == null) return null;
    final putnikId = rpEntry['id']?.toString();
    if (putnikId == null) return null;

    final srRow = rm.polasciCache.values.where((r) => r['putnik_id']?.toString() == putnikId).firstOrNull;
    if (srRow != null) {
      return _buildPutnik(srRow, rpEntry, todayStr);
    }
    return V2Putnik.v2FromProfil(rpEntry);
  }

  Future<V2Putnik?> getPutnikFromAnyTable(dynamic id) async {
    try {
      final todayStr = DateTime.now().toIso8601String().split('T')[0];
      final String idStr = id.toString();
      final rm = V2MasterRealtimeManager.instance;

      final srRow = rm.polasciCache.values.where((r) => r['putnik_id']?.toString() == idStr).firstOrNull;
      final rp = rm.v2GetPutnikById(idStr);

      if (srRow != null) {
        return _buildPutnik(srRow, rp, todayStr);
      }
      if (rp != null) return V2Putnik.v2FromProfil(rp);
      return null;
    } catch (e) {
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
      return [];
    }
  }

  Future<List<V2Putnik>> v2GetAllPutnici({String? targetDay, String? isoDate}) async {
    try {
      final String danasStr = (isoDate ?? DateTime.now().toIso8601String()).split('T')[0];
      return await getPutniciByDayIso(danasStr);
    } catch (e) {
      return [];
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // INTERNI HELPERI
  // ──────────────────────────────────────────────────────────────────────────

  Future<List<V2Putnik>> _fetchPutnici(
      {String? isoDate, String? dan, String? grad, String? vreme, String? vozacId}) async {
    final rm = V2MasterRealtimeManager.instance;

    if (!rm.isInitialized) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    final String danKratica;
    final List<V2Putnik> sviPutnici;
    if (dan != null) {
      danKratica = dan;
      final isoZaDan = V2DanUtils.isoZaDan(dan);
      sviPutnici = rm.polasciCache.values
          .where((sr) => sr['dan']?.toString() == dan)
          .map((sr) {
            final putnikId = sr['putnik_id']?.toString();
            final rp = putnikId != null ? rm.v2GetPutnikById(putnikId) : null;
            return _buildPutnik(sr, rp, isoZaDan);
          })
          .where((p) => p.status != 'bez_polaska')
          .toList();
    } else {
      final todayDate = (isoDate ?? DateTime.now().toIso8601String()).split('T')[0];
      danKratica = V2DanUtils.odIso(todayDate);
      sviPutnici = await getPutniciByDayIso(todayDate);
    }
    final gradNorm = grad == null ? null : V2GradAdresaValidator.normalizeGrad(grad).toUpperCase();
    final vremeNorm = vreme != null ? V2GradAdresaValidator.normalizeTime(vreme) : null;

    return sviPutnici.where((p) {
      if (gradNorm != null) {
        if (V2GradAdresaValidator.normalizeGrad(p.grad).toUpperCase() != gradNorm) return false;
      }
      if (vremeNorm != null) {
        if (V2GradAdresaValidator.normalizeTime(p.polazak) != vremeNorm) return false;
      }
      if (vozacId != null) {
        final putnikIdStr = p.id?.toString() ?? '';
        final gradNormP = V2GradAdresaValidator.normalizeGrad(p.grad).toUpperCase();
        final vremeNormP = V2GradAdresaValidator.normalizeTime(p.polazak);

        final sveDodjele = rm.vozacPutnikCache.values
            .where((vp) =>
                vp['putnik_id']?.toString() == putnikIdStr &&
                vp['dan']?.toString() == danKratica &&
                vp['grad']?.toString().toUpperCase() == gradNormP &&
                V2GradAdresaValidator.normalizeTime(vp['vreme']?.toString()) == vremeNormP)
            .toList();

        if (sveDodjele.isNotEmpty) {
          // Individualna dodjela postoji za ovaj dan+grad+vreme — prikaži samo ako je dodeljen OVOM vozaču
          return sveDodjele.any((vp) => vp['vozac_id']?.toString() == vozacId);
        }

        // Nema individualne dodjele — provjeri raspored za ovaj termin
        final rasporedZaTermin = rm.rasporedCache.values
            .where((vr) =>
                vr['dan']?.toString() == danKratica &&
                vr['grad']?.toString().toUpperCase() == gradNormP &&
                V2GradAdresaValidator.normalizeTime(vr['vreme']?.toString()) == vremeNormP)
            .toList();
        // Nema rasporeda za termin → vozač ne vidi ove putnike (termin nije dodeljen njemu)
        if (rasporedZaTermin.isEmpty) return false;
        return rasporedZaTermin.any((vr) => vr['vozac_id']?.toString() == vozacId);
      }
      return true;
    }).toList();
  }

  static V2Putnik _buildPutnik(
    Map<String, dynamic> srRow,
    Map<String, dynamic>? rp,
    String isoDate,
  ) {
    final bool jePokupljen = srRow['status'] == 'pokupljen';
    final bool jeOtkazan = srRow['status'] == 'otkazano';

    final bool jePlacen = srRow['placen'] == true;
    final double? iznos = (srRow['placen_iznos'] as num?)?.toDouble();
    final String? naplatioVozac = srRow['placen_vozac_ime']?.toString();
    final String? naplatioVozacId = srRow['placen_vozac_id']?.toString();
    final String? vremeUplate = jePlacen
        ? (srRow['placen_at']?.toString() ?? srRow['updated_at']?.toString() ?? srRow['datum_akcije']?.toString())
        : null;

    final String? vozacId = naplatioVozacId ?? (jePokupljen ? _vozacIdZaIme(srRow['pokupio']?.toString()) : null);
    final String? vozacIme = naplatioVozac ?? (jePokupljen ? srRow['pokupio']?.toString() : null);

    final String? pokupioVozac = srRow['pokupio']?.toString();
    final String? pokupioVozacId = _vozacIdZaIme(pokupioVozac);

    String? nazivAdrese;
    final adresaId = srRow['adresa_id']?.toString();
    if (adresaId != null && adresaId.isNotEmpty) {
      nazivAdrese = V2MasterRealtimeManager.instance.adreseCache[adresaId]?['naziv']?.toString();
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
    if (pokupioVozac != null) map['pokupioVozac'] = pokupioVozac;
    if (pokupioVozacId != null) map['pokupioVozacId'] = pokupioVozacId;
    if (naplatioVozac != null) map['naplatioVozac'] = naplatioVozac;
    if (naplatioVozacId != null) map['naplatioVozacId'] = naplatioVozacId;
    if (vremeUplate != null) map['vreme_placanja'] = vremeUplate;
    if (nazivAdrese != null) map['adrese'] = {'naziv': nazivAdrese};
    if (rp != null) map['registrovani_putnici'] = rp;
    return V2Putnik.v2FromPolazak(map);
  }

  /// Pomoćna: traži vozac_id po imenu iz vozaciCache
  static String? _vozacIdZaIme(String? ime) {
    if (ime == null || ime.isEmpty) return null;
    return V2MasterRealtimeManager.instance.vozaciCache.values
        .where((v) => v['ime']?.toString() == ime)
        .firstOrNull?['id']
        ?.toString();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // WRITE METODE
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

  String v2NowString() => DateTime.now().toUtc().toIso8601String();

  Future<void> v2DodajPutnika(V2Putnik putnik) async {
    final allPutnici = V2MasterRealtimeManager.instance.v2GetAllPutnici();
    final found = allPutnici.where((r) => r['ime']?.toString() == putnik.ime).firstOrNull;

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
    if (!value) return;

    final targetDatum = datum ?? DateTime.now().toIso8601String().split('T')[0];

    String? vozacId;
    final rm = V2MasterRealtimeManager.instance;
    if (driver != null) {
      // Čitaj iz cache-a — 0 DB querija
      vozacId = rm.vozaciCache.values.firstWhere((v) => v['ime'] == driver, orElse: () => {})['id'] as String?;
    }

    try {
      final payload = {
        'status': 'pokupljen',
        'updated_at': v2NowString(),
        'processed_at': v2NowString(),
        if (driver != null) 'pokupio': driver,
        'pokupljen_datum': targetDatum,
        'datum_akcije': targetDatum,
      };

      bool polasciUpdated = false;
      String? updatedId;
      if (requestId != null && requestId.isNotEmpty) {
        final res = await supabase.from('v2_polasci').update(payload).eq('id', requestId).select('id');
        polasciUpdated = res.isNotEmpty;
        if (polasciUpdated) updatedId = requestId;
      } else {
        final gradKey = grad != null ? V2GradAdresaValidator.normalizeGrad(grad) : null;
        final vremeKey = vreme != null ? V2GradAdresaValidator.normalizeTime(vreme) : null;
        String? danKey;
        try {
          final dt = DateTime.parse(targetDatum);
          const dani = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
          danKey = dani[dt.weekday - 1];
        } catch (_) {}
        if (gradKey == null || vremeKey == null || danKey == null) {
          return;
        }
        final res = await supabase
            .from('v2_polasci')
            .update(payload)
            .eq('putnik_id', id.toString())
            .eq('dan', danKey)
            .eq('grad', gradKey)
            .eq('zeljeno_vreme', vremeKey)
            .select('id');
        polasciUpdated = res.isNotEmpty;
        if (polasciUpdated) updatedId = res.first['id']?.toString();
      }
      if (!polasciUpdated) {
        return;
      }

      // Optimistički cache patch — UI se osvježava odmah, bez čekanja WebSocket event-a
      if (updatedId != null) {
        rm.v2PatchCache('v2_polasci', updatedId, payload);
      }
    } catch (e) {
      return;
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

    // Audit log — ko je pokupljeno i od koga
    final putnikRow = V2MasterRealtimeManager.instance.v2GetPutnikById(id.toString());
    V2AuditLogService.log(
      tip: 'pokupljen',
      aktorId: vozacId,
      aktorIme: driver,
      aktorTip: 'vozac',
      putnikId: id.toString(),
      putnikIme: putnikRow?['ime']?.toString(),
      putnikTabela: putnikRow?['_tabela']?.toString(),
      dan: () {
        try {
          final dt = DateTime.parse(targetDatum);
          const dani = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
          return dani[dt.weekday - 1];
        } catch (_) {
          return null;
        }
      }(),
      grad: grad,
      vreme: vreme,
      polazakId: requestId?.isNotEmpty == true ? requestId : null,
      novo: {'status': 'pokupljen', 'datum': targetDatum},
      detalji: 'Putnik pokupljen${driver != null ? " od: $driver" : ""}',
    );
  }

  Future<void> v2OznaciStatus(String putnikId, String status, String actor) async {
    try {
      final putnikData = V2MasterRealtimeManager.instance.v2GetPutnikById(putnikId);
      final tabela = putnikData?['_tabela'] as String?;
      if (tabela != null) {
        await supabase.from(tabela).update({
          'status': status,
          'updated_at': v2NowString(),
        }).eq('id', putnikId);
      } else {}

      if (status == 'bolovanje' || status == 'godisnji') {
        final danasDay = DateTime.now().weekday;
        final sutraDay = DateTime.now().add(const Duration(days: 1)).weekday;
        const dani = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
        final danasKratica = dani[danasDay - 1];
        final sutraKratica = dani[sutraDay - 1];

        await supabase
            .from('v2_polasci')
            .update({'status': 'otkazano', 'updated_at': v2NowString()})
            .eq('putnik_id', putnikId)
            .inFilter('dan', [danasKratica, sutraKratica])
            .inFilter('status', ['obrada', 'odobreno']);
        await V2StatistikaIstorijaService.logGeneric(
          tip: status, // 'bolovanje' ili 'godisnji'
          putnikId: putnikId,
          detalji: 'Polasci automatski ukloneni zbog: $status',
          datum: DateTime.now().toIso8601String().split('T')[0],
        );
      }
    } catch (e) {
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
    String? vozacUuid;
    if (driver != null) {
      vozacUuid = V2VozacCache.getUuidByIme(driver);
    }

    final updatePayload = {
      'status': status,
      'processed_at': v2NowString(),
      'updated_at': v2NowString(),
      if (driver != null) 'otkazao': driver,
    };

    bool polasciUpdated = false;
    String? updatedId;

    if (requestId != null && requestId.isNotEmpty) {
      try {
        final res = await supabase.from('v2_polasci').update(updatePayload).eq('id', requestId).select('id');
        polasciUpdated = res.isNotEmpty;
        if (polasciUpdated) updatedId = requestId;
      } catch (e) {}
    }

    if (!polasciUpdated) {
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

      final gradKey = V2GradAdresaValidator.normalizeGrad(finalGrad);
      final normalizedTime = V2GradAdresaValidator.normalizeTime(finalVreme);

      try {
        if (normalizedTime.isNotEmpty) {
          var res = await supabase
              .from('v2_polasci')
              .update(updatePayload)
              .match({'putnik_id': id.toString(), 'dan': danKey})
              .eq('grad', gradKey)
              .eq('zeljeno_vreme', normalizedTime)
              .select('id');

          if (res.isNotEmpty) {
            polasciUpdated = true;
            updatedId = res.first['id']?.toString();
          } else {
            res = await supabase
                .from('v2_polasci')
                .update(updatePayload)
                .match({'putnik_id': id.toString(), 'dan': danKey})
                .eq('grad', gradKey)
                .eq('dodeljeno_vreme', normalizedTime)
                .select('id');
            polasciUpdated = res.isNotEmpty;
            if (polasciUpdated) updatedId = res.first['id']?.toString();
          }
        }
      } catch (e) {
        rethrow;
      }
    }

    if (!polasciUpdated) {
      return;
    }

    // Optimistički cache patch — UI se osvježava odmah, bez čekanja WebSocket event-a
    if (updatedId != null) {
      V2MasterRealtimeManager.instance.v2PatchCache('v2_polasci', updatedId, updatePayload);
    }

    try {
      await V2StatistikaIstorijaService.logGeneric(
        tip: 'otkazivanje',
        putnikId: id.toString(),
        vozacId: vozacUuid,
        vozacImeOverride: vozacUuid == null ? driver : null,
        grad: selectedGrad ?? grad,
        vreme: selectedVreme ?? vreme,
        datum: datum,
      );
    } catch (e) {}

    // Audit log — ko je otkazao i koji status
    final putnikRow = V2MasterRealtimeManager.instance.v2GetPutnikById(id.toString());
    V2AuditLogService.log(
      tip: 'otkazano_vozac',
      aktorId: vozacUuid,
      aktorIme: driver,
      aktorTip: driver != null ? 'vozac' : 'putnik',
      putnikId: id.toString(),
      putnikIme: putnikRow?['ime']?.toString(),
      putnikTabela: putnikRow?['_tabela']?.toString(),
      dan: selectedDan,
      grad: selectedGrad ?? grad,
      vreme: selectedVreme ?? vreme,
      polazakId: updatedId,
      staro: {'status': 'odobreno'},
      novo: {'status': status},
      detalji: 'Otkazano${driver != null ? " od: $driver" : ""} — status: $status',
    );
  }

  Future<void> v2OznaciPlaceno(
    dynamic id,
    num iznos,
    String? driver, {
    String? grad,
    String? selectedVreme,
    String? selectedDan,
    String? requestId,
    String? tipPutnika,
    String? putnikIme,
    String? putnikTabela,
  }) async {
    final dateStr = DateTime.now().toIso8601String().split('T')[0];

    String? vozacId;
    if (driver != null) {
      // Čitaj iz cache-a — 0 DB querija
      final rm = V2MasterRealtimeManager.instance;
      vozacId = rm.vozaciCache.values.firstWhere((v) => v['ime'] == driver, orElse: () => {})['id'] as String?;
    }

    bool polasciUpdated = false;

    if (requestId != null && requestId.isNotEmpty) {
      final res = await supabase
          .from('v2_polasci')
          .update({
            'placen': true,
            'placen_iznos': iznos.toDouble(),
            if (vozacId != null) 'placen_vozac_id': vozacId,
            if (driver != null) 'placen_vozac_ime': driver,
            'datum_akcije': v2NowString(),
            'placen_tip': tipPutnika ?? 'dnevni',
            'placen_at': v2NowString(),
            'updated_at': v2NowString(),
          })
          .eq('id', requestId)
          .select('id');
      polasciUpdated = res.isNotEmpty;
    } else if (selectedDan != null && selectedVreme != null && grad != null) {
      final gradKey = V2GradAdresaValidator.normalizeGrad(grad);
      final vremeKey = V2GradAdresaValidator.normalizeTime(selectedVreme);
      const daniMap = {
        'ponedeljak': 'pon',
        'utorak': 'uto',
        'sreda': 'sre',
        'cetvrtak': 'cet',
        'petak': 'pet',
        'subota': 'sub',
        'nedelja': 'ned',
      };
      final danKey = daniMap[selectedDan.toLowerCase()] ?? selectedDan.toLowerCase();
      final res = await supabase
          .from('v2_polasci')
          .update({
            'placen': true,
            'placen_iznos': iznos.toDouble(),
            if (vozacId != null) 'placen_vozac_id': vozacId,
            if (driver != null) 'placen_vozac_ime': driver,
            'datum_akcije': v2NowString(),
            'placen_tip': tipPutnika ?? 'dnevni',
            'placen_at': v2NowString(),
            'updated_at': v2NowString(),
          })
          .eq('putnik_id', id.toString())
          .eq('dan', danKey)
          .eq('grad', gradKey)
          .eq('zeljeno_vreme', vremeKey)
          .select('id');
      polasciUpdated = res.isNotEmpty;
    }

    // Upiši u statistiku SAMO ako je v2_polasci uspješno ažuriran
    if (!polasciUpdated) {
      return;
    }

    await V2StatistikaIstorijaService.dodajUplatu(
      putnikId: id.toString(),
      datum: DateTime.parse(dateStr),
      iznos: iznos.toDouble(),
      putnikIme: putnikIme,
      putnikTabela: putnikTabela,
      vozacId: vozacId,
      vozacImeParam: driver,
      grad: grad,
      vreme: selectedVreme,
    );

    // Audit log — zabilježi naplatu
    final _gradForAudit = grad != null ? V2GradAdresaValidator.normalizeGrad(grad) : null;
    V2AuditLogService.log(
      tip: 'naplata',
      aktorId: vozacId,
      aktorIme: driver,
      aktorTip: 'vozac',
      putnikId: id.toString(),
      putnikIme: putnikIme,
      putnikTabela: putnikTabela,
      dan: selectedDan,
      grad: _gradForAudit,
      vreme: selectedVreme,
      polazakId: requestId?.isNotEmpty == true ? requestId : null,
      novo: {'placen': true, 'iznos': iznos.toDouble()},
      detalji: 'Naplata: ${iznos.toStringAsFixed(0)} RSD${driver != null ? " od: $driver" : ""}',
    );
  }

  // NAPOMENA: v2GlobalniBezPolaska koristi UPDATE → 'bez_polaska', NE brisanje zapisa.
  // Razlozi:
  //   1. Null/brisanje bi uklonilo putnika iz cache-a (aktivniStatusi u MasterRealtimeManager
  //      eksplicitno uključuje 'bez_polaska') → putnik nestaje iz profila i vozačevog ekrana.
  //   2. jeBezPolaska getter se koristi na 10+ mjesta u vozac_screen i putnik_profil_screen
  //      za poseban prikaz — null bi pokrio drugu granu logike (putnik nema raspored).
  //   3. 'bez_polaska' ima _statusPrioritet = 0 → automatski pregažen novim zahtevom putnika.
  //   4. Semantika: 'bez_polaska' = putnik IMA raspored ali ta nedelja nema polaska.
  //                  null/nema zapisa = putnik NIKAD nije imao raspored za taj dan.
  Future<int> v2GlobalniBezPolaska({
    required String dan,
    required String grad,
    required String vreme,
  }) async {
    try {
      final gradKey = V2GradAdresaValidator.normalizeGrad(grad);
      const _danMap = {
        'ponedeljak': 'pon',
        'utorak': 'uto',
        'sreda': 'sre',
        'cetvrtak': 'cet',
        'petak': 'pet',
        'subota': 'sub',
        'nedelja': 'ned',
      };
      final danLow = dan.toLowerCase();
      final danKey = _danMap[danLow] ?? danLow;

      final now = v2NowString();
      var query = supabase.from('v2_polasci').update({
        'status': 'bez_polaska',
        'processed_at': now,
        'updated_at': now,
      }).match({'dan': danKey}).inFilter('status', ['odobreno', 'obrada', 'pokupljen', 'otkazano']).eq('grad', gradKey);

      if (vreme.isNotEmpty && vreme != 'Sva vremena') {
        query = query.eq('zeljeno_vreme', V2GradAdresaValidator.normalizeTime(vreme));
      }

      final res = await query.select('id');
      final rm = V2MasterRealtimeManager.instance;
      final patchPayload = {
        'status': 'bez_polaska',
        'processed_at': now,
        'updated_at': now,
      };
      for (final row in res) {
        rm.v2PatchCache('v2_polasci', row['id'].toString(), patchPayload);
      }

      // Audit log — jedna globalna stavka koja bilježi broj pogođenih putnika
      V2AuditLogService.log(
        tip: 'bez_polaska_globalni',
        aktorTip: 'admin',
        dan: danKey,
        grad: gradKey,
        vreme: vreme.isNotEmpty && vreme != 'Sva vremena' ? V2GradAdresaValidator.normalizeTime(vreme) : null,
        novo: {'status': 'bez_polaska', 'pogodeni_putnici': res.length},
        detalji:
            'Bez polaska: $danKey $gradKey${vreme.isNotEmpty && vreme != "Sva vremena" ? " $vreme" : " (sva vremena)"} — ${res.length} putnika',
      );

      return res.length;
    } catch (e, st) {
      debugPrint('[v2GlobalniBezPolaska] greška: $e\n$st');
      rethrow;
    }
  }
}
