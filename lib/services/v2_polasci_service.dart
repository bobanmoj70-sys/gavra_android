import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../models/v2_polazak.dart';
import '../utils/v2_grad_adresa_validator.dart';
import 'realtime/v2_master_realtime_manager.dart';

/// Servis za upravljanje aktivnim zahtevima za sedišta (v2_polasci tabela)
class V2PolasciService {
  static SupabaseClient get _supabase => supabase;

  /// ✅ UNIFIKOVANA ULAZNA TAČKA — koriste je svi akteri (V2Putnik, admin, vozač)
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
      final gradKey = GradAdresaValidator.normalizeGrad(grad);
      final normVreme = GradAdresaValidator.normalizeTime(vreme);
      final danKey = dan.toLowerCase();
      final nowStr = DateTime.now().toUtc().toIso8601String();
      final status = isAdmin ? 'odobreno' : 'obrada';

      // Upsert po (putnik_id, dan, grad, zeljeno_vreme) — svaka kombinacija je jedinstvena
      final existing = await _supabase
          .from('v2_polasci')
          .select('id')
          .eq('putnik_id', putnikId)
          .eq('grad', gradKey)
          .eq('dan', danKey)
          .eq('zeljeno_vreme', '$normVreme:00')
          .maybeSingle();

      if (existing != null) {
        await _supabase.from('v2_polasci').update({
          'status': status,
          'broj_mesta': brojMesta,
          if (putnikTabela != null) 'putnik_tabela': putnikTabela,
          if (customAdresaId != null) 'adresa_id': customAdresaId,
          if (isAdmin) 'dodeljeno_vreme': '$normVreme:00',
          'updated_at': nowStr,
        }).eq('id', existing['id']);
        debugPrint('✅ [V2PolasciService] v2PoSaljiZahtev UPDATE $gradKey $normVreme $danKey (isAdmin=$isAdmin)');
      } else {
        await _supabase.from('v2_polasci').insert({
          'putnik_id': putnikId,
          'grad': gradKey,
          'dan': danKey,
          'zeljeno_vreme': '$normVreme:00',
          if (isAdmin) 'dodeljeno_vreme': '$normVreme:00',
          'status': status,
          'broj_mesta': brojMesta,
          if (putnikTabela != null) 'putnik_tabela': putnikTabela,
          if (customAdresaId != null) 'adresa_id': customAdresaId,
          'created_at': nowStr,
          'updated_at': nowStr,
        });
        debugPrint('✅ [V2PolasciService] v2PoSaljiZahtev INSERT $gradKey $normVreme $danKey (isAdmin=$isAdmin)');
      }
    } catch (e) {
      debugPrint('❌ [V2PolasciService] v2PoSaljiZahtev error: $e');
      rethrow;
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
        if (approvedBy != null) 'approved_by': approvedBy,
      }).eq('id', id);

      return true;
    } catch (e) {
      debugPrint('❌ [V2PolasciService] Error approving request: $e');
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
        if (rejectedBy != null) 'cancelled_by': rejectedBy,
      }).eq('id', id);

      return true;
    } catch (e) {
      debugPrint('❌ [V2PolasciService] Error rejecting request: $e');
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
                _ => rm.getPutnikById(putnikId),
              };

        final enriched = putnikRow == null
            ? row
            : {
                ...row,
                'putnik_ime': putnikRow['ime'],
                'broj_telefona': putnikRow['broj_telefona'],
                if (putnikTabela == null) 'putnik_tabela': putnikRow['_tabela'],
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

    // Svakim realtime eventom na v2_polasci master ažurira polasciCache,
    // a mi samo ponovo čitamo iz tog cache-a
    final sub = rm.subscribe('v2_polasci').listen((_) => emit());
    controller.onCancel = () {
      sub.cancel();
      rm.unsubscribe('v2_polasci');
    };
    return controller.stream;
  }

  /// Broj zahteva u statusu `'obrada'` — za bedž na Home ekranu.
  static Stream<int> v2StreamBrojZahteva() => v2StreamZahteviObrada().map((list) => list.length);



  /// 🎫 Prihvata alternativni termin - ODMAH ODOBRAVA
  static Future<bool> v2PrihvatiAlternativu({
    String? requestId,
    required String putnikId,
    required String novoVreme,
    required String grad,
    required String dan,
  }) async {
    try {
      final gradKey = GradAdresaValidator.normalizeGrad(grad);
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
      debugPrint('❌ [V2PolasciService] Error accepting alternative: $e');
      return false;
    }
  }
}
