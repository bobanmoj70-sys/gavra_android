import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../globals.dart';
import '../../utils/v3_belgrade_time.dart';
import 'v3_tracking_config.dart';

/// Background isolate — isti [v3RunTrackingTick] kao foreground.
/// Ne aktivira slot (to radi samo main `start()`).
@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
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
    try {
      if (Supabase.instance.client.auth.currentSession != null) {
        client = Supabase.instance.client;
        return;
      }
    } catch (_) {
      // isolate bez inicijalizovanog Supabase-a
    }
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
      await v3RunTrackingTick(
        client: client!,
        vozacId: activeVozacId!,
        grad: activeGrad!,
        vreme: activeVreme!,
        datumIso: activeDatumIso!,
        logTag: '[BG_TRACKING]',
        log: debugPrint,
      );

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
    final m = args ?? <String, dynamic>{};
    final vozacId = (m['vozac_id']?.toString() ?? '').trim();
    final datumIso = V3BelgradeTime.parseIsoDatePart(m['datum_iso']?.toString() ?? '');
    final grad = (m['grad']?.toString() ?? '').trim().toUpperCase();
    final vreme = V3BelgradeTime.normalizeToHHmm(m['vreme']?.toString() ?? '');

    if (vozacId.isEmpty || datumIso.isEmpty || grad.isEmpty || vreme.isEmpty) {
      debugPrint('[BG_TRACKING] start preskočen: nedostaju podaci');
      return;
    }

    activeVozacId = vozacId;
    activeDatumIso = datumIso;
    activeGrad = grad;
    activeVreme = vreme;
    trackingStartedAt = V3BelgradeTime.parseTs(m['started_at']?.toString()) ?? V3BelgradeTime.now();
    debugPrint('[BG_TRACKING] start $grad $vreme');

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
  service.on('stopTracking').listen((_) => stopTracking());
  service.on('stopService').listen((_) {
    stopTracking();
    service.stopSelf();
  });
}
