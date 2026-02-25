import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../models/seat_request.dart';
import '../utils/grad_adresa_validator.dart';
import 'voznje_log_service.dart';

/// Servis za upravljanje aktivnim zahtevima za sedišta (seat_requests tabela)
class SeatRequestService {
  static SupabaseClient get _supabase => supabase;

  /// 📥 INSERT U SEAT_REQUESTS TABELU ZA BACKEND OBRADU
  static Future<void> insertSeatRequest({
    required String putnikId,
    required String dan,
    required String vreme,
    required String grad,
    int brojMesta = 1,
    String status = 'pending',
    int priority = 1,
    String? customAdresaId, // 🏠 ID custom adrese za brži geocoding
  }) async {
    try {
      final gradKey = GradAdresaValidator.normalizeGrad(grad);
      final normVreme = GradAdresaValidator.normalizeTime(vreme);
      final danKey = dan.toLowerCase();

      // Provjeri da li postoji postojeći zahtev za SPECIFIČAN termin (putnik+grad+dan+VREME).
      // ⚠️ Svaki termin je NEZAVISAN — putnik može imati više različitih vremena za isti dan.
      final existingRequest = await _supabase
          .from('seat_requests')
          .select('id, status')
          .eq('putnik_id', putnikId)
          .eq('grad', gradKey)
          .eq('dan', danKey)
          .eq('zeljeno_vreme', '$normVreme:00')
          .limit(1);

      if (existingRequest.isNotEmpty) {
        final existingId = existingRequest.first['id'];
        final existingStatus = existingRequest.first['status'];

        // Ažuriraj postojeći zahtev za OVAJ specifičan termin
        await _supabase.from('seat_requests').update({
          'broj_mesta': brojMesta,
          'priority': priority,
          'custom_adresa_id': customAdresaId,
          'status': status,
          // confirmed = odmah odobreno, dodeljeno_vreme = zeljeno_vreme
          if (status == 'confirmed' || existingStatus == 'confirmed') 'dodeljeno_vreme': '$normVreme:00',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', existingId);
        debugPrint('✅ [SeatRequestService] Updated existing request for $gradKey $normVreme on $danKey');
      } else {
        // Kreiraj NOVI zahtev za ovaj specifičan termin (ne briše ostale termine)
        await _supabase.from('seat_requests').insert({
          'putnik_id': putnikId,
          'grad': gradKey,
          'dan': danKey,
          'zeljeno_vreme': '$normVreme:00',
          // dodeljeno_vreme se upisuje samo ako je status confirmed (odmah odobreno)
          if (status == 'confirmed') 'dodeljeno_vreme': '$normVreme:00',
          'status': status,
          'broj_mesta': brojMesta,
          'priority': priority,
          'custom_adresa_id': customAdresaId,
        });
        debugPrint('✅ [SeatRequestService] Inserted NEW request for $gradKey $normVreme on $danKey');
      }

      // 📝 LOG: Zablježi zakazanu vožnju u voznje_log (trajni zapis)
      final datumStr = getIsoDateForDan(danKey);
      await VoznjeLogService.logGeneric(
        tip: 'zakazano',
        putnikId: putnikId,
        datum: datumStr,
        grad: gradKey,
        vreme: normVreme,
        brojMesta: brojMesta,
        status: status,
      );
    } catch (e) {
      debugPrint('❌ [SeatRequestService] Error inserting seat request: $e');
    }
  }

  /// Odobrava zahtev — kopira zeljeno_vreme u dodeljeno_vreme
  static Future<bool> approveRequest(String id) async {
    try {
      final nowStr = DateTime.now().toUtc().toIso8601String();

      // 1. Dohvati zeljeno_vreme za ovaj zahtev
      final row = await _supabase.from('seat_requests').select('zeljeno_vreme').eq('id', id).single();

      final zeljenoVreme = row['zeljeno_vreme'];

      // 2. Odobri i upisi dodeljeno_vreme = zeljeno_vreme
      await _supabase.from('seat_requests').update({
        'status': 'approved',
        'dodeljeno_vreme': zeljenoVreme, // kopira zeljeno_vreme u dodeljeno_vreme
        'updated_at': nowStr,
        'processed_at': nowStr,
      }).eq('id', id);

      return true;
    } catch (e) {
      debugPrint('❌ [SeatRequestService] Error approving request: $e');
      return false;
    }
  }

  /// Odbija zahtev
  static Future<bool> rejectRequest(String id) async {
    try {
      await _supabase.from('seat_requests').update({
        'status': 'rejected',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'processed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);

      return true;
    } catch (e) {
      debugPrint('❌ [SeatRequestService] Error rejecting request: $e');
      return false;
    }
  }

  /// Stream za zahteve koji čekaju ručnu obradu admina (SVI sa pending statusom)
  static Stream<List<SeatRequest>> streamManualRequests() {
    return _supabase
        .from('seat_requests')
        .stream(primaryKey: ['id'])
        .eq('status', 'pending')
        .order('created_at', ascending: false)
        .map((data) => data.map((json) => SeatRequest.fromJson(json)).toList());
  }

  /// 🔢 Stream za broj zahteva koji čekaju ručnu obradu (za bedž na Home ekranu - SVI)
  static Stream<int> streamManualRequestCount() {
    return _supabase
        .from('seat_requests')
        .stream(primaryKey: ['id'])
        .eq('status', 'pending')
        .map((list) => list.map((json) => SeatRequest.fromJson(json)).length);
  }

  /// 🤖 POKREĆE DIGITALNOG DISPEČERA U BAZI
  static Future<int> triggerDigitalDispecer() async {
    try {
      // Poziva funkciju koja obrađuje sve 'pending' zahteve
      final response = await _supabase.rpc('obradi_sve_pending_zahteve');
      return (response as List).length;
    } catch (e) {
      // Alternativni poziv ako prva funkcija ne postoji (legacy fallback)
      try {
        final response = await _supabase.rpc('dispecer_cron_obrada');
        return (response as List).length;
      } catch (e2) {
        debugPrint('❌ [SeatRequestService] Error triggering digital dispecer: $e / $e2');
        return 0;
      }
    }
  }

  /// 🎫 Prihvata alternativni termin - ODMAH ODOBRAVA
  static Future<bool> acceptAlternative({
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

      // Otkaži SAMO stari specifičan zahtev (requestId) — ne sve termine za taj dan
      if (requestId != null && requestId.isNotEmpty) {
        // Prvo otkaži stari zahtev
        await _supabase.from('seat_requests').update({'status': 'cancelled'}).eq('id', requestId);

        // Ažuriraj isti red sa novim vremenom i odmah odobri
        await _supabase.from('seat_requests').update({
          'zeljeno_vreme': novoVreme,
          'dodeljeno_vreme': novoVreme, // alternativa odmah odobrena
          'status': 'approved',
          'processed_at': nowStr,
          'updated_at': nowStr,
        }).eq('id', requestId);
      } else {
        // Ako nema requestId, kreiraj novi zahtev (fallback)
        await _supabase.from('seat_requests').insert({
          'putnik_id': putnikId,
          'grad': gradKey,
          'dan': danKey,
          'zeljeno_vreme': novoVreme,
          'dodeljeno_vreme': novoVreme, // alternativa odmah odobrena
          'status': 'approved',
          'processed_at': nowStr,
        });
      }
      return true;
    } catch (e) {
      debugPrint('❌ [SeatRequestService] Error accepting alternative: $e');
      return false;
    }
  }

  /// 📅 Helper: Daje ISO datum za dan u tekućoj sedmici (za voznje_log)
  static String getIsoDateForDan(String danKratica) {
    const daniMap = {'pon': 1, 'uto': 2, 'sre': 3, 'cet': 4, 'pet': 5, 'sub': 6, 'ned': 7};
    final targetWeekday = daniMap[danKratica.toLowerCase()] ?? 1;
    final now = DateTime.now();
    int daysToAdd = targetWeekday - now.weekday;
    if (daysToAdd < 0) daysToAdd += 7;
    return now.add(Duration(days: daysToAdd)).toIso8601String().split('T')[0];
  }
}
