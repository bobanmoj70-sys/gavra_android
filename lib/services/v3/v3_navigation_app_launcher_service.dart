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

    await _launchInPackage(_herePackage, _buildHereWeGoAppRouteUri(waypoints));
  }

  static String _buildHereWeGoAppRouteUri(List<V3RouteWaypoint> waypoints) {
    final points = waypoints.map((w) {
      final label = Uri.encodeComponent(w.label.isNotEmpty ? w.label : 'Stop');
      return '${w.coordinate.latitude},${w.coordinate.longitude},$label';
    }).join('/');
    return 'here-route://mylocation/$points?m=d';
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
