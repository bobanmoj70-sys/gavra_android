import 'dart:async';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';

/// V2BackgroundGpsService
/// Foreground service koji drži GPS tracking aktivan dok je app u pozadini.
/// Vozač može otvoriti HERE WeGo ili drugu app, a lokacija se nastavlja slati.
///
/// ARHITEKTURA:
/// - flutter_background_service pokreće zasebni Dart isolate kao Android foreground service
/// - Entry point: _onBackgroundServiceStart() — inicijalizuje Supabase i GPS stream
/// - Komunikacija sa glavnim izolateom: ServiceInstance poruke (`Map<String, dynamic>`)
/// - Lokacija se šalje u Supabase svake 30s (isti interval kao V2RealtimeGpsService)
///
/// POKRETANJE/ZAUSTAVLJANJE:
/// - start(): poziva se iz V2DriverLocationService.v2StartTracking()
/// - stop(): poziva se iz V2DriverLocationService.v2StopTracking()
/// - updateEta(): ažurira ETA bez restarta servisa (kad se pokupi putnik)

class V2BackgroundGpsService {
  V2BackgroundGpsService._();

  static const String _notifChannelId = 'gavra_gps_fg';
  static const String _notifChannelName = 'Gavra GPS Tracking';
  static const int _notifId = 9002;

  // Poruke između izolata
  static const String _msgStop = 'stop';
  static const String _msgUpdateEta = 'update_eta';
  static const String _msgUpdateNotif = 'update_notif';

  /// Inicijalizuj flutter_background_service (jednom pri startu app-a u main.dart)
  static Future<void> initialize() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onBackgroundServiceStart,
        autoStart: false, // Ne startaj automatski pri boot-u
        isForegroundMode: true,
        notificationChannelId: _notifChannelId,
        initialNotificationTitle: '🚌 Gavra 013',
        initialNotificationContent: 'GPS tracking aktivan',
        foregroundServiceNotificationId: _notifId,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
      ),
    );
  }

  /// Pokreni foreground service sa podacima vozača
  static Future<void> start({
    required String vozacId,
    required String grad,
    required String vremePolaska,
    required String smer,
    Map<String, int>? putniciEta,
    List<String>? putniciRedosled,
  }) async {
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (isRunning) return;

    await service.startService();

    // Kratka pauza da se isolat inicijalizuje
    await Future.delayed(const Duration(milliseconds: 300));

    // Pošalji podatke vozača background isolatu
    service.invoke('init', {
      'vozac_id': vozacId,
      'grad': grad,
      'vreme_polaska': vremePolaska,
      'smer': smer,
      'putnici_eta': putniciEta,
      'putnici_redosled': putniciRedosled,
    });
  }

  /// Zaustavi foreground service
  static Future<void> stop() async {
    final service = FlutterBackgroundService();
    service.invoke(_msgStop);
  }

  /// Ažuriraj ETA putnika bez restarta servisa
  static Future<void> updateEta(Map<String, int> putniciEta) async {
    final service = FlutterBackgroundService();
    service.invoke(_msgUpdateEta, {'putnici_eta': putniciEta});
  }

  /// Ažuriraj tekst notifikacije (npr. "Preostalo putnika: 3")
  static Future<void> updateNotification(String grad, String vreme, int putniciCount) async {
    final service = FlutterBackgroundService();
    service.invoke(_msgUpdateNotif, {
      'grad': grad,
      'vreme': vreme,
      'putnici_count': putniciCount,
    });
  }

  /// Provjeri da li service radi
  static Future<bool> isRunning() async {
    return await FlutterBackgroundService().isRunning();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BACKGROUND ISOLATE ENTRY POINT
// Pokreće se u zasebnom Dart isolatu kao Android foreground service.
// Ne može direktno koristiti state iz glavnog izolata.
// ─────────────────────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
Future<void> _onBackgroundServiceStart(ServiceInstance service) async {
  // Inicijalizuj Supabase u background isolatu
  String? supabaseUrl;
  String? supabaseAnonKey;

  try {
    await configService.initializeBasic();
    supabaseUrl = configService.getSupabaseUrl();
    supabaseAnonKey = configService.getSupabaseAnonKey();
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  } catch (e) {
    // Ne može bez Supabase — zaustavi service
    service.stopSelf();
    return;
  }

  final supabaseClient = Supabase.instance.client;

  // State u background isolatu
  String? vozacId;
  String? grad;
  String? vremePolaska;
  String? smer;
  Map<String, int>? putniciEta;
  bool isSending = false;

  // Notifikacija plugin (ažuriranje teksta ongoing notifikacije)
  final notifPlugin = FlutterLocalNotificationsPlugin();
  await notifPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          V2BackgroundGpsService._notifChannelId,
          V2BackgroundGpsService._notifChannelName,
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
        ),
      );

  // GPS stream — update svakih 30s
  StreamSubscription<Position>? gpsSub;

  Future<void> sendLocation(Position position) async {
    if (vozacId == null || isSending) return;
    isSending = true;
    try {
      await supabaseClient.from('v2_vozac_lokacije').upsert({
        'vozac_id': vozacId,
        'lat': position.latitude,
        'lng': position.longitude,
        'grad': grad,
        'vreme_polaska': vremePolaska,
        'smer': smer,
        'aktivan': true,
        'putnici_eta': putniciEta,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'vozac_id');
    } catch (_) {
      // Tiha greška — ne ubijaj service zbog jednog neuspjelog upisa
    } finally {
      isSending = false;
    }
  }

  void startGpsStream() {
    gpsSub?.cancel();
    gpsSub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: Duration(seconds: 30),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationChannelName: V2BackgroundGpsService._notifChannelName,
          notificationTitle: '🚌 Gavra 013',
          notificationText: 'GPS tracking aktivan',
          notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
          enableWakeLock: true,
        ),
      ),
    ).listen(
      (position) => sendLocation(position),
      onError: (_) {}, // Nastavi rad i pri GPS grešci
    );
  }

  // Slušaj poruke iz glavnog izolata
  service.on('init').listen((data) {
    if (data == null) return;
    vozacId = data['vozac_id'] as String?;
    grad = data['grad'] as String?;
    vremePolaska = data['vreme_polaska'] as String?;
    smer = data['smer'] as String?;
    final etaRaw = data['putnici_eta'];
    if (etaRaw is Map) {
      putniciEta = etaRaw.map((k, v) => MapEntry(k.toString(), v as int));
    }
    startGpsStream();
  });

  service.on(V2BackgroundGpsService._msgUpdateEta).listen((data) {
    if (data == null) return;
    final etaRaw = data['putnici_eta'];
    if (etaRaw is Map) {
      putniciEta = etaRaw.map((k, v) => MapEntry(k.toString(), v as int));
    }
  });

  service.on(V2BackgroundGpsService._msgUpdateNotif).listen((data) {
    if (data == null) return;
    final g = data['grad'] as String? ?? '';
    final v = data['vreme'] as String? ?? '';
    final count = data['putnici_count'] as int? ?? 0;
    notifPlugin.show(
      V2BackgroundGpsService._notifId,
      '🚌 Gavra 013 — $g $v',
      count > 0 ? 'Preostalo putnika: $count' : 'GPS tracking aktivan',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          V2BackgroundGpsService._notifChannelId,
          V2BackgroundGpsService._notifChannelName,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          playSound: false,
          enableVibration: false,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  });

  service.on(V2BackgroundGpsService._msgStop).listen((_) async {
    await gpsSub?.cancel();
    // Označi vozača kao neaktivnog u Supabase
    if (vozacId != null) {
      try {
        await supabaseClient.from('v2_vozac_lokacije').update({
          'aktivan': false,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('vozac_id', vozacId!);
      } catch (_) {}
    }
    service.stopSelf();
  });
}
