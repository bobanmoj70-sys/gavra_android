import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/v3_putnik.dart';
import '../../utils/v3_stream_utils.dart';
import 'v3_trenutna_dodela_service.dart';
import 'v3_vozac_lokacija_service.dart';

/// V3 Foreground GPS Service sa Persistent Notification
/// Drži GPS tracking aktivan u pozadini na Android i iOS platformama
@pragma('vm:entry-point')
class V3ForegroundGpsService {
  V3ForegroundGpsService._();

  static const String _channelId = 'gavra_gps_tracking';
  static const int _notificationId = 888;
  static FlutterLocalNotificationsPlugin? _notifications;

  static bool _isRunning = false;
  static String? _currentVozacId;
  static String? _currentGrad;
  static String? _currentPolazakVreme;
  static String? _currentPolazakTime;
  static List<V3Putnik> _currentPutnici = [];
  static DateTime? _lastAutoStopCheckAt;
  static bool _autoStopInProgress = false;
  static bool _routeEtaRefreshInProgress = false;
  static bool _trackingCycleInProgress = false;

  /// Inicijalizuje notification channel
  static Future<void> initialize() async {
    _notifications = FlutterLocalNotificationsPlugin();

    // Android notification channel
    if (Platform.isAndroid) {
      const androidChannel = AndroidNotificationChannel(
        _channelId,
        'GPS Tracking',
        description: 'Gavra GPS tracking za vozače',
        importance: Importance.max,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      );

      await _notifications!
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);
    }

    // Initialize notifications
    await _notifications!.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
  }

  /// Pokreće GPS tracking sa persistent notification
  static Future<bool> startTracking({
    required String vozacId,
    required String vozacIme,
    required String polazakVreme,
    required List<V3Putnik> putnici,
    required String grad,
  }) async {
    if (_isRunning) {
      debugPrint('[V3ForegroundGpsService] Tracking već pokrenuo');
      return false;
    }

    try {
      // 1. Provjeri permissions
      if (!await _checkPermissions()) {
        debugPrint('[V3ForegroundGpsService] Nedostaju permissions');
        return false;
      }

      // 2. Pokreni foreground service
      await _startForegroundService();

      // 3. Postavi tracking parametre
      _currentVozacId = vozacId;
      _currentGrad = grad;
      _currentPolazakVreme = polazakVreme;
      _currentPolazakTime = polazakVreme;
      _currentPutnici = List.from(putnici);
      _lastAutoStopCheckAt = null;
      _autoStopInProgress = false;
      _isRunning = true;

      // 3b. Inicijalni GPS upis da v3_vozac_lokacije odmah dobije red
      await _seedInitialLocation();

      // 4. Pokreni persistent notification
      await _showPersistentNotification(
        vozacIme: vozacIme,
        polazakVreme: polazakVreme,
        putnici: putnici,
        grad: grad,
      );

      // 5. Pokreni GPS stream
      await _startGpsTracking();

      debugPrint('[V3ForegroundGpsService] Tracking pokrenut uspešno');
      return true;
    } catch (e) {
      debugPrint('[V3ForegroundGpsService] Greška pri pokretanju: $e');
      await stopTracking();
      return false;
    }
  }

  /// Zaustavlja GPS tracking i uklanja notification
  static Future<void> stopTracking() async {
    if (!_isRunning) return;

    _isRunning = false;
    _currentVozacId = null;
    _currentGrad = null;
    _currentPolazakVreme = null;
    _currentPolazakTime = null;
    _currentPutnici.clear();
    _lastAutoStopCheckAt = null;
    _autoStopInProgress = false;
    _routeEtaRefreshInProgress = false;
    _trackingCycleInProgress = false;

    // Zaustavi GPS
    await _stopGpsTracking();

    // Ukloni notification
    await _notifications?.cancel(_notificationId);

    // Zaustavi foreground service
    if (Platform.isAndroid) {
      FlutterBackgroundService().invoke('stop');
    }

    debugPrint('[V3ForegroundGpsService] Tracking zaustavljen');
  }

  /// Provjeri da li je tracking aktivan
  static bool get isRunning => _isRunning;

  /// Provjeri permissions za GPS i notifikacije
  static Future<bool> _checkPermissions() async {
    final locationStatus = await Permission.location.status;
    final notificationStatus = await Permission.notification.status;

    if (!locationStatus.isGranted) return false;

    if (Platform.isAndroid && !notificationStatus.isGranted) return false;

    return true;
  }

  /// Pokreće Android foreground service
  static Future<void> _startForegroundService() async {
    if (Platform.isAndroid) {
      await FlutterBackgroundService().configure(
        androidConfiguration: AndroidConfiguration(
          onStart: _onServiceStart,
          autoStart: false,
          isForegroundMode: true,
          notificationChannelId: _channelId,
          initialNotificationTitle: 'Gavra GPS Tracking',
          initialNotificationContent: 'Praćenje lokacije aktivno...',
          foregroundServiceNotificationId: _notificationId,
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: _onServiceStart,
          onBackground: _onServiceBackground,
        ),
      );

      await FlutterBackgroundService().startService();
    }
  }

  /// Background service callback
  @pragma('vm:entry-point')
  static void _onServiceStart(ServiceInstance service) {
    debugPrint('[V3ForegroundGpsService] Background service pokrenut');

    service.on('stop').listen((event) {
      service.stopSelf();
      debugPrint('[V3ForegroundGpsService] Background service zaustavljen');
    });
  }

  /// iOS background callback
  @pragma('vm:entry-point')
  static Future<bool> _onServiceBackground(ServiceInstance service) async {
    debugPrint('[V3ForegroundGpsService] iOS background mode');
    return true;
  }

  /// Prikazuje persistent notification
  static Future<void> _showPersistentNotification({
    required String vozacIme,
    required String polazakVreme,
    required List<V3Putnik> putnici,
    required String grad,
  }) async {
    final putniciBroj = putnici.length;
    final title = 'Gavra GPS - $grad $polazakVreme';
    final body = '$vozacIme • $putniciBroj putnika • Tracking aktivan';

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      'GPS Tracking',
      channelDescription: 'Gavra GPS tracking za vozače',
      importance: Importance.max,
      priority: Priority.high,
      ongoing: true, // Persistent notification
      autoCancel: false,
      showWhen: false,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: false,
      presentSound: false,
    );

    await _notifications?.show(
      _notificationId,
      title,
      body,
      const NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      payload: jsonEncode({
        'action': 'gps_tracking',
        'vozac_v3_auth_id': _currentVozacId,
        'polazak_vreme': polazakVreme,
      }),
    );
  }

  /// Pokreće 30s GPS ciklus
  static Future<void> _startGpsTracking() async {
    try {
      // Zaustavi postojeći ciklus
      await _stopGpsTracking();

      V3StreamUtils.createPeriodicTimer(
        key: 'foreground_gps_timer',
        period: const Duration(seconds: 30),
        callback: (_) {
          unawaited(_runTrackingCycle());
        },
      );

      debugPrint('[V3ForegroundGpsService] GPS 30s ciklus pokrenut');
    } catch (e) {
      debugPrint('[V3ForegroundGpsService] Greška pri pokretanju GPS ciklusa: $e');
    }
  }

  static Future<void> _seedInitialLocation() async {
    if (!_isRunning || _currentVozacId == null) return;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 12));

      await V3VozacLokacijaService.updateLokacija(
        V3VozacLokacijaUpdate(
          vozacId: _currentVozacId!,
          lat: position.latitude,
          lng: position.longitude,
          brzina: position.speed * 3.6,
        ),
      );

      await _refreshRouteOrderEtaForActiveAssignments();
      await checkAutoStop();
    } catch (e) {
      debugPrint('[V3ForegroundGpsService] Initial location seed failed: $e');
    }
  }

  /// Zaustavlja GPS ciklus
  static Future<void> _stopGpsTracking() async {
    V3StreamUtils.cancelTimer('foreground_gps_timer');
  }

  /// Ažurira notification sa trenutnom brzinom
  static Future<void> _updateNotificationWithSpeed(double brzina) async {
    if (!_isRunning) return;

    final putniciBroj = _currentPutnici.length;
    final brzinaText = brzina > 1.0 ? ' • ${brzina.toStringAsFixed(0)} km/h' : '';
    final gradLabel = (_currentGrad ?? '').trim();
    final timeLabel = (_currentPolazakTime ?? _currentPolazakVreme ?? '').trim();
    final title = gradLabel.isNotEmpty ? 'Gavra GPS - $gradLabel $timeLabel' : 'Gavra GPS - $timeLabel';
    final body = '$putniciBroj putnika • Tracking aktivan$brzinaText';

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      'GPS Tracking',
      importance: Importance.max,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      icon: '@mipmap/ic_launcher',
    );

    await _notifications?.show(
      _notificationId,
      title,
      body,
      const NotificationDetails(android: androidDetails),
    );
  }

  /// Automatski zaustavlja tracking kada se svi putnici pokupe
  static Future<void> checkAutoStop() async {
    if (!_isRunning || _autoStopInProgress) return;

    final vozacId = _currentVozacId;
    if (vozacId == null || vozacId.trim().isEmpty) return;

    final now = DateTime.now();
    if (_lastAutoStopCheckAt != null && now.difference(_lastAutoStopCheckAt!) < const Duration(seconds: 20)) {
      return;
    }
    _lastAutoStopCheckAt = now;

    _autoStopInProgress = true;
    try {
      final hasNepokupljeni = await V3TrenutnaDodelaService.hasNepokupljeniPutnikForVozac(
        vozacId: vozacId,
      );
      if (hasNepokupljeni) return;

      debugPrint('[V3ForegroundGpsService] Auto-stop: nema nepokupljenih putnika, gasim tracking');
      await stopTracking();
    } catch (e) {
      debugPrint('[V3ForegroundGpsService] checkAutoStop error: $e');
    } finally {
      _autoStopInProgress = false;
    }
  }

  static Future<void> _runTrackingCycle() async {
    if (!_isRunning || _trackingCycleInProgress || _currentVozacId == null) return;

    _trackingCycleInProgress = true;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 12));

      await V3VozacLokacijaService.updateLokacija(
        V3VozacLokacijaUpdate(
          vozacId: _currentVozacId!,
          lat: position.latitude,
          lng: position.longitude,
          brzina: position.speed * 3.6,
        ),
      );

      await _updateNotificationWithSpeed(position.speed * 3.6);
      await _refreshRouteOrderEtaForActiveAssignments();
      await checkAutoStop();
    } catch (e) {
      debugPrint('[V3ForegroundGpsService] _runTrackingCycle error: $e');
    } finally {
      _trackingCycleInProgress = false;
    }
  }

  static Future<void> _refreshRouteOrderEtaForActiveAssignments() async {
    if (!_isRunning || _routeEtaRefreshInProgress) return;

    final vozacId = _currentVozacId?.trim() ?? '';
    if (vozacId.isEmpty) return;

    final lokacija = V3VozacLokacijaService.getVozacLokacijaSync(vozacId);
    final lat = _toDouble(lokacija?['lat']);
    final lng = _toDouble(lokacija?['lng']);
    if (lat == null || lng == null) return;

    _routeEtaRefreshInProgress = true;
    try {
      await V3TrenutnaDodelaService.refreshRouteOrderEtaForVozac(
        vozacId: vozacId,
        originLat: lat,
        originLng: lng,
      );
    } catch (e) {
      debugPrint('[V3ForegroundGpsService] _refreshRouteOrderEtaForActiveAssignments error: $e');
    } finally {
      _routeEtaRefreshInProgress = false;
    }
  }

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  /// Javni interfejs za notification action handling
  static Future<void> handleNotificationAction(String action, String? payload) async {
    if (action == 'stop_tracking') {
      await stopTracking();
    }
  }
}
