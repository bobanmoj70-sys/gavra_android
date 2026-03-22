import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart' as fcm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_api_availability/google_api_availability.dart';
import 'package:huawei_push/huawei_push.dart' as hms;
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'globals.dart';
import 'screens/v3_putnik_profil_screen.dart';
import 'screens/v3_welcome_screen.dart';
import 'services/realtime/v3_master_realtime_manager.dart';
import 'services/v2_theme_manager.dart';
import 'services/v3/v3_foreground_gps_service.dart';
import 'services/v3/v3_putnik_service.dart';
import 'services/v3/v3_zahtev_service.dart';

// Globalna instanca za lokalne notifikacije
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // KONFIGURACIJA - Inicijalizuj osnovne kredencijale (bez Supabase)
  try {
    await configService.initializeBasic();
  } catch (e) {
    // Critical error - cannot continue without credentials
    throw Exception('Ne mogu da inicijalizujem osnovne kredencijale: $e');
  }

  // SUPABASE - Inicijalizuj sa osnovnim kredencijalima
  try {
    await Supabase.initialize(
      url: configService.getSupabaseUrl(),
      anonKey: configService.getSupabaseAnonKey(),
    );
  } catch (e) {
    debugPrint('âŒ [main] Supabase.initialize greška: $e');
  }

  // 1. Pokreni V3 Realtime Manager ODMAH (prije UI-a, da ima max vremena za fetch)
  unawaited(V3MasterRealtimeManager.instance
      .initV3()
      .catchError((Object e) => debugPrint('❌ [main] V3MasterRealtimeManager.initV3 greška: $e')));

  // 2. ✨ FIREBASE - Inicijalizuj SINHRONO pre UI-ja (rešava FCM token grešku)
  await _initFirebaseSync();

  // 3. Pokreni UI tek kad je Firebase spreman
  runApp(const MyApp());

  // 4. Čekaj malo da se UI renderira, pa tek onda inicijalizuj ostale servise
  unawaited(Future<void>.delayed(const Duration(milliseconds: 500), _doStartupTasks));
}

/// Pozadinske inicijalizacije koje ne smeju da blokiraju UI
Future<void> _doStartupTasks() async {
  // Wakelock i edge-to-edge UI
  try {
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  } catch (e) {
    debugPrint('âš ï¸ [main] Wakelock/SystemChrome greška: $e');
  }

  // Locale - UTF-8 podrska za dijakritiku
  unawaited(initializeDateFormatting('sr', null));

  // Sve ostalo pokreni istovremeno (paralelno)
  unawaited(_initNotificationHandlers()); // Samo notification handlers, Firebase je već inicijalizovan
  unawaited(_initAppServices());
}

/// ✨ NOVA: Hibridna push inicijalizacija (FCM + HMS) u main() funkciji
Future<void> _initFirebaseSync() async {
  try {
    // 1. Provjeri Google Play Services (FCM)
    final gmsAvailability =
        await GoogleApiAvailability.instance.checkGooglePlayServicesAvailability().timeout(const Duration(seconds: 2));

    bool fcmInitialized = false;
    if (gmsAvailability == GooglePlayServicesAvailability.success) {
      try {
        await Firebase.initializeApp().timeout(const Duration(seconds: 5));
        debugPrint('✅ [FCM] Firebase inicijalizovan - GMS dostupan');
        fcmInitialized = true;
      } catch (e) {
        debugPrint('⚠️ [FCM] Init greška: $e');
      }
    } else {
      debugPrint('⚠️ [FCM] Google Play Services nedostupan: $gmsAvailability');
    }

    // 2. Provjeri HMS (Huawei Push Kit)
    bool hmsInitialized = false;
    try {
      hms.Push.localNotification;
      debugPrint('✅ [HMS] Huawei Push Kit dostupan');
      hmsInitialized = true;
    } catch (e) {
      debugPrint('⚠️ [HMS] Huawei Push Kit nedostupan: $e');
    }

    // 3. Loguj rezultat hibridne inicijalizacije
    if (fcmInitialized && hmsInitialized) {
      debugPrint('🎯 [HYBRID] Oba push sistema dostupna (FCM + HMS)');
    } else if (fcmInitialized) {
      debugPrint('🟢 [HYBRID] Samo FCM dostupan (Google/Samsung/Xiaomi uređaj)');
    } else if (hmsInitialized) {
      debugPrint('🟠 [HYBRID] Samo HMS dostupan (Huawei uređaj)');
    } else {
      debugPrint('🔴 [HYBRID] Nijedan push sistem nije dostupan!');
    }
  } catch (e) {
    debugPrint('⚠️ [HYBRID] Greška u hibridnoj inicijalizaciji: $e');
  }
}

/// Inicijalizacija Notification handlers (Hibridni FCM + HMS)
Future<void> _initNotificationHandlers() async {
  try {
    // 🔔 Zahtevaj notifikacijske dozvole na Android 13+
    if (Platform.isAndroid) {
      try {
        final status = await Permission.notification.request();
        debugPrint('📱 Notification permission: $status');
      } catch (e) {
        debugPrint('⚠️ Notification permission request error: $e');
      }
    }

    // 1. FCM Handlers (ako je Firebase inicijalizovan)
    try {
      // Provjeri da li je Firebase dostupan
      final gmsAvailability = await GoogleApiAvailability.instance.checkGooglePlayServicesAvailability();
      if (gmsAvailability == GooglePlayServicesAvailability.success) {
        // Postavi FCM background handler
        fcm.FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

        // FCM Foreground handler
        fcm.FirebaseMessaging.onMessage.listen(_handleIncomingMessage);
        debugPrint('✅ [FCM] Handlers konfigurisani');
      }
    } catch (e) {
      debugPrint('⚠️ [FCM] Handler setup greška: $e');
    }

    // 2. HMS Handlers (za Huawei uređaje)
    try {
      // HMS Token listener
      hms.Push.getTokenStream.listen((String token) {
        debugPrint('🟠 [HMS] Novi token: $token');
        _saveHmsTokenToDatabase(token);
      });

      // HMS Message listener
      hms.Push.onMessageReceivedStream.listen((hms.RemoteMessage message) {
        debugPrint('🟠 [HMS] Poruka primljena: ${message.data}');
        _handleHmsIncomingMessage(message);
      });

      // Forsirati refresh tokena
      try {
        hms.Push.getToken(""); // Trigger token generation (void return)
        debugPrint('🟠 [HMS] Token generation pokrenut');
      } catch (e) {
        debugPrint('⚠️ [HMS] Greška pri pokretanju tokena: $e');
      }

      debugPrint('✅ [HMS] Handlers konfigurisani');
    } catch (e) {
      debugPrint('⚠️ [HMS] Handler setup greška: $e');
    }

    // 3. Inicijalizuj Local Notifications (za interaktivne gumbe)
    try {
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);

      await flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: onNotificationTap,
        onDidReceiveBackgroundNotificationResponse: onNotificationTap,
      );

      // Kreiraj Android notification kanal (mora da postoji da bi FCM isporučio)
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'gavra_push_v2',
        'Gavra obaveštenja',
        description: 'Obaveštenja o statusu zahteva',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      debugPrint('✅ [Push] Notification handlers konfigurisani');
    } catch (e) {
      debugPrint('⚠️ [Push] Notification handlers greška: $e');
    }
  } catch (e) {
    debugPrint('⚠️ [Push] Opšta greška: $e');
  }
}

/// Pozadinski hendler za Firebase poruke (MORA BITI TOP-LEVEL FUNKCIJA)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(fcm.RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("🔔 [FCM] Background poruka primljena: ${message.messageId}");
  debugPrint("🔔 [FCM] Title: ${message.notification?.title}");
  debugPrint("🔔 [FCM] Body: ${message.notification?.body}");
  debugPrint("🔔 [FCM] Data: ${message.data}");
  await _showAlternativaNotification(message);
}

/// Foreground handler za FCM
Future<void> _handleIncomingMessage(fcm.RemoteMessage message) async {
  debugPrint("📱 [FCM] Foreground poruka: ${message.messageId}");
  debugPrint("📱 [FCM] Title: ${message.notification?.title}");
  debugPrint("📱 [FCM] Body: ${message.notification?.body}");
  debugPrint("📱 [FCM] Data: ${message.data}");

  // Provjeri tip notifikacije
  final type = message.data['type'] as String?;
  if (type == 'gps_tracking_start') {
    await _handleGpsTrackingStart(message.data);
  } else if (type == 'gps_tracking_complete') {
    await _handleGpsTrackingComplete(message.data);
  } else if (type == 'v3_putnik_eta_start') {
    await _handlePutnikEtaStart(message.data);
  } else {
    await _showAlternativaNotification(message);
  }
}

/// Rukovanje GPS tracking start notifikacijom
Future<void> _handleGpsTrackingStart(Map<String, dynamic> data) async {
  final vozacId = data['vozac_id'] as String?;
  final polazakVreme = data['polazak_vreme'] as String?;
  final putniciBroj = int.tryParse('${data['putnici_count'] ?? 0}') ?? 0;

  if (vozacId == null || polazakVreme == null) {
    debugPrint('⚠️ [GPS] Nedostaju podaci u notification: vozacId=$vozacId, polazak=$polazakVreme');
    return;
  }

  // Prikaži notification sa Auto Start dugmetom
  final androidDetails = AndroidNotificationDetails(
    'gavra_gps_auto',
    'GPS Auto Start',
    channelDescription: 'Automatsko pokretanje GPS trackinga',
    importance: Importance.max,
    priority: Priority.high,
    actions: [
      AndroidNotificationAction(
        'auto_start_gps',
        '🚗 Pokreni GPS',
        showsUserInterface: false,
      ),
      AndroidNotificationAction(
        'dismiss_gps',
        '❌ Odbaci',
        showsUserInterface: false,
      ),
    ],
  );

  await flutterLocalNotificationsPlugin.show(
    999, // Fixed ID za GPS tracking
    '🚗 GPS Tracking',
    'Kreće za 15 min ($putniciBroj putnika) - Pokreni GPS tracking?',
    NotificationDetails(android: androidDetails),
    payload: 'gps_auto_start:$vozacId:$polazakVreme',
  );

  debugPrint('📍 [GPS] Auto start notification prikazana za vozača $vozacId');
}

/// Putnik: vozač je krenuo, ETA/live tracking aktivan
Future<void> _handlePutnikEtaStart(Map<String, dynamic> data) async {
  final title = data['title'] as String? ?? '🚗 Vozač je krenuo';
  final body = data['body'] as String? ?? 'ETA tracking je aktivan. Pratite dolazak uživo.';

  const androidDetails = AndroidNotificationDetails(
    'gavra_push_v2',
    'Gavra obaveštenja',
    importance: Importance.max,
    priority: Priority.high,
  );

  await flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecondsSinceEpoch.remainder(100000),
    title,
    body,
    const NotificationDetails(android: androidDetails),
    payload: 'putnik_eta_start:${data['putnik_id'] ?? ''}',
  );
}

/// Vozač: svi pokupljeni → ugasi foreground GPS tracking
Future<void> _handleGpsTrackingComplete(Map<String, dynamic> data) async {
  final shouldStop = '${data['action_stop_foreground'] ?? ''}'.toLowerCase() == 'true';

  if (!shouldStop) return;

  await V3ForegroundGpsService.stopTracking();

  const androidDetails = AndroidNotificationDetails(
    'gavra_gps_success',
    'GPS Success',
    importance: Importance.high,
    priority: Priority.high,
  );

  await flutterLocalNotificationsPlugin.show(
    890,
    '✅ GPS tracking završen',
    'Svi putnici su pokupljeni. Tracking je automatski zaustavljen.',
    const NotificationDetails(android: androidDetails),
  );
}

/// ✨ NOVO: HMS Message handler
Future<void> _handleHmsIncomingMessage(hms.RemoteMessage message) async {
  debugPrint("📱 [HMS] Foreground poruka primljena");
  debugPrint("📱 [HMS] Data: ${message.data}");

  // Direktno pozovi notification funkciju sa HMS data podacima
  await _showHmsNotification(message);
}

/// ✨ NOVO: HMS Notification handler
Future<void> _showHmsNotification(hms.RemoteMessage message) async {
  // Izvuci data iz HMS poruke
  final String? rawData = message.data;
  if (rawData == null || rawData.isEmpty) {
    debugPrint("⚠️ [HMS] Nema data u poruci");
    return;
  }

  // Parsiraj JSON data (HMS šalje kao string)
  Map<String, dynamic> data;
  try {
    // Pokušaj da parsiraj kao JSON string
    if (rawData.startsWith('{')) {
      data = Map<String, dynamic>.from(jsonDecode(rawData) as Map<String, dynamic>);
    } else {
      // Fallback: tretiraj kao običan string podatak
      data = {'message': rawData};
    }
  } catch (e) {
    debugPrint("⚠️ [HMS] Greška u parsiranju data: $e");
    return;
  }

  if (data['type'] != 'v3_alternativa') return;

  final id = data['id'] as String? ?? '';
  final altPre = data['alt_pre'] as String?;
  final altPosle = data['alt_posle'] as String?;
  final title = data['title'] as String? ?? '⚠️ Termin pun';
  final body = data['body'] as String? ?? 'Izaberi alternativni termin';

  final actions = <AndroidNotificationAction>[
    if (altPre != null) AndroidNotificationAction('accept_pre', '✅ $altPre', showsUserInterface: false),
    if (altPosle != null) AndroidNotificationAction('accept_posle', '✅ $altPosle', showsUserInterface: false),
    AndroidNotificationAction('decline', '❌ Odbaci', showsUserInterface: false),
  ];

  final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'gavra_push_v2',
    'Gavra obaveštenja',
    channelDescription: 'Obaveštenja o statusu zahteva',
    importance: Importance.max,
    priority: Priority.high,
    actions: actions,
    styleInformation: BigTextStyleInformation(''),
  );

  await flutterLocalNotificationsPlugin.show(
    id.hashCode,
    title,
    body,
    NotificationDetails(android: androidDetails),
    payload: 'hms_alternativa:$id',
  );

  debugPrint('🟠 [HMS] Notification prikazana za ID: $id');
}

/// Prikazuje lokalnu notifikaciju sa akcijskim dugmadima za v3_alternativa
Future<void> _showAlternativaNotification(fcm.RemoteMessage message) async {
  final data = message.data;
  if (data['type'] != 'v3_alternativa') return;

  final id = data['id'] as String? ?? '';
  final altPre = data['alt_pre'] as String?;
  final altPosle = data['alt_posle'] as String?;
  final title = data['title'] as String? ?? '⚠️ Termin pun';
  final body = data['body'] as String? ?? 'Izaberi alternativni termin';

  final actions = <AndroidNotificationAction>[
    if (altPre != null)
      AndroidNotificationAction(
        'accept_pre',
        '✅ $altPre',
        showsUserInterface: false,
      ),
    if (altPosle != null)
      AndroidNotificationAction(
        'accept_posle',
        '✅ $altPosle',
        showsUserInterface: false,
      ),
    AndroidNotificationAction(
      'reject',
      '❌ Odbij',
      showsUserInterface: false,
    ),
  ];

  final androidDetails = AndroidNotificationDetails(
    'gavra_push_v2',
    'Gavra obaveštenja',
    importance: Importance.max,
    priority: Priority.high,
    actions: actions,
  );

  await flutterLocalNotificationsPlugin.show(
    id.hashCode,
    title,
    body,
    NotificationDetails(android: androidDetails),
    payload: '$id|${altPre ?? ''}|${altPosle ?? ''}',
  );
}

// Hendler za klik na interaktivne gumbe (actions)
@pragma('vm:entry-point')
void onNotificationTap(NotificationResponse response) async {
  final String? payload = response.payload;
  final String? actionId = response.actionId;

  if (payload == null) return;

  // Tap na samu notifikaciju (bez action dugmeta) za putnik ETA flow
  if (payload.startsWith('putnik_eta_start')) {
    await _openPutnikProfilFromNotification(payload);
    return;
  }

  if (actionId == null) return;

  debugPrint('Notification Action Clicked: $actionId, Payload: $payload');

  // Cold start — Supabase možda nije inicijalizovan
  if (!isSupabaseReady) {
    try {
      await configService.initializeBasic();
      await Supabase.initialize(
        url: configService.getSupabaseUrl(),
        anonKey: configService.getSupabaseAnonKey(),
      );
    } catch (e) {
      debugPrint('[onNotificationTap] Supabase init greška: $e');
      return;
    }
  }

  try {
    // GPS Auto Start handling
    if (payload.startsWith('gps_auto_start:') && actionId == 'auto_start_gps') {
      final parts = payload.split(':');
      if (parts.length >= 3) {
        final vozacId = parts[1];
        final polazakVreme = parts[2];
        await _triggerAutoGpsStart(vozacId, polazakVreme);
      }
      return;
    }

    // V3 alternativa handling
    // payload format: "id|altPre|altPosle"
    final parts = payload.split('|');
    final zahtevId = parts[0];
    final altPre = parts.length > 1 ? parts[1] : '';
    final altPosle = parts.length > 2 ? parts[2] : '';

    if (actionId == 'accept_pre' && altPre.isNotEmpty) {
      await V3ZahtevService.prihvatiPonudu(zahtevId, altPre);
    } else if (actionId == 'accept_posle' && altPosle.isNotEmpty) {
      await V3ZahtevService.prihvatiPonudu(zahtevId, altPosle);
    } else if (actionId == 'reject') {
      await V3ZahtevService.odbijPonudu(zahtevId);
    }
  } catch (e) {
    debugPrint('[onNotificationTap] Greška pri obradi akcije: $e');
  }
}

Future<void> _openPutnikProfilFromNotification(String payload) async {
  try {
    if (!isSupabaseReady) {
      await configService.initializeBasic();
      await Supabase.initialize(
        url: configService.getSupabaseUrl(),
        anonKey: configService.getSupabaseAnonKey(),
      );
    }

    final nav = navigatorKey.currentState;
    if (nav == null) {
      debugPrint('⚠️ [Push] Ne mogu da otvorim putnik profil (nema navigatora).');
      return;
    }

    Map<String, dynamic>? putnikData = V3PutnikService.currentPutnik;

    // 1) Payload id fallback: putnik_eta_start:<putnik_id>
    final parts = payload.split(':');
    final payloadPutnikId = parts.length > 1 ? parts[1] : '';
    if ((putnikData == null) && payloadPutnikId.isNotEmpty) {
      putnikData = V3MasterRealtimeManager.instance.getPutnik(payloadPutnikId);
      putnikData ??=
          await supabase.from('v3_putnici').select().eq('id', payloadPutnikId).eq('aktivno', true).maybeSingle();
    }

    // 2) FCM token fallback: nađi putnika po push_token
    if (putnikData == null) {
      final token = await fcm.FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        putnikData =
            await supabase.from('v3_putnici').select().eq('push_token', token).eq('aktivno', true).maybeSingle();
      }
    }

    // 3) Cache refresh fallback
    if (putnikData == null) {
      await V3MasterRealtimeManager.instance.initV3();
      final token = await fcm.FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        putnikData = V3MasterRealtimeManager.instance.putniciCache.values
            .cast<Map<String, dynamic>?>()
            .firstWhere((p) => p != null && p['aktivno'] == true && p['push_token'] == token, orElse: () => null);
      }
    }

    if (putnikData == null) {
      debugPrint('⚠️ [Push] Ne mogu da otvorim putnik profil (putnik nije pronađen).');
      return;
    }

    final resolvedPutnikData = Map<String, dynamic>.from(putnikData);
    V3PutnikService.currentPutnik = resolvedPutnikData;

    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => V3PutnikProfilScreen(
          putnikData: resolvedPutnikData,
        ),
      ),
    );
  } catch (e) {
    debugPrint('❌ [Push] Greška pri otvaranju putnik profila: $e');
  }
}

/// Pokreće GPS tracking iz background notification
Future<void> _triggerAutoGpsStart(String vozacId, String polazakVreme) async {
  try {
    // NOVO: Pozovi SQL funkciju za auto GPS start
    final result = await Supabase.instance.client.rpc('fn_v3_trigger_auto_gps_start', params: {
      'p_vozac_id': vozacId,
      'p_polazak_vreme': polazakVreme,
    });

    if (result != null && result['success'] == true) {
      debugPrint('✅ [GPS AutoStart] ${result['message']}');

      // Prikaži success notification
      await flutterLocalNotificationsPlugin.show(
        888,
        '✅ GPS Automatski Pokrenut',
        '${result['vozac_ime']} - ${result['grad']} ${result['vreme']} (${result['putnici_count']} putnika)',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'gavra_gps_success',
            'GPS Success',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
      );

      // Pozovi V3ForegroundGpsService za stvarni GPS tracking
      final success = await V3ForegroundGpsService.startTracking(
        vozacId: vozacId,
        vozacIme: result['vozac_ime'] ?? 'Vozač',
        polazakVreme: '${result['grad']} ${result['vreme']}',
        putnici: [], // Simplified - dodati parsing ako potrebno
        grad: result['grad'] ?? 'BC',
      );

      if (!success) {
        debugPrint('❌ [GPS AutoStart] Failed to start foreground GPS service');
      }
    } else {
      debugPrint('❌ [GPS AutoStart] SQL function failed: ${result?['message']}');
    }
  } catch (e) {
    debugPrint('❌ [GPS AutoStart] Error: $e');

    // Fallback na stari sistem ako nova funkcija ne radi
    await _triggerAutoGpsStartFallback(vozacId, polazakVreme);
  }
}

/// Fallback - stari sistem za auto GPS start
Future<void> _triggerAutoGpsStartFallback(String vozacId, String polazakVreme) async {
  try {
    // Učitaj vozača
    final vozacData =
        await Supabase.instance.client.from('v3_vozaci').select('id, ime_prezime').eq('id', vozacId).maybeSingle();

    if (vozacData == null) {
      debugPrint('⚠️ [GPS AutoStart Fallback] Vozač not found: $vozacId');
      return;
    }

    debugPrint('⚠️ [GPS AutoStart Fallback] Onemogućen - koristi novi v3_gps_raspored sistem');
    return;
  } catch (e) {
    debugPrint('❌ [GPS AutoStart Fallback] Error: $e');
  }
}

/// Inicijalizacija ostalih servisa
Future<void> _initAppServices() async {
  // Inicijalizuj V3 Foreground GPS Service
  try {
    await V3ForegroundGpsService.initialize();
    debugPrint('✅ [main] V3ForegroundGpsService inicijalizovan');
  } catch (e) {
    debugPrint('⚠️ [main] V3ForegroundGpsService greška: $e');
  }

  // Učitaj nav_bar_type + verziju iz baze
  try {
    final settings = await Supabase.instance.client
        .from('v3_app_settings')
        .select('nav_bar_type, min_version, latest_version, store_url_android, store_url_huawei, store_url_ios')
        .eq('id', 'global')
        .maybeSingle();

    // 1. nav_bar_type
    final navType = settings?['nav_bar_type'] as String?;
    if (navType != null && ['zimski', 'letnji', 'praznici'].contains(navType)) {
      navBarTypeNotifier.value = navType;
      debugPrint('[main] nav_bar_type učitan iz baze: $navType');
    }

    // 2. Provjera verzije — obavezno/opciono ažuriranje
    final minVersion = settings?['min_version'] as String?;
    final latestVersion = settings?['latest_version'] as String?;
    if (minVersion != null && latestVersion != null) {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;

      // Uporedi verzije numerički (npr. 6.0.124)
      final current = _parseVersion(currentVersion);
      final min = _parseVersion(minVersion);
      final latest = _parseVersion(latestVersion);

      final isForced = current < min;
      final hasUpdate = current < latest;

      // Odaberi odgovarajući store URL (Android prioritet)
      final storeUrl = (settings?['store_url_android'] as String?) ??
          (settings?['store_url_huawei'] as String?) ??
          (settings?['store_url_ios'] as String?) ??
          '';

      if (isForced || hasUpdate) {
        updateInfoNotifier.value = V2UpdateInfo(
          latestVersion: latestVersion,
          storeUrl: storeUrl,
          isForced: isForced,
        );
        debugPrint('[main] Update: current=$currentVersion min=$minVersion latest=$latestVersion forced=$isForced');
      } else {
        updateInfoNotifier.value = null;
        debugPrint('[main] No update needed: current=$currentVersion latest=$latestVersion');
      }
    }
  } catch (e) {
    debugPrint('⚠️ [main] Greška pri učitavanju app_settings: $e');
  }
}

/// Parsira verziju u broj za poređenje (npr. "6.0.124" → 6000124)
int _parseVersion(String v) {
  try {
    final parts = v.split('.');
    final major = int.tryParse(parts.elementAtOrNull(0) ?? '0') ?? 0;
    final minor = int.tryParse(parts.elementAtOrNull(1) ?? '0') ?? 0;
    final patch = int.tryParse(parts.elementAtOrNull(2) ?? '0') ?? 0;
    return major * 1000000 + minor * 1000 + patch;
  } catch (_) {
    return 0;
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();

    // Dozvole se pozivaju iz V2WelcomeScreen da izbegnu MaterialLocalizations gresku
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}

  Future<void> _initializeApp() async {}

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeData>(
      valueListenable: V2ThemeManager().themeNotifier,
      builder: (context, themeData, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'Gavra 013',
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en', 'US'),
            Locale('sr'),
          ],
          locale: const Locale('sr'),
          theme: themeData,
          // home: const V3WelcomeScreen(),
          home: const V3WelcomeScreen(),
        );
      },
    );
  }
}

/// ✨ Čuva HMS token u bazu za hibridni push sistem
Future<void> _saveHmsTokenToDatabase(String hmsToken) async {
  try {
    debugPrint('💾 [HMS] Čuvam token u bazu...');

    // Pronađi trenutnog korisnika (Bojan) - možemo proširiti za sve korisnike
    final response = await supabase
        .from('v3_vozaci')
        .select('id, ime_prezime')
        .ilike('ime_prezime', '%bojan%')
        .limit(1)
        .maybeSingle();

    if (response == null) {
      debugPrint('⚠️ [HMS] Korisnik nije pronađen u bazi');
      return;
    }

    final vozacId = response['id'];

    // Ažuriraj HMS token i push_type
    await supabase.from('v3_vozaci').update({
      'hms_token': hmsToken,
      'push_type': 'hms',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', vozacId);

    debugPrint('✅ [HMS] Token sačuvan u bazu za ${response['ime_prezime']}');
  } catch (e) {
    debugPrint('❌ [HMS] Greška pri čuvanju tokena: $e');
  }
}
