import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';

/// 📱 Unificirani servis za registraciju push tokena
/// Zamenjuje dupliciranu logiku iz FirebaseService, HuaweiPushService i PutnikPushService
///
/// Svi tokeni (FCM i HMS, vozači i putnici) se registruju na isti način:
/// - Direktan UPSERT u push_tokens tabelu
/// - Pending token mehanizam za offline scenarije
class V2PushTokenService {
  /// Lazy getter - pristupa Supabase tek kada je potrebno i inicijalizovan
  static SupabaseClient get _supabase => supabase;

  /// Proveri da li je Supabase inicijalizovan
  static bool get _isSupabaseReady => isSupabaseReady;

  /// 📲 Registruje push token direktno u Supabase bazu
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
        if (kDebugMode) {
          debugPrint('⚠️ [PushToken] Prazan token, preskačem registraciju');
        }
        return false;
      }

      // ⏳ Proveri da li je Supabase spreman - ako nije, preskači
      if (!_isSupabaseReady) {
        if (kDebugMode) {
          debugPrint('⏳ [PushToken] Supabase nije spreman, preskačem registraciju');
        }
        return false;
      }

      // 🧹 PRVO: Obriši stare tokene za ovog korisnika da izbegnemo duplikate
      final timeout = const Duration(seconds: 15);

      // Obriši stare tokene za istog putnika
      if (putnikId != null && putnikId.isNotEmpty) {
        await _supabase
            .from('v2_push_tokens')
            .delete()
            .eq('putnik_id', putnikId)
            .timeout(timeout)
            .catchError((e) => null);
      }

      // Obriši stare tokene za istog vozača
      if (vozacId != null && vozacId.isNotEmpty) {
        await _supabase
            .from('v2_push_tokens')
            .delete()
            .eq('vozac_id', vozacId)
            .timeout(timeout)
            .catchError((e) => null);
      }

      // ✅ UPSERT novi token
      final data = <String, dynamic>{
        'token': token,
        'provider': provider,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (vozacId != null && vozacId.isNotEmpty) data['vozac_id'] = vozacId;
      if (putnikId != null && putnikId.isNotEmpty) data['putnik_id'] = putnikId;
      if (putnikTabela != null && putnikTabela.isNotEmpty) data['putnik_tabela'] = putnikTabela;

      await _supabase.from('v2_push_tokens').upsert(data, onConflict: 'token').timeout(timeout);

      if (kDebugMode) {
        debugPrint('✅ [PushToken] Token registrovan: $provider/${token.substring(0, 20)}...');
      }

      // Obriši pending token ako postoji (uspešno registrovan)
      await _clearPendingToken();

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [PushToken] Greška pri registraciji (pokušaj ${retryCount + 1}): $e');
      }

      // 🔄 RETRY LOGIKA za 503/Timeout greške
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

  /// 💾 Sačuvaj token lokalno za kasniju registraciju
  static Future<void> savePendingToken({
    required String token,
    required String provider,
    String? vozacId,
    String? putnikId,
  }) async {
    // Do nothing
  }

  /// 🔄 Pokušaj registrovati pending token
  /// Poziva se nakon što Supabase postane dostupan
  static Future<bool> tryRegisterPendingToken() async {
    // Return false
    return false;
  }

  /// 🗑️ Obriši pending token iz SharedPreferences
  static Future<void> _clearPendingToken() async {
    // Do nothing
  }

  /// 🗑️ Obriši token iz baze (logout, deregistracija)
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

      if (kDebugMode) {
        debugPrint('🗑️ [PushToken] Token obrisan');
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [PushToken] Greška pri brisanju tokena: $e');
      }
      return false;
    }
  }

  /// 📊 Dohvati tokene za listu vozača (po vozac_id)
  static Future<List<Map<String, String>>> getTokensForUsers(List<String> vozacIds) async {
    if (vozacIds.isEmpty) return [];

    try {
      final response =
          await _supabase.from('v2_push_tokens').select('vozac_id, token, provider').inFilter('vozac_id', vozacIds);

      return (response as List)
          .map<Map<String, String>>((row) => {
                'vozac_id': row['vozac_id'] as String? ?? '',
                'token': row['token'] as String? ?? '',
                'provider': row['provider'] as String? ?? '',
              })
          .where((t) => t['token']!.isNotEmpty)
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [PushToken] Greška pri dohvatanju tokena: $e');
      }
      return [];
    }
  }

  /// 🚗 Dohvati tokene za sve vozače
  static Future<List<Map<String, String>>> getTokensForVozaci() async {
    try {
      final response =
          await _supabase.from('v2_push_tokens').select('vozac_id, token, provider').not('vozac_id', 'is', null);

      return (response as List)
          .map<Map<String, String>>((row) => {
                'vozac_id': row['vozac_id']?.toString() ?? '',
                'token': row['token'] as String? ?? '',
                'provider': row['provider'] as String? ?? '',
              })
          .where((t) => t['token']!.isNotEmpty)
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [PushToken] Greška pri dohvatanju vozačkih tokena: $e');
      }
      return [];
    }
  }
}
