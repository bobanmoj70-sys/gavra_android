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
///
/// Sesija se čita iz SharedPreferences na startu isolate-a jer
/// `invoke('startTracking')` može stići PRE nego što se listener registruje
/// (Android servicePipe onda tiho odbaci event → tracking se "prekine" u BG).
@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  V3BelgradeTime.location;

  String? vozacId;
  String? datumIso;
  String? grad;
  String? vreme;
  DateTime? startedAt;
  DateTime? polazakAt;
  V3SelfReschedulingTicker? ticker;
  SupabaseClient? client;

  Future<void> ensureSupabase() async {
    if (client != null) return;
    try {
      if (Supabase.instance.client.auth.currentSession != null) {
        client = Supabase.instance.client;
        return;
      }
    } catch (_) {}
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

  void stopTracking() {
    debugPrint('[BG_TRACKING] stop');
    ticker?.cancel();
    ticker = null;
    vozacId = null;
    datumIso = null;
    grad = null;
    vreme = null;
    startedAt = null;
    polazakAt = null;
  }

  /// Potpuno gasi BG: ticker, GPS tickovi, foreground notifikacija (stopSelf).
  /// Obaveštava main isolate da resetuje `_isRunning` (inače bi na resume
  /// ponovo digao tracking).
  void finishAndStop(String reason) {
    debugPrint('[BG_TRACKING] stop reason=$reason');
    stopTracking();
    unawaited(v3ClearBgTrackingSession());
    try {
      service.invoke('trackingEnded', <String, dynamic>{'reason': reason});
    } catch (e) {
      debugPrint('[BG_TRACKING] trackingEnded invoke greška: $e');
    }
    service.stopSelf();
  }

  Future<void> doTick() async {
    if (vozacId == null || datumIso == null || grad == null || vreme == null) return;

    if (v3TrackingTimedOut(startedAt: startedAt, polazakAt: polazakAt)) {
      finishAndStop('timeout polazak=$polazakAt');
      return;
    }

    await ensureSupabase();
    if (client == null) return;

    try {
      await v3RunTrackingTick(
        client: client!,
        vozacId: vozacId!,
        grad: grad!,
        vreme: vreme!,
        datumIso: datumIso!,
        logTag: '[BG_TRACKING]',
      );

      final allDone = await v3AllPassengersCompleted(
        client: client!,
        datumIso: datumIso!,
        grad: grad!,
        vreme: vreme!,
      );
      if (allDone) {
        finishAndStop('all_passengers_completed');
      }
    } catch (e) {
      debugPrint('[BG_TRACKING] tick greška: $e');
    }
  }

  void startTracking(Map<String, dynamic>? args) {
    final m = args ?? <String, dynamic>{};
    final id = (m['vozac_id']?.toString() ?? '').trim();
    final datum = V3BelgradeTime.parseIsoDatePart(m['datum_iso']?.toString() ?? '');
    final g = (m['grad']?.toString() ?? '').trim().toUpperCase();
    final v = V3BelgradeTime.normalizeToHHmm(m['vreme']?.toString() ?? '');

    if (id.isEmpty || datum.isEmpty || g.isEmpty || v.isEmpty) {
      debugPrint('[BG_TRACKING] start preskočen: nedostaju podaci');
      return;
    }

    vozacId = id;
    datumIso = datum;
    grad = g;
    vreme = v;
    startedAt = V3BelgradeTime.parseTs(m['started_at']?.toString()) ?? V3BelgradeTime.now();
    polazakAt = V3BelgradeTime.parseTs(m['polazak_at']?.toString()) ?? v3PolazakDateTime(datumIso: datum, vreme: v);
    debugPrint('[BG_TRACKING] start $g $v polazak=$polazakAt');

    ticker?.cancel();
    ticker = V3SelfReschedulingTicker(interval: v3TrackingTickInterval, onTick: doTick)..start();
  }

  service.on('startTracking').listen((event) {
    startTracking(event is Map<String, dynamic> ? event : null);
  });
  service.on('stopTracking').listen((_) {
    // Privremeni handoff FG↔BG — ne briši prefs (main stop() briše sesiju).
    stopTracking();
  });
  service.on('stopService').listen((_) {
    stopTracking();
    service.stopSelf();
  });

  // Ako je invoke izgubljen zbog race-a, sesija iz prefs i dalje podiže tickove.
  try {
    final saved = await v3LoadBgTrackingSession();
    if (saved != null) {
      debugPrint('[BG_TRACKING] resume iz prefs');
      startTracking(saved);
    }
  } catch (e) {
    debugPrint('[BG_TRACKING] prefs resume greška: $e');
  }
}
