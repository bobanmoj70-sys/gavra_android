import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import 'firebase_service.dart';
import 'huawei_push_service.dart';
import 'realtime/v2_master_realtime_manager.dart';
import 'v2_push_token_service.dart';

/// ðŸ“± Servis za registraciju push tokena putnika
/// Koristi unificirani PushTokenService za registraciju
class PutnikPushService {
  /// Registruje push token za putnika u push_tokens tabelu
  /// Koristi unificirani PushTokenService
  static Future<bool> registerPutnikToken(dynamic putnikId) async {
    try {
      if (kDebugMode) {
        debugPrint('ðŸ“± [PutnikPush] Registrujem token za putnika: $putnikId');
      }

      String? token;
      String? provider;

      // Prvo pokuÅ¡aj FCM (GMS ureÄ‘aji)
      token = await FirebaseService.getFCMToken();
      if (token != null && token.isNotEmpty) {
        provider = 'fcm';
        if (kDebugMode) {
          debugPrint('âœ… [PutnikPush] FCM token dobijen: ${token.substring(0, 20)}...');
        }
      } else {
        if (kDebugMode) {
          debugPrint('âš ï¸ [PutnikPush] FCM token nije dostupan, pokuÅ¡avam HMS...');
        }
        // Fallback na HMS (Huawei ureÄ‘aji)
        token = await HuaweiPushService().initialize();
        if (token != null && token.isNotEmpty) {
          provider = 'huawei';
          if (kDebugMode) {
            debugPrint('âœ… [PutnikPush] HMS token dobijen: ${token.substring(0, 20)}...');
          }
        }
      }

      if (token == null || provider == null) {
        if (kDebugMode) {
          debugPrint('âŒ [PutnikPush] Nijedan push provider nije dostupan!');
        }
        return false;
      }

      // Dohvati ime putnika iz cache-a
      final putnikData = V2MasterRealtimeManager.instance.getPutnikById(putnikId ?? '');
      final putnikIme = putnikData?['ime'] as String?;
      if (kDebugMode) debugPrint('ðŸ“ [PutnikPush] Ime putnika: $putnikIme');

      // Koristi unificirani PushTokenService
      final success = await V2PushTokenService.registerToken(
        token: token,
        provider: provider,
        userType: 'putnik',
        userId: putnikIme,
        putnikId: putnikId?.toString(),
      );

      if (kDebugMode) {
        debugPrint('${success ? "âœ…" : "âŒ"} [PutnikPush] Registracija ${success ? "uspeÅ¡na" : "neuspeÅ¡na"}');
      }
      return success;
    } catch (e) {
      if (kDebugMode) debugPrint('âŒ [PutnikPush] GreÅ¡ka pri registraciji: $e');
      return false;
    }
  }
}
