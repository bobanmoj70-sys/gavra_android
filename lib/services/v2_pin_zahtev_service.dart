import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import 'realtime/v2_master_realtime_manager.dart';
import 'v2_realtime_notification_service.dart';

/// Servis za upravljanje PIN zahtevima putnika
class V2PinZahtevService {
  V2PinZahtevService._();
  static SupabaseClient get _supabase => supabase;

  static Future<bool> posaljiZahtev({
    required String putnikId,
    required String email,
    required String telefon,
    String? putnikTabela,
  }) async {
    try {
      final existing = await _supabase
          .from('v2_pin_zahtevi')
          .select('id')
          .eq('putnik_id', putnikId)
          .eq('status', 'ceka')
          .maybeSingle();

      if (existing != null) {
        return true;
      }

      await _supabase.from('v2_pin_zahtevi').insert({
        'putnik_id': putnikId,
        'email': email,
        'telefon': telefon,
        'status': 'ceka',
        if (putnikTabela != null) 'putnik_tabela': putnikTabela,
      });

      // Pošalji notifikaciju adminima
      await V2RealtimeNotificationService.sendNotificationToAdmins(
        title: '🔔 Novi zahtev za PIN',
        body: 'V2Putnik traži PIN za pristup aplikaciji',
        data: {'type': 'pin_zahtev', 'putnik_id': putnikId},
      );

      return true;
    } catch (e) {
      debugPrint('[V2PinZahtevService] posaljiZahtev error: $e');
      return false;
    }
  }

  /// Realtime stream: Prati nove zahteve za PIN — direktno iz pinCache, 0 DB upita
  static Stream<List<Map<String, dynamic>>> streamZahteviKojiCekaju() =>
      V2MasterRealtimeManager.instance.streamFromCache(
        tables: ['v2_pin_zahtevi'],
        build: _buildEnrichedList,
      );

  /// Izgradi enriched listu iz pinCache
  static List<Map<String, dynamic>> _buildEnrichedList() {
    final rm = V2MasterRealtimeManager.instance;
    final zahtevi = rm.pinCache.values.where((z) => z['status'] == 'ceka').toList()
      ..sort((a, b) {
        final ca = a['created_at'] as String? ?? '';
        final cb = b['created_at'] as String? ?? '';
        return ca.compareTo(cb);
      });

    return zahtevi.map((z) {
      final putnikId = z['putnik_id'] as String?;
      final putnikData = putnikId != null ? rm.getPutnikById(putnikId) : null;
      return <String, dynamic>{
        ...Map<String, dynamic>.from(z),
        'putnik_ime': putnikData?['ime'],
        'broj_telefona': putnikData?['telefon'],
        'tip': _tabelaToTip(z['putnik_tabela'] as String? ?? ''),
      };
    }).toList();
  }

  static int brojZahtevaKojiCekaju() {
    return V2MasterRealtimeManager.instance.pinCache.values.where((z) => z['status'] == 'ceka').length;
  }

  static Future<bool> odobriZahtev({
    required String zahtevId,
    required String pin,
  }) async {
    try {
      final zahtev = V2MasterRealtimeManager.instance.pinCache[zahtevId];
      if (zahtev == null) return false;

      final putnikId = zahtev['putnik_id'] as String?;
      if (putnikId == null) return false;
      final putnikTabela = zahtev['putnik_tabela'] as String? ?? '';

      // UPDATE pin na pravoj v2_ tabeli
      if (putnikTabela.isNotEmpty) {
        await _supabase.from(putnikTabela).update({'pin': pin}).eq('id', putnikId);
      }

      await _supabase.from('v2_pin_zahtevi').update({
        'status': 'odobren',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', zahtevId);

      return true;
    } catch (e) {
      debugPrint('[V2PinZahtevService] odobriZahtev error: $e');
      return false;
    }
  }

  static Future<bool> odbijZahtev(String zahtevId) async {
    try {
      await _supabase.from('v2_pin_zahtevi').update({
        'status': 'odbijen',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', zahtevId);

      return true;
    } catch (e) {
      debugPrint('[V2PinZahtevService] odbijZahtev error: $e');
      return false;
    }
  }

  /// Generisi nasumičan 4-cifreni PIN
  static String generatePin() {
    return (1000 + Random.secure().nextInt(9000)).toString();
  }

  static bool imaZahtevKojiCeka(String putnikId) {
    return V2MasterRealtimeManager.instance.pinCache.values
        .any((z) => z['putnik_id'] == putnikId && z['status'] == 'ceka');
  }

  /// Async verzija — provjerava cache, a ako je prazan pada na DB.
  /// Koristi se pri loginovanju da ne prikaže dialog ako je zahtev već poslat.
  static Future<bool> imaZahtevKojiCekuAsync(String putnikId) async {
    // Provjeri lokalni cache prvo (0 DB upita)
    final izCachea = V2MasterRealtimeManager.instance.pinCache.values
        .any((z) => z['putnik_id'] == putnikId && z['status'] == 'ceka');
    if (izCachea) return true;

    // Cache može biti prazan (cold start) — provjeri DB
    try {
      final row = await _supabase
          .from('v2_pin_zahtevi')
          .select('id')
          .eq('putnik_id', putnikId)
          .eq('status', 'ceka')
          .maybeSingle();
      return row != null;
    } catch (e) {
      debugPrint('[V2PinZahtevService] imaZahtevKojiCekuAsync error: $e');
      return false;
    }
  }

  static Future<bool> azurirajEmail({
    required String putnikId,
    required String putnikTabela,
    required String email,
  }) async {
    try {
      if (putnikTabela.isNotEmpty) {
        await _supabase.from(putnikTabela).update({'email': email}).eq('id', putnikId);
      }
      return true;
    } catch (e) {
      debugPrint('[V2PinZahtevService] azurirajEmail error: $e');
      return false;
    }
  }

  static String _tabelaToTip(String tabela) => switch (tabela) {
        'v2_radnici' => 'radnik',
        'v2_ucenici' => 'ucenik',
        'v2_dnevni' => 'dnevni',
        'v2_posiljke' => 'posiljka',
        _ => tabela,
      };
}
