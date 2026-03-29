import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../globals.dart';
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
  static String? _currentGrad;
  static String? _currentPolazakVreme;
  static String? _currentPolazakTime;
  static List<V3Putnik> _currentPutnici = [];
  static DateTime? _lastHeartbeatSentAt;
  static DateTime? _lastAutoStopCheckAt;
  static bool _autoStopInProgress = false;

  static String _normalizePolazakTime(String? value) {
    if (value == null || value.trim().isEmpty) return '';
    final match = RegExp(r'((?:[01]?\d|2[0-3]):[0-5]\d(?:\:[0-5]\d)?)').firstMatch(value);
    if (match == null) return value.trim();
    final raw = match.group(1)!;
    final parts = raw.split(':');
    if (parts.length < 2) return raw;
    final h = (int.tryParse(parts[0]) ?? 0).toString().padLeft(2, '0');
    final m = (int.tryParse(parts[1]) ?? 0).toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String? _extractTimeToken(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final match = RegExp(r'((?:[01]?\d|2[0-3]):[0-5]\d(?:\:[0-5]\d)?)').firstMatch(value);
    if (match == null) return null;
    final raw = match.group(1)!;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final h = (int.tryParse(parts[0]) ?? 0).toString().padLeft(2, '0');
    final m = (int.tryParse(parts[1]) ?? 0).toString().padLeft(2, '0');
    return '$h:$m';
  }

  static bool _isCanceledOrRejected(String status) {
    final s = status.trim().toLowerCase();
    return s == 'otkazano' || s == 'odbijeno';
  }

  static Future<void> syncTrackingStatus({
    required String vozacId,
    required String grad,
    required String polazakVreme,
    required String gpsStatus,
    String? datumIso,
  }) async {
    try {
      final gradUp = grad.trim().toUpperCase();
      final timeNorm = _normalizePolazakTime(polazakVreme);
      if (gradUp.isEmpty || timeNorm.isEmpty) return;

      final now = DateTime.now();
      final fromDate = datumIso ?? DateTime(now.year, now.month, now.day).toIso8601String().split('T').first;
      final toDate = datumIso ??
          DateTime(now.year, now.month, now.day).add(const Duration(days: 1)).toIso8601String().split('T').first;

      final rowsRaw = await supabase
          .from('v3_operativna_nedelja')
          .select('id, datum, grad, dodeljeno_vreme, zeljeno_vreme, status_final, aktivno, putnik_id')
          .eq('vozac_id', vozacId)
          .eq('aktivno', true)
          .gte('datum', fromDate)
          .lte('datum', toDate);

      final rows = (rowsRaw as List).cast<Map<String, dynamic>>();

      String? rowTime(Map<String, dynamic> row) {
        final raw = row['dodeljeno_vreme']?.toString() ?? row['zeljeno_vreme']?.toString();
        return _extractTimeToken(raw);
      }

      final targetIds = rows
          .where((row) {
            if (row['putnik_id'] == null) return false;
            final status = row['status_final']?.toString() ?? '';
            if (_isCanceledOrRejected(status)) return false;
            final rowGrad = (row['grad']?.toString() ?? '').toUpperCase();
            if (rowGrad != gradUp) return false;
            final rt = rowTime(row);
            return rt == timeNorm;
          })
          .map((row) => row['id']?.toString())
          .whereType<String>()
          .toList();

      if (targetIds.isEmpty) return;

      await supabase.from('v3_operativna_nedelja').update({
        'gps_status': gpsStatus,
        'updated_by': 'app:foreground_gps_sync',
        if (gpsStatus == 'tracking') 'notification_sent': true,
      }).inFilter('id', targetIds);
    } catch (e) {
      debugPrint('[V3ForegroundGpsService] syncTrackingStatus error: $e');
    }
  }

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
      _currentPolazakTime = _normalizePolazakTime(polazakVreme);
      _currentPutnici = List.from(putnici);
      _lastAutoStopCheckAt = null;
      _autoStopInProgress = false;
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

      // 6. Sinhronizuj status termina u bazi
      await syncTrackingStatus(
        vozacId: vozacId,
        grad: grad,
        polazakVreme: _currentPolazakTime ?? polazakVreme,
        gpsStatus: 'tracking',
      );

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

    final vozacId = _currentVozacId;
    final grad = _currentGrad;
    final polazakTime = _currentPolazakTime ?? _currentPolazakVreme;

    _isRunning = false;
    _currentVozacId = null;
    _currentGrad = null;
    _currentPolazakVreme = null;
    _currentPolazakTime = null;
    _currentPutnici.clear();
    _lastAutoStopCheckAt = null;
    _autoStopInProgress = false;

    // Zaustavi GPS
    await _stopGpsTracking();

    // Ukloni notification
    await _notifications?.cancel(_notificationId);

    // Zaustavi foreground service
    if (Platform.isAndroid) {
      FlutterBackgroundService().invoke('stop');
    }

    if (vozacId != null &&
        grad != null &&
        polazakTime != null &&
        grad.trim().isNotEmpty &&
        polazakTime.trim().isNotEmpty) {
      await syncTrackingStatus(
        vozacId: vozacId,
        grad: grad,
        polazakVreme: polazakTime,
        gpsStatus: 'pending',
      );
    }

    debugPrint('[V3ForegroundGpsService] Tracking zaustavljen');
  }

  /// Provjeri da li je tracking aktivan
  static bool get isRunning => _isRunning;

  /// Provjeri permissions za GPS i notifikacije
  static Future<bool> _checkPermissions() async {
    final locationStatus = await Permission.locationAlways.status;
    final locationWhenInUse = await Permission.location.status;
    final notificationStatus = await Permission.notification.status;

    if (!locationStatus.isGranted && !locationWhenInUse.isGranted) return false;

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

      _lastHeartbeatSentAt = null;

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

          _lastHeartbeatSentAt = DateTime.now();

          // Pošalji GPS update
          await V3VozacLokacijaService.updateLokacija(
            V3VozacLokacijaUpdate(
              vozacId: _currentVozacId!,
              lat: position.latitude,
              lng: position.longitude,
              bearing: position.heading,
              brzina: position.speed * 3.6, // m/s -> km/h
              grad: _currentGrad ?? '',
              vremePolaska: _currentPolazakTime ?? (_currentPolazakVreme ?? ''),
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

      V3StreamUtils.createPeriodicTimer(
        key: 'foreground_gps_timer',
        period: const Duration(seconds: 30),
        callback: (_) {
          unawaited(_sendHeartbeatGpsUpdate());
          unawaited(checkAutoStop());
        },
      );

      debugPrint('[V3ForegroundGpsService] GPS stream pokrenut');
    } catch (e) {
      debugPrint('[V3ForegroundGpsService] Greška pri pokretanju GPS stream-a: $e');
    }
  }

  static Future<void> _sendHeartbeatGpsUpdate() async {
    if (!_isRunning || _currentVozacId == null) return;

    final now = DateTime.now();
    if (_lastHeartbeatSentAt != null && now.difference(_lastHeartbeatSentAt!) < const Duration(seconds: 20)) {
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      _lastHeartbeatSentAt = now;

      await V3VozacLokacijaService.updateLokacija(
        V3VozacLokacijaUpdate(
          vozacId: _currentVozacId!,
          lat: position.latitude,
          lng: position.longitude,
          bearing: position.heading,
          brzina: position.speed * 3.6,
          grad: _currentGrad ?? '',
          vremePolaska: _currentPolazakTime ?? (_currentPolazakVreme ?? ''),
          aktivno: true,
        ),
      );
    } catch (e) {
      debugPrint('[V3ForegroundGpsService] Heartbeat GPS update greška: $e');
    }
  }

  /// Zaustavlja GPS poziciju streaming
  static Future<void> _stopGpsTracking() async {
    V3StreamUtils.cancelSubscription('foreground_gps_service_gps');
    V3StreamUtils.cancelTimer('foreground_gps_timer');
    _lastHeartbeatSentAt = null;
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
    if (!_isRunning || _autoStopInProgress) return;

    final vozacId = _currentVozacId;
    final grad = (_currentGrad ?? '').trim().toUpperCase();
    final vreme = (_currentPolazakTime ?? _currentPolazakVreme ?? '').trim();

    if (vozacId == null || grad.isEmpty || vreme.isEmpty) return;

    final now = DateTime.now();
    if (_lastAutoStopCheckAt != null && now.difference(_lastAutoStopCheckAt!) < const Duration(seconds: 20)) {
      return;
    }
    _lastAutoStopCheckAt = now;

    _autoStopInProgress = true;
    try {
      final fromDate = DateTime(now.year, now.month, now.day).toIso8601String().split('T').first;
      final toDate =
          DateTime(now.year, now.month, now.day).add(const Duration(days: 1)).toIso8601String().split('T').first;

      final rowsRaw = await supabase
          .from('v3_operativna_nedelja')
          .select('id, datum, grad, dodeljeno_vreme, zeljeno_vreme, status_final, aktivno, putnik_id, pokupljen')
          .eq('vozac_id', vozacId)
          .eq('aktivno', true)
          .gte('datum', fromDate)
          .lte('datum', toDate);

      final rows = (rowsRaw as List).cast<Map<String, dynamic>>();

      String? rowTime(Map<String, dynamic> row) {
        final raw = row['dodeljeno_vreme']?.toString() ?? row['zeljeno_vreme']?.toString();
        return _extractTimeToken(raw);
      }

      final relevantRows = rows.where((row) {
        if (row['putnik_id'] == null) return false;
        final status = row['status_final']?.toString() ?? '';
        if (_isCanceledOrRejected(status)) return false;
        final rowGrad = (row['grad']?.toString() ?? '').toUpperCase();
        if (rowGrad != grad) return false;
        final rt = rowTime(row);
        return rt == _normalizePolazakTime(vreme);
      }).toList();

      if (relevantRows.isEmpty) return;

      final allPickedUp = relevantRows.every((row) => row['pokupljen'] == true);
      if (!allPickedUp) return;

      debugPrint('[V3ForegroundGpsService] Auto-stop: svi putnici su pokupljeni, gasim tracking');
      await stopTracking();
    } catch (e) {
      debugPrint('[V3ForegroundGpsService] checkAutoStop error: $e');
    } finally {
      _autoStopInProgress = false;
    }
  }

  /// Javni interfejs za notification action handling
  static Future<void> handleNotificationAction(String action, String? payload) async {
    if (action == 'stop_tracking') {
      await stopTracking();
    }
  }
}
