import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'globals.dart';
import 'screens/v3_putnik_profil_screen.dart';
import 'screens/v3_vozac_screen.dart';
import 'screens/v3_welcome_screen.dart';
import 'services/realtime/v3_master_realtime_manager.dart';
import 'services/v3/v3_app_settings_service.dart';
import 'services/v3/v3_app_update_service.dart';
import 'services/v3/v3_background_location_handler.dart';
import 'services/v3/v3_device_identity_service.dart';
import 'services/v3/v3_push_token_provider.dart';
import 'services/v3/v3_putnik_service.dart';
import 'services/v3/v3_role_permission_service.dart';
import 'services/v3/v3_trenutna_dodela_slot_service.dart';
import 'services/v3/v3_vozac_location_tracking_service.dart';
import 'services/v3/v3_vozac_service.dart';
import 'services/v3_locale_manager.dart';
import 'services/v3_theme_manager.dart';
import 'utils/v3_time_utils.dart';
import 'widgets/v3_pazar_listener.dart';

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
final Map<String, DateTime> _canceledStatusPushSeenAt = <String, DateTime>{};
const Duration _canceledStatusPushDedupWindow = Duration(seconds: 20);

bool _isCanceledZahtevStatusPush({
  required String type,
  required String title,
  required String body,
  required Map<String, String> data,
}) {
  if (type.trim() != 'zahtev_status') return false;

  final normalizedStatus = (data['status'] ?? data['zahtev_status'] ?? '').trim().toLowerCase();
  if (normalizedStatus == 'otkazano' ||
      normalizedStatus == 'otkazan' ||
      normalizedStatus == 'cancelled' ||
      normalizedStatus == 'canceled') {
    return true;
  }

  final text = '${title.toLowerCase()} ${body.toLowerCase()}';
  return text.contains('otkaz');
}

String _canceledZahtevStatusDedupKey({
  required String title,
  required String body,
  required Map<String, String> data,
}) {
  final putnikId = (data['v3_auth_id'] ?? data['putnik_id'] ?? '').trim();
  final zahtevId = (data['zahtev_id'] ?? '').trim();
  final status = (data['status'] ?? 'otkazano').trim().toLowerCase();
  return [
    putnikId,
    zahtevId,
    status,
    title.trim().toLowerCase(),
    body.trim().toLowerCase(),
  ].join('|');
}

bool _isDuplicateCanceledZahtevStatusPush({
  required String type,
  required String title,
  required String body,
  required Map<String, String> data,
}) {
  if (!_isCanceledZahtevStatusPush(type: type, title: title, body: body, data: data)) {
    return false;
  }

  final now = DateTime.now();
  final staleCutoff = now.subtract(const Duration(minutes: 2));
  _canceledStatusPushSeenAt.removeWhere((_, ts) => ts.isBefore(staleCutoff));

  final key = _canceledZahtevStatusDedupKey(title: title, body: body, data: data);
  final lastSeen = _canceledStatusPushSeenAt[key];
  if (lastSeen != null && now.difference(lastSeen) <= _canceledStatusPushDedupWindow) {
    return true;
  }

  _canceledStatusPushSeenAt[key] = now;
  return false;
}

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

    final List<DarwinNotificationCategory> darwinNotificationCategories = <DarwinNotificationCategory>[
      DarwinNotificationCategory(
        'alternativa_oba',
        actions: <DarwinNotificationAction>[
          DarwinNotificationAction.plain('accept_pre', 'Prihvati prvi termin'),
          DarwinNotificationAction.plain('accept_posle', 'Prihvati drugi termin'),
          DarwinNotificationAction.plain('reject', 'Odbij', options: <DarwinNotificationActionOption>{
            DarwinNotificationActionOption.destructive,
          }),
        ],
      ),
      DarwinNotificationCategory(
        'alternativa_pre',
        actions: <DarwinNotificationAction>[
          DarwinNotificationAction.plain('accept_pre', 'Prihvati termin'),
          DarwinNotificationAction.plain('reject', 'Odbij', options: <DarwinNotificationActionOption>{
            DarwinNotificationActionOption.destructive,
          }),
        ],
      ),
      DarwinNotificationCategory(
        'alternativa_posle',
        actions: <DarwinNotificationAction>[
          DarwinNotificationAction.plain('accept_posle', 'Prihvati termin'),
          DarwinNotificationAction.plain('reject', 'Odbij', options: <DarwinNotificationActionOption>{
            DarwinNotificationActionOption.destructive,
          }),
        ],
      ),
    ];

    final DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: darwinNotificationCategories,
    );
    final InitializationSettings initializationSettings = InitializationSettings(
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

    const AndroidNotificationChannel gpsTrackingChannel = AndroidNotificationChannel(
      'gavra_gps_tracking',
      'GPS Tracking',
      description: 'Praćenje lokacije vozača tokom vožnje',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    );

    final androidImpl =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(channel);
    await androidImpl?.createNotificationChannel(alternativaChannel);
    await androidImpl?.createNotificationChannel(gpsTrackingChannel);

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
      if (startupPhaseNotifier.value == V3StartupPhase.booting) {
        startupPhaseNotifier.value = V3StartupPhase.dbReady;
      }
    } else {
      debugPrint('⚠️ [main] Supabase init incomplete, nastavljam sa fallback tokom.');
      startupPhaseNotifier.value = V3StartupPhase.degraded;
    }
  } catch (e) {
    debugPrint('❌ [main] Supabase.initialize greška/timeout: $e');
    startupPhaseNotifier.value = V3StartupPhase.degraded;
  }

  // FOREGROUND SERVICE - konfiguracija za background GPS tracking
  try {
    debugPrint('🚀 [main] 4b. Foreground service config start');
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onBackgroundServiceStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'gavra_gps_tracking',
        initialNotificationTitle: 'GPS Tracking',
        initialNotificationContent: 'Praćenje lokacije aktivno',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: null,
        onBackground: (_) => true,
      ),
    );
    debugPrint('🚀 [main] 4b. Foreground service config completed');
  } catch (e) {
    debugPrint('⚠️ [main] Foreground service config greška: $e');
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

  // Aktiviraj lifecycle observer za background tracking servis
  V3VozacLocationTrackingService.instance.initialize();
}

/// Pokretanje servisa u pozadini kako UI ne bi čekao i pravio deadlock
Future<void> _postRunAppInitialization() async {
  // 1. Kritični app servisi (settings + update gate) pre ostalih background taskova
  try {
    debugPrint('🚀 [main] 6. _initAppServices start (critical)');
    await _initAppServices().timeout(const Duration(seconds: 8));
    debugPrint('🚀 [main] 6. _initAppServices completed');
    if (startupPhaseNotifier.value != V3StartupPhase.realtimeReady) {
      startupPhaseNotifier.value = V3StartupPhase.dbReady;
    }
  } catch (e) {
    debugPrint('⚠️ [main] _initAppServices timeout/greška: $e');
    startupPhaseNotifier.value = V3StartupPhase.degraded;
  }

  // 2. Pokreni V3 Realtime Manager (background)
  if (!isSupabaseReady) {
    try {
      await _ensureSupabaseInitialized().timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('⚠️ [main] Preskačem initV3 (Supabase nije spreman): $e');
    }
  }

  if (isSupabaseReady) {
    debugPrint('🚀 [main] 7. V3MasterRealtimeManager.initV3 start (background)');
    _startBackgroundTask(
      label: 'V3MasterRealtimeManager.initV3',
      task: () async {
        try {
          await V3MasterRealtimeManager.instance.initV3();
          startupPhaseNotifier.value = V3StartupPhase.realtimeReady;
        } catch (e) {
          startupPhaseNotifier.value = V3StartupPhase.degraded;
          rethrow;
        }
      },
      timeout: const Duration(seconds: 12),
      retries: 1,
    );
  } else {
    debugPrint('⚠️ [main] Preskačem initV3: Supabase nije inicijalizovan.');
    startupPhaseNotifier.value = V3StartupPhase.degraded;
  }

  // 3. 🎨 Tema - učitaj iz secure storage (ui će automatski reagovati na promenu teme)
  try {
    debugPrint('🚀 [main] 8. loadThemeFromStorage start');
    await V3ThemeManager().loadThemeFromStorage().timeout(const Duration(seconds: 3));
    debugPrint('🚀 [main] 8. loadThemeFromStorage completed');
  } catch (e) {
    debugPrint('⚠️ [main] Theme load timeout/greška: $e');
  }

  // 3b. 🌐 Jezik - učitaj sačuvani izbor SR/EN iz secure storage
  try {
    await V3LocaleManager().loadLocaleFromStorage().timeout(const Duration(seconds: 3));
  } catch (e) {
    debugPrint('⚠️ [main] Locale load timeout/greška: $e');
  }

  // 4. Pokreni sve ostale servise sa malom pauzom
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
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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
  _startBackgroundTask(
    label: 'FCM handlers init',
    task: _initIosFcmHandlers,
    timeout: const Duration(seconds: 8),
    retries: 1,
  );
  _startBackgroundTask(
    label: 'notification handlers init',
    task: _initNotificationHandlers,
    timeout: const Duration(seconds: 8),
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

  if (_isDuplicateCanceledZahtevStatusPush(
    type: payload,
    title: title,
    body: body,
    data: data,
  )) {
    debugPrint('[Push] Preskočen dupli otkazano zahtev_status push.');
    return;
  }

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
  final hardwareId = await V3DeviceIdentityService.getHardwareId();

  Future<bool> doSyncAttempt() async {
    final putnikId = (V3PutnikService.currentPutnik?['id']?.toString() ?? '').trim();
    if (putnikId.isNotEmpty) {
      await V3PutnikService.writePushTokenOnLogin(
        putnikId: putnikId,
        pushToken: safeToken,
        installationId: installationId,
        hardwareId: hardwareId,
      );
      return true;
    }

    final vozacId = (V3VozacService.currentVozac?.id ?? '').trim();
    if (vozacId.isNotEmpty) {
      await V3VozacService.writePushTokenOnLogin(
        vozacId: vozacId,
        pushToken: safeToken,
        installationId: installationId,
        hardwareId: hardwareId,
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
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();
  await _ensureFirebaseInitialized();

  final type = message.data['type']?.toString() ?? '';
  final title = message.notification?.title ?? message.data['title']?.toString() ?? '';
  final body = message.notification?.body ?? message.data['body']?.toString() ?? '';
  final data = _messageDataToStringMap(message.data);
  debugPrint('[FCM][BG] background message type=$type id=${message.messageId}');

  if (type == 'v3_alternativa') {
    await _showAlternativaFromData(
      data,
      title: title,
      body: body,
    );
    return;
  }

  // Kada je app killed, GavraFcmService se ne poziva — background handler
  // mora sam da prikaže notifikaciju za sve ostale tipove.
  if (title.isNotEmpty || body.isNotEmpty) {
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
      payload: _encodeTapPayload(type, data),
    );
  }
}

Future<void> _initIosFcmHandlers() async {
  if (_iosFcmHandlersInitialized) return;

  final inFlight = _iosFcmHandlersInitInFlight;
  if (inFlight != null) {
    await inFlight;
    return;
  }

  final initFuture = () async {
    if (!Platform.isIOS) {
      debugPrint('ℹ️ [FCM][iOS] Preskačem iOS FCM handlere na ne-iOS platformi.');
      return;
    }

    final firebaseReady = await _ensureFirebaseInitialized();
    if (!firebaseReady) {
      debugPrint('⚠️ [FCM][iOS] Preskačem FCM handlers: Firebase nije spreman.');
      return;
    }

    final messaging = FirebaseMessaging.instance;

    // alert: false — iOS NE prikazuje automatski banner u foregroundu.
    // onMessage handler ispod sam prikazuje lokalnu notifikaciju da izbegnemo duplikat.
    await messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
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

      if (type == 'vozac_auto_start_tracking') {
        // Vozač je već u aplikaciji (foreground/background sa aktivnim engine-om) —
        // NEMA potrebe za tap-om na notifikaciju. Tracking se pokreće sam.
        unawaited(
          _autoStartVozacTrackingFromPush(data)
              .catchError((Object e) => debugPrint('⚠️ [FCM][iOS] auto-start tracking greška: $e')),
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

          if (type == 'vozac_auto_start_tracking') {
            // Vozač je već u aplikaciji (ili je engine aktivan u pozadini) —
            // NEMA potrebe za tap-om na notifikaciju. Tracking se pokreće sam,
            // a Android sam prikazuje trajnu "GPS Tracking" notifikaciju
            // (foreground service, već konfigurisano u main()).
            unawaited(
              _autoStartVozacTrackingFromPush(data)
                  .catchError((Object e) => debugPrint('⚠️ [FCM] auto-start tracking greška: $e')),
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
/// Tipovi koji otvaraju V3PutnikProfilScreen:
///  - `zahtev_status`, `v3_zahtev_odobren`, `v3_zahtev_odbijen`, `v3_otkazano`, `putnik_eta_start`
/// Posebni tipovi:
///  - `v3_alternativa` → prikazuje dijalog za izbor alternativnog termina
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
      final launchMarker = (data['google.message_id'] ?? '').trim();
      if (Platform.isAndroid && launchMarker.startsWith('gavra_alt_')) {
        debugPrint('[FCM launch] Android alternativa tap detektovan — preskačem ponovno prikazivanje notifikacije.');
        return;
      }
      await _showAlternativaFromData(data);
      return;

    case 'zahtev_status':
    case 'v3_zahtev_odobren':
    case 'v3_zahtev_odbijen':
    case 'v3_otkazano':
    case 'putnik_eta_start':
      // Svi ovi tipovi vode na putnik profil ekran.
      // recipient_id ili v3_auth_id identifikuju putnika.
      final putnikId = (data['v3_auth_id'] ?? data['recipient_id'] ?? '').trim();
      final payload = putnikId.isNotEmpty ? 'zahtev_status:$putnikId' : 'zahtev_status';
      await _openPutnikProfilFromNotification(payload);
      return;

    case 'vozac_auto_start_tracking':
      final vozacId = (data['v3_auth_id'] ?? data['vozac_id'] ?? '').trim();
      if (vozacId.isNotEmpty) {
        // Navigiraj na V3VozacScreen i pokreni auto tracking
        final nav = navigatorKey.currentState;
        if (nav != null) {
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) => V3VozacScreen(
                vozacId: vozacId,
                autoStartTracking: true,
              ),
            ),
          );
        }
      }
      return;

    default:
      debugPrint('[FCM launch] Nepoznat type=$type, ignoriši');
      return;
  }
}

/// Pokreće GPS tracking direktno iz push podataka — BEZ tap-a, bez otvaranja
/// bilo kakvog ekrana. Poziva se čim stigne `vozac_auto_start_tracking` push
/// dok je Flutter engine aktivan (foreground ili background sa keširanim
/// engine-om — što je slučaj sve dok vozač drži aplikaciju otvorenu/pokrenutu).
///
/// Android sam prikazuje trajnu "GPS Tracking" notifikaciju preko foreground
/// service-a (već konfigurisano u main()) — to je jedina notifikacija koju
/// vozač vidi, bez potrebe da bilo šta klikne.
Future<void> _autoStartVozacTrackingFromPush(Map<String, String> data) async {
  final vozacId = (data['v3_auth_id'] ?? data['vozac_id'] ?? '').trim();
  final grad = (data['grad'] ?? '').trim().toUpperCase();
  final vreme = V3TimeUtils.normalizeToHHmm(data['vreme'] ?? '');
  final datumIso = (data['datum'] ?? '').trim();

  if (vozacId.isEmpty || grad.isEmpty || vreme.isEmpty || datumIso.isEmpty) {
    debugPrint('[AUTO-START] Nedostaju podaci u push-u: vozacId=$vozacId grad=$grad vreme=$vreme datum=$datumIso');
    return;
  }

  if (!isSupabaseReady) {
    try {
      await _ensureSupabaseInitialized().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('⚠️ [AUTO-START] Supabase init nije uspeo: $e');
      return;
    }
  }

  if (V3VozacLocationTrackingService.instance.isRunning &&
      V3VozacLocationTrackingService.instance.activeVozacId == vozacId) {
    debugPrint('[AUTO-START] Tracking već aktivan za ovog vozača, preskačem.');
    return;
  }

  debugPrint('[AUTO-START] Pokrećem tracking automatski: vozac=$vozacId grad=$grad vreme=$vreme datum=$datumIso');

  // Osiguraj da slot red postoji (idempotentan upsert, ne diraj waypoints_json
  // ako ga je kron već popunio) — sprečava 'no_active_slot' race ako push
  // stigne pre nego što je kron-ova transakcija vidljiva, ili ako je
  // prethodni ručni start obrisao slot.
  try {
    await V3TrenutnaDodelaSlotService.activateSlot(
      datumIso: datumIso,
      grad: grad,
      vreme: vreme,
      vozacId: vozacId,
      updatedBy: vozacId,
    );
  } catch (e) {
    debugPrint('⚠️ [AUTO-START] activateSlot greška (nastavljam): $e');
  }

  V3VozacLocationTrackingService.instance.setActiveTermin(
    datumIso: datumIso,
    grad: grad,
    vreme: vreme,
  );
  await V3VozacLocationTrackingService.instance.start(vozacId: vozacId);
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
  String title = '🕒 Predlog alternativnog termina',
  String body = 'Nema slobodnih mesta u traženom terminu. Izaberi dostupnu opciju.',
}) async {
  await _ensureLocalNotificationsInitialized();

  final payload = '$zahtevId|$altPre|$altPosle';
  final optionsText = [
    if (altPre.isNotEmpty) altPre,
    if (altPosle.isNotEmpty) altPosle,
  ].join('  •  ');
  final modernBody = optionsText.isNotEmpty ? '$body\nDostupno: $optionsText' : body;

  final actions = <AndroidNotificationAction>[
    if (altPre.isNotEmpty)
      AndroidNotificationAction(
        'accept_pre',
        '✅ $altPre',
        showsUserInterface: true,
        cancelNotification: true,
      ),
    if (altPosle.isNotEmpty)
      AndroidNotificationAction(
        'accept_posle',
        '✅ $altPosle',
        showsUserInterface: true,
        cancelNotification: true,
      ),
    const AndroidNotificationAction(
      'reject',
      '❌ Odbij',
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
      modernBody,
      contentTitle: title,
      summaryText: 'Gavra • Alternativa',
    ),
  );

  String iosCategory = '';
  String finalBody = modernBody;
  if (altPre.isNotEmpty && altPosle.isNotEmpty) {
    iosCategory = 'alternativa_oba';
    finalBody = '$body\nOpcije: $altPre ili $altPosle';
  } else if (altPre.isNotEmpty) {
    iosCategory = 'alternativa_pre';
    finalBody = '$body\nOpcija: $altPre';
  } else if (altPosle.isNotEmpty) {
    iosCategory = 'alternativa_posle';
    finalBody = '$body\nOpcija: $altPosle';
  }

  final iosDetails = DarwinNotificationDetails(
    categoryIdentifier: iosCategory.isNotEmpty ? iosCategory : null,
  );

  await flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecondsSinceEpoch.remainder(100000),
    title,
    finalBody,
    NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    ),
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

  Map<String, dynamic>? settings;

  // Učitaj globalna app podešavanja iz baze
  try {
    settings = await V3AppSettingsService.loadGlobal(
      selectColumns:
          'latest_version_android, min_supported_version_android, force_update_android, store_url_android, maintenance_mode_android, maintenance_title_android, maintenance_message_android, '
          'latest_version_ios, min_supported_version_ios, force_update_ios, store_url_ios, maintenance_mode_ios, maintenance_title_ios, maintenance_message_ios',
    );
  } catch (e) {
    debugPrint('⚠️ [main] Greška pri učitavanju app_settings: $e');
  }

  // Provera da li je dostupna nova verzija aplikacije
  try {
    await V3AppUpdateService.refreshUpdateInfo(appSettingsRow: settings);
  } catch (e) {
    debugPrint('⚠️ [main] App update info greška: $e');
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
      valueListenable: V3ThemeManager().themeNotifier,
      builder: (context, themeData, _) {
        return ValueListenableBuilder<Locale>(
          valueListenable: V3LocaleManager().localeNotifier,
          builder: (context, locale, __) {
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
                Locale('ru'),
                Locale('de'),
              ],
              locale: locale,
              theme: themeData,
              builder: (context, child) => V3PazarListener(child: child ?? const SizedBox.shrink()),
              home: const V3WelcomeScreen(),
            );
          },
        );
      },
    );
  }
}
