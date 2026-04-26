import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class V3VozacLocationTrackingService {
  V3VozacLocationTrackingService._();

  static final V3VozacLocationTrackingService instance = V3VozacLocationTrackingService._();
  static const Duration _interval = Duration(seconds: 30);

  Timer? _timer;
  bool _inFlight = false;
  String _activeVozacId = '';
  String? _resolvedTable;
  Map<String, String>? _resolvedColumns;

  bool get isRunning => _timer != null;

  Future<void> start({required String vozacId}) async {
    final normalizedVozacId = vozacId.trim();
    if (normalizedVozacId.isEmpty) return;

    if (_activeVozacId == normalizedVozacId && _timer != null) return;

    stop();
    _activeVozacId = normalizedVozacId;

    await _sendCurrentLocation();
    _timer = Timer.periodic(_interval, (_) {
      unawaited(_sendCurrentLocation());
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _activeVozacId = '';
    _inFlight = false;
  }

  Future<void> _sendCurrentLocation() async {
    if (_inFlight || _activeVozacId.isEmpty) return;
    _inFlight = true;

    try {
      final hasPermission = await _ensureLocationPermission();
      if (!hasPermission) {
        debugPrint('[V3VozacLocationTrackingService] location permission/service unavailable');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      await _insertLocation(
        vozacId: _activeVozacId,
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] send error: $e');
    } finally {
      _inFlight = false;
    }
  }

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  Future<void> _insertLocation({
    required String vozacId,
    required double latitude,
    required double longitude,
  }) async {
    final supabase = Supabase.instance.client;

    final tableCandidates = <String>[
      (dotenv.maybeGet('VOZAC_LOKACIJE_TABLE') ?? '').trim(),
      'v3_vozac_lokacije',
      'vozac_lokacije',
    ].where((name) => name.isNotEmpty).toList(growable: false);

    final columnCandidates = <Map<String, String>>[
      {
        'vozacId': 'created_by',
        'lat': 'lat',
        'lng': 'lng',
        'at': 'updated_at',
      },
      {
        'vozacId': 'vozac_id',
        'lat': 'latitude',
        'lng': 'longitude',
        'at': 'recorded_at',
      },
      {
        'vozacId': 'vozac_id',
        'lat': 'lat',
        'lng': 'lng',
        'at': 'recorded_at',
      },
      {
        'vozacId': 'vozac_id',
        'lat': 'gps_lat',
        'lng': 'gps_lng',
        'at': 'recorded_at',
      },
      {
        'vozacId': 'driver_id',
        'lat': 'latitude',
        'lng': 'longitude',
        'at': 'recorded_at',
      },
      {
        'vozacId': 'vozac',
        'lat': 'latitude',
        'lng': 'longitude',
        'at': 'recorded_at',
      },
      {
        'vozacId': 'created_by',
        'lat': 'latitude',
        'lng': 'longitude',
        'at': 'recorded_at',
      },
    ];

    final orderedTables = <String>[
      if (_resolvedTable != null) _resolvedTable!,
      ...tableCandidates.where((name) => name != _resolvedTable),
    ];

    final orderedColumns = <Map<String, String>>[
      if (_resolvedColumns != null) _resolvedColumns!,
      ...columnCandidates.where((c) => c != _resolvedColumns),
    ];

    Object? lastError;

    for (final table in orderedTables) {
      for (final cols in orderedColumns) {
        final payload = <String, dynamic>{
          cols['vozacId']!: vozacId,
          cols['lat']!: latitude,
          cols['lng']!: longitude,
          cols['at']!: DateTime.now().toUtc().toIso8601String(),
        };

        try {
          await supabase.from(table).upsert(payload, onConflict: cols['vozacId']);
          _resolvedTable = table;
          _resolvedColumns = cols;
          debugPrint(
            '[V3VozacLocationTrackingService] inserted vozac=$vozacId table=$table lat=$latitude lng=$longitude',
          );
          return;
        } catch (e) {
          lastError = e;
        }
      }
    }

    if (lastError != null) {
      debugPrint('[V3VozacLocationTrackingService] insert failed: $lastError');
    }
  }
}
