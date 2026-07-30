import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/v3_belgrade_time.dart';
import '../../utils/v3_status_policy.dart';

const Duration v3TrackingMaxDuration = Duration(minutes: 55);

/// Koliko pre polaska kreće auto-start (V3VozacScreen, foreground).
/// Uskladiti sa windowStart u `v3-auto-prepare-termins`.
const Duration v3AutoStartLeadTime = Duration(minutes: 15);

const Duration v3TrackingTickInterval = Duration(seconds: 20);

/// Spoljni timeout jednog tick-a (GPS + ETA). Mora biti > [v3ComputeEtaNetworkTimeout] + GPS.
const Duration v3TrackingTickTimeout = Duration(seconds: 90);

/// Client timeout za `v3-compute-eta` (edge worst-case OSRM ~55s + margina).
const Duration v3ComputeEtaNetworkTimeout = Duration(seconds: 65);

const LocationSettings v3TrackingLocationSettings = LocationSettings(
  accuracy: LocationAccuracy.high,
  timeLimit: Duration(seconds: 12),
);

bool v3TrackingTimedOut(DateTime? startedAt) {
  if (startedAt == null) return false;
  return V3BelgradeTime.now().difference(startedAt) >= v3TrackingMaxDuration;
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

  bool get isActive => !_cancelled;

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

/// Jedan GPS fix + upsert lokacije + `v3-compute-eta`.
/// Koriste ga i foreground servis i background isolate.
Future<({Map<String, int> etaMap, List<String> order, Position position})> v3RunTrackingTick({
  required SupabaseClient client,
  required String vozacId,
  required String grad,
  required String vreme,
  required String datumIso,
  String logTag = '[v3RunTrackingTick]',
  void Function(String message)? log,
}) async {
  final position = await Geolocator.getCurrentPosition(
    locationSettings: v3TrackingLocationSettings,
  );

  await v3UpdateVozacLocation(
    client: client,
    vozacId: vozacId,
    lat: position.latitude,
    lng: position.longitude,
    logTag: logTag,
    log: log,
  );

  final requestBody = <String, dynamic>{
    'vozac_id': vozacId,
    'grad': grad,
    'vreme': vreme,
    if (datumIso.isNotEmpty) 'datum_iso': datumIso,
  };
  log?.call('$logTag computeEta request: $requestBody');

  final response = await client.functions
      .invoke('v3-compute-eta', body: requestBody)
      .timeout(v3ComputeEtaNetworkTimeout);
  log?.call('$logTag computeEta response: ${response.data}');

  final parsed = v3ParseEtaResponse(response.data);
  return (etaMap: parsed.etaMap, order: parsed.order, position: position);
}

Future<void> v3ClearEtaForVozac({
  required SupabaseClient client,
  required String vozacId,
  String logTag = '[v3ClearEtaForVozac]',
}) async {
  final normalized = vozacId.trim();
  if (normalized.isEmpty) return;
  try {
    await client.from('v3_eta_results').delete().eq('vozac_id', normalized);
  } catch (e) {
    debugPrint('$logTag ETA cleanup error: $e');
  }
}

/// `true` samo ako slot postoji i svi putnici u njemu su pokupljeni/otkazani.
Future<bool> v3AllPassengersCompleted({
  required SupabaseClient client,
  required String datumIso,
  required String grad,
  required String vreme,
  String logTag = '[v3AllPassengersCompleted]',
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
    debugPrint('$logTag Greška pri proveri putnika: $e');
    return false;
  }
}

/// GPS uključen + dozvola. Ne traži dozvole (to radi V3RolePermissionService).
Future<bool> v3CheckLocationPrerequisites({
  String logTag = '[v3CheckLocationPrerequisites]',
}) async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    debugPrint('$logTag GPS servis isključen');
    return false;
  }

  final permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.deniedForever || permission == LocationPermission.denied) {
    debugPrint('$logTag Dozvola za lokaciju nije odobrena: $permission');
    return false;
  }

  return true;
}

Future<void> v3UpdateVozacLocation({
  required SupabaseClient client,
  required String? vozacId,
  required double lat,
  required double lng,
  String logTag = '[v3UpdateVozacLocation]',
  void Function(String message)? log,
}) async {
  if (vozacId == null || vozacId.isEmpty) {
    log?.call('$logTag preskačem: nedostaje vozacId');
    return;
  }

  try {
    await client.from('v3_vozac_location').upsert(<String, dynamic>{
      'vozac_id': vozacId,
      'lat': lat,
      'lng': lng,
      'updated_at': V3BelgradeTime.nowIsoUtc(),
    });
    log?.call('$logTag lokacija ažurirana $lat, $lng za vozača $vozacId');
  } catch (e) {
    log?.call('$logTag greška: $e');
  }
}
