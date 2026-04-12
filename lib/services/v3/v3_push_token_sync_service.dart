import 'dart:async';

import 'package:flutter/foundation.dart';

import 'v3_push_token_provider.dart';
import 'v3_putnik_service.dart';
import 'v3_vozac_service.dart';

class V3PushTokenSyncService {
  V3PushTokenSyncService._();

  static Future<bool> syncCurrentUser({
    String? token,
    String provider = 'hms',
    String reason = 'unspecified',
  }) async {
    final safeToken = (token ?? '').trim();
    if (safeToken.isNotEmpty) {
      return _syncWithToken(safeToken, provider: provider, reason: reason);
    }

    try {
      final tokenResult = await V3PushTokenProvider.getBestToken();
      if (tokenResult == null) {
        debugPrint('[PushSync] Nema dostupnog push tokena (reason=$reason).');
        return false;
      }
      return _syncWithToken(
        tokenResult.token,
        provider: V3PushTokenProvider.providerAsString(tokenResult.provider),
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

  static Future<bool> _syncWithToken(
    String token, {
    required String provider,
    required String reason,
  }) async {
    try {
      final currentVozac = V3VozacService.currentVozac;
      if (currentVozac != null) {
        final updated = await V3VozacService.updatePushTokensOnLogin(
          vozacId: currentVozac.id,
          token: token,
          existingToken1: currentVozac.pushToken,
          existingToken2: currentVozac.pushToken2,
          provider: provider,
        );
        if (updated.isNotEmpty) {
          V3VozacService.currentVozac = V3VozacService.currentVozac?.copyWith(
            pushToken: updated['push_token'] ?? currentVozac.pushToken,
            pushProvider: updated['push_provider'] ?? currentVozac.pushProvider,
            pushToken2: updated['push_token_2'] ?? currentVozac.pushToken2,
            pushProvider2: updated['push_provider_2'] ?? currentVozac.pushProvider2,
          );
        }
        debugPrint('✅ [PushSync] Token sync: v3_auth (vozac) provider=$provider reason=$reason');
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
          provider: provider,
        );
        currentPutnik?.addAll(updated);
        debugPrint('✅ [PushSync] Token sync: v3_auth (putnik) provider=$provider reason=$reason');
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
