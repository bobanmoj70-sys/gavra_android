import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Idempotentan upsert u `v3_trenutna_dodela_slot` sa exponential-backoff
/// retry logikom (500ms, 1000ms, 2000ms).
///
/// JEDINA implementacija ove logike u celoj aplikaciji — koriste je i main
/// isolate (`V3VozacLocationTrackingService.start`) i Android background
/// isolate (`v3_background_location_handler.dart`). Ranije su postojale dve
/// odvojene, međusobno duplirane verzije; ovo ih zamenjuje jednim izvorom
/// istine za "aktiviraj slot" operaciju, bez obzira odakle se poziva.
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
