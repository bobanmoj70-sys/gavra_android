import 'dart:async';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

/// 🛰️ GPS FOREGROUND SERVICE
/// Drži GPS tracking aktivan dok vozač pokupi sve putnike ili klikne STOP.
/// Prikazuje persistentnu notifikaciju u status baru (kao Waze).
/// OS ne može ubiti proces dok je notifikacija vidljiva.

const _kNotificationChannelId = 'gavra_gps_tracking';
const _kNotificationId = 888;

/// Ključevi za poruke između UI i background isolate-a
class GpsServiceKeys {
  static const start = 'start';
  static const stop = 'stop';
  static const updateNotification = 'update_notification';
  static const locationUpdate = 'location_update';
  static const allPickedUp = 'all_picked_up';

  // Data keys
  static const vozacIme = 'vozac_ime';
  static const grad = 'grad';
  static const vreme = 'vreme';
  static const lat = 'lat';
  static const lng = 'lng';
  static const notifBody = 'notif_body';
}

class GpsForegroundService {
  GpsForegroundService._();

  static final _service = FlutterBackgroundService();
  static bool _initialized = false;

  /// 🚀 Inicijalizacija — poziva se jednom pri startu app-a (main.dart)
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    const androidNotifChannel = AndroidNotificationChannel(
      _kNotificationChannelId,
      'Gavra GPS Tracking',
      description: 'Aktivna ruta — vozač prati putnike',
      importance: Importance.low, // Low = tiha notifikacija, bez zvuka
      playSound: false,
      enableVibration: false,
    );

    final plugin = FlutterLocalNotificationsPlugin();
    await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidNotifChannel);

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false, // Pokrećemo ručno pri kliku na START
        isForegroundMode: true,
        notificationChannelId: _kNotificationChannelId,
        initialNotificationTitle: '🚌 Gavra 013',
        initialNotificationContent: 'GPS tracking se pokreće...',
        foregroundServiceNotificationId: _kNotificationId,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  /// 📍 Pokreni foreground service
  static Future<void> startService({
    required String vozacIme,
    required String grad,
    required String vreme,
  }) async {
    await _service.startService();
    // Prosledi podatke background isolate-u
    _service.invoke(GpsServiceKeys.start, {
      GpsServiceKeys.vozacIme: vozacIme,
      GpsServiceKeys.grad: grad,
      GpsServiceKeys.vreme: vreme,
    });
  }

  /// 🛑 Zaustavi foreground service
  static Future<void> stopService() async {
    _service.invoke(GpsServiceKeys.stop);
  }

  /// 📝 Ažuriraj tekst notifikacije (npr. "Sledeći: Marko — 7 min")
  static void updateNotificationText(String body) {
    _service.invoke(GpsServiceKeys.updateNotification, {
      GpsServiceKeys.notifBody: body,
    });
  }

  /// 📡 Stream GPS pozicija iz background isolate-a
  static Stream<Map<String, dynamic>?> get locationStream => _service.on(GpsServiceKeys.locationUpdate);

  /// 📡 Stream — svi putnici pokupljeni (auto-stop)
  static Stream<Map<String, dynamic>?> get allPickedUpStream => _service.on(GpsServiceKeys.allPickedUp);

  static bool get isRunning => _initialized;
}

// ═══════════════════════════════════════════════════════════════════
// BACKGROUND ISOLATE — radi odvojeno od UI threada
// ═══════════════════════════════════════════════════════════════════

/// iOS background handler (mora biti top-level funkcija)
@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  return true;
}

/// Glavni background entry point (mora biti top-level funkcija)
@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final plugin = FlutterLocalNotificationsPlugin();
  String _vozacIme = 'Vozač';
  String _grad = '';
  String _vreme = '';
  StreamSubscription<Position>? _positionSub;
  Timer? _notifUpdateTimer;

  // Helper: ažuriraj notifikaciju
  void _updateNotif(String body) {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: '🚌 Gavra 013 — GPS aktivan',
        content: body,
      );
    }
  }

  // Primi START komandu sa podacima o vozaču
  service.on(GpsServiceKeys.start).listen((data) async {
    if (data == null) return;
    _vozacIme = data[GpsServiceKeys.vozacIme] ?? 'Vozač';
    _grad = data[GpsServiceKeys.grad] ?? '';
    _vreme = data[GpsServiceKeys.vreme] ?? '';

    _updateNotif('$_vozacIme — $_grad $_vreme');

    // Pokreni GPS stream svakih 30s
    _positionSub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 30),
      ),
    ).listen((position) {
      // Pošalji poziciju nazad u UI isolate
      service.invoke(GpsServiceKeys.locationUpdate, {
        GpsServiceKeys.lat: position.latitude,
        GpsServiceKeys.lng: position.longitude,
      });
    });
  });

  // Primi STOP komandu
  service.on(GpsServiceKeys.stop).listen((_) async {
    _positionSub?.cancel();
    await service.stopSelf();
  });

  // Ažuriranje teksta notifikacije
  service.on(GpsServiceKeys.updateNotification).listen((data) {
    if (data == null) return;
    final body = data[GpsServiceKeys.notifBody] as String?;
    if (body != null) _updateNotif(body);
  });
}
