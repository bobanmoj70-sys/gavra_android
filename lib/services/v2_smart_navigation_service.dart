import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../config/v2_route_config.dart';
import '../models/v2_putnik.dart';
import '../utils/v2_grad_adresa_validator.dart';
import 'v2_here_wego_navigation_service.dart';
import 'v2_osrm_service.dart';
import 'v2_permission_service.dart';
import 'v2_unified_geocoding_service.dart';

/// SMART NAVIGATION SERVICE
/// Implementira pravu GPS navigaciju sa optimizovanim redosledom putnika
/// Koristi OSRM za optimizaciju rute i HERE WeGo za navigaciju
///
/// HERE WEGO ONLY:
/// - HERE WeGo (10 waypoints) - besplatno, radi na svim uredajima
/// - Automatska segmentacija rute kada prelazi limit waypoinata
/// - Offline mape, poštuje redosled putnika
class V2SmartNavigationService {
  V2SmartNavigationService._();

  /// Vrati krajnju destinaciju na osnovu startCity
  /// startCity je grad ODAKLE putnici krecu (polazište putnika)
  ///
  /// LOGIKA VOžNJE:
  /// - BC polazak (ujutru): Putnici su u BC, vozac ih pokuplja i vozi u VS
  /// -> endDestination = Vrsac (gde ih vozi)
  /// - VS polazak (popodne): Putnici su u VS, vozac ih pokuplja i vraca u BC
  /// -> endDestination = Bela Crkva (gde ih vraca)
  ///
  /// Dakle: endDestination je SUPROTNI grad od startCity
  static Position? _getEndDestination(String startCity) {
    if (V2GradAdresaValidator.isBelaCrkva(startCity)) {
      // Putnici krecu IZ Bele Crkve -> vozac ih vozi U Vrsac
      return Position(
        latitude: V2RouteConfig.vrsacLat,
        longitude: V2RouteConfig.vrsacLng,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
        altitudeAccuracy: 0,
        headingAccuracy: 0,
      );
    }

    if (V2GradAdresaValidator.isVrsac(startCity)) {
      // Putnici krecu IZ Vrsca -> vozac ih vozi U Belu Crkvu
      return Position(
        latitude: V2RouteConfig.belaCrkvaLat,
        longitude: V2RouteConfig.belaCrkvaLng,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
        altitudeAccuracy: 0,
        headingAccuracy: 0,
      );
    }

    return null; // Nije prepoznat grad
  }

  /// SAMO OPTIMIZACIJA RUTE (bez otvaranja mape) - za "Pokreni" dugme
  static Future<V2NavigationResult> optimizeRouteOnly({
    required List<V2Putnik> putnici,
    required String startCity,
    bool optimizeForTime = true,
  }) async {
    try {
      // 1. DOBIJ TRENUTNU GPS POZICIJU VOZACA
      final currentPosition = await _getCurrentPosition();

      // Odredi krajnju destinaciju (suprotni grad)
      final endDestination = _getEndDestination(startCity);

      // KORISTI OSRM ZA PRAVU TSP OPTIMIZACIJU (sa fallback na lokalni algoritam)
      final osrmResult = await V2OsrmService.optimizeRoute(
        startPosition: currentPosition,
        putnici: putnici,
        endDestination: endDestination,
      );

      // OSRM neuspešan - vrati grešku
      if (!osrmResult.success || osrmResult.optimizedPutnici == null) {
        return V2NavigationResult.error(osrmResult.message);
      }

      // OSRM uspešan
      final List<V2Putnik> optimizedRoute = osrmResult.optimizedPutnici!;
      final Map<String, Position> coordinates = osrmResult.coordinates ?? {};

      // Nadi preskocene putnike (nemaju koordinate)
      final skipped = putnici
          .where((p) => !coordinates.containsKey(p.adresaId ?? p.id?.toString() ?? ''))
          .toList();

      // 3. VRATI OPTIMIZOVANU RUTU
      return V2NavigationResult.success(
        message: 'Ruta optimizovana',
        optimizedPutnici: optimizedRoute,
        totalDistance:
            osrmResult.totalDistanceKm ?? _calculateTotalDistance(currentPosition, optimizedRoute, coordinates),
        skippedPutnici: skipped.isNotEmpty ? skipped : null,
        putniciEta: osrmResult.putniciEta,
      );
    } catch (e) {
      return V2NavigationResult.error('Greška pri optimizaciji: $e');
    }
  }

  // -----------------------------------------------------------------------
  // HERE WEGO NAVIGATION
  // -----------------------------------------------------------------------

  /// GLAVNA FUNKCIJA - HERE WeGo navigacija
  /// Koristi iskljucivo HERE WeGo - besplatno, radi na svim uredajima
  ///
  /// [context] - BuildContext za dijaloge
  /// [putnici] - Lista optimizovanih putnika
  /// [startCity] - Pocetni grad (za krajnju destinaciju)
  static Future<V2NavigationResult> startMultiProviderNavigation({
    required BuildContext context,
    required List<V2Putnik> putnici,
    required String startCity,
  }) async {
    try {
      // 1. DOBIJ KOORDINATE
      final coordinates = await V2UnifiedGeocodingService.getCoordinatesForPutnici(putnici);

      if (coordinates.isEmpty) {
        return V2NavigationResult.error('Nijedan putnik nema validnu adresu');
      }

      // 2. ODREDI KRAJNJU DESTINACIJU
      final endDestination = _getEndDestination(startCity);

      // 3. POKRENI MULTI-PROVIDER NAVIGACIJU
      if (!context.mounted) {
        return V2NavigationResult.error('Context nije više aktivan');
      }
      final result = await V2HereWeGoNavigationService.startNavigation(
        context: context,
        putnici: putnici,
        coordinates: coordinates,
        endDestination: endDestination,
      );

      // 4. KONVERTUJ REZULTAT
      if (result.success) {
        return V2NavigationResult.success(
          message: result.message,
          optimizedPutnici: result.launchedPutnici ?? putnici,
        );
      } else {
        return V2NavigationResult.error(result.message);
      }
    } catch (e) {
      return V2NavigationResult.error('Greška: $e');
    }
  }

  // -----------------------------------------------------------------------
  // HELPER FUNKCIJE
  // -----------------------------------------------------------------------

  /// Dobij trenutnu GPS poziciju vozaca
  static Future<Position> _getCurrentPosition() async {
    // Centralizovana provera GPS dozvola (ukljucuje i GPS service check)
    final hasPermission = await V2PermissionService.ensureGpsForNavigation();
    if (!hasPermission) {
      throw Exception('GPS dozvole nisu odobrene ili GPS nije ukljucen');
    }

    // Dobij poziciju sa visokom tacnošcu
    return await Geolocator.getCurrentPosition();
  }

  /// Izracunaj distancu izmedu dve pozicije (Haversine formula)
  static double _calculateDistance(Position pos1, Position pos2) {
    return Geolocator.distanceBetween(
      pos1.latitude,
      pos1.longitude,
      pos2.latitude,
      pos2.longitude,
    );
  }

  /// Izracunaj ukupnu distancu optimizovane rute (u kilometrima)
  static double _calculateTotalDistance(
    Position start,
    List<V2Putnik> route,
    Map<String, Position> coordinates,
  ) {
    if (route.isEmpty) return 0.0;

    double totalDistance = 0.0;
    Position currentPos = start;

    for (final putnik in route) {
      final nextPos = coordinates[putnik.adresaId ?? putnik.id?.toString() ?? ''];
      if (nextPos == null) continue;
      totalDistance += _calculateDistance(currentPos, nextPos);
      currentPos = nextPos;
    }

    return totalDistance / 1000; // m -> km
  }
}

/// Rezultat navigacije
class V2NavigationResult {
  V2NavigationResult._({
    required this.success,
    required this.message,
    this.optimizedPutnici,
    this.totalDistance,
    this.skippedPutnici,
    this.putniciEta,
  });

  factory V2NavigationResult.success({
    required String message,
    required List<V2Putnik> optimizedPutnici,
    double? totalDistance,
    List<V2Putnik>? skippedPutnici,
    Map<String, int>? putniciEta,
  }) {
    return V2NavigationResult._(
      success: true,
      message: message,
      optimizedPutnici: optimizedPutnici,
      totalDistance: totalDistance,
      skippedPutnici: skippedPutnici,
      putniciEta: putniciEta,
    );
  }

  factory V2NavigationResult.error(String message) {
    return V2NavigationResult._(
      success: false,
      message: message,
    );
  }
  final bool success;
  final String message;
  final List<V2Putnik>? optimizedPutnici;
  final double? totalDistance;
  final List<V2Putnik>? skippedPutnici;
  final Map<String, int>? putniciEta;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is V2NavigationResult &&
          runtimeType == other.runtimeType &&
          success == other.success &&
          message == other.message;

  @override
  int get hashCode => Object.hash(success, message);
}
