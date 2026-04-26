import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';

import 'v3_osrm_route_service.dart';

class V3NavigationAppLauncherService {
  static const String _herePackage = 'com.here.app.maps';

  static Future<void> launchHereWeGoAppOnly({
    required List<V3RouteWaypoint> waypoints,
  }) async {
    if (!Platform.isAndroid) {
      throw Exception('App-only launch je trenutno podržan samo na Android-u.');
    }

    if (waypoints.isEmpty) {
      throw Exception('Nema waypoint-a za navigaciju.');
    }

    await _launchInPackage(_herePackage, _buildHereWeGoRouteUrl(waypoints));
  }

  static String _buildHereWeGoRouteUrl(List<V3RouteWaypoint> waypoints) {
    final points = waypoints.map((w) => '${w.coordinate.latitude},${w.coordinate.longitude}').join('/');
    return 'https://wego.here.com/directions/drive/$points';
  }

  static Future<void> _launchInPackage(String packageName, String url) async {
    final intent = AndroidIntent(
      action: 'android.intent.action.VIEW',
      data: url,
      package: packageName,
    );

    try {
      await intent.launch();
    } catch (_) {
      throw Exception('Aplikacija nije dostupna: $packageName');
    }
  }
}
