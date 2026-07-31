import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/v3_belgrade_time.dart';
import '../../utils/v3_status_policy.dart';

/// Hard stop: polazak + ovoliko (T+55).
const Duration v3TrackingMaxDuration = Duration(minutes: 55);

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

/// Hard-stop: raniji od (polazak+55) i (start+15+55).
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
      final pid = item['putnik_id']?.toString();
      final sec = (item['eta_seconds'] as num?)?.toInt();
      if (pid != null && pid.isNotEmpty && sec != null) {
        etaMap[pid] = sec;
      }
    }
  }

  final optimizedOrder = data['optimized_order'];
  if (optimizedOrder is List) {
    for (final pid in optimizedOrder) {
      if (pid is String && pid.isNotEmpty) order.add(pid);
    }
  }

  return (etaMap: etaMap, order: order);
}

/// Jedan tick: live GPS fix + upsert `v3_vozac_location` + `v3-compute-eta`.
///
/// Uvek se izvršava u celini — nema distance/speed/idle uslova koji bi
/// preskočili ETA. Trenutna GPS lokacija je jedini ulaz za optimizaciju;
/// edge funkcija čita isključivo iz `v3_vozac_location` (ne iz payload lat/lng).
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
    logTag: logTag,
  );

  // Lokacija ide u v3_vozac_location; edge ne prima lat/lng — čita iz tabele.
  final requestBody = <String, dynamic>{
    'vozac_id': vozacId,
    'grad': grad,
    'vreme': vreme,
    if (datumIso.isNotEmpty) 'datum_iso': datumIso,
  };
  debugPrint('$logTag computeEta request: $requestBody');

  final response =
      await client.functions.invoke('v3-compute-eta', body: requestBody).timeout(v3ComputeEtaNetworkTimeout);
  debugPrint('$logTag computeEta response: ${response.data}');

  return v3ParseEtaResponse(response.data);
}

Future<void> v3ClearEtaForVozac({
  required SupabaseClient client,
  required String vozacId,
}) async {
  final normalized = vozacId.trim();
  if (normalized.isEmpty) return;
  try {
    await client.from('v3_eta_results').delete().eq('vozac_id', normalized);
  } catch (e) {
    debugPrint('[v3ClearEtaForVozac] error: $e');
  }
}

/// `true` samo ako slot postoji i svi putnici u njemu su pokupljeni/otkazani.
Future<bool> v3AllPassengersCompleted({
  required SupabaseClient client,
  required String datumIso,
  required String grad,
  required String vreme,
}) async {
  if (datumIso.isEmpty || grad.isEmpty || vreme.isEmpty) return false;

  try {
    final slotRows = await client
        .from('v3_trenutna_dodela_slot')
        .select('id')
        .eq('datum', datumIso)
        .eq('grad', grad)
        .eq('vreme', vreme);

    final activeSlot = (slotRows as List<dynamic>?)?.firstOrNull as Map<String, dynamic>?;
    if (activeSlot == null) return false;

    final dodelaRows = await client.from('v3_trenutna_dodela').select('termin_id').eq('slot_id', activeSlot['id']);

    final slotTerminIds = (dodelaRows as List<dynamic>?)
        ?.map((r) => (r as Map<String, dynamic>)['termin_id']?.toString())
        .where((id) => id != null && id.isNotEmpty)
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

/// GPS uključen + **Always** dozvola.
///
/// WhenInUse nije dovoljno: Android FGS location i iOS background location
/// zahtevaju Always da bi ETA tickovi nastavili dok je app u pozadini.
/// Dozvole se traže pri login-u (`V3RolePermissionService`); ovde samo gate.
/// Ako je status whileInUse, jednom pokušavamo upgrade na Always.
Future<bool> v3CheckLocationPrerequisites() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    debugPrint('[v3CheckLocationPrerequisites] GPS isključen');
    return false;
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
    debugPrint('[v3CheckLocationPrerequisites] dozvola: $permission');
    return false;
  }

  // whileInUse → pokušaj Always (iOS upgrade dijalog / Android background).
  if (permission == LocationPermission.whileInUse) {
    debugPrint('[v3CheckLocationPrerequisites] whileInUse — tražim Always');
    permission = await Geolocator.requestPermission();
  }

  if (permission != LocationPermission.always) {
    debugPrint('[v3CheckLocationPrerequisites] treba Always, trenutno: $permission');
    return false;
  }

  return true;
}

Future<void> v3UpdateVozacLocation({
  required SupabaseClient client,
  required String vozacId,
  required double lat,
  required double lng,
  String logTag = '[v3UpdateVozacLocation]',
}) async {
  if (vozacId.isEmpty) {
    throw StateError('$logTag empty vozacId');
  }

  await client.from('v3_vozac_location').upsert(<String, dynamic>{
    'vozac_id': vozacId,
    'lat': lat,
    'lng': lng,
    'updated_at': V3BelgradeTime.nowIsoUtc(),
  });
  debugPrint('$logTag lokacija $lat, $lng vozac=$vozacId');
}
