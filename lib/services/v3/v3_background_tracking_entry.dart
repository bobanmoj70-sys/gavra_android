import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../globals.dart';
import '../../utils/v3_belgrade_time.dart';
import 'v3_tracking_config.dart';

/// Android FGS isolate — isti [v3RunTrackingTick] kao main.
/// Ne aktivira slot (to radi samo main `start()`).
///
/// Sesija se čita iz SharedPreferences na startu isolate-a jer
/// `invoke('startTracking')` može stići pre listenera.
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
  var ticksPaused = false;

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

  void pauseTicks() {
    ticksPaused = true;
    ticker?.cancel();
    ticker = null;
    debugPrint('[BG_TRACKING] pauseTicks');
  }

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
        vozacId: vozacId!,
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

    ticksPaused = false;
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
  service.on('pauseTicks').listen((_) {
    pauseTicks();
  });
  service.on('stopService').listen((_) {
    stopTracking();
    service.stopSelf();
  });

  try {
    final saved = await v3LoadBgTrackingSession();
    if (saved != null && saved['ticks_paused'] != true) {
      debugPrint('[BG_TRACKING] resume iz prefs');
      startTracking(saved);
    } else if (saved != null) {
      ticksPaused = true;
      debugPrint('[BG_TRACKING] FGS živ, ticker pauziran');
    }
  } catch (e) {
    debugPrint('[BG_TRACKING] prefs resume greška: $e');
  }
}

/// iOS BG fetch mreža — jedan tick iz sesije.
/// Primarni put je main ticker + location keep-alive.
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  V3BelgradeTime.location;

  try {
    final saved = await v3LoadBgTrackingSession();
    if (saved == null) return true;

    final id = (saved['vozac_id']?.toString() ?? '').trim();
    final datum = V3BelgradeTime.parseIsoDatePart(saved['datum_iso']?.toString() ?? '');
    final g = (saved['grad']?.toString() ?? '').trim().toUpperCase();
    final v = V3BelgradeTime.normalizeToHHmm(saved['vreme']?.toString() ?? '');
    if (id.isEmpty || datum.isEmpty || g.isEmpty || v.isEmpty) return true;

    final startedAt = V3BelgradeTime.parseTs(saved['started_at']?.toString());
    final polazakAt =
        V3BelgradeTime.parseTs(saved['polazak_at']?.toString()) ?? v3PolazakDateTime(datumIso: datum, vreme: v);

    Future<void> end(String reason) async {
      debugPrint('[BG_TRACKING_IOS] stop reason=$reason');
      await v3ClearBgTrackingSession();
      try {
        service.invoke('trackingEnded', <String, dynamic>{'reason': reason});
      } catch (e) {
        debugPrint('[BG_TRACKING_IOS] trackingEnded invoke greška: $e');
      }
    }

    if (v3TrackingTimedOut(startedAt: startedAt, polazakAt: polazakAt)) {
      await end('timeout');
      return true;
    }

    SupabaseClient? client;
    try {
      client = Supabase.instance.client;
    } catch (_) {
      client = null;
    }
    if (client == null) {
      await configService.initializeBasic();
      final url = configService.getSupabaseUrl().trim();
      final anonKey = configService.getSupabaseAnonKey().trim();
      if (url.isEmpty || anonKey.isEmpty) return true;
      await Supabase.initialize(url: url, anonKey: anonKey);
      client = Supabase.instance.client;
    }

    await v3RunTrackingTick(
      client: client,
      vozacId: id,
      grad: g,
      vreme: v,
      datumIso: datum,
      logTag: '[BG_TRACKING_IOS]',
    ).timeout(const Duration(seconds: 25));

    final allDone = await v3AllPassengersCompleted(
      client: client,
      vozacId: id,
      datumIso: datum,
      grad: g,
      vreme: v,
    ).timeout(const Duration(seconds: 10), onTimeout: () => false);

    if (allDone) {
      await end('all_passengers_completed');
    } else {
      debugPrint('[BG_TRACKING_IOS] jedan background tick OK');
    }
  } catch (e) {
    debugPrint('[BG_TRACKING_IOS] background tick greška: $e');
  }
  return true;
}
