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
import 'v3_vozac_lokacija_service.dart';

/// V3 Foreground GPS Service sa Persistent Notification
/// Drži GPS tracking aktivan u pozadini na Android i iOS platformama
class V3ForegroundGpsService {
  V3ForegroundGpsService._();

  static const String _channelId = 'gavra_gps_tracking';
  static const int _notificationId = 888;
  static FlutterLocalNotificationsPlugin? _notifications;

  static bool _isRunning = false;
  static String? _currentVozacId;
  static String? _currentPolazakVreme;
  static List<V3Putnik> _currentPutnici = [];

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
      _currentPolazakVreme = polazakVreme;
      _currentPutnici = List.from(putnici);
      _isRunning = true;

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
    _currentPolazakVreme = null;
    _currentPutnici.clear();

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
    final locationStatus = await Permission.locationAlways.status;
    final notificationStatus = await Permission.notification.status;

    if (!locationStatus.isGranted) {
      final locationRequest = await Permission.locationAlways.request();
      if (!locationRequest.isGranted) return false;
    }

    if (Platform.isAndroid && !notificationStatus.isGranted) {
      final notificationRequest = await Permission.notification.request();
      if (!notificationRequest.isGranted) return false;
    }

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
  static void _onServiceStart(ServiceInstance service) {
    debugPrint('[V3ForegroundGpsService] Background service pokrenut');

    service.on('stop').listen((event) {
      service.stopSelf();
      debugPrint('[V3ForegroundGpsService] Background service zaustavljen');
    });
  }

  /// iOS background callback
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
      actions: [
        AndroidNotificationAction(
          'stop_tracking',
          'Zaustavi Tracking',
          icon: DrawableResourceAndroidBitmap('@drawable/ic_stop'),
        ),
      ],
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
        'vozac_id': _currentVozacId,
        'polazak_vreme': polazakVreme,
      }),
    );
  }

  /// Pokreće GPS poziciju streaming
  static Future<void> _startGpsTracking() async {
    try {
      // Zaustavi postojeći stream
      await _stopGpsTracking();

      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update svakih 10 metara
        timeLimit: Duration(seconds: 15),
      );

      V3StreamUtils.subscribeToGPS<Position>(
        key: 'foreground_gps_service',
        positionStream: Geolocator.getPositionStream(
          locationSettings: locationSettings,
        ),
        onPosition: (position) async {
          if (!_isRunning || _currentVozacId == null) return;

          // Pošalji GPS update
          await V3VozacLokacijaService.updateLokacija(
            V3VozacLokacijaUpdate(
              vozacId: _currentVozacId!,
              lat: position.latitude,
              lng: position.longitude,
              bearing: position.heading,
              brzina: position.speed * 3.6, // m/s -> km/h
              grad: '', // Će biti setovano iz konteksta
              vremePolaska: _currentPolazakVreme ?? '',
              aktivno: true,
            ),
          );

          // Update notification sa trenutnom brzinom
          await _updateNotificationWithSpeed(position.speed * 3.6);
        },
        onError: (error) {
          debugPrint('[V3ForegroundGpsService] GPS stream greška: $error');
        },
      );

      debugPrint('[V3ForegroundGpsService] GPS stream pokrenut');
    } catch (e) {
      debugPrint('[V3ForegroundGpsService] Greška pri pokretanju GPS stream-a: $e');
    }
  }

  /// Zaustavlja GPS poziciju streaming
  static Future<void> _stopGpsTracking() async {
    V3StreamUtils.cancelSubscription('foreground_gps_service_gps');
    V3StreamUtils.cancelTimer('foreground_gps_timer');
  }

  /// Ažurira notification sa trenutnom brzinom
  static Future<void> _updateNotificationWithSpeed(double brzina) async {
    if (!_isRunning) return;

    final putniciBroj = _currentPutnici.length;
    final brzinaText = brzina > 1.0 ? ' • ${brzina.toStringAsFixed(0)} km/h' : '';
    final title = 'Gavra GPS - ${_currentPolazakVreme ?? ''}';
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
      actions: [
        AndroidNotificationAction(
          'stop_tracking',
          'Zaustavi Tracking',
          icon: DrawableResourceAndroidBitmap('@drawable/ic_stop'),
        ),
      ],
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
    if (!_isRunning || _currentPutnici.isEmpty) return;

    // Logika za auto-stop će biti implementirana kada
    // se implementira fn_v3_auto_detect_adresa trigger
    // koji će detektovati kada vozač pokupe sve putnike
  }

  /// Javni interfejs za notification action handling
  static Future<void> handleNotificationAction(String action, String? payload) async {
    if (action == 'stop_tracking') {
      await stopTracking();
    }
  }
}
