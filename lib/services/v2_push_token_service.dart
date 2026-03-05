import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import 'realtime/v2_master_realtime_manager.dart';
import 'v2_firebase_service.dart';
import 'v2_huawei_push_service.dart';

/// Unificirani servis za registraciju push tokena.
/// Zamenjuje dupliciranu logiku iz V2FirebaseService, V2HuaweiPushService i V2PutnikPushService.
///
/// Svi tokeni (FCM i HMS, vozači i putnici) se registruju na isti način:
/// - Direktan UPSERT u push_tokens tabelu
/// - Pending token mehanizam za offline scenarije
class V2PushTokenService {
  V2PushTokenService._();

  /// Lazy getter - pristupa Supabase tek kada je potrebno i inicijalizovan
  static SupabaseClient get _supabase => supabase;

  /// Proveri da li je Supabase inicijalizovan
  static bool get _isSupabaseReady => isSupabaseReady;

  /// Registruje push token direktno u Supabase bazu.
  ///
  /// [token] - FCM ili HMS token
  /// [provider] - 'fcm' za Firebase ili 'huawei' za HMS
  /// [vozacId] - UUID vozača iz vozaci tabele (samo za vozače)
  /// [putnikId] - ID putnika (samo za putnike)
  static Future<bool> registerToken({
    required String token,
    required String provider,
    String? vozacId,
    String? putnikId,
    String? putnikTabela,
    int retryCount = 0,
  }) async {
    try {
      if (token.isEmpty) {
        debugPrint('[PushToken] Prazan token, preskačem registraciju');
        return false;
      }

      // Proveri da li je Supabase spreman - ako nije, preskaci
      if (!_isSupabaseReady) {
        debugPrint('[PushToken] Supabase nije spreman, preskačem registraciju');
        return false;
      }

      // PRVO: Obrisi stare tokene za ovog korisnika da izbegnemo duplikate
      final timeout = const Duration(seconds: 15);

      // Obrisi stare tokene za istog putnika
      if (putnikId != null && putnikId.isNotEmpty) {
        await _supabase.from('v2_push_tokens').delete().eq('putnik_id', putnikId).timeout(timeout).catchError((e) {
          debugPrint('[PushToken] Greska pri brisanju starih putnik tokena: $e');
          return <dynamic>[];
        });
      }

      // Obrisi stare tokene za istog vozaca
      if (vozacId != null && vozacId.isNotEmpty) {
        await _supabase.from('v2_push_tokens').delete().eq('vozac_id', vozacId).timeout(timeout).catchError((e) {
          debugPrint('[PushToken] Greska pri brisanju starih vozac tokena: $e');
          return <dynamic>[];
        });
      }

      // UPSERT novi token
      final data = <String, dynamic>{
        'token': token,
        'provider': provider,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (vozacId != null && vozacId.isNotEmpty) data['vozac_id'] = vozacId;
      if (putnikId != null && putnikId.isNotEmpty) data['putnik_id'] = putnikId;
      if (putnikTabela != null && putnikTabela.isNotEmpty) data['putnik_tabela'] = putnikTabela;

      await _supabase.from('v2_push_tokens').upsert(data, onConflict: 'token').timeout(timeout);

      debugPrint('[PushToken] Token registrovan: $provider/${token.substring(0, token.length.clamp(0, 20))}...');

      // Obriši pending token ako postoji (uspešno registrovan)
      await _clearPendingToken();

      return true;
    } catch (e) {
      debugPrint('[PushToken] Greška pri registraciji (pokušaj ${retryCount + 1}): $e');

      // RETRY LOGIKA za 503/Timeout greške
      final errorStr = e.toString().toLowerCase();
      if ((errorStr.contains('503') || errorStr.contains('timeout') || errorStr.contains('upstream')) &&
          retryCount < 2) {
        await Future.delayed(Duration(seconds: 2 * (retryCount + 1)));
        return registerToken(
          token: token,
          provider: provider,
          vozacId: vozacId,
          putnikId: putnikId,
          putnikTabela: putnikTabela,
          retryCount: retryCount + 1,
        );
      }

      // Ako ni retries ne pomognu, sačuvaj kao pending
      await savePendingToken(
        token: token,
        provider: provider,
        vozacId: vozacId,
        putnikId: putnikId,
      );

      return false;
    }
  }

  /// Sačuvaj token lokalno za kasniju registraciju
  static Future<void> savePendingToken({
    required String token,
    required String provider,
    String? vozacId,
    String? putnikId,
  }) async {
    // Do nothing
  }

  /// Pokušaj registrovati pending token.
  /// Poziva se nakon što Supabase postane dostupan.
  static Future<bool> tryRegisterPendingToken() async {
    // Return false
    return false;
  }

  /// Obrisi pending token iz SharedPreferences
  static Future<void> _clearPendingToken() async {
    // Do nothing
  }

  /// Obrisi token iz baze (logout, deregistracija)
  static Future<bool> clearToken({
    String? token,
    String? putnikId,
    String? vozacId,
  }) async {
    try {
      if (token != null) {
        await _supabase.from('v2_push_tokens').delete().eq('token', token);
      } else if (putnikId != null) {
        await _supabase.from('v2_push_tokens').delete().eq('putnik_id', putnikId);
      } else if (vozacId != null) {
        await _supabase.from('v2_push_tokens').delete().eq('vozac_id', vozacId);
      } else {
        return false;
      }

      debugPrint('[PushToken] Token obrisan');

      return true;
    } catch (e) {
      debugPrint('[PushToken] Greška pri brisanju tokena: $e');
      return false;
    }
  }

  /// Dohvati tokene za listu vozača (po vozac_id)
  static Future<List<Map<String, String>>> getTokensForUsers(List<String> vozacIds) async {
    if (vozacIds.isEmpty) return [];

    try {
      final response =
          await _supabase.from('v2_push_tokens').select('vozac_id, token, provider').inFilter('vozac_id', vozacIds);

      return response
          .map<Map<String, String>>((row) => {
                'vozac_id': row['vozac_id']?.toString() ?? '',
                'token': row['token']?.toString() ?? '',
                'provider': row['provider']?.toString() ?? '',
              })
          .where((t) => t['token']!.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[PushToken] Greška pri dohvatanju tokena: $e');
      return [];
    }
  }

  /// Dohvati tokene za sve vozače
  static Future<List<Map<String, String>>> getTokensForVozaci() async {
    try {
      final response =
          await _supabase.from('v2_push_tokens').select('vozac_id, token, provider').not('vozac_id', 'is', null);

      return response
          .map<Map<String, String>>((row) => {
                'vozac_id': row['vozac_id']?.toString() ?? '',
                'token': row['token']?.toString() ?? '',
                'provider': row['provider']?.toString() ?? '',
              })
          .where((t) => t['token']!.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[PushToken] Greška pri dohvatanju vozačkih tokena: $e');
      return [];
    }
  }
}

// =============================================================================
// Spojeno iz v2_putnik_push_service.dart
// =============================================================================

/// Servis za registraciju push tokena putnika.
/// Koristi unificirani PushTokenService za registraciju.
class V2PutnikPushService {
  V2PutnikPushService._();

  /// Registruje push token za putnika u push_tokens tabelu.
  static Future<bool> registerPutnikToken(dynamic putnikId, {String? putnikTabela}) async {
    try {
      debugPrint('[PutnikPush] Registrujem token za putnika: $putnikId');

      String? token;
      String? provider;

      token = await V2FirebaseService.getFCMToken();
      if (token != null && token.isNotEmpty) {
        provider = 'fcm';
        debugPrint('[PutnikPush] FCM token dobijen: ${token.substring(0, token.length.clamp(0, 20))}...');
      } else {
        debugPrint('[PutnikPush] FCM token nije dostupan, pokusavam HMS...');
        token = await V2HuaweiPushService().initialize();
        if (token != null && token.isNotEmpty) {
          provider = 'huawei';
          debugPrint('[PutnikPush] HMS token dobijen: ${token.substring(0, token.length.clamp(0, 20))}...');
        }
      }

      if (token == null || provider == null) {
        debugPrint('[PutnikPush] Nijedan push provider nije dostupan!');
        return false;
      }

      final resolvedTabela = putnikTabela ??
          V2MasterRealtimeManager.instance.getPutnikById(putnikId?.toString() ?? '')?['putnik_tabela']?.toString();
      debugPrint('[PutnikPush] putnikTabela: $resolvedTabela');

      final success = await V2PushTokenService.registerToken(
        token: token,
        provider: provider,
        putnikId: putnikId?.toString(),
        putnikTabela: resolvedTabela,
      );

      debugPrint('[PutnikPush] Registracija ${success ? "uspesna" : "neuspesna"}');
      return success;
    } catch (e) {
      debugPrint('[PutnikPush] Greška pri registraciji: $e');
      return false;
    }
  }
}
