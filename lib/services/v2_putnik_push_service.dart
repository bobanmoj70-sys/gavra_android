import 'package:flutter/foundation.dart';

import 'realtime/v2_master_realtime_manager.dart';
import 'v2_firebase_service.dart';
import 'v2_huawei_push_service.dart';
import 'v2_push_token_service.dart';

/// 📱 Servis za registraciju push tokena putnika
/// Koristi unificirani PushTokenService za registraciju
class PutnikPushService {
  /// Registruje push token za putnika u push_tokens tabelu
  /// Koristi unificirani PushTokenService
  static Future<bool> registerPutnikToken(dynamic putnikId) async {
    try {
      if (kDebugMode) {
        debugPrint('📱 [PutnikPush] Registrujem token za putnika: $putnikId');
      }

      String? token;
      String? provider;

      // Prvo pokušaj FCM (GMS uređaji)
      token = await FirebaseService.getFCMToken();
      if (token != null && token.isNotEmpty) {
        provider = 'fcm';
        if (kDebugMode) {
          debugPrint('✅ [PutnikPush] FCM token dobijen: ${token.substring(0, 20)}...');
        }
      } else {
        if (kDebugMode) {
          debugPrint('⚠️ [PutnikPush] FCM token nije dostupan, pokušavam HMS...');
        }
        // Fallback na HMS (Huawei uređaji)
        token = await HuaweiPushService().initialize();
        if (token != null && token.isNotEmpty) {
          provider = 'huawei';
          if (kDebugMode) {
            debugPrint('✅ [PutnikPush] HMS token dobijen: ${token.substring(0, 20)}...');
          }
        }
      }

      if (token == null || provider == null) {
        if (kDebugMode) {
          debugPrint('❌ [PutnikPush] Nijedan push provider nije dostupan!');
        }
        return false;
      }

      // Dohvati podatke putnika iz cache-a (ako dostupno)
      final putnikData = V2MasterRealtimeManager.instance.getPutnikById(putnikId ?? '');
      final putnikTabela = putnikData?['putnik_tabela'] as String?;
      if (kDebugMode) debugPrint('📝 [PutnikPush] putnikTabela: $putnikTabela');

      // Koristi unificirani PushTokenService
      final success = await V2PushTokenService.registerToken(
        token: token,
        provider: provider,
        putnikId: putnikId?.toString(),
        putnikTabela: putnikTabela,
      );

      if (kDebugMode) {
        debugPrint('${success ? "✅" : "❌"} [PutnikPush] Registracija ${success ? "uspešna" : "neuspešna"}');
      }
      return success;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [PutnikPush] Greška pri registraciji: $e');
      return false;
    }
  }
}
