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
  required SupabaseClient client,
  required String vozacId,
  required String datumIso,
  required String grad,
  required String vreme,
  String logTag = '[SlotActivation]',
  void Function(String message)? log,
}) async {
  const maxRetries = 3;
  const initialDelayMs = 500;
  var retryCount = 0;

  while (retryCount < maxRetries) {
    try {
      final nowIso = V3BelgradeTime.nowIsoUtc();

      final existing = await client
          .from('v3_trenutna_dodela_slot')
          .select('id, vozac_v3_auth_id, tracking_started_at')
          .eq('datum', datumIso)
          .eq('grad', grad)
          .eq('vreme', vreme)
          .maybeSingle();

      if (existing == null) {
        await client.from('v3_trenutna_dodela_slot').insert(<String, dynamic>{
          'datum': datumIso,
          'grad': grad,
          'vreme': vreme,
          'vozac_v3_auth_id': vozacId,
          'updated_by': vozacId,
          'tracking_started_at': nowIso,
        });
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
        await client.from('v3_trenutna_dodela_slot').update(patch).eq('id', slotId);
      }

      // Jednom po prozoru / dodeli (RPC no-op ako je driver_started_notified_at već set).
      await client.rpc(
        'v3_notify_passengers_driver_started',
        params: <String, dynamic>{
          'p_vozac_id': vozacId,
          'p_datum': datumIso,
          'p_grad': grad,
          'p_vreme': vreme,
        },
      );

      log?.call('$logTag ✅ activateSlot + notify uspešan (attempt ${retryCount + 1})');
      return;
    } catch (e) {
      retryCount++;
      if (retryCount >= maxRetries) {
        log?.call('$logTag ⚠️ activateSlot/notify greška nakon $maxRetries pokušaja: $e');
        return;
      }
      final delayMs = initialDelayMs * (1 << (retryCount - 1));
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }
  }
}
