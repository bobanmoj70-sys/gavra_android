import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../globals.dart';
import '../models/v2_vozac.dart';
import '../screens/v2_welcome_screen.dart';
import '../utils/v2_vozac_cache.dart';
import 'realtime/v2_master_realtime_manager.dart';
import 'v2_firebase_service.dart';
import 'v2_huawei_push_service.dart';
import 'v2_push_token_service.dart';

/// Centralizovani auth manager.
/// Upravlja lokalnim auth operacijama kroz SharedPreferences.
/// Koristi push token recognition i session management bez Supabase Auth.
class V2AuthManager {
  static const String _authSessionKey = 'auth_session';
  static const _secureStorage = FlutterSecureStorage();

  // In-memory cache — jedan Supabase poziv po sesiji
  static String? _cachedDriverName;

  /// Sinhron pristup in-memory cache-u — bez async, koristi se za brzi initState
  static String? get cachedDriverName => _cachedDriverName;

  // ── DRIVER SESSION MANAGEMENT ─────────────────────────────────────────────────

  /// Postavi trenutnog vozača (bez email auth-a).
  static Future<void> setCurrentDriver(String driverName) async {
    // Validacija samo ako je cache već inicijalizovan (izbjegava race condition pri startu)
    if (V2VozacCache.isInitialized && !V2VozacCache.isValidIme(driverName)) {
      throw ArgumentError('Vozač "$driverName" nije registrovan');
    }

    _cachedDriverName = driverName;
    await _saveDriverSession(driverName);

    // Ažuriraj push token u pozadini — ne blokira login flow
    unawaited(_updatePushTokenWithUserId(driverName));
  }

  /// Ažurira push token sa vozac_id vozača.
  /// Podržava i FCM (Google) i HMS (Huawei) tokene.
  static Future<void> _updatePushTokenWithUserId(String driverName) async {
    try {
      final V2Vozac? vozac = V2VozacCache.getVozacByIme(driverName);
      final String? vozacId = vozac?.id;

      if (vozacId == null || vozacId.isEmpty || driverName.isEmpty) {
        return;
      }

      // 1. FCM token (Google/Samsung uređaji)
      final fcmToken = await V2FirebaseService.getFCMToken();
      if (fcmToken != null && fcmToken.isNotEmpty) {
        await V2PushTokenService.registerToken(
          token: fcmToken,
          provider: 'fcm',
          vozacId: vozacId,
        );
      }

      // 2. HMS token (Huawei uređaji)
      try {
        final hmsToken = await V2HuaweiPushService().getHMSToken();
        if (hmsToken != null && hmsToken.isNotEmpty) {
          await V2PushTokenService.registerToken(
            token: hmsToken,
            provider: 'huawei',
            vozacId: vozacId,
          );
        }
      } catch (e) {
        debugPrint('[V2AuthManager] _updatePushTokenWithUserId HMS greška: $e');
      }
    } catch (e) {
      debugPrint('[V2AuthManager] _updatePushTokenWithUserId greška: $e');
    }
  }

  /// Dobij trenutnog vozača — in-memory cache, pa Supabase
  static Future<String?> getCurrentDriver() async {
    // 0. In-memory cache — nema Supabase poziva ako već znamo
    if (_cachedDriverName != null && _cachedDriverName!.isNotEmpty) {
      return _cachedDriverName;
    }

    // 1. Pokušaj Supabase (jedini izvor istine)
    try {
      final driverFromSupabase = await _getDriverFromSupabase();
      if (driverFromSupabase != null && driverFromSupabase.isNotEmpty) {
        _cachedDriverName = driverFromSupabase;
        return _cachedDriverName;
      }
    } catch (e) {
      debugPrint('[V2AuthManager] getCurrentDriver Supabase greška: $e');
    }

    return _cachedDriverName;
  }

  /// Dohvati vozača iz Supabase po FCM/HMS tokenu.
  static Future<String?> _getDriverFromSupabase() async {
    String? token;

    try {
      token = await V2FirebaseService.getFCMToken();

      if (token == null || token.isEmpty) {
        try {
          token = await V2HuaweiPushService().getHMSToken();
        } catch (e) {
          debugPrint('[V2AuthManager] _getDriverFromSupabase HMS greška: $e');
        }
      }

      if (token == null || token.isEmpty) return null;

      final tokenRow = await supabase
          .from('v2_push_tokens')
          .select('vozac_id')
          .eq('token', token)
          .not('vozac_id', 'is', null)
          .maybeSingle();

      if (tokenRow != null && tokenRow['vozac_id'] != null) {
        final vozacId = tokenRow['vozac_id'] as String;
        // Čitaj iz cache-a — 0 DB querija
        final ime = V2MasterRealtimeManager.instance.vozaciCache[vozacId]?['ime'] as String?;
        if (ime != null && ime.isNotEmpty) return ime;
        // Fallback: DB upit ako cache nije spreman
        final vozacRow = await supabase.from('v2_vozaci').select('ime').eq('id', vozacId).maybeSingle();
        if (vozacRow != null && vozacRow['ime'] != null) {
          return vozacRow['ime'] as String;
        }
      }
    } catch (e) {
      debugPrint('[V2AuthManager] _getDriverFromSupabase greška: $e');
    }
    return null;
  }

  // ── LOGOUT ─────────────────────────────────────────────────────────────────────

  /// Centralizovan logout — briše sve session podatke.
  static Future<void> logout(BuildContext context) async {
    try {
      // 1. Pročitaj trenutnog vozača iz in-memory cache-a PRE brisanja sesije (potrebno za push token)
      final currentDriver = _cachedDriverName;

      // 2. Obriši in-memory cache i SecureStorage (vozač + putnik sesija)
      _cachedDriverName = null;
      await _secureStorage.delete(key: _authSessionKey);
      await _secureStorage.delete(key: 'registrovani_putnik_id');
      await _secureStorage.delete(key: 'registrovani_putnik_ime');

      // 2b. Obriši biometrijske kredencijale vozača iz SecureStorage
      if (currentDriver != null) {
        unawaited(_secureStorage.delete(key: 'biometric_vozac_$currentDriver'));
      }

      // 3. Obriši push tokene iz Supabase baze
      try {
        if (currentDriver != null) {
          final V2Vozac? vozac = V2VozacCache.getVozacByIme(currentDriver);
          if (vozac?.id != null) {
            await V2PushTokenService.clearToken(vozacId: vozac!.id);
          }
        }
      } catch (e) {
        debugPrint('[V2AuthManager] logout clearToken greška: $e');
      }

      // 5. Navigiraj na V2WelcomeScreen — koristi globalnu navigatorKey
      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const V2WelcomeScreen()),
          (route) => false,
        );
      } else if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const V2WelcomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('[V2AuthManager] logout greška: $e');
      try {
        if (navigatorKey.currentState != null) {
          navigatorKey.currentState!.pushAndRemoveUntil(
            MaterialPageRoute<void>(builder: (_) => const V2WelcomeScreen()),
            (route) => false,
          );
        }
      } catch (e2) {
        debugPrint('[V2AuthManager] logout navigacija greška: $e2');
      }
    }
  }

  // ── REMEMBERED DEVICE ──────────────────────────────────────────────────────────

  static const String _rememberedEmailKey = 'remembered_email';
  static const String _rememberedDriverNameKey = 'remembered_driver_name';
  static const String _rememberedTimestampKey = 'remembered_timestamp';

  /// Zapamti uređaj — snima email, ime vozača i timestamp za auto-login.
  static Future<void> rememberDevice(String email, String driverName) async {
    await _secureStorage.write(key: _rememberedEmailKey, value: email);
    await _secureStorage.write(key: _rememberedDriverNameKey, value: driverName);
    await _secureStorage.write(key: _rememberedTimestampKey, value: DateTime.now().toUtc().toIso8601String());
  }

  /// Vrati zapamćene kredencijale uređaja ili null ako nisu sačuvani ili su stariji od 30 dana.
  static Future<Map<String, String>?> getRememberedDevice() async {
    final email = await _secureStorage.read(key: _rememberedEmailKey);
    final driverName = await _secureStorage.read(key: _rememberedDriverNameKey);
    if (email == null || driverName == null) return null;

    // Provjeri expiry — 30 dana
    final tsStr = await _secureStorage.read(key: _rememberedTimestampKey);
    if (tsStr != null) {
      try {
        final ts = DateTime.parse(tsStr);
        if (DateTime.now().toUtc().difference(ts).inDays >= 30) {
          // Isteklo — obriši i vrati null
          await _secureStorage.delete(key: _rememberedEmailKey);
          await _secureStorage.delete(key: _rememberedDriverNameKey);
          await _secureStorage.delete(key: _rememberedTimestampKey);
          return null;
        }
      } catch (_) {}
    }

    return {'email': email, 'driverName': driverName};
  }

  /// Provjeri da li je sesija aktivna (timestamp unutar 30 dana).
  static Future<bool> isSessionActive() async {
    final sessionStr = await _secureStorage.read(key: _authSessionKey);
    if (sessionStr == null) return false;
    try {
      final sessionTime = DateTime.parse(sessionStr);
      final age = DateTime.now().toUtc().difference(sessionTime);
      return age.inDays < 30;
    } catch (e) {
      return false;
    }
  }

  // ── PRIVATE HELPERS ─────────────────────────────────────────────────────────────

  static Future<void> _saveDriverSession(String driverName) async {
    await _secureStorage.write(key: _authSessionKey, value: DateTime.now().toUtc().toIso8601String());
  }
}

// =============================================================================
// Spojeno iz v2_admin_security_service.dart
// =============================================================================

/// Centralizovani servis za upravljanje admin privilegijama.
class V2AdminSecurityService {
  V2AdminSecurityService._();

  static const Set<String> _adminUsers = {'Bojan'};

  static List<String> get adminUsers => List.unmodifiable(_adminUsers);

  static bool isAdmin(String? driverName) {
    if (driverName == null || driverName.isEmpty) return false;
    return _adminUsers.contains(driverName);
  }

  static Map<String, double> filterPazarByPrivileges(
    String currentDriver,
    Map<String, double> pazarData,
  ) {
    if (currentDriver.isEmpty) return {};
    if (isAdmin(currentDriver)) return Map.from(pazarData);
    return {
      if (pazarData.containsKey(currentDriver)) currentDriver: pazarData[currentDriver]!,
    };
  }

  static List<String> getVisibleDrivers(
    String currentDriver,
    List<String> allDrivers,
  ) {
    if (currentDriver.isEmpty) return [];
    if (isAdmin(currentDriver)) return List.from(allDrivers);
    return allDrivers.where((driver) => driver == currentDriver).toList();
  }
}
