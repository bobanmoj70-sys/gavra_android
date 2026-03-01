import 'dart:async';
import 'dart:io';

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

/// "CENTRALIZOVANI AUTH MANAGER
/// Upravlja lokalnim auth operacijama kroz SharedPreferences
/// Koristi device recognition i session management bez Supabase Auth
class AuthManager {
  // Unified SharedPreferences key
  static const String _driverKey = 'current_driver';
  static const String _authSessionKey = 'auth_session';
  static const String _deviceIdKey = 'device_id';
  static const String _rememberedDevicesKey = 'remembered_devices';

  /// s- DRIVER SESSION MANAGEMENT

  /// Postavi trenutnog vozača (bez email auth-a)
  static Future<void> setCurrentDriver(String driverName) async {
    // Validacija samo ako je cache već inicijalizovan (izbjegava race condition pri startu)
    if (VozacCache.isInitialized && !VozacCache.isValidIme(driverName)) {
      throw ArgumentError('Vozač "$driverName" nije registrovan');
    }

    await _saveDriverSession(driverName);
    await FirebaseService.setCurrentDriver(driverName);

    // "Ažuriraj push token u pozadini - NE BLOKIRAJ login flow
    _updatePushTokenWithUserId(driverName);
  }

  /// "Ažurira push token sa user_id i vozac_id vozača
  /// Podržava i FCM (Google) i HMS (Huawei) tokene
  static Future<void> _updatePushTokenWithUserId(String driverName) async {
    try {
      debugPrint('"" [AuthManager] Ažuriram token za vozača: $driverName');

      // Dohvati vozac_id direktno iz baze
      Vozac? vozac = VozacCache.getVozacByIme(driverName);
      String? vozacId = vozac?.id;

      // Fallback: Ako VozacCache nema podatke, probaj direktno iz baze
      if (vozacId == null) {
        debugPrint('"" [AuthManager] VozacCache nema podatke, koristim direktno iz baze...');

        // Direktno iz baze
        try {
          vozac = VozacCache.getVozacByIme(driverName);
          vozacId = vozac?.id;
          if (vozacId != null) {
            debugPrint('"" [AuthManager] Vozac_id dobijen direktno: $vozacId');
          }
        } catch (e) {
          debugPrint(' [AuthManager] VozacBoja inicijalizacija neuspešna: $e');
        }

        // Ako i dalje nema podataka, probaj direktno iz baze
        if (vozacId == null) {
          debugPrint('"" [AuthManager] VozacBoja nema podatke, pokušavam fallback iz baze...');
          try {
            final response = await supabase
                .from('v2_vozaci')
                .select('id')
                .eq('ime', driverName)
                .single()
                .timeout(const Duration(seconds: 3));

            vozacId = response['id'] as String?;
            debugPrint('"" [AuthManager] Fallback vozac_id: $vozacId');
          } catch (e) {
            debugPrint(' [AuthManager] Fallback iz baze neuspešan: $e');
          }
        }
      }

      debugPrint('"" [AuthManager] Final vozac_id: $vozacId');

      // Registruj tokene samo ako je vozač uspešno identifikovan
      if (vozacId == null || vozacId.isEmpty || driverName.isEmpty) {
        debugPrint(' [AuthManager] Vozač nije ulogovan ili identifikovan - preskačem registraciju tokena');
        return;
      }

      // 1. Pokušaj FCM token (Google/Samsung ureaji)
      final fcmToken = await FirebaseService.getFCMToken();
      if (fcmToken != null && fcmToken.isNotEmpty) {
        debugPrint('"" [AuthManager] FCM token: ${fcmToken.substring(0, 30)}...');
        final success = await V2PushTokenService.registerToken(
          token: fcmToken,
          provider: 'fcm',
          vozacId: vozacId,
        );
        debugPrint('"" [AuthManager] FCM registracija: ${success ? "USPEH" : "NEUSPEH"}');
      }

      // 2. Pokušaj HMS token (Huawei ureaji)
      // Koristi direktno dobijanje tokena
      try {
        final hmsToken = await HuaweiPushService().getHMSToken();
        if (hmsToken != null && hmsToken.isNotEmpty) {
          debugPrint('"" [AuthManager] HMS token: ${hmsToken.substring(0, 10)}...');
          final success = await V2PushTokenService.registerToken(
            token: hmsToken,
            provider: 'huawei',
            vozacId: vozacId,
          );
          debugPrint('"" [AuthManager] HMS registracija: ${success ? "USPEH" : "NEUSPEH"}');
        } else {
          debugPrint('"" [AuthManager] HMS token nije dostupan (token je null/prazan)');
        }
      } catch (e) {
        // HMS nije dostupan na ovom ureaju - OK
        debugPrint('"" [AuthManager] HMS nije dostupan: $e');
      }
    } catch (e) {
      debugPrint(' [AuthManager] Greška pri ažuriranju tokena: $e');
    }
  }

  /// Dobij trenutnog vozača - PRVO iz SharedPreferences (brzo, bez mreže),
  /// pa Supabase sinhronizacija u pozadini (unawaited)
  static Future<String?> getCurrentDriver() async {
    debugPrint(
        '🔍 [AuthManager] getCurrentDriver POZVAN | stack: ${StackTrace.current.toString().split('\n').take(3).join(' | ')}');

    // 1. Odmah vrati lokalni podatak — nema čekanja na mrežu
    final prefs = await SharedPreferences.getInstance();
    final localDriver = prefs.getString(_driverKey);

    // 2. Supabase sinhronizacija u pozadini — ne blokira UI
    unawaited(_syncDriverFromSupabase(localDriver));

    return localDriver;
  }

  /// Sinhronizuje vozača iz Supabase u pozadini (ne blokira)
  static Future<void> _syncDriverFromSupabase(String? currentLocal) async {
    try {
      final driverFromSupabase = await _getDriverFromSupabase();
      if (driverFromSupabase != null && driverFromSupabase != currentLocal) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_driverKey, driverFromSupabase);
        debugPrint(' [AuthManager] Vozač sinhronizovan iz Supabase: $driverFromSupabase');
      }
    } catch (e) {
      debugPrint(' [AuthManager] Supabase sync neuspešan: $e');
    }
  }

  /// "Dohvati vozača iz Supabase po FCM/HMS tokenu
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
          debugPrint(' Error getting HMS token: $e');
        }
      }

      if (token == null || token.isEmpty) {
        debugPrint(' [AuthManager] Nema FCM/HMS tokena');
        return null;
      }

      // Query push_tokens po tokenu da dobijemo vozac_id
      try {
        final tokenRow = await supabase
            .from('v2_push_tokens')
            .select('vozac_id')
            .eq('token', token)
            .not('vozac_id', 'is', null)
            .maybeSingle();

        if (tokenRow != null && tokenRow['vozac_id'] != null) {
          final vozacId = tokenRow['vozac_id'] as String;
          // Dohvati ime vozača iz v2_vozaci tabele
          final vozacRow = await supabase.from('v2_vozaci').select('ime').eq('id', vozacId).maybeSingle();
          if (vozacRow != null && vozacRow['ime'] != null) {
            final ime = vozacRow['ime'] as String;
            debugPrint(' [AuthManager] Vozač iz Supabase: $ime');
            return ime;
          }
        }
      } catch (supabaseError) {
        // Supabase nije inicijalizovan ili je nedostupan
        debugPrint(' [AuthManager] Supabase greška: $supabaseError');
        return null;
      }

      return null;
    } catch (e) {
      debugPrint(' [AuthManager] Greška pri čitanju iz Supabase: $e');
      return null;
    }
  }

  /// .SESSION VALIDATION

  /// Proveri da li je sesija još aktivna (sveža)
  /// Vraa true ako je korisnik bio autentifikovan u poslednjih 30 minuta
  static Future<bool> isSessionActive() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionTimestamp = prefs.getString(_authSessionKey);

      if (sessionTimestamp == null) {
        debugPrint('.[AuthManager] Sesija nije aktivna - nema timestamp');
        return false;
      }

      final sessionTime = DateTime.parse(sessionTimestamp);
      final now = DateTime.now();
      final difference = now.difference(sessionTime);

      final isActive = difference.inMinutes < 30;
      debugPrint('.[AuthManager] Sesija: ${difference.inMinutes} min od logina - ${isActive ? "AKTIVNA" : "ISTEKLA"}');

      return isActive;
    } catch (e) {
      debugPrint('.[AuthManager] Greška pri proveri sesije: $e');
      return false;
    }
  }

  /// sLOGOUT FUNCTIONALITY

  /// Centralizovan logout - briše sve session podatke
  static Future<void> logout(BuildContext context) async {
    try {
      debugPrint('"" Starting logout process...');

      final prefs = await SharedPreferences.getInstance();

      // 1. Obriši SharedPreferences - SVE session podatke uključujui zapamene ureaje
      await prefs.remove(_driverKey);
      await prefs.remove(_authSessionKey);
      await prefs.remove(_rememberedDevicesKey);
      debugPrint('. SharedPreferences cleared');

      // 2. Obriši push tokene iz Supabase baze
      try {
        final currentDriver = await getCurrentDriver();
        if (currentDriver != null) {
          // Nai vozac_id za trenutnog vozača
          Vozac? vozac = VozacCache.getVozacByIme(currentDriver);
          if (vozac?.id != null) {
            await V2PushTokenService.clearToken(vozacId: vozac!.id);
            debugPrint('. Push tokens cleared for vozac: $currentDriver');
          }
        }
      } catch (e) {
        debugPrint(' Error clearing push tokens: $e');
      }

      // 3. Očisti Firebase session (ako postoji)
      try {
        await FirebaseService.clearCurrentDriver();
        debugPrint('. Firebase session cleared');
      } catch (e) {
        debugPrint(' Error clearing Firebase session: $e');
      }

      // 4. Navigiraj na WelcomeScreen sa punim refresh-om (uklanja sve rute)
      //  Koristi globalnu navigatorKey umesto konteksta jer context može biti invalidiran
      debugPrint('s? Navigating to WelcomeScreen...');

      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
          (route) => false,
        );
        debugPrint('. Navigation successful');
      } else {
        debugPrint(' NavigatorKey state is null, attempting fallback');
        if (context.mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      debugPrint(' Error during logout: $e');
      // Logout greška - svejedno navigiraj na welcome
      try {
        if (navigatorKey.currentState != null) {
          navigatorKey.currentState!.pushAndRemoveUntil(
            MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
            (route) => false,
          );
        }
      } catch (e2) {
        debugPrint(' Error in logout error handler: $e2');
      }
    }
  }

  /// > HELPER METHODS

  static Future<void> _saveDriverSession(String driverName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_driverKey, driverName);
    await prefs.setString(_authSessionKey, DateTime.now().toIso8601String());
  }

  /// "DEVICE RECOGNITION

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

  /// Zapamti ovaj ureaj za automatski login
  static Future<void> rememberDevice(String email, String driverName) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = await _getDeviceId();

    // Format: "deviceId:email:driverName"
    final deviceInfo = '$deviceId:$email:$driverName';

    // Sačuvaj u listi zapamenih ureaja
    final rememberedDevices = prefs.getStringList(_rememberedDevicesKey) ?? [];

    // Ukloni stari entry za isti email ako postoji
    rememberedDevices.removeWhere((device) => device.contains(':$email:'));

    // Dodaj novi
    rememberedDevices.add(deviceInfo);

    await prefs.setStringList(_rememberedDevicesKey, rememberedDevices);
  }

  /// Proveri da li je ovaj ureaj zapamen
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

/// "S AUTH RESULT CLASS
class AuthResult {
  AuthResult.success([this.message = '']) : isSuccess = true;
  AuthResult.error(this.message) : isSuccess = false;
  final bool isSuccess;
  final String message;
}
