import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'globals.dart';
import 'screens/v3_putnik_profil_screen.dart';
import 'screens/v3_welcome_screen.dart';
import 'services/realtime/v3_master_realtime_manager.dart';
import 'services/v3/v3_app_settings_service.dart';
import 'services/v3/v3_app_update_service.dart';
import 'services/v3/v3_push_token_provider.dart';
import 'services/v3/v3_putnik_service.dart';
import 'services/v3/v3_role_permission_service.dart';
import 'services/v3/v3_vozac_service.dart';
import 'services/v3_theme_manager.dart';
import 'utils/v3_time_utils.dart';

// Globalna instanca za lokalne notifikacije
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
bool _localNotificationsInitialized = false;
bool _notificationLaunchHandled = false;
Future<void>? _localNotificationsInitInFlight;
Future<void>? _supabaseInitInFlight;
Future<void>? _fcmChannelInitInFlight;
Future<void>? _iosFcmHandlersInitInFlight;
String _lastSyncedPushToken = '';
bool _fcmChannelInitialized = false;
bool _iosFcmHandlersInitialized = false;

void _startBackgroundTask({
  required String label,
  required Future<void> Function() task,
  Duration timeout = const Duration(seconds: 8),
  int retries = 1,
  Duration retryDelay = const Duration(seconds: 2),
}) {
  unawaited(
    _runBackgroundTask(
      label: label,
      task: task,
      timeout: timeout,
      retries: retries,
      retryDelay: retryDelay,
    ),
  );
}

Future<void> _runBackgroundTask({
  required String label,
  required Future<void> Function() task,
  required Duration timeout,
  required int retries,
  required Duration retryDelay,
}) async {
  final totalAttempts = retries + 1;
  for (var attempt = 1; attempt <= totalAttempts; attempt++) {
    try {
      await task().timeout(timeout);
      if (attempt > 1) {
        debugPrint('✅ [main] Task "$label" uspeo nakon retry pokušaja #$attempt');
      }
      return;
    } catch (e) {
      debugPrint('⚠️ [main] Task "$label" pokušaj #$attempt/$totalAttempts neuspešan: $e');
      if (attempt >= totalAttempts) return;
      await Future<void>.delayed(Duration(milliseconds: retryDelay.inMilliseconds * attempt));
    }
  }
}

Future<void> _ensureLocalNotificationsInitialized() async {
  if (_localNotificationsInitialized) return;

  final inFlight = _localNotificationsInitInFlight;
  if (inFlight != null) {
    await inFlight;
    return;
  }

  final initFuture = () async {
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

    const AndroidNotificationChannel alternativaChannel = AndroidNotificationChannel(
      'gavra_alternativa',
      'Alternativa termina',
      description: 'Klikabilna obaveštenja za alternativne termine',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    final androidImpl =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(channel);
    await androidImpl?.createNotificationChannel(alternativaChannel);

    if (!_notificationLaunchHandled) {
      final launchDetails = await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
      final notificationResponse = launchDetails?.notificationResponse;
      if ((launchDetails?.didNotificationLaunchApp ?? false) && notificationResponse != null) {
        _notificationLaunchHandled = true;
        onNotificationTap(notificationResponse);
      }
    }

    _localNotificationsInitialized = true;
  }();

  _localNotificationsInitInFlight = initFuture;
  try {
    await initFuture;
  } finally {
    _localNotificationsInitInFlight = null;
  }
}

Future<bool> _ensureSupabaseInitialized() async {
  if (isSupabaseReady) return true;

  final inFlight = _supabaseInitInFlight;
  if (inFlight != null) {
    await inFlight;
    return isSupabaseReady;
  }

  final initFuture = () async {
    await configService.initializeBasic();
    if (isSupabaseReady) return;
    final url = configService.getSupabaseUrl().trim();
    final anonKey = configService.getSupabaseAnonKey().trim();
    if (url.isEmpty || anonKey.isEmpty) {
      debugPrint('⚠️ [main] Supabase kredencijali nisu dostupni.');
      return;
    }
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
  }();

  _supabaseInitInFlight = initFuture;
  try {
    await initFuture;
  } finally {
    _supabaseInitInFlight = null;
  }

  return isSupabaseReady;
}

void _installGlobalErrorHandlers() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('❌ [main] FlutterError: ${details.exceptionAsString()}');
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('❌ [main] Uncaught platform error: $error');
    return true;
  };
}

void main() async {
  debugPrint('🚀 [main] 1. START');
  WidgetsFlutterBinding.ensureInitialized();
  _installGlobalErrorHandlers();
  debugPrint('🚀 [main] 2. WidgetsFlutterBinding DONE');
  initDanHelperGlobals();

  // KONFIGURACIJA - Inicijalizuj osnovne kredencijale (bez Supabase)
  try {
    debugPrint('🚀 [main] 3. configService start');
    await configService.initializeBasic().timeout(const Duration(seconds: 3));
    debugPrint('🚀 [main] 3. configService completed');
  } catch (e) {
    debugPrint('⚠️ [main] configService timeout/greška, nastavljam sa fallback tokom: $e');
  }

  // SUPABASE - Inicijalizuj sa osnovnim kredencijalima
  try {
    debugPrint('🚀 [main] 4. Supabase init start');
    final supabaseReady = await _ensureSupabaseInitialized().timeout(const Duration(seconds: 4));
    if (supabaseReady) {
      debugPrint('🚀 [main] 4. Supabase init completed');
    } else {
      debugPrint('⚠️ [main] Supabase init incomplete, nastavljam sa fallback tokom.');
    }
  } catch (e) {
    debugPrint('❌ [main] Supabase.initialize greška/timeout: $e');
  }

  // ODMAH POKREĆEMO UI KAKO BI IZBEGLI CRN OS EKRAN
  debugPrint('🚀 [main] 5. runApp start (Native non-blocking UI)');
  runApp(const MyApp());

  // SVE OSTALE ZADATKE GURAMO U POZADINU
  _startBackgroundTask(
    label: 'postRunAppInitialization',
    task: _postRunAppInitialization,
    timeout: const Duration(seconds: 20),
    retries: 0,
  );
}

/// Pokretanje servisa u pozadini kako UI ne bi čekao i pravio deadlock
Future<void> _postRunAppInitialization() async {
  // 1. Pokreni V3 Realtime Manager (background)
  if (!isSupabaseReady) {
    try {
      await _ensureSupabaseInitialized().timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('⚠️ [main] Preskačem initV3 (Supabase nije spreman): $e');
    }
  }

  if (isSupabaseReady) {
    debugPrint('🚀 [main] 6. V3MasterRealtimeManager.initV3 start (background)');
    _startBackgroundTask(
      label: 'V3MasterRealtimeManager.initV3',
      task: () => V3MasterRealtimeManager.instance.initV3(),
      timeout: const Duration(seconds: 12),
      retries: 1,
    );
  } else {
    debugPrint('⚠️ [main] Preskačem initV3: Supabase nije inicijalizovan.');
  }

  // 2. 🎨 Tema - učitaj iz secure storage (ui će automatski reagovati na promenu teme)
  try {
    debugPrint('🚀 [main] 7. loadThemeFromStorage start');
    await V3ThemeManager().loadThemeFromStorage().timeout(const Duration(seconds: 3));
    debugPrint('🚀 [main] 7. loadThemeFromStorage completed');
  } catch (e) {
    debugPrint('⚠️ [main] Theme load timeout/greška: $e');
  }

  // 3. Pokreni sve ostale servise sa malom pauzom
  _startBackgroundTask(
    label: 'startup tasks',
    task: () async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _doStartupTasks();
    },
    timeout: const Duration(seconds: 20),
    retries: 0,
  );
}

/// Pozadinske inicijalizacije koje ne smeju da blokiraju UI
Future<void> _doStartupTasks() async {
  // Wakelock i edge-to-edge UI
  try {
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  } catch (e) {
    debugPrint('⚠️ [main] Wakelock/SystemChrome greška: $e');
  }

  // Locale - UTF-8 podrska za dijakritiku
  _startBackgroundTask(
    label: 'initializeDateFormatting(sr)',
    task: () => initializeDateFormatting('sr', null),
    timeout: const Duration(seconds: 5),
    retries: 0,
  );

  // Sve ostalo pokreni istovremeno (paralelno)
  _startBackgroundTask(
    label: 'FCM channel init',
    task: _initFcmChannel,
    timeout: const Duration(seconds: 6),
    retries: 1,
  );
  if (Platform.isIOS) {
    _startBackgroundTask(
      label: 'iOS FCM handlers init',
      task: _initIosFcmHandlers,
      timeout: const Duration(seconds: 8),
      retries: 1,
    );
  }
  _startBackgroundTask(
    label: 'notification handlers init',
    task: _initNotificationHandlers,
    timeout: const Duration(seconds: 8),
    retries: 2,
  );
  _startBackgroundTask(
    label: 'app services init',
    task: _initAppServices,
    timeout: const Duration(seconds: 10),
    retries: 2,
  );
}

Future<bool> _ensureFirebaseInitialized() async {
  if (Firebase.apps.isNotEmpty) return true;

  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 5));
    return true;
  } catch (e) {
    debugPrint('⚠️ [main] Firebase init nije uspeo: $e');
    return Firebase.apps.isNotEmpty;
  }
}

Map<String, dynamic> _toStringDynamicMap(Object? raw) {
  if (raw is! Map) return <String, dynamic>{};
  return raw.map((k, v) => MapEntry(k.toString(), v));
}

Map<String, String> _toStringStringMap(Object? raw) {
  if (raw is! Map) return <String, String>{};
  return raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
}

Map<String, String> _messageDataToStringMap(Map<String, dynamic> raw) {
  return raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
}

String _encodeTapPayload(String type, Map<String, String> data) {
  final safeType = type.trim();
  final safeData = <String, String>{
    for (final entry in data.entries)
      if (entry.key.trim().isNotEmpty) entry.key.trim(): entry.value,
  };

  if (safeData.isEmpty) {
    return safeType;
  }

  return jsonEncode({
    'kind': 'fcm',
    'type': safeType,
    'data': safeData,
  });
}

({String type, Map<String, String> data}) _decodeTapPayload(String payload) {
  try {
    final decoded = jsonDecode(payload);
    if (decoded is Map<String, dynamic>) {
      final type = decoded['type']?.toString().trim() ?? '';
      final rawData = decoded['data'];
      final data =
          rawData is Map ? rawData.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')) : <String, String>{};

      if (type.isNotEmpty) {
        return (type: type, data: data);
      }
    }
  } catch (_) {}

  if (payload.startsWith('zahtev_status')) {
    final parts = payload.split(':');
    final putnikId = parts.length > 1 ? parts[1].trim() : '';
    return (
      type: 'zahtev_status',
      data: putnikId.isNotEmpty ? {'v3_auth_id': putnikId} : <String, String>{},
    );
  }

  return (type: payload.trim(), data: <String, String>{});
}

Future<void> _showForegroundPushNotification({
  required String title,
  required String body,
  required String payload,
  Map<String, String> data = const <String, String>{},
}) async {
  if (title.isEmpty && body.isEmpty) return;

  await _ensureLocalNotificationsInitialized();
  final androidDetails = AndroidNotificationDetails(
    'gavra_push_v2',
    'Gavra obaveštenja',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
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
    NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(),
    ),
    payload: _encodeTapPayload(payload, data),
  );
}

Future<void> _showAlternativaFromData(
  Map<String, String> data, {
  String? title,
  String? body,
}) async {
  final zahtevId = (data['zahtev_id'] ?? '').trim();
  final altPre = V3TimeUtils.normalizeToHHmm((data['alt_pre'] ?? '').trim());
  final altPosle = V3TimeUtils.normalizeToHHmm((data['alt_posle'] ?? '').trim());

  if (zahtevId.isEmpty) {
    debugPrint('⚠️ [alternativa] Nedostaje zahtevId u FCM data payload-u: $data');
    return;
  }

  await showAlternativaNotification(
    zahtevId: zahtevId,
    altPre: altPre,
    altPosle: altPosle,
    title: (title == null || title.trim().isEmpty) ? 'Informacija o dostupnosti termina' : title,
    body: (body == null || body.trim().isEmpty)
        ? 'Trenutno nema slobodnih mesta u željenom terminu. Izaberite dostupni termin.'
        : body,
  );
}

Future<void> _syncRefreshedPushToken(String token) async {
  final safeToken = token.trim();
  if (safeToken.isEmpty) return;
  if (_lastSyncedPushToken == safeToken) return;
  final installationId = (await V3PushTokenProvider.getInstallationId())?.trim() ?? '';
  final tokenResult = await V3PushTokenProvider.getBestToken();
  final apnsToken = tokenResult?.apnsToken?.trim() ?? '';

  Future<bool> doSyncAttempt() async {
    final putnikId = (V3PutnikService.currentPutnik?['id']?.toString() ?? '').trim();
    if (putnikId.isNotEmpty) {
      await V3PutnikService.writePushTokenOnLogin(
        putnikId: putnikId,
        pushToken: safeToken,
        installationId: installationId,
        pushToken2: apnsToken,
      );
      return true;
    }

    final vozacId = (V3VozacService.currentVozac?.id ?? '').trim();
    if (vozacId.isNotEmpty) {
      await V3VozacService.writePushTokenOnLogin(
        vozacId: vozacId,
        pushToken: safeToken,
        installationId: installationId,
        pushToken2: apnsToken,
      );
      return true;
    }

    return false;
  }

  try {
    final synced = await doSyncAttempt().timeout(const Duration(seconds: 5));
    if (synced) {
      _lastSyncedPushToken = safeToken;
    }
  } catch (e) {
    debugPrint('[FCM] Token refresh sync prvi pokušaj nije uspeo: $e');
    unawaited(
      Future<void>.delayed(const Duration(seconds: 2), () async {
        try {
          final synced = await doSyncAttempt().timeout(const Duration(seconds: 5));
          if (synced) {
            _lastSyncedPushToken = safeToken;
          }
        } catch (retryError) {
          debugPrint('[FCM] Token refresh sync retry nije uspeo: $retryError');
        }
      }),
    );
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await _ensureFirebaseInitialized();

  final type = message.data['type']?.toString() ?? '';
  debugPrint('[FCM][iOS] background message type=$type id=${message.messageId}');
}

Future<void> _initIosFcmHandlers() async {
  if (_iosFcmHandlersInitialized) return;

  final inFlight = _iosFcmHandlersInitInFlight;
  if (inFlight != null) {
    await inFlight;
    return;
  }

  final initFuture = () async {
    final firebaseReady = await _ensureFirebaseInitialized();
    if (!firebaseReady) {
      debugPrint('⚠️ [FCM][iOS] Preskačem FCM handlers: Firebase nije spreman.');
      return;
    }

    final messaging = FirebaseMessaging.instance;
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final type = message.data['type']?.toString() ?? '';
      final title = message.notification?.title ?? message.data['title']?.toString() ?? '';
      final body = message.notification?.body ?? message.data['body']?.toString() ?? '';
      final data = _messageDataToStringMap(message.data);

      debugPrint('[FCM][iOS] onMessage type=$type title=$title');
      unawaited(V3RolePermissionService.wakeScreenOnPush());

      if (type == 'v3_alternativa') {
        await _showAlternativaFromData(
          data,
          title: title,
          body: body,
        );
        return;
      }

      // Uvek prikaži lokalnu notifikaciju dok je app u foregroundu.
      // Na Androidu FCM ne prikazuje notification automatski — app mora sama.
      // Prethodni uslov `if (message.notification == null)` preskakao je sve
      // push-ove koji imaju notification payload (npr. putnik_eta_start).
      await _showForegroundPushNotification(
        title: title,
        body: body,
        payload: type,
        data: data,
      );
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final type = message.data['type']?.toString() ?? '';
      final data = _messageDataToStringMap(message.data);
      debugPrint('[FCM][iOS] onMessageOpenedApp type=$type data=$data');
      unawaited(
        _handleFcmLaunch(type, data)
            .catchError((Object e) => debugPrint('⚠️ [FCM][iOS] onMessageOpenedApp launch handler greška: $e')),
      );
    });

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      final type = initialMessage.data['type']?.toString() ?? '';
      final data = _messageDataToStringMap(initialMessage.data);
      debugPrint('[FCM][iOS] getInitialMessage type=$type data=$data');
      unawaited(
        _handleFcmLaunch(type, data)
            .catchError((Object e) => debugPrint('⚠️ [FCM][iOS] getInitialMessage launch handler greška: $e')),
      );
    }

    messaging.onTokenRefresh.listen((token) {
      if (token.trim().isNotEmpty) {
        debugPrint('[FCM][iOS] Token refresh primljen.');
        unawaited(_syncRefreshedPushToken(token));
      }
    });

    _iosFcmHandlersInitialized = true;
    debugPrint('✅ [FCM][iOS] Firebase Messaging handlers konfigurisani');
  }();

  _iosFcmHandlersInitInFlight = initFuture;
  try {
    await initFuture;
  } finally {
    _iosFcmHandlersInitInFlight = null;
  }
}

/// Sluša FCM poruke prosleđene od GavraFcmService (Kotlin) via MethodChannel.
/// Hvata:
///  - onMessage     → prikazuje lokalnu notifikaciju + budi ekran
///  - onTokenRefresh → sync-uje novi FCM token sa Supabase
Future<void> _initFcmChannel() async {
  if (_fcmChannelInitialized) return;

  final inFlight = _fcmChannelInitInFlight;
  if (inFlight != null) {
    await inFlight;
    return;
  }

  final initFuture = () async {
    const channel = MethodChannel('com.gavra013.gavra_android/fcm');
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onMessage':
          final args = _toStringDynamicMap(call.arguments);
          if (args.isEmpty) {
            debugPrint('[FCM] onMessage ignorisan: neispravni arguments.');
            return;
          }
          final title = args['title']?.toString() ?? '';
          final body = args['body']?.toString() ?? '';
          final type = args['type']?.toString() ?? '';
          final rawData = args['data'];
          final data =
              rawData is Map ? rawData.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')) : <String, String>{};
          debugPrint('[FCM] onMessage type=$type title=$title');

          // Budi ekran
          unawaited(V3RolePermissionService.wakeScreenOnPush());

          if (type == 'v3_alternativa') {
            await _showAlternativaFromData(
              data,
              title: title,
              body: body,
            );
            return;
          }

          // Prikaži lokalnu notifikaciju (foreground)
          if (title.isNotEmpty || body.isNotEmpty) {
            await _showForegroundPushNotification(
              title: title,
              body: body,
              payload: type,
              data: data,
            );
          }
          return;

        case 'onTokenRefresh':
          final args = _toStringDynamicMap(call.arguments);
          final token = args['token']?.toString().trim() ?? '';
          if (token.isNotEmpty) {
            debugPrint('[FCM] Token refresh primljen.');
            unawaited(_syncRefreshedPushToken(token));
          }
          return;

        case 'onLaunchMessage':
          // Korisnik je tapnuo FCM notifikaciju dok je app bila killed/background.
          // `arguments` je Map<String, String> sa svim FCM data key-value parovima.
          final launchData = _toStringStringMap(call.arguments);
          if (launchData.isEmpty) {
            debugPrint('[FCM] onLaunchMessage ignorisan: neispravni arguments.');
            return;
          }
          final launchType = launchData['type'] ?? '';
          debugPrint('[FCM] onLaunchMessage type=$launchType data=$launchData');
          unawaited(
            _handleFcmLaunch(launchType, launchData)
                .catchError((Object e) => debugPrint('⚠️ [FCM] onLaunchMessage launch handler greška: $e')),
          );
          return;

        default:
          debugPrint('[FCM] Nepoznata MethodChannel metoda: ${call.method}');
          return;
      }
    });
    _fcmChannelInitialized = true;
    debugPrint('✅ [FCM] MethodChannel handler registrovan');
  }();

  _fcmChannelInitInFlight = initFuture;
  try {
    await initFuture;
  } finally {
    _fcmChannelInitInFlight = null;
  }
}

/// Rutira na pravi ekran kada korisnik tapne FCM notifikaciju dok je app bila killed/background.
///
/// Tipovi:
///  - `zahtev_status`   → putnik otvori V3PutnikProfilScreen, vozač — nema navigacije (već je na svom ekranu)
Future<void> _handleFcmLaunch(String type, Map<String, String> data) async {
  // Sačekaj da navigator bude dostupan (max 5s)
  for (var i = 0; i < 50; i++) {
    if (navigatorKey.currentState != null) break;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  if (!isSupabaseReady) {
    try {
      await _ensureSupabaseInitialized().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('⚠️ [FCM launch] Supabase init nije uspeo: $e');
    }
  }

  switch (type) {
    case 'v3_alternativa':
      await _showAlternativaFromData(data);
      return;

    case 'zahtev_status':
      // v3_auth_id je v3_auth.id — direktno otvori profil ekran
      final putnikId = data['v3_auth_id'] ?? '';
      final payload = putnikId.isNotEmpty ? 'zahtev_status:$putnikId' : 'zahtev_status';
      await _openPutnikProfilFromNotification(payload);
      return;

    default:
      debugPrint('[FCM launch] Nepoznat type=$type, ignoriši');
      return;
  }
}

/// Inicijalizacija notification handlers + push token sync (manual SMS tok)
Future<void> _initNotificationHandlers() async {
  try {
    await _ensureLocalNotificationsInitialized();
    debugPrint('✅ [Push] Notification handlers konfigurisani');
  } catch (e) {
    debugPrint('⚠️ [Push] Notification handlers greška: $e');
  }

  if (!isSupabaseReady) {
    try {
      await _ensureSupabaseInitialized().timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('⚠️ [Push] Preskačem token sync (Supabase nije spreman): $e');
      return;
    }
  }
}

/// Prikazuje lokalnu klikabilnu notifikaciju za alternativu.
/// [zahtevId] — id zahteva, [altPre] — HH:mm ili '', [altPosle] — HH:mm ili ''
Future<void> showAlternativaNotification({
  required String zahtevId,
  required String altPre,
  required String altPosle,
  String title = 'Alternativa termina',
  String body = 'Trenutno nema slobodnih mesta. Izaberite dostupni termin.',
}) async {
  await _ensureLocalNotificationsInitialized();

  final payload = '$zahtevId|$altPre|$altPosle';

  final actions = <AndroidNotificationAction>[
    if (altPre.isNotEmpty)
      AndroidNotificationAction(
        'accept_pre',
        altPre,
        showsUserInterface: true,
        cancelNotification: true,
      ),
    if (altPosle.isNotEmpty)
      AndroidNotificationAction(
        'accept_posle',
        altPosle,
        showsUserInterface: true,
        cancelNotification: true,
      ),
    const AndroidNotificationAction(
      'reject',
      'Odbij',
      showsUserInterface: true,
      cancelNotification: true,
    ),
  ];

  final androidDetails = AndroidNotificationDetails(
    'gavra_alternativa',
    'Alternativa termina',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
    actions: actions,
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
    payload: payload,
  );
}

Future<Map<String, dynamic>> _executeAlternativaEdgeAction({
  required String zahtevId,
  required String actionId,
}) async {
  final safeZahtevId = zahtevId.trim();
  final safeActionId = actionId.trim();

  if (safeZahtevId.isEmpty) {
    throw Exception('Nedostaje zahtev_id za alternativa akciju.');
  }

  if (!{'accept_pre', 'accept_posle', 'reject'}.contains(safeActionId)) {
    throw Exception('Nepoznata alternativa akcija: $safeActionId');
  }

  final response = await supabase.functions.invoke(
    'v3-alternativa-action',
    body: {
      'zahtev_id': safeZahtevId,
      'action': safeActionId,
    },
  );

  final data = response.data;
  if (response.status < 200 || response.status >= 300 || data is! Map) {
    throw Exception('Edge alternativa action failed (status=${response.status}, data=$data)');
  }

  final map = Map<String, dynamic>.from(data);
  if (map['ok'] != true) {
    final reason = (map['reason'] ?? 'unknown_error').toString();
    throw Exception('Alternativa akcija nije uspela: $reason');
  }

  return map;
}

// Hendler za klik na interaktivne gumbe (actions)
@pragma('vm:entry-point')
void onNotificationTap(NotificationResponse response) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  final String? payload = response.payload;
  final String? actionId = response.actionId;

  if (payload == null) return;

  final decodedPayload = _decodeTapPayload(payload);
  final decodedType = decodedPayload.type;
  final decodedData = decodedPayload.data;

  // Tap na samu notifikaciju (bez action dugmeta) za putnik status flow
  if (decodedType == 'zahtev_status') {
    await _handleFcmLaunch(decodedType, decodedData);
    return;
  }

  if (actionId == null) {
    return;
  }

  debugPrint('Notification Action Clicked: $actionId, Payload: $payload');

  // Cold start — Supabase možda nije inicijalizovan
  if (!isSupabaseReady) {
    try {
      final ready = await _ensureSupabaseInitialized();
      if (!ready) {
        await _showActionFeedback('⚠️ Greška', 'Servis trenutno nije dostupan. Pokušajte ponovo.');
        return;
      }
    } catch (e) {
      debugPrint('[onNotificationTap] Supabase init greška: $e');
      await _showActionFeedback('⚠️ Greška', 'Akcija nije uspela (init): $e');
      return;
    }
  }

  try {
    // V3 alternativa handling (Edge-only)
    // payload format (strict): "id|altPre|altPosle"
    final parts = payload.split('|');
    if (parts.length != 3 || parts[0].trim().isEmpty) {
      await _showActionFeedback('⚠️ Akcija nije izvršena', 'Neispravan format notifikacije.');
      return;
    }

    final zahtevId = parts[0].trim();
    if (actionId == 'accept_pre' || actionId == 'accept_posle' || actionId == 'reject') {
      final result = await _executeAlternativaEdgeAction(
        zahtevId: zahtevId,
        actionId: actionId,
      );

      if (actionId == 'reject') {
        await _showActionFeedback('❌ Alternativa odbijena', 'Zahtev je postavljen na odbijeno.');
      } else {
        final selectedTime = (result['selected_time'] ?? '').toString().trim();
        final suffix = selectedTime.isNotEmpty ? 'Prihvaćen termin: $selectedTime' : 'Alternativa je prihvaćena.';
        await _showActionFeedback('✅ Alternativa prihvaćena', suffix);
      }
    } else {
      await _showActionFeedback('⚠️ Akcija nije izvršena', 'Nepoznata akcija notifikacije.');
    }
  } catch (e) {
    debugPrint('[onNotificationTap] Greška pri obradi akcije: $e');
    await _showActionFeedback('⚠️ Greška', 'Akcija nije uspela: $e');
  }
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
      final ready = await _ensureSupabaseInitialized();
      if (!ready) {
        debugPrint('⚠️ [Push] Ne mogu da otvorim putnik profil (Supabase nije spreman).');
        return;
      }
    }

    final nav = navigatorKey.currentState;
    if (nav == null) {
      debugPrint('⚠️ [Push] Ne mogu da otvorim putnik profil (nema navigatora).');
      return;
    }

    Map<String, dynamic>? putnikData = V3PutnikService.currentPutnik;

    // 1) Payload id fallback: zahtev_status:<putnik_id>
    final parts = payload.split(':');
    final payloadPutnikId = parts.length > 1 ? parts[1] : '';
    if ((putnikData == null) && payloadPutnikId.isNotEmpty) {
      putnikData = V3MasterRealtimeManager.instance.getPutnik(payloadPutnikId);
      putnikData ??= await V3PutnikService.getActiveById(payloadPutnikId);
    }

    // 2) Push token fallback: nađi putnika po push_token ili push_token_2
    if (putnikData == null) {
      final tokenResult = await V3PushTokenProvider.getBestToken();
      final token = tokenResult?.token.trim() ?? '';
      if (token.isNotEmpty) {
        putnikData = await V3PutnikService.getActiveByPushToken(token);
      }
    }

    // 3) Cache refresh fallback
    if (putnikData == null) {
      await V3MasterRealtimeManager.instance.initV3().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint('⚠️ [Push] initV3 timeout nakon 15s; nastavljam bez cache refresh-a.');
        },
      );
      final tokenResult = await V3PushTokenProvider.getBestToken();
      final token = tokenResult?.token.trim() ?? '';
      if (token.isNotEmpty) {
        putnikData = V3MasterRealtimeManager.instance.putniciCache.values.cast<Map<String, dynamic>?>().firstWhere(
              (p) => p != null && (p['push_token'] == token || p['push_token_2'] == token),
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
  if (!isSupabaseReady) {
    try {
      await _ensureSupabaseInitialized().timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('⚠️ [main] Preskačem app services init (Supabase nije spreman): $e');
      return;
    }
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
