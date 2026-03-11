import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

import '../globals.dart';
import '../utils/v2_grad_adresa_validator.dart';
import 'v2_background_gps_service.dart';
import 'v2_openrouteservice.dart';
import 'v2_permission_service.dart';

/// Servis za slanje GPS lokacije vozaca u realtime
/// Putnici mogu pratiti lokaciju kombija dok cekaju
class V2DriverLocationService {
  static final V2DriverLocationService _instance = V2DriverLocationService._internal();
  factory V2DriverLocationService() => _instance;
  V2DriverLocationService._internal();

  static V2DriverLocationService get instance => _instance;

  // V2RealtimeGpsService garantuje slanje lokacije svakih 30s putem positionStream.
  // Lokacija (lat/lng) → Supabase svake 30s (bez API poziva).
  // ORS ETA korekcija → svake 60s (odvojeni timer, ~900 poziva/dan).
  static const Duration _etaUpdateInterval = Duration(minutes: 1);
  static final _notifPlugin = FlutterLocalNotificationsPlugin();
  static const int _gpsNotifId = 9001;
  static const String _gpsChannelId = 'gavra_gps_tracking';

  // State
  Timer? _etaTimer;
  bool _isSending = false; // Lock: sprecava konkurentne _sendCurrentLocation pozive
  Position? _lastPosition;
  bool _isTracking = false;
  String? _currentVozacId;
  String? _currentVozacIme;
  String? _currentGrad;
  String? _currentVremePolaska;
  String? _currentSmer;
  Map<String, int>? _currentPutniciEta;
  Map<String, Position>? _putniciCoordinates;
  List<String>? _putniciRedosled; // Redosled putnika (optimizovan)
  VoidCallback? _onAllPassengersPickedUp; // Callback za auto-stop

  // Getteri
  bool get isTracking => _isTracking;
  String? get currentVozacId => _currentVozacId;

  /// Broj preostalih putnika za pokupiti (ETA >= 0)
  int get remainingPassengers => _currentPutniciEta?.values.where((v) => v >= 0).length ?? 0;

  /// Pokreni pracenje lokacije za vozaca
  Future<bool> v2StartTracking({
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
    // Ako je tracking vec aktivan, samo ažuriraj ETA
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
    _currentGrad = V2GradAdresaValidator.normalizeGrad(grad); // 'BC' ili 'VS'
    _currentVremePolaska = vremePolaska;
    _currentSmer = smer;
    _currentPutniciEta = putniciEta != null ? Map.from(putniciEta) : null;
    _putniciCoordinates = putniciCoordinates != null ? Map.from(putniciCoordinates) : null;
    _putniciRedosled = putniciRedosled != null ? List.from(putniciRedosled) : null;
    _onAllPassengersPickedUp = onAllPassengersPickedUp;
    _isTracking = true;

    await _sendCurrentLocation();

    // ORS ETA korekcija — svake 60s (ne šalje lokaciju, samo ETA)
    _etaTimer = Timer.periodic(_etaUpdateInterval, (_) => unawaited(_refreshEta()));

    // Pokreni Android foreground service — GPS ostaje aktivan i kada app ide u pozadinu
    await V2BackgroundGpsService.start(
      vozacId: vozacId,
      grad: grad,
      vremePolaska: vremePolaska ?? '',
      smer: smer ?? '',
      putniciEta: putniciEta,
      putniciRedosled: putniciRedosled,
    );

    return true;
  }

  /// Rucno stopiranje tracking-a
  Future<void> v2StopTracking() async {
    _etaTimer?.cancel();
    _etaTimer = null;
    // Postavi flag odmah da spriječi novi _sendCurrentLocation
    _isTracking = false;

    // Zaustavi foreground service (on sam markira vozača neaktivnim u Supabase i uklanja notifikaciju)
    await V2BackgroundGpsService.stop();

    // Ukloni i lokalnu notifikaciju ako je još prikazana
    await _cancelGpsNotif();

    // Uvijek pokušaj update bez obzira na _isTracking flag
    if (_currentVozacId != null) {
      try {
        await supabase.from('v2_vozac_lokacije').update({
          'aktivan': false,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('vozac_id', _currentVozacId!);
      } catch (e) {
        debugPrint('[V2DriverLocationService] v2StopTracking greška: $e');
      }
    }

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

  /// Ažuriraj ETA za putnike bez ponovnog pokretanja trackinga.
  /// Poziva se nakon reoptimizacije rute kada se doda/otkaže V2Putnik.
  Future<void> v2UpdatePutniciEta(Map<String, int> newPutniciEta) async {
    if (!_isTracking) return;

    _currentPutniciEta = Map.from(newPutniciEta);
    // Ažuriraj ETA i u background servisu
    await V2BackgroundGpsService.updateEta(newPutniciEta);
    await _sendCurrentLocation();

    final activeCount = _currentPutniciEta!.values.where((v) => v >= 0).length;
    if (activeCount == 0 && _isTracking) {
      _onAllPassengersPickedUp?.call();
      await v2StopTracking();
    }
  }

  /// ORS ETA korekcija — poziva se svake 60s.
  /// Ako API ne odgovori — zadrži stari ETA (nema skakanja).
  Future<void> _refreshEta() async {
    if (!_isTracking || _lastPosition == null) return;
    if (_putniciCoordinates == null || _putniciRedosled == null || _currentPutniciEta == null) return;

    final aktivniPutnici = _putniciRedosled!
        .where((ime) => _currentPutniciEta!.containsKey(ime) && _currentPutniciEta![ime]! >= 0)
        .toList();

    if (aktivniPutnici.isEmpty) return;

    final result = await V2OpenRouteService.getRealtimeEta(
      currentPosition: _lastPosition!,
      putnikImena: aktivniPutnici,
      putnikCoordinates: _putniciCoordinates!,
    );

    if (!_isTracking || _currentPutniciEta == null) return;

    if (result.success && result.putniciEta != null) {
      for (final entry in result.putniciEta!.entries) {
        _currentPutniciEta![entry.key] = entry.value;
      }
      await _sendCurrentLocation();
    } else {
      debugPrint('[V2DriverLocationService] _refreshEta: ORS API nije vratio ETA, zadržan stari');
    }
  }

  /// Proveri i zatraži dozvole za lokaciju - CENTRALIZOVANO
  /// Forsiraj slanje trenutne lokacije (npr. kada se pokupi V2Putnik)
  Future<void> forceLocationUpdate({Position? knownPosition}) async {
    await _sendCurrentLocation(knownPosition: knownPosition);
  }

  Future<bool> _checkLocationPermission() async {
    return await V2PermissionService.ensureGpsForNavigation();
  }

  /// Ukloni ongoing notifikaciju (fallback, background service sam uklanja svoju)
  Future<void> _cancelGpsNotif() async {
    await _notifPlugin.cancel(_gpsNotifId);
  }

  /// Pošalji trenutnu lokaciju u Supabase
  Future<void> _sendCurrentLocation({Position? knownPosition}) async {
    if (!_isTracking || _currentVozacId == null) return;
    // Ako je prethodni poziv još aktivan (npr. spor GPS ili DB), preskoči
    if (_isSending) {
      return;
    }
    _isSending = true;

    try {
      final position = knownPosition ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 10),
            ),
          );

      _lastPosition = position;

      await supabase.from('v2_vozac_lokacije').upsert({
        'vozac_id': _currentVozacId,
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
      debugPrint('[V2DriverLocationService] _sendCurrentLocation greška: $e');
    } finally {
      _isSending = false; // Oslobodi lock bez obzira na ishod
    }
  }
}
