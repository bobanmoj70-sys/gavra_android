import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../globals.dart';
import '../../utils/v3_belgrade_time.dart';
import 'v3_slot_activation.dart';
import 'v3_tracking_config.dart';

/// Background isolate entry point za vozački GPS/ETA tracking.
///
/// Koristi ISTE deljene helper-e kao foreground servis
/// (`v3UpdateVozacLocation`, `v3AllPassengersCompleted`, `v3TrackingTimedOut`,
/// `V3SelfReschedulingTicker`) — nema duplirane poslovne logike.
///
/// Prima parametre preko `service.invoke('startTracking', {...})` i
/// `service.invoke('stopTracking')`. Zaustavlja se sam ako istekne
/// [v3TrackingMaxDuration] ili ako su svi putnici završeni.
@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // Inicijalizuj timezone podatke koji su potrebni za V3BelgradeTime.now().
  V3BelgradeTime.location;

  String? activeVozacId;
  String? activeDatumIso;
  String? activeGrad;
  String? activeVreme;
  DateTime? trackingStartedAt;
  V3SelfReschedulingTicker? ticker;

  SupabaseClient? client;

  Future<void> ensureSupabase() async {
    if (client != null) return;
    if (Supabase.instance.client.auth.currentSession != null) {
      client = Supabase.instance.client;
      return;
    }
    // Background isolate nema inicijalizovan Supabase — inicijalizuj ga
    // iz configService-a.
    try {
      await configService.initializeBasic();
      final url = configService.getSupabaseUrl().trim();
      final anonKey = configService.getSupabaseAnonKey().trim();
      if (url.isEmpty || anonKey.isEmpty) {
        debugPrint('[BG_TRACKING] Nedostaju Supabase kredencijali');
        return;
      }
      await Supabase.initialize(url: url, anonKey: anonKey);
      client = Supabase.instance.client;
    } catch (e) {
      debugPrint('[BG_TRACKING] Supabase init greška: $e');
    }
  }

  Future<void> doTick() async {
    if (activeVozacId == null || activeDatumIso == null || activeGrad == null || activeVreme == null) {
      debugPrint('[BG_TRACKING] tick preskočen: nedostaju podaci');
      return;
    }

    if (v3TrackingTimedOut(trackingStartedAt)) {
      debugPrint('[BG_TRACKING] stop reason=timeout');
      service.stopSelf();
      return;
    }

    await ensureSupabase();
    if (client == null) return;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      await v3UpdateVozacLocation(
        client: client!,
        vozacId: activeVozacId,
        lat: position.latitude,
        lng: position.longitude,
        logTag: '[BG_TRACKING]',
        log: debugPrint,
      );

      final requestBody = <String, dynamic>{
        'vozac_id': activeVozacId,
        'grad': activeGrad,
        'vreme': activeVreme,
        'datum_iso': activeDatumIso,
      };
      debugPrint('[BG_TRACKING] computeEta request: $requestBody');

      final response =
          await client!.functions.invoke('v3-compute-eta', body: requestBody).timeout(v3ComputeEtaNetworkTimeout);
      debugPrint('[BG_TRACKING] computeEta response: ${response.data}');

      final data = response.data;
      if (data is Map && data['ok'] == true) {
        final etaList = data['eta_results'];
        final order = data['optimized_order'];
        service.invoke(
          'etaUpdated',
          <String, dynamic>{
            'vozac_id': activeVozacId,
            'eta_results': etaList,
            'optimized_order': order,
          },
        );
      }

      final allDone = await v3AllPassengersCompleted(
        client: client!,
        datumIso: activeDatumIso!,
        grad: activeGrad!,
        vreme: activeVreme!,
        logTag: '[BG_TRACKING]',
      );
      if (allDone) {
        debugPrint('[BG_TRACKING] stop reason=all_passengers_completed');
        service.stopSelf();
      }
    } catch (e) {
      debugPrint('[BG_TRACKING] tick greška: $e');
    }
  }

  void startTracking(Map<String, dynamic>? args) {
    final argsMap = args ?? <String, dynamic>{};
    final vozacId = (argsMap['vozac_id']?.toString() ?? '').trim();
    final datumIso = V3BelgradeTime.parseIsoDatePart(argsMap['datum_iso']?.toString() ?? '');
    final grad = (argsMap['grad']?.toString() ?? '').trim().toUpperCase();
    final vreme = V3BelgradeTime.normalizeToHHmm(argsMap['vreme']?.toString() ?? '');

    if (vozacId.isEmpty || datumIso.isEmpty || grad.isEmpty || vreme.isEmpty) {
      debugPrint('[BG_TRACKING] start preskočen: nedostaju podaci $argsMap');
      return;
    }

    activeVozacId = vozacId;
    activeDatumIso = datumIso;
    activeGrad = grad;
    activeVreme = vreme;
    trackingStartedAt = V3BelgradeTime.now();
    debugPrint('[BG_TRACKING] start vozac=$activeVozacId termin=$activeGrad $activeVreme');

    // Aktiviraj slot i u pozadini (idempotentno).
    unawaited(ensureSupabase().then((_) {
      if (client == null) return;
      unawaited(activateSlotWithRetry(
        client: client!,
        vozacId: vozacId,
        datumIso: datumIso,
        grad: grad,
        vreme: vreme,
        logTag: '[BG_TRACKING]',
        log: debugPrint,
      ));
    }));

    ticker?.cancel();
    ticker = V3SelfReschedulingTicker(interval: v3TrackingTickInterval, onTick: doTick)..start();
  }

  void stopTracking() {
    debugPrint('[BG_TRACKING] stop');
    ticker?.cancel();
    ticker = null;
    activeVozacId = null;
    activeDatumIso = null;
    activeGrad = null;
    activeVreme = null;
    trackingStartedAt = null;
  }

  service.on('startTracking').listen((event) {
    startTracking(event is Map<String, dynamic> ? event : null);
  });

  service.on('stopTracking').listen((_) {
    stopTracking();
  });

  // Ako servis dobije stopSelf iz native strane, zaustavi ticker.
  service.on('stopService').listen((_) {
    stopTracking();
    service.stopSelf();
  });
}
