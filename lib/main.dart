import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart' as fcm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_api_availability/google_api_availability.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'globals.dart';
import 'screens/v3_putnik_profil_screen.dart';
import 'screens/v3_welcome_screen.dart';
import 'services/realtime/v3_master_realtime_manager.dart';
import 'services/v3/v3_app_settings_service.dart';
import 'services/v3/v3_app_update_service.dart';
import 'services/v3/v3_foreground_gps_service.dart';
import 'services/v3/v3_putnik_service.dart';
import 'services/v3/v3_vozac_service.dart';
import 'services/v3/v3_zahtev_service.dart';
import 'services/v3_theme_manager.dart';
import 'utils/v3_time_utils.dart';

// Globalna instanca za lokalne notifikacije
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
bool _localNotificationsInitialized = false;
// Rezultat Firebase inicijalizacije - keširano da se izbegne dupli GMS check
bool _firebaseInitialized = false;

Future<void> _ensureLocalNotificationsInitialized() async {
  if (_localNotificationsInitialized) return;

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: onNotificationTap,
    onDidReceiveBackgroundNotificationResponse: onNotificationTap,
  );

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

  _localNotificationsInitialized = true;
}

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
    throw Exception('Ne mogu da inicijalizujem Supabase: $e');
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
  unawaited(
    Future<void>.delayed(const Duration(milliseconds: 500), _doStartupTasks)
        .catchError((Object e) => debugPrint('⚠️ [main] Startup tasks greška: $e')),
  );
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
  unawaited(
    initializeDateFormatting('sr', null)
        .catchError((Object e) => debugPrint('⚠️ [main] initializeDateFormatting greška: $e')),
  );

  // Sve ostalo pokreni istovremeno (paralelno)
  unawaited(
    _initNotificationHandlers().catchError((Object e) => debugPrint('⚠️ [main] Notification handlers greška: $e')),
  ); // Samo notification handlers, Firebase je već inicijalizovan
  unawaited(
    _initAppServices().catchError((Object e) => debugPrint('⚠️ [main] App services greška: $e')),
  );
}

/// FCM push inicijalizacija u main() funkciji
Future<void> _initFirebaseSync() async {
  try {
    bool firebaseCoreReady = false;
    bool fcmReady = false;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp().timeout(const Duration(seconds: 5));
      }
      firebaseCoreReady = true;
      debugPrint('✅ [Firebase] Core inicijalizovan');
    } catch (e) {
      debugPrint('⚠️ [Firebase] Core init greška: $e');
    }

    if (firebaseCoreReady) {
      if (Platform.isIOS) {
        fcmReady = true;
      } else {
        final gmsAvailability = await GoogleApiAvailability.instance
            .checkGooglePlayServicesAvailability()
            .timeout(const Duration(seconds: 2));

        if (gmsAvailability == GooglePlayServicesAvailability.success) {
          fcmReady = true;
          debugPrint('✅ [FCM] GMS dostupan');
        } else {
          debugPrint('⚠️ [FCM] Google Play Services nedostupan: $gmsAvailability');
        }
      }
    }

    _firebaseInitialized = firebaseCoreReady && fcmReady;
    if (_firebaseInitialized) {
      debugPrint('🟢 [Push] FCM dostupan');
    } else {
      debugPrint('🔴 [Push] FCM nije dostupan!');
    }
  } catch (e) {
    debugPrint('⚠️ [Push] Greška u FCM inicijalizaciji: $e');
  }
}

/// Inicijalizacija Notification handlers (FCM)
Future<void> _initNotificationHandlers() async {
  try {
    // 1. FCM Handlers (ako je Firebase inicijalizovan)
    try {
      // Koristimo keširani rezultat iz _initFirebaseSync - nema potrebe za ponovnim GMS pozivom
      if (_firebaseInitialized) {
        if (Platform.isIOS) {
          await fcm.FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          );
        }

        // Postavi FCM background handler
        fcm.FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

        // FCM Foreground handler
        fcm.FirebaseMessaging.onMessage.listen(_handleIncomingMessage);

        // FCM tap na sistemsku notifikaciju (app u background-u)
        fcm.FirebaseMessaging.onMessageOpenedApp.listen((message) async {
          await _handleNotificationOpenedFromData(message.data);
        });

        // FCM token refresh → sync u bazu
        fcm.FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
          await _syncPushTokenToCurrentUser(token);
        });

        // FCM tap na sistemsku notifikaciju (cold start)
        final initialMessage = await fcm.FirebaseMessaging.instance.getInitialMessage();
        if (initialMessage != null) {
          await _handleNotificationOpenedFromData(initialMessage.data);
        }

        // Initial token sync nakon starta
        final initialToken = await fcm.FirebaseMessaging.instance.getToken();
        if (initialToken != null && initialToken.isNotEmpty) {
          await _syncPushTokenToCurrentUser(initialToken);
        }

        debugPrint('✅ [FCM] Handlers konfigurisani');
      }
    } catch (e) {
      debugPrint('⚠️ [FCM] Handler setup greška: $e');
    }

    // 2. Inicijalizuj Local Notifications (za interaktivne gumbe)
    try {
      await _ensureLocalNotificationsInitialized();

      debugPrint('✅ [Push] Notification handlers konfigurisani');
    } catch (e) {
      debugPrint('⚠️ [Push] Notification handlers greška: $e');
    }
  } catch (e) {
    debugPrint('⚠️ [Push] Opšta greška: $e');
  }
}

Future<void> _syncPushTokenToCurrentUser(String token) async {
  final safeToken = token.trim();
  if (safeToken.isEmpty) return;

  try {
    final currentVozac = V3VozacService.currentVozac;
    if (currentVozac != null) {
      await V3VozacService.updatePushToken(vozacId: currentVozac.id, pushToken: safeToken);
      debugPrint('✅ [Push] Token sync: v3_auth (vozac)');
      return;
    }

    final currentPutnik = V3PutnikService.currentPutnik;
    final putnikId = currentPutnik?['id']?.toString();
    if (putnikId != null && putnikId.isNotEmpty) {
      final token1 = currentPutnik?['push_token']?.toString();
      final token2 = currentPutnik?['push_token_2']?.toString();

      final updated = await V3PutnikService.updatePushTokensOnLogin(
        putnikId: putnikId,
        token: safeToken,
        existingToken1: token1,
        existingToken2: token2,
      );
      currentPutnik?.addAll(updated);

      debugPrint('✅ [Push] Token sync: v3_auth (putnik)');
    }
  } catch (e) {
    debugPrint('⚠️ [Push] Token sync greška: $e');
  }
}

Future<void> _handleNotificationOpenedFromData(Map<String, dynamic> data) async {
  try {
    final type = data['type']?.toString().trim();
    if (type == 'v3_putnik_eta_start') {
      final putnikId = data['putnik_id']?.toString().trim() ?? '';
      await _openPutnikProfilFromNotification('putnik_eta_start:$putnikId');
    }
  } catch (e) {
    debugPrint('⚠️ [Push] open-from-data handler greška: $e');
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
  final type = message.data['type']?.toString().trim() ?? '';
  if (type == 'v3_alternativa') {
    try {
      await _ensureLocalNotificationsInitialized();
      final title = (message.notification?.title ?? message.data['title']?.toString() ?? '').trim();
      final body = (message.notification?.body ?? message.data['body']?.toString() ?? '').trim();
      await _showAlternativaActionsNotification(
        message.data,
        title: title,
        body: body,
      );
      debugPrint('✅ [Push] Background alternativa akcije prikazane');
    } catch (e) {
      debugPrint('⚠️ [Push] Background alternativa fallback greška: $e');
    }
    return;
  }
  if (type.startsWith('v3_')) {
    debugPrint('⏭️ [Push] Edge-only: background lokalni fallback isključen za type=$type');
  }
}

/// Foreground handler za FCM
Future<void> _handleIncomingMessage(fcm.RemoteMessage message) async {
  debugPrint("📱 [FCM] Foreground poruka: ${message.messageId}");
  debugPrint("📱 [FCM] Title: ${message.notification?.title}");
  debugPrint("📱 [FCM] Body: ${message.notification?.body}");
  debugPrint("📱 [FCM] Data: ${message.data}");

  // Provjeri tip notifikacije
  final type = message.data['type']?.toString().trim();
  final title = (message.notification?.title ?? message.data['title']?.toString() ?? '').trim();
  final body = (message.notification?.body ?? message.data['body']?.toString() ?? '').trim();
  if (type == 'gps_tracking_start') {
    await _handleGpsTrackingStart(message.data);
  } else if (type == 'gps_tracking_complete') {
    await _handleGpsTrackingComplete(message.data);
  } else if (type == 'v3_alternativa') {
    await _showAlternativaActionsNotification(
      message.data,
      title: title,
      body: body,
    );
    debugPrint('✅ [Push] Foreground alternativa akcije prikazane');
  } else if ((type ?? '').startsWith('v3_')) {
    final safeTitle = title.isNotEmpty ? title : '🔔 Gavra obaveštenje';
    final safeBody = body.isNotEmpty ? body : 'Imate novo obaveštenje.';
    await _showActionFeedback(safeTitle, safeBody);
    debugPrint('✅ [Push] Foreground lokalni fallback prikazan za type=$type');
  } else {
    debugPrint('⏭️ [Push] Edge-only: nepoznat tip bez lokalnog fallback-a: $type');
  }
}

/// Rukovanje GPS tracking start notifikacijom
Future<void> _handleGpsTrackingStart(Map<String, dynamic> data) async {
  final vozacId = data['vozac_id']?.toString().trim();
  final polazakVreme = data['polazak_vreme']?.toString().trim();
  final putniciBroj = int.tryParse('${data['putnici_count'] ?? 0}') ?? 0;

  if (vozacId == null || vozacId.isEmpty || polazakVreme == null || polazakVreme.isEmpty) {
    debugPrint('⚠️ [GPS] Nedostaju podaci u notification: vozacId=$vozacId, polazak=$polazakVreme');
    return;
  }

  final isDriverDevice = await _isCurrentDeviceDriverForGps(vozacId);
  if (!isDriverDevice) {
    debugPrint('⏭️ [GPS] Preskačem reminder: uređaj nije vozačev (vozacId=$vozacId)');
    return;
  }

  // Prikaži informativnu notifikaciju (auto-start je ugašen)
  final gpsStartBody = 'Kreće za 15 min ($putniciBroj putnika). Pokreni START ručno u vozač ekranu.';
  final androidDetails = AndroidNotificationDetails(
    'gavra_gps_auto',
    'GPS Podsetnik',
    channelDescription: 'Podsetnik vozaču za ručno pokretanje GPS trackinga',
    importance: Importance.max,
    priority: Priority.high,
    styleInformation: BigTextStyleInformation(
      gpsStartBody,
      contentTitle: '🚗 GPS Tracking',
      summaryText: 'Gavra GPS',
    ),
  );

  await flutterLocalNotificationsPlugin.show(
    999, // Fixed ID za GPS tracking
    '🚗 GPS Tracking',
    gpsStartBody,
    NotificationDetails(android: androidDetails),
  );

  debugPrint('📍 [GPS] Podsetnik prikazan za vozača $vozacId');
}

Future<bool> _isCurrentDeviceDriverForGps(String vozacId) async {
  final targetVozacId = vozacId.trim();
  if (targetVozacId.isEmpty) return false;

  final currentVozacId = V3VozacService.currentVozac?.id;
  if (currentVozacId != null && currentVozacId == targetVozacId) {
    return true;
  }

  try {
    final token = await fcm.FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return false;
    return await V3VozacService.hasActiveVozacWithPushToken(
      vozacId: targetVozacId,
      pushToken: token,
    );
  } catch (e) {
    debugPrint('⚠️ [GPS] Driver-device check greška: $e');
    return false;
  }
}

/// Vozač: svi pokupljeni → ugasi foreground GPS tracking
Future<void> _handleGpsTrackingComplete(Map<String, dynamic> data) async {
  final shouldStop = '${data['action_stop_foreground'] ?? ''}'.toLowerCase() == 'true';

  if (!shouldStop) return;

  await V3ForegroundGpsService.stopTracking();

  const gpsCompleteBody = 'Svi putnici su pokupljeni. Tracking je automatski zaustavljen.';
  final androidDetails = AndroidNotificationDetails(
    'gavra_gps_success',
    'GPS Success',
    importance: Importance.high,
    priority: Priority.high,
    styleInformation: BigTextStyleInformation(
      gpsCompleteBody,
      contentTitle: '✅ GPS tracking završen',
      summaryText: 'Gavra GPS',
    ),
  );

  await flutterLocalNotificationsPlugin.show(
    890,
    '✅ GPS tracking završen',
    gpsCompleteBody,
    NotificationDetails(android: androidDetails),
  );
}

// Hendler za klik na interaktivne gumbe (actions)
@pragma('vm:entry-point')
void onNotificationTap(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();

  final String? payload = response.payload;
  final String? actionId = response.actionId;

  if (payload == null) return;

  // Tap na samu notifikaciju (bez action dugmeta) za putnik ETA flow
  if (payload.startsWith('putnik_eta_start')) {
    await _openPutnikProfilFromNotification(payload);
    return;
  }

  if (actionId == null) {
    final parts = payload.split('|');
    if (parts.length == 3 && parts[0].trim().isNotEmpty) {
      await _showActionFeedback('ℹ️ Alternativa', 'Izaberi: Vreme pre, Vreme posle ili Odbij.');
    }
    return;
  }

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
      await _showActionFeedback('⚠️ Greška', 'Akcija nije uspela (init): $e');
      return;
    }
  }

  try {
    // V3 alternativa handling
    // payload format (strict): "id|altPre|altPosle"
    final parts = payload.split('|');
    if (parts.length != 3 || parts[0].trim().isEmpty) {
      await _showActionFeedback('⚠️ Akcija nije izvršena', 'Neispravan format notifikacije.');
      return;
    }

    final zahtevId = parts[0].trim();
    final altPre = parts[1].trim();
    final altPosle = parts[2].trim();

    if (actionId == 'accept_pre' && altPre.isNotEmpty) {
      await V3ZahtevService.prihvatiAlternativu(zahtevId, altPre);
      await _showActionFeedback('✅ Alternativa prihvaćena', 'Prihvaćen termin: $altPre');
    } else if (actionId == 'accept_posle' && altPosle.isNotEmpty) {
      await V3ZahtevService.prihvatiAlternativu(zahtevId, altPosle);
      await _showActionFeedback('✅ Alternativa prihvaćena', 'Prihvaćen termin: $altPosle');
    } else if (actionId == 'reject') {
      await V3ZahtevService.odbijAlternativu(zahtevId);
      await _showActionFeedback('❌ Alternativa odbijena', 'Zahtev je postavljen na odbijeno.');
    } else {
      await _showActionFeedback('⚠️ Akcija nije izvršena', 'Alternativni termin nije prosleđen u notifikaciji.');
    }
  } catch (e) {
    debugPrint('[onNotificationTap] Greška pri obradi akcije: $e');
    await _showActionFeedback('⚠️ Greška', 'Akcija nije uspela: $e');
  }
}

String? _extractNormalizedTime(String? rawValue) {
  if (rawValue == null) return null;
  final value = rawValue.trim();
  if (value.isEmpty) return null;
  final token = V3TimeUtils.extractHHmmToken(value);
  if (token == null || token.isEmpty) return null;
  return V3TimeUtils.normalizeToHHmm(token);
}

Future<void> _showAlternativaActionsNotification(
  Map<String, dynamic> data, {
  required String title,
  required String body,
}) async {
  final rawZahtevId = data['zahtev_id']?.toString() ?? data['id']?.toString() ?? '';
  final zahtevId = rawZahtevId.trim();
  final altPre = _extractNormalizedTime(data['alt_pre']?.toString() ?? data['alt_vreme_pre']?.toString());
  final altPosle = _extractNormalizedTime(data['alt_posle']?.toString() ?? data['alt_vreme_posle']?.toString());

  if (zahtevId.isEmpty) {
    final safeTitle = title.isNotEmpty ? title : 'Informacija o dostupnosti termina';
    final safeBody = body.isNotEmpty ? body : 'Imate novo obaveštenje.';
    await _showActionFeedback(safeTitle, safeBody);
    return;
  }

  final actions = <AndroidNotificationAction>[];
  if (altPre != null) {
    actions.add(
      AndroidNotificationAction(
        'accept_pre',
        'Vreme pre $altPre',
        showsUserInterface: false,
      ),
    );
  }
  if (altPosle != null) {
    actions.add(
      AndroidNotificationAction(
        'accept_posle',
        'Vreme posle $altPosle',
        showsUserInterface: false,
      ),
    );
  }
  actions.add(
    const AndroidNotificationAction(
      'reject',
      'Odbij',
      showsUserInterface: false,
    ),
  );

  final safeTitle = title.isNotEmpty ? title : 'Informacija o dostupnosti termina';
  final safeBody = body.isNotEmpty
      ? body
      : 'Trenutno nema slobodnih mesta u željenom terminu. Pripremili smo najbliže dostupne alternative za Vas.';

  final androidDetails = AndroidNotificationDetails(
    'gavra_push_v2',
    'Gavra obaveštenja',
    importance: Importance.max,
    priority: Priority.high,
    styleInformation: BigTextStyleInformation(
      safeBody,
      contentTitle: safeTitle,
      summaryText: 'Gavra',
    ),
    actions: actions,
  );

  await flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecondsSinceEpoch.remainder(100000),
    safeTitle,
    safeBody,
    NotificationDetails(android: androidDetails),
    payload: '$zahtevId|${altPre ?? ''}|${altPosle ?? ''}',
  );
}

Future<void> _showActionFeedback(String title, String body) async {
  final androidDetails = AndroidNotificationDetails(
    'gavra_push_v2',
    'Gavra obaveštenja',
    importance: Importance.high,
    priority: Priority.high,
    styleInformation: BigTextStyleInformation(
      body,
      contentTitle: title,
      summaryText: 'Gavra',
    ),
  );

  await flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecondsSinceEpoch.remainder(100000),
    title,
    body,
    NotificationDetails(android: androidDetails),
  );
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
      putnikData ??= await V3PutnikService.getActiveById(payloadPutnikId);
    }

    // 2) FCM token fallback: nađi putnika po push_token ili push_token_2
    if (putnikData == null) {
      final token = await fcm.FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        putnikData = await V3PutnikService.getActiveByPushToken(token);
      }
    }

    // 3) Cache refresh fallback
    if (putnikData == null) {
      await V3MasterRealtimeManager.instance.initV3().timeout(const Duration(seconds: 15));
      final token = await fcm.FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        putnikData = V3MasterRealtimeManager.instance.putniciCache.values.cast<Map<String, dynamic>?>().firstWhere(
              (p) => p != null && p['aktivno'] == true && (p['push_token'] == token || p['push_token_2'] == token),
              orElse: () => null,
            );
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

/// Inicijalizacija ostalih servisa
Future<void> _initAppServices() async {
  // Inicijalizuj V3 Foreground GPS Service
  try {
    await V3ForegroundGpsService.initialize();
    debugPrint('✅ [main] V3ForegroundGpsService inicijalizovan');
  } catch (e) {
    debugPrint('⚠️ [main] V3ForegroundGpsService greška: $e');
  }

  // Učitaj nav_bar_type iz baze
  try {
    final settings = await V3AppSettingsService.loadGlobal(
      selectColumns: 'nav_bar_type, nav_bar_type_next, nav_bar_type_effective_at',
    );

    final navType = resolveEffectiveNavBarType(
      currentType: settings['nav_bar_type']?.toString(),
      nextType: settings['nav_bar_type_next']?.toString(),
      effectiveAt: settings['nav_bar_type_effective_at'],
    );

    if (navType != null) {
      navBarTypeNotifier.value = navType;
      debugPrint('[main] efektivni nav_bar_type učitan iz baze: $navType');
    }
  } catch (e) {
    debugPrint('⚠️ [main] Greška pri učitavanju app_settings: $e');
  }

  // Provera da li je dostupna nova verzija aplikacije
  unawaited(
    V3AppUpdateService.refreshUpdateInfo().catchError((Object e) => debugPrint('⚠️ [main] App update info greška: $e')),
  );
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
      valueListenable: V3ThemeManager().themeNotifier,
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
