import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_api_availability/google_api_availability.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'globals.dart';
import 'screens/v3_welcome_screen.dart';
import 'services/realtime/v3_master_realtime_manager.dart';
import 'services/v2_theme_manager.dart';
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
    debugPrint('âŒ [main] Supabase.initialize greÅ¡ka: $e');
  }

  // 1. Pokreni V3 Realtime Manager ODMAH (prije UI-a, da ima max vremena za fetch)
  unawaited(V3MasterRealtimeManager.instance
      .initV3()
      .catchError((Object e) => debugPrint('❌ [main] V3MasterRealtimeManager.initV3 greška: $e')));

  // 2. Pokreni UI ODMAH (bez cekanja Supabase)
  runApp(const MyApp());

  // 3. Čekaj malo da se UI renderira, pa tek onda inicijalizuj servise
  unawaited(Future<void>.delayed(const Duration(milliseconds: 500), _doStartupTasks));
}

/// Pozadinske inicijalizacije koje ne smeju da blokiraju UI
Future<void> _doStartupTasks() async {
  // Wakelock i edge-to-edge UI
  try {
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  } catch (e) {
    debugPrint('âš ï¸ [main] Wakelock/SystemChrome greÅ¡ka: $e');
  }

  // Locale - UTF-8 podrska za dijakritiku
  unawaited(initializeDateFormatting('sr', null));

  // Sve ostalo pokreni istovremeno (paralelno)
  unawaited(_initPushSystems());
  unawaited(_initAppServices());
}

/// Inicijalizacija Notifikacija (GMS vs HMS)
Future<void> _initPushSystems() async {
  try {
    final availability =
        await GoogleApiAvailability.instance.checkGooglePlayServicesAvailability().timeout(const Duration(seconds: 2));

    if (availability == GooglePlayServicesAvailability.success) {
      try {
        await Firebase.initializeApp().timeout(const Duration(seconds: 5));

        // Postavi background handler
        FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

        // Foreground handler — data-only poruke (npr. v3_alternativa)
        FirebaseMessaging.onMessage.listen(_handleIncomingMessage);

        // Inicijalizuj Local Notifications (za interaktivne gumbe)
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

        debugPrint('✅ [Push] FCM Inicijalizovan');
      } catch (e) {
        debugPrint('⚠️ [main] Firebase init greška: $e');
      }
    }
  } catch (e) {
    debugPrint('⚠️ [main] GMS provjera greška: $e');
  }
}

/// Pozadinski hendler za Firebase poruke (MORA BITI TOP-LEVEL FUNKCIJA)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
  await _showAlternativaNotification(message);
}

/// Foreground handler
Future<void> _handleIncomingMessage(RemoteMessage message) async {
  await _showAlternativaNotification(message);
}

/// Prikazuje lokalnu notifikaciju sa akcijskim dugmadima za v3_alternativa
Future<void> _showAlternativaNotification(RemoteMessage message) async {
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

  if (payload != null && actionId != null) {
    debugPrint('Notification Action Clicked: $actionId, Payload: $payload');

    // Akcije za V3 zahtev: accept_pre, accept_posle, reject
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
  }
}

/// Inicijalizacija ostalih servisa
Future<void> _initAppServices() async {
  // Učitaj nav_bar_type iz baze PRIJE nego što se UI osloni na notifier
  try {
    final settings =
        await Supabase.instance.client.from('v3_app_settings').select('nav_bar_type').eq('id', 'global').maybeSingle();
    final navType = settings?['nav_bar_type'] as String?;
    if (navType != null && ['zimski', 'letnji', 'praznici'].contains(navType)) {
      navBarTypeNotifier.value = navType;
      debugPrint('[main] nav_bar_type učitan iz baze: $navType');
    }
  } catch (e) {
    debugPrint('⚠️ [main] Greška pri učitavanju nav_bar_type: $e');
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
