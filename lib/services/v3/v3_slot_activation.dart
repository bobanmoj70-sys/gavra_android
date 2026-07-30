import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/v3_belgrade_time.dart';

/// Idempotentan upsert u `v3_trenutna_dodela_slot` sa exponential-backoff
/// retry logikom (500ms, 1000ms, 2000ms).
///
/// Poziva se iz `V3VozacLocationTrackingService.start()` (foreground) i iz
/// background isolate-a (`v3_background_tracking_entry`) kao sigurnosna mreža.
/// `tracking_started_at` se upisuje SAMO pri prvom startu (null → non-null),
/// što okida DB trigger za obaveštavanje putnika.
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
      // Ownership / aktivacija slota — uvek (idempotent upsert).
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

      // Prvi real tracking start: upiši tracking_started_at SAMO ako je još null.
      // DB trigger `trg_v3_notify_passengers_on_tracking_start` okida se na
      // null → non-null. Ne prepisujemo postojeći timestamp (BG re-activate).
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
        log?.call('$logTag ⚠️ activateSlot greška nakon $maxRetries pokušaja: $e (nastavljam bez slota)');
        return;
      }
      final delayMs = initialDelayMs * (1 << (retryCount - 1));
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }
  }
}
