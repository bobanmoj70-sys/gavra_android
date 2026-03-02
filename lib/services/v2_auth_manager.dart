import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../globals.dart';
import '../models/v2_vozac.dart';
import '../screens/v2_welcome_screen.dart';
import '../utils/v2_vozac_cache.dart';
import 'v2_firebase_service.dart';
import 'v2_huawei_push_service.dart';
import 'v2_pin_zahtev_service.dart';
import 'v2_push_token_service.dart';

/// Centralizovani auth manager.
/// Upravlja lokalnim auth operacijama kroz SharedPreferences.
/// Koristi push token recognition i session management bez Supabase Auth.
class AuthManager {
  static const String _driverKey = 'current_driver';
  static const String _authSessionKey = 'auth_session';

  // In-memory cache — jedan Supabase poziv po sesiji
  static String? _cachedDriverName;

  // ── DRIVER SESSION MANAGEMENT ─────────────────────────────────────────────────

  /// Postavi trenutnog vozača (bez email auth-a).
  static Future<void> setCurrentDriver(String driverName) async {
    // Validacija samo ako je cache već inicijalizovan (izbjegava race condition pri startu)
    if (VozacCache.isInitialized && !VozacCache.isValidIme(driverName)) {
      throw ArgumentError('Vozač "$driverName" nije registrovan');
    }

    _cachedDriverName = driverName;
    await _saveDriverSession(driverName);
    await FirebaseService.setCurrentDriver(driverName);

    // Ažuriraj push token u pozadini — ne blokira login flow
    _updatePushTokenWithUserId(driverName);
  }

  /// Ažurira push token sa vozac_id vozača.
  /// Podržava i FCM (Google) i HMS (Huawei) tokene.
  static Future<void> _updatePushTokenWithUserId(String driverName) async {
    try {
      final Vozac? vozac = VozacCache.getVozacByIme(driverName);
      final String? vozacId = vozac?.id;

      if (vozacId == null || vozacId.isEmpty || driverName.isEmpty) {
        debugPrint('[AuthManager] Vozač nije identifikovan — preskačem registraciju tokena');
        return;
      }

      // 1. FCM token (Google/Samsung uređaji)
      final fcmToken = await FirebaseService.getFCMToken();
      if (fcmToken != null && fcmToken.isNotEmpty) {
        debugPrint('[AuthManager] FCM token: ${fcmToken.substring(0, 30)}...');
        final success = await V2PushTokenService.registerToken(
          token: fcmToken,
          provider: 'fcm',
          vozacId: vozacId,
        );
        debugPrint('[AuthManager] FCM registracija: ${success ? "USPEH" : "NEUSPEH"}');
      }

      // 2. HMS token (Huawei uređaji)
      try {
        final hmsToken = await HuaweiPushService().getHMSToken();
        if (hmsToken != null && hmsToken.isNotEmpty) {
          debugPrint('[AuthManager] HMS token: ${hmsToken.substring(0, 10)}...');
          final success = await V2PushTokenService.registerToken(
            token: hmsToken,
            provider: 'huawei',
            vozacId: vozacId,
          );
          debugPrint('[AuthManager] HMS registracija: ${success ? "USPEH" : "NEUSPEH"}');
        }
      } catch (e) {
        debugPrint('[AuthManager] HMS nije dostupan: $e');
      }
    } catch (e) {
      debugPrint('[AuthManager] Greška pri ažuriranju tokena: $e');
    }
  }

  /// Dobij trenutnog vozača — in-memory cache, pa Supabase, pa SharedPreferences
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
        // Spremi u SharedPreferences kao cache za offline fallback
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_driverKey, driverFromSupabase);
        return _cachedDriverName;
      }
    } catch (e) {
      debugPrint('⚠️ [AuthManager] Supabase nedostupan, koristim lokalni cache: $e');
    }

    // 2. Offline fallback — stari lokalni podatak
    final prefs = await SharedPreferences.getInstance();
    final fromPrefs = prefs.getString(_driverKey);
    if (fromPrefs != null && fromPrefs.isNotEmpty) {
      _cachedDriverName = fromPrefs;
    }
    return _cachedDriverName;
  }

  /// Dohvati vozača iz Supabase po FCM/HMS tokenu.
  static Future<String?> _getDriverFromSupabase() async {
    String? token;

    try {
      token = await FirebaseService.getFCMToken();

      if (token == null || token.isEmpty) {
        try {
          token = await HuaweiPushService().getHMSToken();
        } catch (e) {
          debugPrint('[AuthManager] Greška pri čitanju HMS tokena: $e');
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
        final vozacRow = await supabase.from('v2_vozaci').select('ime').eq('id', vozacId).maybeSingle();
        if (vozacRow != null && vozacRow['ime'] != null) {
          return vozacRow['ime'] as String;
        }
      }
    } catch (e) {
      debugPrint('[AuthManager] Greška pri čitanju iz Supabase: $e');
    }
    return null;
  }

  // ── LOGOUT ─────────────────────────────────────────────────────────────────────

  /// Centralizovan logout — briše sve session podatke.
  static Future<void> logout(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Obriši in-memory cache i SharedPreferences
      _cachedDriverName = null;
      await prefs.remove(_driverKey);
      await prefs.remove(_authSessionKey);

      // 2. Obriši push tokene iz Supabase baze
      try {
        final currentDriver = await getCurrentDriver();
        if (currentDriver != null) {
          final Vozac? vozac = VozacCache.getVozacByIme(currentDriver);
          if (vozac?.id != null) {
            await V2PushTokenService.clearToken(vozacId: vozac!.id);
          }
        }
      } catch (e) {
        debugPrint('[AuthManager] Greška pri brisanju push tokena: $e');
      }

      // 3. Očisti Firebase session
      try {
        await FirebaseService.clearCurrentDriver();
      } catch (e) {
        debugPrint('[AuthManager] Greška pri čišćenju Firebase sesije: $e');
      }

      // 4. Očisti PIN zahtevi subscription
      try {
        V2PinZahtevService.dispose();
      } catch (e) {
        debugPrint('[AuthManager] Greška pri dispose PinZahtevService: $e');
      }

      // 5. Navigiraj na WelcomeScreen — koristi globalnu navigatorKey
      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
          (route) => false,
        );
      } else if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('[AuthManager] Greška tokom logout-a: $e');
      try {
        if (navigatorKey.currentState != null) {
          navigatorKey.currentState!.pushAndRemoveUntil(
            MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
            (route) => false,
          );
        }
      } catch (e2) {
        debugPrint('[AuthManager] Greška u logout error handler-u: $e2');
      }
    }
  }

  // ── PRIVATE HELPERS ─────────────────────────────────────────────────────────────

  static Future<void> _saveDriverSession(String driverName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_driverKey, driverName);
    await prefs.setString(_authSessionKey, DateTime.now().toUtc().toIso8601String());
  }
}
