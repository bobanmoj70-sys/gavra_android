import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/v3_belgrade_time.dart';
import '../../utils/v3_status_policy.dart';
import '../realtime/v3_master_realtime_manager.dart';

/// Hard stop: polazak + ovoliko (T+40).
/// Primer BC 07:00 → tracking 06:45–07:40.
const Duration v3TrackingMaxDuration = Duration(minutes: 40);

/// Auto-start koliko pre polaska (T-15). Uskladiti sa `v3-auto-prepare-termins`.
const Duration v3AutoStartLeadTime = Duration(minutes: 15);

const Duration v3TrackingTickInterval = Duration(seconds: 20);

/// Spoljni timeout jednog tick-a (GPS + ETA).
const Duration v3TrackingTickTimeout = Duration(seconds: 90);

/// Client timeout za `v3-compute-eta`.
const Duration v3ComputeEtaNetworkTimeout = Duration(seconds: 65);

/// GPS settings za `getCurrentPosition` (tick).
///
/// iOS: Always + `allowBackgroundLocationUpdates` + automotive navigation —
/// inače OS suspenduje app i ETA zastari u pozadini.
/// Android: high accuracy + interval hint za FusedLocation.
LocationSettings get v3TrackingLocationSettings {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return AppleSettings(
      accuracy: LocationAccuracy.high,
      activityType: ActivityType.automotiveNavigation,
      distanceFilter: 0,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
      allowBackgroundLocationUpdates: true,
      timeLimit: const Duration(seconds: 12),
    );
  }
  if (defaultTargetPlatform == TargetPlatform.android) {
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 10),
      timeLimit: const Duration(seconds: 12),
    );
  }
  return const LocationSettings(
    accuracy: LocationAccuracy.high,
    timeLimit: Duration(seconds: 12),
  );
}

/// iOS continuous stream — drži proces živim u pozadini (UIBackgroundModes=location).
/// `distanceFilter` smanjuje wake-upove; tick i dalje ide na 20s tajmeru / throttle.
LocationSettings get v3IosBackgroundStreamSettings {
  return AppleSettings(
    accuracy: LocationAccuracy.high,
    activityType: ActivityType.automotiveNavigation,
    distanceFilter: 25,
    pauseLocationUpdatesAutomatically: false,
    showBackgroundLocationIndicator: true,
    allowBackgroundLocationUpdates: true,
  );
}

/// SharedPreferences ključ — BG isolate čita ovo ako `invoke(startTracking)` stigne pre listener-a.
const String v3BgTrackingSessionPrefsKey = 'v3_bg_tracking_session';

/// Snima aktivnu tracking sesiju da BG FGS može da je podigne bez race-a na invoke.
Future<void> v3SaveBgTrackingSession(Map<String, dynamic> session) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(v3BgTrackingSessionPrefsKey, jsonEncode(session));
  } catch (e) {
    debugPrint('[v3SaveBgTrackingSession] greška: $e');
  }
}

Future<Map<String, dynamic>?> v3LoadBgTrackingSession() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    // BG isolate često vidi stale snapshot dok se ne uradi reload.
    await prefs.reload();
    final raw = prefs.getString(v3BgTrackingSessionPrefsKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (e) {
    debugPrint('[v3LoadBgTrackingSession] greška: $e');
  }
  return null;
}

Future<void> v3ClearBgTrackingSession() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(v3BgTrackingSessionPrefsKey);
  } catch (e) {
    debugPrint('[v3ClearBgTrackingSession] greška: $e');
  }
}

/// Polazak termina u Europe/Belgrade (datum ISO + HH:mm).
DateTime? v3PolazakDateTime({required String datumIso, required String vreme}) {
  final datePart = V3BelgradeTime.parseIsoDatePart(datumIso);
  final parsedDate = V3BelgradeTime.parseDatum(datePart);
  if (parsedDate == null) return null;
  final hhmm = V3BelgradeTime.normalizeToHHmm(vreme);
  final parts = hhmm.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return V3BelgradeTime.dateTime(
    parsedDate.year,
    parsedDate.month,
    parsedDate.day,
    hour,
    minute,
  );
}

/// Hard-stop: raniji od (polazak+40) i (start+15+40).
bool v3TrackingTimedOut({DateTime? startedAt, DateTime? polazakAt}) {
  DateTime? deadline;
  if (polazakAt != null) {
    deadline = polazakAt.add(v3TrackingMaxDuration);
  }
  if (startedAt != null) {
    final fromStart = startedAt.add(v3AutoStartLeadTime + v3TrackingMaxDuration);
    if (deadline == null || fromStart.isBefore(deadline)) deadline = fromStart;
  }
  if (deadline == null) return false;
  return !V3BelgradeTime.now().isBefore(deadline);
}

/// Sam-zakazujući tajmer — fiksni razmak [interval] između početaka tick-ova.
class V3SelfReschedulingTicker {
  V3SelfReschedulingTicker({
    required this.interval,
    required this.onTick,
    this.tickTimeout = v3TrackingTickTimeout,
  });

  final Duration interval;
  final Future<void> Function() onTick;
  final Duration tickTimeout;

  Timer? _timer;
  bool _cancelled = true;
  DateTime? _nextTickAt;

  void start() {
    cancel();
    _cancelled = false;
    _nextTickAt = DateTime.now();
    unawaited(_scheduleNext());
  }

  Future<void> _scheduleNext() async {
    try {
      await onTick().timeout(tickTimeout);
    } catch (e) {
      debugPrint('[V3SelfReschedulingTicker] tick greška/timeout: $e');
    }
    if (_cancelled) return;

    _nextTickAt = _nextTickAt!.add(interval);
    final now = DateTime.now();
    final delay = _nextTickAt!.isAfter(now) ? _nextTickAt!.difference(now) : Duration.zero;
    _timer = Timer(delay, () => unawaited(_scheduleNext()));
  }

  void cancel() {
    _cancelled = true;
    _timer?.cancel();
    _timer = null;
    _nextTickAt = null;
  }
}

/// Parsira odgovor edge funkcije `v3-compute-eta`.
///
/// Jednostavno: ok=true → etaMap (putnik_id → sekunde) + optimized_order.
/// ok=false / prazno → prazan rezultat (pozivalac zadržava prethodni order).
({Map<String, int> etaMap, List<String> order}) v3ParseEtaResponse(dynamic data) {
  final etaMap = <String, int>{};
  final order = <String>[];
  if (data is! Map || data['ok'] != true) {
    return (etaMap: etaMap, order: order);
  }

  final etaList = data['eta_results'];
  if (etaList is List) {
    for (final item in etaList) {
      if (item is! Map) continue;
      final pid = item['putnik_id']?.toString().trim() ?? '';
      final sec = (item['eta_seconds'] as num?)?.toInt();
      if (pid.isNotEmpty && sec != null) {
        etaMap[pid] = sec;
      }
    }
  }

  final optimizedOrder = data['optimized_order'];
  if (optimizedOrder is List) {
    for (final pid in optimizedOrder) {
      final s = pid?.toString().trim() ?? '';
      if (s.isNotEmpty) order.add(s);
    }
  }

  return (etaMap: etaMap, order: order);
}

/// Jedan tick: live GPS fix + upsert `v3_vozac_location` + `v3-compute-eta`.
///
/// Uvek se izvršava u celini — nema distance/speed/idle uslova koji bi
/// preskočili ETA. Trenutna GPS lokacija ide u tabelu i u payload edge funkcije
/// (payload je preferiran izvor da se izbegne race/clock na updated_at).
/// Koriste ga i foreground servis i background isolate.
Future<({Map<String, int> etaMap, List<String> order})> v3RunTrackingTick({
  required SupabaseClient client,
  required String vozacId,
  required String grad,
  required String vreme,
  required String datumIso,
  String logTag = '[v3RunTrackingTick]',
}) async {
  final position = await Geolocator.getCurrentPosition(
    locationSettings: v3TrackingLocationSettings,
  );

  // Mora uspeti pre compute-eta — inače edge bi računao na staroj lokaciji.
  await v3UpdateVozacLocation(
    client: client,
    vozacId: vozacId,
    lat: position.latitude,
    lng: position.longitude,
    // Geolocator: m/s; negativno = invalid.
    speedKmh: position.speed >= 0 ? position.speed * 3.6 : null,
    logTag: logTag,
  );

  // lat/lng u payload-u: edge preferira ovo nad čitanjem tabele (isti tick).
  final requestBody = <String, dynamic>{
    'vozac_id': vozacId,
    'grad': grad,
    'vreme': vreme,
    'lat': position.latitude,
    'lng': position.longitude,
    if (datumIso.isNotEmpty) 'datum_iso': datumIso,
  };
  debugPrint('$logTag computeEta request: $requestBody');

  final response =
      await client.functions.invoke('v3-compute-eta', body: requestBody).timeout(v3ComputeEtaNetworkTimeout);
  debugPrint('$logTag computeEta response status=${response.status} data=${response.data}');

  final parsed = v3ParseEtaResponse(response.data);
  if (parsed.etaMap.isEmpty) {
    final data = response.data;
    final reason = data is Map ? data['reason']?.toString() : null;
    final ok = data is Map ? data['ok'] : null;
    final warning = data is Map ? data['warning']?.toString() : null;
    final fallback = data is Map ? data['fallback'] : null;
    debugPrint('$logTag computeEta empty etaMap ok=$ok reason=$reason warning=$warning fallback=$fallback');
  }
  return parsed;
}

/// `true` samo ako ovaj vozač nema više aktivnih putnika na terminu (pokupljeni/otkazani).
/// Multi-driver: ne čeka tuđe putnike na istom fizičkom slotu.
Future<bool> v3AllPassengersCompleted({
  required SupabaseClient client,
  required String vozacId,
  required String datumIso,
  required String grad,
  required String vreme,
}) async {
  final id = vozacId.trim();
  if (id.isEmpty || datumIso.isEmpty || grad.isEmpty || vreme.isEmpty) return false;

  // Main: cache iz master managera. BG isolate → null → DB fallback.
  try {
    final cached = V3MasterRealtimeManager.instance.tryAllPassengersCompleted(
      datumIso: datumIso,
      grad: grad,
      vreme: vreme,
      vozacId: id,
    );
    if (cached != null) return cached;
  } catch (_) {}

  try {
    // Isto kao edge: datum+grad, pa match HH:mm (DB može biti 07:00 ili 07:00:00).
    final slotRows =
        await client.from('v3_trenutna_dodela_slot').select('id, vreme').eq('datum', datumIso).eq('grad', grad);

    final wantVreme = V3BelgradeTime.normalizeToHHmm(vreme);
    Map<String, dynamic>? activeSlot;
    for (final raw in (slotRows as List<dynamic>? ?? const [])) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      if (V3BelgradeTime.normalizeToHHmm(row['vreme']?.toString()) == wantVreme) {
        activeSlot = row;
        break;
      }
    }
    if (activeSlot == null) return false;

    final dodelaRows = await client
        .from('v3_trenutna_dodela')
        .select('termin_id')
        .eq('slot_id', activeSlot['id'])
        .eq('vozac_v3_auth_id', id);

    final slotTerminIds = (dodelaRows as List<dynamic>?)
        ?.map((r) => (r as Map<String, dynamic>)['termin_id']?.toString())
        .where((tid) => tid != null && tid.isNotEmpty)
        .toSet();

    if (slotTerminIds == null || slotTerminIds.isEmpty) return false;

    final rows = await client
        .from('v3_operativna_nedelja')
        .select('id, pokupljen_at, otkazano_at')
        .inFilter('id', slotTerminIds.toList());

    if (rows.isEmpty) return false;

    for (final row in rows) {
      final pokupljen = V3StatusPolicy.isTimestampSet(row['pokupljen_at']);
      final otkazan = V3StatusPolicy.isTimestampSet(row['otkazano_at']);
      if (!pokupljen && !otkazan) return false;
    }
    return true;
  } catch (e) {
    debugPrint('[v3AllPassengersCompleted] greška: $e');
    return false;
  }
}

/// Rezultat provere GPS + Always dozvole pre starta trackinga.
enum V3LocationPrereqResult {
  ok,
  gpsDisabled,
  denied,
  deniedForever,
  alwaysRequired,
}

/// `ok` samo ako je GPS uključen i dozvola **Always** (Android + iOS).
///
/// WhenInUse nije dovoljno za background ETA.
/// Request UI je isključivo u [V3RolePermissionService] (permission_handler) —
/// ovde samo gate (check), bez drugog request dijaloga.
Future<V3LocationPrereqResult> v3CheckLocationPrerequisites() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    debugPrint('[v3CheckLocationPrerequisites] GPS isključen');
    return V3LocationPrereqResult.gpsDisabled;
  }

  final permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    return V3LocationPrereqResult.denied;
  }
  if (permission == LocationPermission.deniedForever) {
    return V3LocationPrereqResult.deniedForever;
  }
  if (permission != LocationPermission.always) {
    debugPrint('[v3CheckLocationPrerequisites] treba Always, ima: $permission');
    return V3LocationPrereqResult.alwaysRequired;
  }

  return V3LocationPrereqResult.ok;
}

Future<void> v3UpdateVozacLocation({
  required SupabaseClient client,
  required String vozacId,
  required double lat,
  required double lng,
  double? speedKmh,
  String logTag = '[v3UpdateVozacLocation]',
}) async {
  if (vozacId.isEmpty) {
    throw StateError('$logTag empty vozacId');
  }

  final updatedAt = V3BelgradeTime.nowIsoUtc();
  // Zaokruži na 1 decimalu radi čitljivog UI-a; null ostaje null.
  final speed = speedKmh == null ? null : double.parse(speedKmh.clamp(0, 300).toStringAsFixed(1));
  await client.from('v3_vozac_location').upsert(<String, dynamic>{
    'vozac_id': vozacId,
    'lat': lat,
    'lng': lng,
    'speed_kmh': speed,
    'updated_at': updatedAt,
  });
  try {
    V3MasterRealtimeManager.instance.applyLocalVozacLocation(
      vozacId: vozacId,
      lat: lat,
      lng: lng,
      speedKmh: speed,
      updatedAtIso: updatedAt,
    );
  } catch (_) {}
  debugPrint('$logTag lokacija $lat, $lng speed=$speed km/h vozac=$vozacId');
}
