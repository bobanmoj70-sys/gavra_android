import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/v3_belgrade_time.dart';

/// Aktivacija slota + push putnicima pri stvarnom startu trackinga (main isolate).
///
/// Prozor termina: T-15 .. T+40 (Belgrade). Za taj prozor putnici OVOG vozača
/// dobijaju tačno jedan push ("Vozač je krenuo…") — RPC je idempotentan preko
/// `v3_trenutna_dodela.driver_started_notified_at`.
///
/// Slot (datum,grad,vreme) je zajednički; ne prepisuje se `vozac_v3_auth_id`
/// ako već postoji (multi-driver).
Future<void> activateSlotWithRetry({
  SupabaseClient? client,
  required String vozacId,
  required String datumIso,
  required String grad,
  required String vreme,
  String logTag = '[SlotActivation]',
  void Function(String message)? log,
  Future<Map<String, dynamic>?> Function()? findExistingSlot,
  Future<void> Function(String nowIso)? insertSlot,
  Future<void> Function(String slotId, Map<String, dynamic> patch)? updateSlot,
  Future<dynamic> Function()? notifyDriverStarted,
  Future<void> Function(Duration duration)? sleep,
}) async {
  const maxRetries = 3;
  const initialDelayMs = 500;
  var retryCount = 0;

  Future<Map<String, dynamic>?> loadExistingSlot() {
    if (findExistingSlot != null) {
      return findExistingSlot();
    }
    final localClient = client;
    if (localClient == null) {
      throw StateError('Supabase client is required when findExistingSlot is not provided');
    }
    return localClient
        .from('v3_trenutna_dodela_slot')
        .select('id, vozac_v3_auth_id, tracking_started_at')
        .eq('datum', datumIso)
        .eq('grad', grad)
        .eq('vreme', vreme)
        .maybeSingle();
  }

  Future<void> createSlot(String nowIso) {
    if (insertSlot != null) {
      return insertSlot(nowIso);
    }
    final localClient = client;
    if (localClient == null) {
      throw StateError('Supabase client is required when insertSlot is not provided');
    }
    return localClient.from('v3_trenutna_dodela_slot').insert(<String, dynamic>{
      'datum': datumIso,
      'grad': grad,
      'vreme': vreme,
      'vozac_v3_auth_id': vozacId,
      'updated_by': vozacId,
      'tracking_started_at': nowIso,
    });
  }

  Future<void> patchSlot(String slotId, Map<String, dynamic> patch) {
    if (updateSlot != null) {
      return updateSlot(slotId, patch);
    }
    final localClient = client;
    if (localClient == null) {
      throw StateError('Supabase client is required when updateSlot is not provided');
    }
    return localClient.from('v3_trenutna_dodela_slot').update(patch).eq('id', slotId);
  }

  Future<dynamic> callNotifyRpc() {
    if (notifyDriverStarted != null) {
      return notifyDriverStarted();
    }
    final localClient = client;
    if (localClient == null) {
      throw StateError('Supabase client is required when notifyDriverStarted is not provided');
    }
    return localClient.rpc(
      'v3_notify_passengers_driver_started',
      params: <String, dynamic>{
        'p_vozac_id': vozacId,
        'p_datum': datumIso,
        'p_grad': grad,
        'p_vreme': vreme,
      },
    );
  }

  while (retryCount < maxRetries) {
    try {
      final nowIso = V3BelgradeTime.nowIsoUtc();

      final existing = await loadExistingSlot();

      if (existing == null) {
        await createSlot(nowIso);
      } else {
        final slotId = existing['id']?.toString();
        if (slotId == null || slotId.isEmpty) {
          throw StateError('slot bez id');
        }
        final patch = <String, dynamic>{
          'updated_by': vozacId,
        };
        if (existing['tracking_started_at'] == null) {
          patch['tracking_started_at'] = nowIso;
        }
        await patchSlot(slotId, patch);
      }

      // Jednom po prozoru / dodeli (RPC no-op ako je driver_started_notified_at već set).
      final rpcResponse = await callNotifyRpc();

      if (rpcResponse is Map && rpcResponse['ok'] == false) {
        final reason = (rpcResponse['reason'] ?? 'unknown').toString();
        throw StateError('v3_notify_passengers_driver_started returned ok=false ($reason)');
      }

      log?.call('$logTag ✅ activateSlot + notify uspešan (attempt ${retryCount + 1})');
      return;
    } catch (e) {
      retryCount++;
      if (retryCount >= maxRetries) {
        log?.call('$logTag ⚠️ activateSlot/notify greška nakon $maxRetries pokušaja: $e');
        return;
      }
      final delayMs = initialDelayMs * (1 << (retryCount - 1));
      final pause = sleep ?? (Duration duration) => Future<void>.delayed(duration);
      await pause(Duration(milliseconds: delayMs));
    }
  }
}
