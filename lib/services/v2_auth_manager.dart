?import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../globals.dart';
import '../models/v2_vozac.dart';
import '../screens/v2_welcome_screen.dart';
import '../utils/v2_vozac_cache.dart';
import 'v2_firebase_service.dart';
import 'v2_huawei_push_service.dart';
import 'v2_push_token_service.dart';

/// �Y"� CENTRALIZOVANI AUTH MANAGER
/// Upravlja lokalnim auth operacijama kroz SharedPreferences
/// Koristi device recognition i session management bez Supabase Auth
class AuthManager {
  // Unified SharedPreferences key
  static const String _driverKey = 'current_driver';
  static const String _authSessionKey = 'auth_session';
  static const String _deviceIdKey = 'device_id';
  static const String _rememberedDevicesKey = 'remembered_devices';

  /// �Ys- DRIVER SESSION MANAGEMENT

  /// Postavi trenutnog vozača (bez email auth-a)
  static Future<void> setCurrentDriver(String driverName) async {
    // Validacija da je vozač prepoznat
    if (!(VozacCache.isValidIme(driverName))) {
      throw ArgumentError('Vozač "$driverName" nije registrovan');
    }

    await _saveDriverSession(driverName);
    await FirebaseService.setCurrentDriver(driverName);

    // �Y"� Ažuriraj push token u pozadini - NE BLOKIRAJ login flow
    _updatePushTokenWithUserId(driverName);
  }

  /// �Y"� Ažurira push token sa user_id i vozac_id vozača
  /// Podržava i FCM (Google) i HMS (Huawei) tokene
  static Future<void> _updatePushTokenWithUserId(String driverName) async {
    try {
      debugPrint('�Y"" [AuthManager] Ažuriram token za vozača: $driverName');

      // Dohvati vozac_id direktno iz baze
      Vozac? vozac = VozacCache.getVozacByIme(driverName);
      String? vozacId = vozac?.id;

      // Fallback: Ako VozacCache nema podatke, probaj direktno iz baze
      if (vozacId == null) {
        debugPrint('�Y"" [AuthManager] VozacCache nema podatke, koristim direktno iz baze...');

        // Direktno iz baze
        try {
          vozac = VozacCache.getVozacByIme(driverName);
          vozacId = vozac?.id;
          if (vozacId != null) {
            debugPrint('�Y"" [AuthManager] Vozac_id dobijen direktno: $vozacId');
          }
        } catch (e) {
          debugPrint('�s�️ [AuthManager] VozacBoja inicijalizacija neuspešna: $e');
        }

        // Ako i dalje nema podataka, probaj direktno iz baze
        if (vozacId == null) {
          debugPrint('�Y"" [AuthManager] VozacBoja nema podatke, pokušavam fallback iz baze...');
          try {
            final response = await supabase
                .from('v2_vozaci')
                .select('id')
                .eq('ime', driverName)
                .single()
                .timeout(const Duration(seconds: 3));

            vozacId = response['id'] as String?;
            debugPrint('�Y"" [AuthManager] Fallback vozac_id: $vozacId');
          } catch (e) {
            debugPrint('�s�️ [AuthManager] Fallback iz baze neuspešan: $e');
          }
        }
      }

      debugPrint('�Y"" [AuthManager] Final vozac_id: $vozacId');

      // Registruj tokene samo ako je vozač uspešno identifikovan
      if (vozacId == null || vozacId.isEmpty || driverName.isEmpty) {
        debugPrint('�s�️ [AuthManager] Vozač nije ulogovan ili identifikovan - preskačem registraciju tokena');
        return;
      }

      // 1. Pokušaj FCM token (Google/Samsung ure�'aji)
      final fcmToken = await FirebaseService.getFCMToken();
      if (fcmToken != null && fcmToken.isNotEmpty) {
        debugPrint('�Y"" [AuthManager] FCM token: ${fcmToken.substring(0, 30)}...');
        final success = await V2PushTokenService.registerToken(
          token: fcmToken,
          provider: 'fcm',
          vozacId: vozacId,
        );
        debugPrint('�Y"" [AuthManager] FCM registracija: ${success ? "USPEH" : "NEUSPEH"}');
      }

      // 2. Pokušaj HMS token (Huawei ure�'aji)
      // Koristi direktno dobijanje tokena
      try {
        final hmsToken = await HuaweiPushService().getHMSToken();
        if (hmsToken != null && hmsToken.isNotEmpty) {
          debugPrint('�Y"" [AuthManager] HMS token: ${hmsToken.substring(0, 10)}...');
          final success = await V2PushTokenService.registerToken(
            token: hmsToken,
            provider: 'huawei',
            vozacId: vozacId,
          );
          debugPrint('�Y"" [AuthManager] HMS registracija: ${success ? "USPEH" : "NEUSPEH"}');
        } else {
          debugPrint('�Y"" [AuthManager] HMS token nije dostupan (token je null/prazan)');
        }
      } catch (e) {
        // HMS nije dostupan na ovom ure�'aju - OK
        debugPrint('�Y"" [AuthManager] HMS nije dostupan: $e');
      }
    } catch (e) {
      debugPrint('�O [AuthManager] Greška pri ažuriranju tokena: $e');
    }
  }

  /// Dobij trenutnog vozača - �OITA IZ SUPABASE po FCM/HMS tokenu
  /// Fallback na SharedPreferences ako nema interneta
  static Future<String?> getCurrentDriver() async {
    // 2. Pokušaj iz Supabase
    try {
      final driverFromSupabase = await _getDriverFromSupabase();
      if (driverFromSupabase != null) {
        // Sinhronizuj sa SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_driverKey, driverFromSupabase);
        return driverFromSupabase;
      }
    } catch (e) {
      debugPrint('�s�️ [AuthManager] Supabase nedostupan: $e');
    }

    // 3. Fallback na SharedPreferences (offline mod)
    final prefs = await SharedPreferences.getInstance();
    final localDriver = prefs.getString(_driverKey);
    return localDriver;
  }

  /// �Y"� Dohvati vozača iz Supabase po FCM/HMS tokenu
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
          debugPrint('�s�️ Error getting HMS token: $e');
        }
      }

      if (token == null || token.isEmpty) {
        debugPrint('�s�️ [AuthManager] Nema FCM/HMS tokena');
        return null;
      }

      // Query push_tokens po tokenu - zaštiti pristup preko globalnog gettera
      try {
        final response = await supabase
            .from('v2_push_tokens')
            .select('user_id')
            .eq('token', token)
            .eq('user_type', 'vozac')
            .maybeSingle();

        if (response != null && response['user_id'] != null) {
          final userId = response['user_id'] as String;
          debugPrint('�o. [AuthManager] Vozač iz Supabase: $userId');
          return userId;
        }
      } catch (supabaseError) {
        // Supabase nije inicijalizovan ili je nedostupan
        debugPrint('�s�️ [AuthManager] Supabase greška: $supabaseError');
        return null;
      }

      return null;
    } catch (e) {
      debugPrint('�O [AuthManager] Greška pri čitanju iz Supabase: $e');
      return null;
    }
  }

  /// �Y.� SESSION VALIDATION

  /// Proveri da li je sesija još aktivna (sveža)
  /// Vra�?a true ako je korisnik bio autentifikovan u poslednjih 30 minuta
  static Future<bool> isSessionActive() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionTimestamp = prefs.getString(_authSessionKey);

      if (sessionTimestamp == null) {
        debugPrint('�Y.� [AuthManager] Sesija nije aktivna - nema timestamp');
        return false;
      }

      final sessionTime = DateTime.parse(sessionTimestamp);
      final now = DateTime.now();
      final difference = now.difference(sessionTime);

      final isActive = difference.inMinutes < 30;
      debugPrint(
          '�Y.� [AuthManager] Sesija: ${difference.inMinutes} min od logina - ${isActive ? "AKTIVNA" : "ISTEKLA"}');

      return isActive;
    } catch (e) {
      debugPrint('�Y.� [AuthManager] Greška pri proveri sesije: $e');
      return false;
    }
  }

  /// �Ys� LOGOUT FUNCTIONALITY

  /// Centralizovan logout - briše sve session podatke
  static Future<void> logout(BuildContext context) async {
    try {
      debugPrint('�Y"" Starting logout process...');

      final prefs = await SharedPreferences.getInstance();

      // 1. Obriši SharedPreferences - SVE session podatke uključuju�?i zapam�?ene ure�'aje
      await prefs.remove(_driverKey);
      await prefs.remove(_authSessionKey);
      await prefs.remove(_rememberedDevicesKey);
      debugPrint('�o. SharedPreferences cleared');

      // 2. Obriši push tokene iz Supabase baze
      try {
        final currentDriver = await getCurrentDriver();
        if (currentDriver != null) {
          // Na�'i vozac_id za trenutnog vozača
          Vozac? vozac = VozacCache.getVozacByIme(currentDriver);
          if (vozac?.id != null) {
            await V2PushTokenService.clearToken(vozacId: vozac!.id);
            debugPrint('�o. Push tokens cleared for vozac: $currentDriver');
          }
        }
      } catch (e) {
        debugPrint('�s�️ Error clearing push tokens: $e');
      }

      // 3. Očisti Firebase session (ako postoji)
      try {
        await FirebaseService.clearCurrentDriver();
        debugPrint('�o. Firebase session cleared');
      } catch (e) {
        debugPrint('�s�️ Error clearing Firebase session: $e');
      }

      // 4. Navigiraj na WelcomeScreen sa punim refresh-om (uklanja sve rute)
      // �s�️ Koristi globalnu navigatorKey umesto konteksta jer context može biti invalidiran
      debugPrint('�Ys? Navigating to WelcomeScreen...');

      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
          (route) => false,
        );
        debugPrint('�o. Navigation successful');
      } else {
        debugPrint('�s�️ NavigatorKey state is null, attempting fallback');
        if (context.mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      debugPrint('�s�️ Error during logout: $e');
      // Logout greška - svejedno navigiraj na welcome
      try {
        if (navigatorKey.currentState != null) {
          navigatorKey.currentState!.pushAndRemoveUntil(
            MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
            (route) => false,
          );
        }
      } catch (e2) {
        debugPrint('�s�️ Error in logout error handler: $e2');
      }
    }
  }

  /// �Y>�️ HELPER METHODS

  static Future<void> _saveDriverSession(String driverName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_driverKey, driverName);
    await prefs.setString(_authSessionKey, DateTime.now().toIso8601String());
  }

  /// �Y"� DEVICE RECOGNITION

  /// Generiše jedinstveni device ID
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

  /// Zapamti ovaj ure�'aj za automatski login
  static Future<void> rememberDevice(String email, String driverName) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = await _getDeviceId();

    // Format: "deviceId:email:driverName"
    final deviceInfo = '$deviceId:$email:$driverName';

    // Sačuvaj u listi zapam�?enih ure�'aja
    final rememberedDevices = prefs.getStringList(_rememberedDevicesKey) ?? [];

    // Ukloni stari entry za isti email ako postoji
    rememberedDevices.removeWhere((device) => device.contains(':$email:'));

    // Dodaj novi
    rememberedDevices.add(deviceInfo);

    await prefs.setStringList(_rememberedDevicesKey, rememberedDevices);
  }

  /// Proveri da li je ovaj ure�'aj zapam�?en
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

/// �Y"S AUTH RESULT CLASS
class AuthResult {
  AuthResult.success([this.message = '']) : isSuccess = true;
  AuthResult.error(this.message) : isSuccess = false;
  final bool isSuccess;
  final String message;
}
