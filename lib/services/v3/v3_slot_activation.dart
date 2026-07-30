import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Idempotentan upsert u `v3_trenutna_dodela_slot` sa exponential-backoff
/// retry logikom (500ms, 1000ms, 2000ms).
///
/// Koristi je `V3VozacLocationTrackingService.start()` — jedini poziv koji
/// realno pokreće tracking (foreground-only, ručno ili auto-start).
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
          // Upisuje se SAMO ovde (real tracking start, foreground-only).
          // DB trigger `trg_v3_notify_passengers_on_tracking_start` koristi
          // ovo polje kao pouzdan okidač za obaveštavanje putnika — umesto
          // da se putnicima slepo javlja na T-10min iz crona bez obzira da
          // li je tracking stvarno aktivan.
          'tracking_started_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'datum,grad,vreme',
      );
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
