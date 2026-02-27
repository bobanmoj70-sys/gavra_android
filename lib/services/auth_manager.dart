import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../globals.dart';
import '../models/vozac.dart';
import '../screens/v2_welcome_screen.dart';
import '../utils/vozac_cache.dart';
import 'firebase_service.dart';
import 'huawei_push_service.dart';
import 'v2_push_token_service.dart';

/// ðŸ” CENTRALIZOVANI AUTH MANAGER
/// Upravlja lokalnim auth operacijama kroz SharedPreferences
/// Koristi device recognition i session management bez Supabase Auth
class AuthManager {
  // Unified SharedPreferences key
  static const String _driverKey = 'current_driver';
  static const String _authSessionKey = 'auth_session';
  static const String _deviceIdKey = 'device_id';
  static const String _rememberedDevicesKey = 'remembered_devices';

  /// ðŸš— DRIVER SESSION MANAGEMENT

  /// Postavi trenutnog vozaÄa (bez email auth-a)
  static Future<void> setCurrentDriver(String driverName) async {
    // Validacija da je vozaÄ prepoznat
    if (!(VozacCache.isValidIme(driverName))) {
      throw ArgumentError('VozaÄ "$driverName" nije registrovan');
    }

    await _saveDriverSession(driverName);
    await FirebaseService.setCurrentDriver(driverName);

    // ðŸ“± AÅ¾uriraj push token u pozadini - NE BLOKIRAJ login flow
    _updatePushTokenWithUserId(driverName);
  }

  /// ðŸ“± AÅ¾urira push token sa user_id i vozac_id vozaÄa
  /// PodrÅ¾ava i FCM (Google) i HMS (Huawei) tokene
  static Future<void> _updatePushTokenWithUserId(String driverName) async {
    try {
      debugPrint('ðŸ”„ [AuthManager] AÅ¾uriram token za vozaÄa: $driverName');

      // Dohvati vozac_id direktno iz baze
      Vozac? vozac = VozacCache.getVozacByIme(driverName);
      String? vozacId = vozac?.id;

      // Fallback: Ako VozacCache nema podatke, probaj direktno iz baze
      if (vozacId == null) {
        debugPrint('ðŸ”„ [AuthManager] VozacCache nema podatke, koristim direktno iz baze...');

        // Direktno iz baze
        try {
          vozac = VozacCache.getVozacByIme(driverName);
          vozacId = vozac?.id;
          if (vozacId != null) {
            debugPrint('ðŸ”„ [AuthManager] Vozac_id dobijen direktno: $vozacId');
          }
        } catch (e) {
          debugPrint('âš ï¸ [AuthManager] VozacBoja inicijalizacija neuspeÅ¡na: $e');
        }

        // Ako i dalje nema podataka, probaj direktno iz baze
        if (vozacId == null) {
          debugPrint('ðŸ”„ [AuthManager] VozacBoja nema podatke, pokuÅ¡avam fallback iz baze...');
          try {
            final response = await supabase
                .from('v2_vozaci')
                .select('id')
                .eq('ime', driverName)
                .single()
                .timeout(const Duration(seconds: 3));

            vozacId = response['id'] as String?;
            debugPrint('ðŸ”„ [AuthManager] Fallback vozac_id: $vozacId');
          } catch (e) {
            debugPrint('âš ï¸ [AuthManager] Fallback iz baze neuspeÅ¡an: $e');
          }
        }
      }

      debugPrint('ðŸ”„ [AuthManager] Final vozac_id: $vozacId');

      // Registruj tokene samo ako je vozaÄ uspeÅ¡no identifikovan
      if (vozacId == null || vozacId.isEmpty || driverName.isEmpty) {
        debugPrint('âš ï¸ [AuthManager] VozaÄ nije ulogovan ili identifikovan - preskaÄem registraciju tokena');
        return;
      }

      // 1. PokuÅ¡aj FCM token (Google/Samsung ureÄ‘aji)
      final fcmToken = await FirebaseService.getFCMToken();
      if (fcmToken != null && fcmToken.isNotEmpty) {
        debugPrint('ðŸ”„ [AuthManager] FCM token: ${fcmToken.substring(0, 30)}...');
        final success = await V2PushTokenService.registerToken(
          token: fcmToken,
          provider: 'fcm',
          userType: 'vozac',
          userId: driverName,
          vozacId: vozacId,
        );
        debugPrint('ðŸ”„ [AuthManager] FCM registracija: ${success ? "USPEH" : "NEUSPEH"}');
      }

      // 2. PokuÅ¡aj HMS token (Huawei ureÄ‘aji)
      // Koristi direktno dobijanje tokena
      try {
        final hmsToken = await HuaweiPushService().getHMSToken();
        if (hmsToken != null && hmsToken.isNotEmpty) {
          debugPrint('ðŸ”„ [AuthManager] HMS token: ${hmsToken.substring(0, 10)}...');
          final success = await V2PushTokenService.registerToken(
            token: hmsToken,
            provider: 'huawei',
            userType: 'vozac',
            userId: driverName,
            vozacId: vozacId,
          );
          debugPrint('ðŸ”„ [AuthManager] HMS registracija: ${success ? "USPEH" : "NEUSPEH"}');
        } else {
          debugPrint('ðŸ”„ [AuthManager] HMS token nije dostupan (token je null/prazan)');
        }
      } catch (e) {
        // HMS nije dostupan na ovom ureÄ‘aju - OK
        debugPrint('ðŸ”„ [AuthManager] HMS nije dostupan: $e');
      }
    } catch (e) {
      debugPrint('âŒ [AuthManager] GreÅ¡ka pri aÅ¾uriranju tokena: $e');
    }
  }

  /// Dobij trenutnog vozaÄa - ÄŒITA IZ SUPABASE po FCM/HMS tokenu
  /// Fallback na SharedPreferences ako nema interneta
  static Future<String?> getCurrentDriver() async {
    // 2. PokuÅ¡aj iz Supabase
    try {
      final driverFromSupabase = await _getDriverFromSupabase();
      if (driverFromSupabase != null) {
        // Sinhronizuj sa SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_driverKey, driverFromSupabase);
        return driverFromSupabase;
      }
    } catch (e) {
      debugPrint('âš ï¸ [AuthManager] Supabase nedostupan: $e');
    }

    // 3. Fallback na SharedPreferences (offline mod)
    final prefs = await SharedPreferences.getInstance();
    final localDriver = prefs.getString(_driverKey);
    return localDriver;
  }

  /// ðŸ” Dohvati vozaÄa iz Supabase po FCM/HMS tokenu
  static Future<String?> _getDriverFromSupabase() async {
    // Dobij trenutni FCM token
    String? token;

    try {
      token = await FirebaseService.getFCMToken();

      // Ako nema FCM, probaj HMS (Huawei)
      if (token == null || token.isEmpty) {
        try {
          token = await HuaweiPushService().getHMSToken();
        } catch (e) {
          debugPrint('âš ï¸ Error getting HMS token: $e');
        }
      }

      if (token == null || token.isEmpty) {
        debugPrint('âš ï¸ [AuthManager] Nema FCM/HMS tokena');
        return null;
      }

      // Query push_tokens po tokenu - zaÅ¡titi pristup preko globalnog gettera
      try {
        final response = await supabase
            .from('v2_push_tokens')
            .select('user_id')
            .eq('token', token)
            .eq('user_type', 'vozac')
            .maybeSingle();

        if (response != null && response['user_id'] != null) {
          final userId = response['user_id'] as String;
          debugPrint('âœ… [AuthManager] VozaÄ iz Supabase: $userId');
          return userId;
        }
      } catch (supabaseError) {
        // Supabase nije inicijalizovan ili je nedostupan
        debugPrint('âš ï¸ [AuthManager] Supabase greÅ¡ka: $supabaseError');
        return null;
      }

      return null;
    } catch (e) {
      debugPrint('âŒ [AuthManager] GreÅ¡ka pri Äitanju iz Supabase: $e');
      return null;
    }
  }

  /// ðŸ• SESSION VALIDATION

  /// Proveri da li je sesija joÅ¡ aktivna (sveÅ¾a)
  /// VraÄ‡a true ako je korisnik bio autentifikovan u poslednjih 30 minuta
  static Future<bool> isSessionActive() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionTimestamp = prefs.getString(_authSessionKey);

      if (sessionTimestamp == null) {
        debugPrint('ðŸ• [AuthManager] Sesija nije aktivna - nema timestamp');
        return false;
      }

      final sessionTime = DateTime.parse(sessionTimestamp);
      final now = DateTime.now();
      final difference = now.difference(sessionTime);

      final isActive = difference.inMinutes < 30;
      debugPrint(
          'ðŸ• [AuthManager] Sesija: ${difference.inMinutes} min od logina - ${isActive ? "AKTIVNA" : "ISTEKLA"}');

      return isActive;
    } catch (e) {
      debugPrint('ðŸ• [AuthManager] GreÅ¡ka pri proveri sesije: $e');
      return false;
    }
  }

  /// ðŸšª LOGOUT FUNCTIONALITY

  /// Centralizovan logout - briÅ¡e sve session podatke
  static Future<void> logout(BuildContext context) async {
    try {
      debugPrint('ðŸ”„ Starting logout process...');

      final prefs = await SharedPreferences.getInstance();

      // 1. ObriÅ¡i SharedPreferences - SVE session podatke ukljuÄujuÄ‡i zapamÄ‡ene ureÄ‘aje
      await prefs.remove(_driverKey);
      await prefs.remove(_authSessionKey);
      await prefs.remove(_rememberedDevicesKey);
      debugPrint('âœ… SharedPreferences cleared');

      // 2. ObriÅ¡i push tokene iz Supabase baze
      try {
        final currentDriver = await getCurrentDriver();
        if (currentDriver != null) {
          // NaÄ‘i vozac_id za trenutnog vozaÄa
          Vozac? vozac = VozacCache.getVozacByIme(currentDriver);
          if (vozac?.id != null) {
            await V2PushTokenService.clearToken(vozacId: vozac!.id);
            debugPrint('âœ… Push tokens cleared for vozac: $currentDriver');
          }
        }
      } catch (e) {
        debugPrint('âš ï¸ Error clearing push tokens: $e');
      }

      // 3. OÄisti Firebase session (ako postoji)
      try {
        await FirebaseService.clearCurrentDriver();
        debugPrint('âœ… Firebase session cleared');
      } catch (e) {
        debugPrint('âš ï¸ Error clearing Firebase session: $e');
      }

      // 4. Navigiraj na WelcomeScreen sa punim refresh-om (uklanja sve rute)
      // âš ï¸ Koristi globalnu navigatorKey umesto konteksta jer context moÅ¾e biti invalidiran
      debugPrint('ðŸš€ Navigating to WelcomeScreen...');

      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
          (route) => false,
        );
        debugPrint('âœ… Navigation successful');
      } else {
        debugPrint('âš ï¸ NavigatorKey state is null, attempting fallback');
        if (context.mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      debugPrint('âš ï¸ Error during logout: $e');
      // Logout greÅ¡ka - svejedno navigiraj na welcome
      try {
        if (navigatorKey.currentState != null) {
          navigatorKey.currentState!.pushAndRemoveUntil(
            MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
            (route) => false,
          );
        }
      } catch (e2) {
        debugPrint('âš ï¸ Error in logout error handler: $e2');
      }
    }
  }

  /// ðŸ› ï¸ HELPER METHODS

  static Future<void> _saveDriverSession(String driverName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_driverKey, driverName);
    await prefs.setString(_authSessionKey, DateTime.now().toIso8601String());
  }

  /// ðŸ“± DEVICE RECOGNITION

  /// GeneriÅ¡e jedinstveni device ID
  static Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_deviceIdKey);

    if (deviceId == null) {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceId = '${androidInfo.id}_${androidInfo.model}_${androidInfo.brand}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceId = '${iosInfo.identifierForVendor}_${iosInfo.model}';
      } else {
        deviceId = 'unknown_${DateTime.now().millisecondsSinceEpoch}';
      }

      await prefs.setString(_deviceIdKey, deviceId);
    }

    return deviceId;
  }

  /// Zapamti ovaj ureÄ‘aj za automatski login
  static Future<void> rememberDevice(String email, String driverName) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = await _getDeviceId();

    // Format: "deviceId:email:driverName"
    final deviceInfo = '$deviceId:$email:$driverName';

    // SaÄuvaj u listi zapamÄ‡enih ureÄ‘aja
    final rememberedDevices = prefs.getStringList(_rememberedDevicesKey) ?? [];

    // Ukloni stari entry za isti email ako postoji
    rememberedDevices.removeWhere((device) => device.contains(':$email:'));

    // Dodaj novi
    rememberedDevices.add(deviceInfo);

    await prefs.setStringList(_rememberedDevicesKey, rememberedDevices);
  }

  /// Proveri da li je ovaj ureÄ‘aj zapamÄ‡en
  static Future<Map<String, String>?> getRememberedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = await _getDeviceId();
    final rememberedDevices = prefs.getStringList(_rememberedDevicesKey) ?? [];

    for (final deviceInfo in rememberedDevices) {
      final parts = deviceInfo.split(':');
      if (parts.length == 3 && parts[0] == deviceId) {
        return {
          'email': parts[1],
          'driverName': parts[2],
        };
      }
    }

    return null;
  }
}

/// ðŸ“Š AUTH RESULT CLASS
class AuthResult {
  AuthResult.success([this.message = '']) : isSuccess = true;
  AuthResult.error(this.message) : isSuccess = false;
  final bool isSuccess;
  final String message;
}
