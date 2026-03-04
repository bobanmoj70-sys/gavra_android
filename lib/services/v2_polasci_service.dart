import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart' as globals_file;
import '../globals.dart';
import '../models/v2_polazak.dart';
import '../models/v2_putnik.dart';
import '../utils/v2_grad_adresa_validator.dart';
import '../utils/v2_vozac_cache.dart';
import 'realtime/v2_master_realtime_manager.dart';
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

      // 1. Ukloni sve ostale aktivne zahtjeve za isti grad+dan (drugačije vreme)
      // Putnik može imati samo jedan aktivan zahtjev po grad+dan.
      // isAdmin=true → 'bez_polaska' (tiho brisanje, ne utiče na statistiku)
      // isAdmin=false → 'cancelled' (putnik sam menja zahtev)
      await _supabase
          .from('v2_polasci')
          .update({'status': isAdmin ? 'bez_polaska' : 'cancelled', 'updated_at': nowStr})
          .eq('putnik_id', putnikId)
          .eq('grad', gradKey)
          .eq('dan', danKey)
          .neq('zeljeno_vreme', normVreme)
          .inFilter('status', ['obrada', 'odobreno', 'odbijeno']);

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
        await _supabase.from('v2_polasci').update({
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
        }).eq('id', existing['id']);
        debugPrint('[V2PolasciService] v2PoSaljiZahtev UPDATE $gradKey $normVreme $danKey (isAdmin=$isAdmin)');
      } else {
        await _supabase.from('v2_polasci').insert({
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
        });
        debugPrint('[V2PolasciService] v2PoSaljiZahtev INSERT $gradKey $normVreme $danKey (isAdmin=$isAdmin)');
      }
    } catch (e) {
      debugPrint('[V2PolasciService] v2PoSaljiZahtev error: $e');
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

      debugPrint('[V2PolasciService] v2SetBrojMesta: updated ${res.length} rows → $brojMesta mesta');
      return res.isNotEmpty;
    } catch (e) {
      debugPrint('[V2PolasciService] v2SetBrojMesta error: $e');
      return false;
    }
  }

  /// Odobrava zahtev — kopira zeljeno_vreme u dodeljeno_vreme
  static Future<bool> v2OdobriZahtev(String id, {String? approvedBy}) async {
    try {
      final nowStr = DateTime.now().toUtc().toIso8601String();

      // 1. Dohvati zeljeno_vreme za ovaj zahtev
      final row = await _supabase.from('v2_polasci').select('zeljeno_vreme').eq('id', id).single();

      final zeljenoVreme = row['zeljeno_vreme'];

      // 2. Odobri i upisi dodeljeno_vreme = zeljeno_vreme
      await _supabase.from('v2_polasci').update({
        'status': 'odobreno',
        'dodeljeno_vreme': zeljenoVreme, // kopira zeljeno_vreme u dodeljeno_vreme
        'updated_at': nowStr,
        'processed_at': nowStr,
        if (approvedBy != null) 'odobrio': approvedBy,
      }).eq('id', id);

      return true;
    } catch (e) {
      debugPrint('[V2PolasciService] Error approving request: $e');
      return false;
    }
  }

  /// Odbija zahtev
  static Future<bool> v2OdbijZahtev(String id, {String? rejectedBy}) async {
    try {
      await _supabase.from('v2_polasci').update({
        'status': 'odbijeno',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'processed_at': DateTime.now().toUtc().toIso8601String(),
        if (rejectedBy != null) 'otkazao': rejectedBy,
      }).eq('id', id);

      return true;
    } catch (e) {
      debugPrint('[V2PolasciService] Error rejecting request: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // JAVNI STREAMOVI — čitaju direktno iz V2MasterRealtimeManager cache-a
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

    // v2_polasci je statička tabela — onCacheChanged je dovoljan, subscribe višak
    final cacheSub = rm.onCacheChanged.where((t) => t == 'v2_polasci').listen((_) => emit());
    controller.onCancel = () {
      cacheSub.cancel();
      controller.close();
    };
    return controller.stream;
  }

  /// Broj zahteva u statusu `'obrada'` samo za dnevne putnike — za bedž na Home ekranu.
  static Stream<int> v2StreamBrojZahteva() =>
      v2StreamZahteviObrada().map((list) => list.where((z) => z.tipPutnika == 'dnevni').length);

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

      // Atomski UPDATE — direktno postavi novo vreme bez međukoraka 'cancelled'
      if (requestId != null && requestId.isNotEmpty) {
        await _supabase.from('v2_polasci').update({
          'zeljeno_vreme': novoVreme, // cekaonica → premestamo na novi termin
          'dodeljeno_vreme': novoVreme, // stvarni termin putovanja → novi termin
          'status': 'odobreno',
          'processed_at': nowStr,
          'updated_at': nowStr,
        }).eq('id', requestId);
      } else {
        // Ako nema requestId, kreiraj novi zahtev (fallback)
        await _supabase.from('v2_polasci').insert({
          'putnik_id': putnikId,
          'grad': gradKey,
          'dan': danKey,
          'zeljeno_vreme': novoVreme, // cekaonica
          'dodeljeno_vreme': novoVreme, // stvarni termin putovanja
          'status': 'odobreno',
          'processed_at': nowStr,
        });
      }
      return true;
    } catch (e) {
      debugPrint('[V2PolasciService] Error accepting alternative: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // STATIČKI WRAPPERI — delegiraju na _svc instancu
  // ---------------------------------------------------------------------------

  static final V2PutnikStreamService _svc = V2PutnikStreamService();

  static Stream<List<V2Putnik>> streamPutnici() => _svc.streamPutnici();

  static Stream<List<V2Putnik>> streamKombinovaniPutniciFiltered({
    String? isoDate,
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
        grad: grad,
        vreme: vreme ?? selectedVreme,
      );

  static void refreshAllActiveStreams() => _svc.refreshAllActiveStreams();

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
    final tabela = putnikTabela ?? rm.getPutnikById(putnikId)?['_tabela']?.toString();
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
      vozacId,
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
  // STREAM METODE — emituju direktno iz RM cache-a
  // ──────────────────────────────────────────────────────────────────────────

  /// Stream kombinovanih putnika sa opcionim filterima (isoDate, grad, vreme, vozacId).
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
    final cacheSub = rm.onCacheChanged
        .where((t) =>
            t == 'v2_polasci' ||
            t == 'v2_vozac_raspored' ||
            t == 'v2_vozac_putnik' ||
            t == 'v2_dnevni' ||
            t == 'v2_radnici' ||
            t == 'v2_ucenici' ||
            t == 'v2_posiljke')
        .listen((_) => emit());

    controller.onCancel = () {
      cacheSub.cancel();
      controller.close();
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
    debugPrint('[V2PutnikStreamService] refreshAllActiveStreams — osvežavam polasciCache...');
    V2MasterRealtimeManager.instance.refreshPolasciCache();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // READ METODE
  // ──────────────────────────────────────────────────────────────────────────

  Future<List<V2Putnik>> getPutniciByDayIso(String isoDate) async {
    try {
      final todayDate = isoDate.split('T')[0];
      final targetDan = _isoToDanKratica(todayDate);
      final rm = V2MasterRealtimeManager.instance;

      return rm.polasciCache.values
          .where((sr) => sr['dan']?.toString() == targetDan)
          .map((sr) {
            final putnikId = sr['putnik_id']?.toString();
            final rp = putnikId != null ? rm.getPutnikById(putnikId) : null;
            return _buildPutnik(sr, rp, todayDate);
          })
          .where((p) => p.status != 'bez_polaska')
          .toList();
    } catch (e) {
      debugPrint('[PutnikService] Error fetching by day: $e');
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
      final rp = rm.getPutnikById(idStr);

      if (srRow != null) {
        return _buildPutnik(srRow, rp, todayStr);
      }
      if (rp != null) return V2Putnik.v2FromProfil(rp);
      return null;
    } catch (e) {
      debugPrint('[PolasciService] getPutnikById error: $e');
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
      debugPrint('[PutnikService] Error in getPutniciByIds: $e');
      return [];
    }
  }

  Future<List<V2Putnik>> getAllPutnici({String? targetDay, String? isoDate}) async {
    try {
      final String danasStr = (isoDate ?? DateTime.now().toIso8601String()).split('T')[0];
      return await getPutniciByDayIso(danasStr);
    } catch (e) {
      debugPrint('[PutnikService] Error in getAllPutnici: $e');
      return [];
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // INTERNI HELPERI
  // ──────────────────────────────────────────────────────────────────────────

  Future<List<V2Putnik>> _fetchPutnici({String? isoDate, String? grad, String? vreme, String? vozacId}) async {
    final todayDate = (isoDate ?? DateTime.now().toIso8601String()).split('T')[0];
    final rm = V2MasterRealtimeManager.instance;

    if (!rm.isInitialized) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    final sviPutnici = await getPutniciByDayIso(todayDate);
    final gradNorm = grad == null ? null : V2GradAdresaValidator.normalizeGrad(grad).toUpperCase();
    final vremeNorm = vreme != null ? V2GradAdresaValidator.normalizeTime(vreme) : null;
    final danKratica = _isoToDanKratica(todayDate);

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

        // Provjeri ima li ovaj putnik individualnu dodjelu za OVAJ dan+grad+vreme
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

  static String _isoToDanKratica(String iso) {
    const map = {1: 'pon', 2: 'uto', 3: 'sre', 4: 'cet', 5: 'pet', 6: 'sub', 7: 'ned'};
    return map[DateTime.tryParse(iso)?.weekday ?? 1]!;
  }

  static V2Putnik _buildPutnik(
    Map<String, dynamic> srRow,
    Map<String, dynamic>? rp,
    String isoDate,
  ) {
    final bool jePokupljen = srRow['status'] == 'pokupljen';
    final bool jeOtkazan = srRow['status'] == 'otkazano';

    // Čita direktno sa v2_polasci reda — nove kolone (Faza 2)
    final bool jePlacen = srRow['placen'] == true;
    final double? iznos = (srRow['placen_iznos'] as num?)?.toDouble();
    final String? naplatioVozac = srRow['placen_vozac_ime']?.toString();
    final String? naplatioVozacId = srRow['placen_vozac_id']?.toString();
    final String? datumAkcije = srRow['datum_akcije']?.toString();
    final String? vremeUplate = jePlacen ? datumAkcije : null;

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

  String nowToString() => DateTime.now().toUtc().toIso8601String();

  Future<void> v2DodajPutnika(V2Putnik putnik) async {
    debugPrint('[PutnikService] v2DodajPutnika: ime="${putnik.ime}"');

    final allPutnici = V2MasterRealtimeManager.instance.getAllPutnici();
    final found = allPutnici.where((r) => r['ime']?.toString() == putnik.ime).firstOrNull;

    debugPrint('[PutnikService] Cache lookup: ${found != null ? "FOUND id=${found['id']}" : 'NOT FOUND'}');

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
    if (driver != null) {
      // Čitaj iz cache-a — 0 DB querija
      final rm = V2MasterRealtimeManager.instance;
      vozacId = rm.vozaciCache.values.firstWhere((v) => v['ime'] == driver, orElse: () => {})['id'] as String?;
    }

    try {
      final payload = {
        'status': 'pokupljen',
        'updated_at': nowToString(),
        'processed_at': nowToString(),
        if (driver != null) 'pokupio': driver,
        'pokupljen_datum': targetDatum,
        'datum_akcije': targetDatum,
      };

      bool polasciUpdated = false;
      if (requestId != null && requestId.isNotEmpty) {
        final res = await supabase.from('v2_polasci').update(payload).eq('id', requestId).select('id');
        polasciUpdated = res.isNotEmpty;
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
          debugPrint('[PutnikService] v2OznaciPokupljen: Nedostaje grad, vreme ili dan!');
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
      }
      if (!polasciUpdated) {
        debugPrint('[PutnikService] v2OznaciPokupljen: v2_polasci update nije pronašao red, preskačem statistiku.');
        return;
      }
    } catch (e) {
      debugPrint('[PutnikService] v2OznaciPokupljen: Greška pri update v2_polasci: $e');
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
  }

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
        debugPrint('[PutnikService] v2OznaciStatus: Putnik $putnikId nije u v2_ cache-u!');
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
        await V2StatistikaIstorijaService.logGeneric(
          tip: status, // 'bolovanje' ili 'godisnji'
          putnikId: putnikId,
          detalji: 'Polasci automatski ukloneni zbog: $status',
          datum: DateTime.now().toIso8601String().split('T')[0],
        );
      }
    } catch (e) {
      debugPrint('[PutnikService] Error setting bolovanje/godisnji: $e');
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
      'processed_at': nowToString(),
      'updated_at': nowToString(),
      if (driver != null) 'otkazao': driver,
    };

    bool polasciUpdated = false;

    if (requestId != null && requestId.isNotEmpty) {
      try {
        final res = await supabase.from('v2_polasci').update(updatePayload).eq('id', requestId).select('id');
        polasciUpdated = res.isNotEmpty;
      } catch (e) {
        debugPrint('[PutnikService] v2OtkaziPutnika: Error matching by requestId: $e');
      }
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
          } else {
            res = await supabase
                .from('v2_polasci')
                .update(updatePayload)
                .match({'putnik_id': id.toString(), 'dan': danKey})
                .eq('grad', gradKey)
                .eq('dodeljeno_vreme', normalizedTime)
                .select('id');
            polasciUpdated = res.isNotEmpty;
          }
        }
      } catch (e) {
        debugPrint('[PutnikService] v2OtkaziPutnika ERROR: $e');
        rethrow;
      }
    }

    if (!polasciUpdated) {
      debugPrint('[PutnikService] v2OtkaziPutnika: v2_polasci update nije pronašao red, preskačem statistiku.');
      return;
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
    } catch (e) {
      debugPrint('[PutnikService] Greška pri logovanju otkazivanja: $e');
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
    String? tipPutnika,
  }) async {
    final dateStr = DateTime.now().toIso8601String().split('T')[0];

    String? vozacId;
    if (driver != null) {
      // Čitaj iz cache-a — 0 DB querija
      final rm = V2MasterRealtimeManager.instance;
      vozacId = rm.vozaciCache.values.firstWhere((v) => v['ime'] == driver, orElse: () => {})['id'] as String?;
    }

    // Upiši direktno u v2_polasci (nove kolone Faza 2)
    bool polasciUpdated = false;

    if (requestId != null && requestId.isNotEmpty) {
      final res = await supabase
          .from('v2_polasci')
          .update({
            'placen': true,
            'placen_iznos': iznos.toDouble(),
            if (vozacId != null) 'placen_vozac_id': vozacId,
            if (driver != null) 'placen_vozac_ime': driver,
            'datum_akcije': nowToString(),
            'placen_tip': tipPutnika ?? 'dnevni',
            'updated_at': nowToString(),
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
            'datum_akcije': nowToString(),
            'placen_tip': tipPutnika ?? 'dnevni',
            'updated_at': nowToString(),
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
      debugPrint(
          '[v2OznaciPlaceno] v2_polasci nije ažuriran — statistika se ne upisuje (id=$id, requestId=$requestId)');
      return;
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

      var query = supabase.from('v2_polasci').update({
        'status': 'bez_polaska',
        'processed_at': nowToString(),
        'updated_at': nowToString(),
      }).match({'dan': danKey}).inFilter('status', ['odobreno', 'obrada']).eq('grad', gradKey);

      if (vreme.isNotEmpty && vreme != 'Sva vremena') {
        query = query.eq('zeljeno_vreme', V2GradAdresaValidator.normalizeTime(vreme));
      }

      final res = await query.select('id');
      debugPrint('[PutnikService] globalniBezPolaska: updated ${res.length} rows');
      return res.length;
    } catch (e) {
      debugPrint('[PutnikService] globalniBezPolaska ERROR: $e');
      return 0;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATISTIKA / PLAĆANJA — direktni upiti na v2_statistika_istorija
// ─────────────────────────────────────────────────────────────────────────────
class V2PutnikStatistikaService {
  V2PutnikStatistikaService._();

  static SupabaseClient get _db => supabase;

  /// Dohvata sva plaćanja za putnika iz v2_statistika_istorija
  static Future<List<Map<String, dynamic>>> dohvatiPlacanja(String putnikId) async {
    try {
      final rows = await _db
          .from('v2_statistika_istorija')
          .select('iznos,datum,created_at,vozac_ime,placeni_mesec,placena_godina,tip')
          .eq('putnik_id', putnikId)
          .inFilter('tip', ['uplata']).order('datum', ascending: false);
      return rows
          .map<Map<String, dynamic>>((row) => {
                'iznos': row['iznos'],
                'datum': row['datum'],
                'created_at': row['created_at'],
                'vozac_ime': row['vozac_ime'],
                'placeni_mesec': row['placeni_mesec'],
                'placena_godina': row['placena_godina'],
                'tip': row['tip'],
              })
          .toList();
    } catch (e) {
      debugPrint('[V2PutnikStatistikaService] dohvatiPlacanja: $e');
      return [];
    }
  }

  /// Dohvata ukupno plaćeno za putnika
  static Future<double> dohvatiUkupnoPlaceno(String putnikId) async {
    try {
      final rows = await _db
          .from('v2_statistika_istorija')
          .select('iznos')
          .eq('putnik_id', putnikId)
          .inFilter('tip', ['uplata']);
      double ukupno = 0.0;
      for (final row in rows) {
        ukupno += (row['iznos'] as num?)?.toDouble() ?? 0.0;
      }
      return ukupno;
    } catch (e) {
      debugPrint('[V2PutnikStatistikaService] dohvatiUkupnoPlaceno: $e');
      return 0.0;
    }
  }

  /// Upisuje mesečnu uplatu u v2_statistika_istorija (arhiva) + v2_polasci (operativna)
  static Future<bool> upisPlacanjaULog({
    required String putnikId,
    required String putnikIme,
    required String putnikTabela,
    required double iznos,
    required String vozacIme,
    required DateTime datum,
    int? placeniMesec,
    int? placenaGodina,
  }) async {
    try {
      String? vozacId;
      if (vozacIme.isNotEmpty) {
        vozacId = V2VozacCache.getUuidByIme(vozacIme);
        vozacId ??= await V2VozacCache.getUuidByImeAsync(vozacIme);
      }
      final datumStr = datum.toIso8601String().split('T')[0];

      // Operativna — pazar tekuceg dana (opcionalno - samo ako postoji polazak danas)
      final rm = V2MasterRealtimeManager.instance;
      final srRow = rm.polasciCache.values.where((r) => r['putnik_id']?.toString() == putnikId).firstOrNull;
      if (srRow != null) {
        await _db.from('v2_polasci').update({
          'placen': true,
          'placen_iznos': iznos,
          if (vozacId != null) 'placen_vozac_id': vozacId,
          if (vozacIme.isNotEmpty) 'placen_vozac_ime': vozacIme,
          'datum_akcije': datumStr,
          'placen_tip': const {
                'v2_radnici': 'radnik',
                'v2_ucenici': 'ucenik',
                'v2_dnevni': 'dnevni',
                'v2_posiljke': 'posiljka',
              }[putnikTabela] ??
              'radnik',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', srRow['id'].toString());
      }

      // Arhiva — uvijek se upisuje (i retroaktivna plaćanja bez polaska danas)
      await V2StatistikaIstorijaService.dodajUplatu(
        putnikId: putnikId,
        datum: datum,
        iznos: iznos,
        vozacId: vozacId,
        vozacImeParam: vozacIme,
        placeniMesec: placeniMesec ?? datum.month,
        placenaGodina: placenaGodina ?? datum.year,
        tipUplate: 'uplata',
      );

      return true;
    } catch (e) {
      debugPrint('[V2PutnikStatistikaService] upisPlacanjaULog: $e');
      rethrow;
    }
  }
}
