import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'v3_app_settings_state.dart';
import 'v3_route_models.dart';

/// Rezultat pokušaja otvaranja HERE WeGo navigacije.
///
/// Politika (iOS + Android, uniformno):
/// - HERE WeGo je jedina podržana map/nav app
/// - Ako je instalirana → otvori rutu
/// - Ako nije → obavesti korisnika; opciono otvori install URL iz remote config-a
/// - Nema Apple Maps / Google Maps fallback
enum V3HereWeGoLaunchResult {
  opened,
  notInstalled,
  noWaypoints,
  failed,
}

/// Centralni launcher za GPS navigaciju putnika / multi-stop rute.
///
/// Samo HERE WeGo. Nema fallback na druge mape.
/// Install URL-ovi dolaze isključivo iz `v3_app_settings` (runtime),
/// nisu hardkodovani u binaru (Guideline 2.3.10).
class V3NavigationAppLauncherService {
  V3NavigationAppLauncherService._();

  /// Android package name — samo za Intent `package:` filter, ne store URL.
  static const String androidPackage = 'com.here.app.maps';

  /// Deep-link šema koju HERE WeGo registruje za rute.
  static const String routeScheme = 'here-route';

  /// Otvori multi-stop (ili single-stop) rutu u HERE WeGo.
  ///
  /// [waypoints] = stanice posle trenutne lokacije vozača (mylocation → w1 → w2 → …).
  static Future<V3HereWeGoLaunchResult> launchHereWeGo({
    required List<V3RouteWaypoint> waypoints,
  }) async {
    if (waypoints.isEmpty) {
      return V3HereWeGoLaunchResult.noWaypoints;
    }

    final routeUrl = buildHereWeGoRouteUrl(waypoints);

    try {
      if (Platform.isAndroid) {
        return await _launchAndroid(routeUrl);
      }
      if (Platform.isIOS) {
        return await _launchIos(routeUrl);
      }
      return await _launchViaUrl(routeUrl);
    } catch (e, st) {
      debugPrint('[V3NavigationAppLauncher] launch failed: $e\n$st');
      return V3HereWeGoLaunchResult.failed;
    }
  }

  /// Single destinacija (pin na kartici putnika).
  static Future<V3HereWeGoLaunchResult> launchHereWeGoToCoordinate({
    required double latitude,
    required double longitude,
    String? label,
  }) {
    final safeLabel = (label == null || label.trim().isEmpty) ? 'Stop' : label.trim();
    return launchHereWeGo(
      waypoints: [
        V3RouteWaypoint(
          id: 'single',
          label: safeLabel,
          coordinate: V3RouteCoordinate(latitude: latitude, longitude: longitude),
        ),
      ],
    );
  }

  /// HERE WeGo route URL:
  /// `here-route://mylocation/lat,lng,Label/lat2,lng2,Label2?m=d`
  static String buildHereWeGoRouteUrl(List<V3RouteWaypoint> waypoints) {
    final points = waypoints.map((w) {
      final label = Uri.encodeComponent(w.label.isNotEmpty ? w.label : 'Stop');
      final lat = w.coordinate.latitude.toStringAsFixed(6);
      final lng = w.coordinate.longitude.toStringAsFixed(6);
      return '$lat,$lng,$label';
    }).join('/');
    return '$routeScheme://mylocation/$points?m=d';
  }

  /// Install listing URL iz remote config-a (platform-specific).
  static String? installUrlFromRemoteConfig() {
    return V3AppSettingsState.instance.hereWegoInstallUrlForCurrentPlatform(
      isIos: Platform.isIOS,
      isAndroid: Platform.isAndroid,
    );
  }

  /// Otvori install listing za HERE WeGo (URL samo iz Supabase).
  static Future<bool> openInstallFromRemoteConfig() async {
    final raw = installUrlFromRemoteConfig();
    if (raw == null || raw.isEmpty) return false;
    try {
      final uri = Uri.tryParse(raw);
      if (uri == null) return false;
      if (await canLaunchUrl(uri)) {
        return launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return false;
    } catch (e) {
      debugPrint('[V3NavigationAppLauncher] openInstallFromRemoteConfig failed: $e');
      return false;
    }
  }

  /// SnackBar: instaliraj HERE WeGo; dugme samo ako postoji remote install URL.
  static void showInstallPrompt(
    BuildContext context, {
    required String message,
    String? actionLabel,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    final hasInstallUrl = installUrlFromRemoteConfig()?.isNotEmpty == true;
    final label = (actionLabel ?? '').trim();
    final showAction = hasInstallUrl && label.isNotEmpty;

    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 8),
        action: showAction
            ? SnackBarAction(
                label: label,
                onPressed: () {
                  openInstallFromRemoteConfig();
                },
              )
            : null,
      ),
    );
  }

  // ─── Platform launch ─────────────────────────────────────────────

  static Future<V3HereWeGoLaunchResult> _launchAndroid(String routeUrl) async {
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.VIEW',
        data: routeUrl,
        package: androidPackage,
      );
      await intent.launch();
      return V3HereWeGoLaunchResult.opened;
    } catch (_) {
      // package nije instaliran ili intent nije resolved
    }

    final uri = Uri.parse(routeUrl);
    if (await canLaunchUrl(uri)) {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return ok ? V3HereWeGoLaunchResult.opened : V3HereWeGoLaunchResult.failed;
    }

    return V3HereWeGoLaunchResult.notInstalled;
  }

  static Future<V3HereWeGoLaunchResult> _launchIos(String routeUrl) async {
    final uri = Uri.parse(routeUrl);

    // Na iOS canLaunchUrl zahteva LSApplicationQueriesSchemes (here-route).
    if (await canLaunchUrl(uri)) {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return ok ? V3HereWeGoLaunchResult.opened : V3HereWeGoLaunchResult.failed;
    }

    // Fallback pokušaj (nekad canLaunch laže); ako padne → notInstalled.
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return V3HereWeGoLaunchResult.opened;
    } catch (_) {
      // expected when app missing
    }

    return V3HereWeGoLaunchResult.notInstalled;
  }

  static Future<V3HereWeGoLaunchResult> _launchViaUrl(String routeUrl) async {
    final uri = Uri.parse(routeUrl);
    if (await canLaunchUrl(uri)) {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return ok ? V3HereWeGoLaunchResult.opened : V3HereWeGoLaunchResult.failed;
    }
    return V3HereWeGoLaunchResult.notInstalled;
  }
}
