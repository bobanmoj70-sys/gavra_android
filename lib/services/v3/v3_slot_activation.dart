import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/v3_belgrade_time.dart';

/// Idempotentan upsert slota + prvi `tracking_started_at` (null → non-null).
/// Poziva se SAMO iz `V3VozacLocationTrackingService.start()` (main isolate).
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
      await client.from('v3_trenutna_dodela_slot').upsert(
        <String, dynamic>{
          'datum': datumIso,
          'grad': grad,
          'vreme': vreme,
          'vozac_v3_auth_id': vozacId,
          'updated_by': vozacId,
        },
        onConflict: 'datum,grad,vreme',
      );

      // Trigger putnika: samo prvi put (null → non-null).
      await client
          .from('v3_trenutna_dodela_slot')
          .update(<String, dynamic>{
            'tracking_started_at': V3BelgradeTime.nowIsoUtc(),
          })
          .eq('datum', datumIso)
          .eq('grad', grad)
          .eq('vreme', vreme)
          .isFilter('tracking_started_at', null);

      log?.call('$logTag ✅ activateSlot uspešan (attempt ${retryCount + 1})');
      return;
    } catch (e) {
      retryCount++;
      if (retryCount >= maxRetries) {
        log?.call('$logTag ⚠️ activateSlot greška nakon $maxRetries pokušaja: $e');
        return;
      }
      final delayMs = initialDelayMs * (1 << (retryCount - 1));
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }
  }
}
