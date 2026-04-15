import 'dart:async';

import 'package:flutter/foundation.dart';

import 'v3_os_device_id_service.dart';
import 'v3_push_token_edge_service.dart';
import 'v3_push_token_provider.dart';
import 'v3_putnik_service.dart';
import 'v3_vozac_service.dart';

class V3PushTokenSyncService {
  V3PushTokenSyncService._();

  static Future<bool> syncCurrentUser({
    String? token,
    String reason = 'unspecified',
  }) async {
    final safeToken = (token ?? '').trim();
    if (safeToken.isNotEmpty) {
      return _syncWithToken(safeToken, reason: reason);
    }

    try {
      final tokenResult = await V3PushTokenProvider.getBestToken();
      if (tokenResult == null) {
        debugPrint('[PushSync] Nema dostupnog push tokena (reason=$reason).');
        return false;
      }
      return _syncWithToken(
        tokenResult.token,
        reason: reason,
      );
    } catch (e) {
      debugPrint('[PushSync] provider getToken greška (reason=$reason): $e');
      return false;
    }
  }

  static Future<void> syncCurrentUserWithRetry({
    String reason = 'retry',
    int attempts = 3,
    Duration initialDelay = const Duration(milliseconds: 700),
  }) async {
    final maxAttempts = attempts < 1 ? 1 : attempts;

    for (var index = 0; index < maxAttempts; index++) {
      final synced = await syncCurrentUser(reason: '$reason#${index + 1}');
      if (synced) {
        return;
      }

      if (index < maxAttempts - 1) {
        final factor = index + 1;
        await Future<void>.delayed(initialDelay * factor);
      }
    }
  }

  static Future<bool> clearCurrentUserDeviceTokenOnLogout({
    String reason = 'logout',
  }) async {
    try {
      final osDeviceId = (await V3OsDeviceIdService.getOsDeviceId() ?? '').trim();
      if (osDeviceId.isEmpty) {
        debugPrint('[PushSync] Nema os_device_id za clear (reason=$reason).');
        return false;
      }

      final currentVozac = V3VozacService.currentVozac;
      if (currentVozac != null) {
        await V3PushTokenEdgeService.clearPushTokenByDevice(
          osDeviceId: osDeviceId,
          expectedTip: 'vozac',
          expectedV3AuthId: currentVozac.id,
        );
        debugPrint('✅ [PushSync] Device token cleared: v3_auth (vozac) reason=$reason');
        return true;
      }

      final currentPutnik = V3PutnikService.currentPutnik;
      final putnikId = currentPutnik?['id']?.toString().trim() ?? '';
      if (putnikId.isNotEmpty) {
        await V3PushTokenEdgeService.clearPushTokenByDevice(
          osDeviceId: osDeviceId,
          expectedV3AuthId: putnikId,
        );
        debugPrint('✅ [PushSync] Device token cleared: v3_auth (putnik) reason=$reason');
        return true;
      }

      debugPrint('[PushSync] Nema trenutno ulogovanog korisnika za clear (reason=$reason).');
      return false;
    } catch (e) {
      debugPrint('⚠️ [PushSync] Device clear greška (reason=$reason): $e');
      return false;
    }
  }

  static Future<bool> _syncWithToken(
    String token, {
    required String reason,
  }) async {
    try {
      final osDeviceId = (await V3OsDeviceIdService.getOsDeviceId() ?? '').trim();
      if (osDeviceId.isEmpty) {
        debugPrint('[PushSync] Nema os_device_id za sync (reason=$reason).');
        return false;
      }
      final currentVozac = V3VozacService.currentVozac;
      if (currentVozac != null) {
        final updated = await V3VozacService.updatePushTokensOnLogin(
          vozacId: currentVozac.id,
          token: token,
          existingToken1: currentVozac.pushToken,
          existingToken2: currentVozac.pushToken2,
          osDeviceId: osDeviceId,
        );
        if (updated.isNotEmpty) {
          V3VozacService.currentVozac = V3VozacService.currentVozac?.copyWith(
            pushToken: updated['push_token'] ?? currentVozac.pushToken,
            pushToken2: updated['push_token_2'] ?? currentVozac.pushToken2,
          );
        }
        debugPrint('✅ [PushSync] Token sync: v3_auth (vozac) provider=fcm reason=$reason');
        return true;
      }

      final currentPutnik = V3PutnikService.currentPutnik;
      final putnikId = currentPutnik?['id']?.toString();
      if (putnikId != null && putnikId.isNotEmpty) {
        final token1 = currentPutnik?['push_token']?.toString();
        final token2 = currentPutnik?['push_token_2']?.toString();

        final updated = await V3PutnikService.updatePushTokensOnLogin(
          putnikId: putnikId,
          token: token,
          existingToken1: token1,
          existingToken2: token2,
          osDeviceId: osDeviceId,
        );
        currentPutnik?.addAll(updated);
        debugPrint('✅ [PushSync] Token sync: v3_auth (putnik) provider=fcm reason=$reason');
        return true;
      }

      debugPrint('[PushSync] Nema trenutno ulogovanog korisnika (reason=$reason).');
      return false;
    } catch (e) {
      debugPrint('⚠️ [PushSync] Token sync greška (reason=$reason): $e');
      return false;
    }
  }
}
