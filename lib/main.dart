import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'globals.dart';
import 'screens/v3_putnik_profil_screen.dart';
import 'screens/v3_welcome_screen.dart';
import 'services/realtime/v3_master_realtime_manager.dart';
import 'services/v3/v3_app_settings_service.dart';
import 'services/v3/v3_app_update_service.dart';
import 'services/v3/v3_foreground_gps_service.dart';
import 'services/v3/v3_push_token_provider.dart';
import 'services/v3/v3_push_token_sync_service.dart';
import 'services/v3/v3_putnik_service.dart';
import 'services/v3/v3_zahtev_service.dart';
import 'services/v3_theme_manager.dart';

// Globalna instanca za lokalne notifikacije
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
bool _localNotificationsInitialized = false;
Future<void>? _localNotificationsInitInFlight;
Future<void>? _supabaseInitInFlight;

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

void main() async {
  debugPrint('🚀 [main] 1. START');
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('🚀 [main] 2. WidgetsFlutterBinding DONE');
  initDanHelperGlobals();

  // KONFIGURACIJA - Inicijalizuj osnovne kredencijale (bez Supabase)
  try {
    debugPrint('🚀 [main] 3. configService start');
    await configService.initializeBasic().timeout(const Duration(seconds: 3));
    debugPrint('🚀 [main] 3. configService completed');
  } catch (e) {
    // Critical error - cannot continue without credentials
    throw Exception('Ne mogu da inicijalizujem osnovne kredencijale: $e');
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
  unawaited(_postRunAppInitialization());
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
    unawaited(V3MasterRealtimeManager.instance
        .initV3()
        .catchError((Object e) => debugPrint('❌ [main] V3MasterRealtimeManager.initV3 greška: $e')));
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
  );
  unawaited(
    _initAppServices().catchError((Object e) => debugPrint('⚠️ [main] App services greška: $e')),
  );
}

/// Inicijalizacija notification handlers + push token sync (manual SMS tok)
Future<void> _initNotificationHandlers() async {
  try {
    final tokenResult = await V3PushTokenProvider.getBestToken();
    if (tokenResult != null && tokenResult.token.trim().isNotEmpty) {
      await V3PushTokenSyncService.syncCurrentUser(
        token: tokenResult.token,
        provider: V3PushTokenProvider.providerAsString(tokenResult.provider),
        reason: 'main:init_notification_handlers',
      );
    }

    // Inicijalizuj Local Notifications (za interaktivne gumbe)
    try {
      await _ensureLocalNotificationsInitialized();
      debugPrint('✅ [Push] Notification handlers konfigurisani');
    } catch (e) {
      debugPrint('⚠️ [Push] Notification handlers greška: $e');
    }

    // HMS push data handler — prima data poruke iz native strane
    const MethodChannel hmsPushChannel = MethodChannel('com.gavra013.gavra_android/hms_push_data');
    hmsPushChannel.setMethodCallHandler((call) async {
      if (call.method == 'onPushData') {
        final data = Map<String, String>.from(call.arguments as Map);
        await _handleIncomingPushData(data);
      }
    });
  } catch (e) {
    debugPrint('⚠️ [Push] Opšta greška: $e');
  }
}

/// Obrađuje dolazni push data (HMS i FCM data-only poruke).
Future<void> _handleIncomingPushData(Map<String, String> data) async {
  final type = data['type'] ?? '';
  debugPrint('[Push] handleIncomingPushData type=$type');

  if (type == 'v3_alternativa') {
    final zahtevId = data['zahtev_id'] ?? data['entity_id'] ?? data['id'] ?? '';
    final altPre = data['alt_pre'] ?? '';
    final altPosle = data['alt_posle'] ?? '';
    if (zahtevId.isEmpty) return;

    await showAlternativaNotification(
      zahtevId: zahtevId,
      altPre: altPre,
      altPosle: altPosle,
    );
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
        showsUserInterface: false,
        cancelNotification: true,
      ),
    if (altPosle.isNotEmpty)
      AndroidNotificationAction(
        'accept_posle',
        altPosle,
        showsUserInterface: false,
        cancelNotification: true,
      ),
    const AndroidNotificationAction(
      'reject',
      'Odbij',
      showsUserInterface: false,
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

  if (payload.startsWith('sms_auth_request|')) {
    if (actionId == null || actionId == 'approve_sms') {
      final opened = await _openSmsComposerFromAuthPayload(payload);
      if (opened) {
        await _showActionFeedback('✅ SMS odobren', 'Otvorena je SMS aplikacija sa pripremljenom šifrom.');
      } else {
        await _showActionFeedback('⚠️ Greška', 'Ne mogu da otvorim SMS aplikaciju za ovaj zahtev.');
      }
      return;
    }
  }

  if (actionId == null) {
    final parts = payload.split('|');
    if (parts.length == 3 && parts[0].trim().isNotEmpty) {
      // Korisnik tapnuo na body notifikacije — ponovo prikaži sa akcijama
      await showAlternativaNotification(
        zahtevId: parts[0].trim(),
        altPre: parts[1].trim(),
        altPosle: parts[2].trim(),
      );
    }
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

Future<bool> _openSmsComposerFromAuthPayload(String payload) async {
  final parts = payload.split('|');
  if (parts.length < 3) return false;

  final phone = parts[1].trim();
  final otp = parts[2].trim();
  if (phone.isEmpty || otp.isEmpty) return false;

  final smsUri = Uri(
    scheme: 'sms',
    path: phone,
    queryParameters: {
      'body': 'Vaš verifikacioni kod je: $otp',
    },
  );

  if (await canLaunchUrl(smsUri)) {
    await launchUrl(smsUri, mode: LaunchMode.externalApplication);
    return true;
  }
  return false;
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

    // 1) Payload id fallback: putnik_eta_start:<putnik_id>
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
      await V3MasterRealtimeManager.instance.initV3().timeout(const Duration(seconds: 15));
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
