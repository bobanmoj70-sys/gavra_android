import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../globals.dart';
import '../utils/grad_adresa_validator.dart';
import 'gps_foreground_service.dart';
import 'openrouteservice.dart';
import 'permission_service.dart';

/// Servis za slanje GPS lokacije vozaca u realtime
/// Putnici mogu pratiti lokaciju kombija dok cekaju
class V2DriverLocationService {
  static final V2DriverLocationService _instance = V2DriverLocationService._internal();
  factory V2DriverLocationService() => _instance;
  V2DriverLocationService._internal();

  static V2DriverLocationService get instance => _instance;

  // RealtimeGpsService garantuje slanje lokacije svakih 30s putem positionStream.
  // Lokacija (lat/lng) ? Supabase svake 30s (bez API poziva).
  // ORS ETA korekcija ? svake 60s (odvojeni timer, ~900 poziva/dan).
  static const Duration _etaUpdateInterval = Duration(minutes: 1);

  // State
  Timer? _etaTimer;
  bool _isSending = false; // ?? Lock: sprecava konkurentne _sendCurrentLocation pozive
  StreamSubscription<Position>? _positionSubscription;
  Position? _lastPosition;
  bool _isTracking = false;
  String? _currentVozacId;
  String? _currentVozacIme;
  String? _currentGrad;
  String? _currentVremePolaska;
  String? _currentSmer;
  Map<String, int>? _currentPutniciEta;
  Map<String, Position>? _putniciCoordinates;
  List<String>? _putniciRedosled; // ?? Redosled putnika (optimizovan)
  VoidCallback? _onAllPassengersPickedUp; // Callback za auto-stop

  // Getteri
  bool get isTracking => _isTracking;
  String? get currentVozacId => _currentVozacId;

  /// Broj preostalih putnika za pokupiti (ETA >= 0)
  int get remainingPassengers => _currentPutniciEta?.values.where((v) => v >= 0).length ?? 0;

  /// Pokreni pracenje lokacije za vozaca
  Future<bool> startTracking({
    required String vozacId,
    required String vozacIme,
    required String grad,
    String? vremePolaska,
    String? smer,
    Map<String, int>? putniciEta,
    Map<String, Position>? putniciCoordinates,
    List<String>? putniciRedosled,
    VoidCallback? onAllPassengersPickedUp,
  }) async {
    // ?? REALTIME FIX: Ako je tracking vec aktivan, samo ažuriraj ETA
    if (_isTracking) {
      if (putniciEta != null) {
        _currentPutniciEta = Map.from(putniciEta);
        // Odmah pošalji ažurirani ETA u Supabase
        await _sendCurrentLocation();
      }
      return true;
    }

    final hasPermission = await _checkLocationPermission();
    if (!hasPermission) {
      return false;
    }

    _currentVozacId = vozacId;
    _currentVozacIme = vozacIme;
    _currentGrad = GradAdresaValidator.normalizeGrad(grad); // 'BC' ili 'VS'
    _currentVremePolaska = vremePolaska;
    _currentSmer = smer;
    _currentPutniciEta = putniciEta != null ? Map.from(putniciEta) : null;
    _putniciCoordinates = putniciCoordinates != null ? Map.from(putniciCoordinates) : null;
    _putniciRedosled = putniciRedosled != null ? List.from(putniciRedosled) : null;
    _onAllPassengersPickedUp = onAllPassengersPickedUp;
    _isTracking = true;

    await _sendCurrentLocation();

    // ? Lokacija (lat/lng) se šalje svake 30s putem RealtimeGpsService (bez API).
    // ? ORS ETA se racuna odvojeno svake 60s.
    _etaTimer = Timer.periodic(_etaUpdateInterval, (_) => _refreshEta());

    // ??? Pokreni Android Foreground Service — drži proces živ (kao Waze)
    await GpsForegroundService.startService(
      vozacIme: vozacIme,
      grad: grad,
      vreme: vremePolaska ?? '',
    );

    return true;
  }

  /// Rucno stopiranje tracking-a
  Future<void> stopTracking() async {
    _etaTimer?.cancel();
    _positionSubscription?.cancel();

    // ?? Zaustavi Android Foreground Service — ukloni notifikaciju iz status bara
    await GpsForegroundService.stopService();

    // Uvijek pokušaj update bez obzira na _isTracking flag
    if (_currentVozacId != null) {
      try {
        debugPrint('?? [DriverLocation] Stopping tracking for vozac: $_currentVozacId');
        await supabase.from('v2_vozac_lokacije').update({
          'aktivan': false,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('vozac_id', _currentVozacId!);
        debugPrint('? [DriverLocation] aktivan=false upisano u DB');
      } catch (e) {
        debugPrint('? [DriverLocation] Stop error: $e');
      }
    } else {
      debugPrint('?? [DriverLocation] stopTracking pozvan ali _currentVozacId je null');
    }

    _isTracking = false;
    _currentVozacId = null;
    _currentVozacIme = null;
    _currentGrad = null;
    _currentVremePolaska = null;
    _currentSmer = null;
    _currentPutniciEta = null;
    _putniciCoordinates = null;
    _putniciRedosled = null;
    _onAllPassengersPickedUp = null;
    _lastPosition = null;
  }

  /// ?? REALTIME FIX: Ažuriraj ETA za putnike bez ponovnog pokretanja trackinga
  /// Poziva se nakon reoptimizacije rute kada se doda/otkaže putnik
  Future<void> updatePutniciEta(Map<String, int> newPutniciEta) async {
    if (!_isTracking) return;

    _currentPutniciEta = Map.from(newPutniciEta);
    await _sendCurrentLocation();

    // ?? Check if all finished
    final activeCount = _currentPutniciEta!.values.where((v) => v >= 0).length;
    if (activeCount == 0 && _isTracking) {
      debugPrint('? Svi putnici zaVrseni (ETA update) - zaustavljam tracking');
      _onAllPassengersPickedUp?.call();
      stopTracking();
    }
  }

  /// ?? ORS ETA korekcija — poziva se svake 60s
  /// Ako API ne odgovori — zadrži stari ETA (nema skakanja).
  Future<void> _refreshEta() async {
    if (!_isTracking || _lastPosition == null) return;
    if (_putniciCoordinates == null || _putniciRedosled == null) return;

    final aktivniPutnici = _putniciRedosled!
        .where((ime) =>
            _currentPutniciEta != null && _currentPutniciEta!.containsKey(ime) && _currentPutniciEta![ime]! >= 0)
        .toList();

    if (aktivniPutnici.isEmpty) return;

    final result = await OpenRouteService.getRealtimeEta(
      currentPosition: _lastPosition!,
      putnikImena: aktivniPutnici,
      putnikCoordinates: _putniciCoordinates!,
    );

    if (result.success && result.putniciEta != null) {
      for (final entry in result.putniciEta!.entries) {
        _currentPutniciEta![entry.key] = entry.value;
      }
      debugPrint('?? [DriverLocation] ORS ETA (60s): ${result.putniciEta}');
      // Pošalji ažurirani ETA u Supabase odmah
      await _sendCurrentLocation();

      // ?? Ažuriraj tekst notifikacije — prikaži sledeceg putnika i ETA
      if (_putniciRedosled != null && _currentPutniciEta != null) {
        final sledeci = _putniciRedosled!.firstWhere(
          (ime) => (_currentPutniciEta![ime] ?? -1) >= 0,
          orElse: () => '',
        );
        if (sledeci.isNotEmpty) {
          final eta = _currentPutniciEta![sledeci];
          GpsForegroundService.updateNotificationText(
            'Sledeci: $sledeci — $eta min | $_currentGrad $_currentVremePolaska',
          );
        }
      }
    } else {
      debugPrint('?? [DriverLocation] ORS ETA neuspješan — zadržan stari ETA');
    }
  }

  /// Proveri i zatraži dozvole za lokaciju - CENTRALIZOVANO
  /// Forsiraj slanje trenutne lokacije (npr. kada se pokupi putnik)
  Future<void> forceLocationUpdate({Position? knownPosition}) async {
    await _sendCurrentLocation(knownPosition: knownPosition);
  }

  Future<bool> _checkLocationPermission() async {
    return await PermissionService.ensureGpsForNavigation();
  }

  /// Pošalji trenutnu lokaciju u Supabase
  Future<void> _sendCurrentLocation({Position? knownPosition}) async {
    if (!_isTracking || _currentVozacId == null) return;
    // ?? Ako je prethodni poziv još aktivan (npr. spor GPS ili DB), preskoci
    if (_isSending) {
      debugPrint('?? [DriverLocation] _sendCurrentLocation preskocen — prethodni poziv još aktivan');
      return;
    }
    _isSending = true;

    try {
      final position = knownPosition ?? await Geolocator.getCurrentPosition();

      if (_lastPosition != null) {
        final distance = Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          position.latitude,
          position.longitude,
        );
        // Log distance za debugging ako treba
        debugPrint('?? GPS: pomeraj ${distance.toStringAsFixed(0)}m');
      }

      _lastPosition = position;

      await supabase.from('v2_vozac_lokacije').upsert({
        'vozac_id': _currentVozacId,
        'vozac_ime': _currentVozacIme,
        'lat': position.latitude,
        'lng': position.longitude,
        'grad': _currentGrad,
        'vreme_polaska': _currentVremePolaska,
        'smer': _currentSmer,
        'aktivan': true,
        'putnici_eta': _currentPutniciEta,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'vozac_id');
    } catch (e) {
      debugPrint('? [DriverLocation] _sendCurrentLocation greška: $e');
    } finally {
      _isSending = false; // ?? Oslobodi lock bez obzira na ishod
    }
  }
}
