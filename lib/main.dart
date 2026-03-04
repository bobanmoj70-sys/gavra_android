import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_api_availability/google_api_availability.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'globals.dart';
import 'screens/v2_welcome_screen.dart';
import 'services/realtime/v2_master_realtime_manager.dart';
import 'services/v2_firebase_service.dart';
import 'services/v2_huawei_push_service.dart';
import 'services/v2_realtime_gps_service.dart';
import 'services/v2_slobodna_mesta_service.dart';
import 'services/v2_statistika_istorija_service.dart';
import 'services/v2_theme_manager.dart';
import 'services/v2_weather_alert_service.dart';
import 'services/v2_weather_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('[Main] App starting...');

  // KONFIGURACIJA - Inicijalizuj osnovne kredencijale (bez Supabase)
  try {
    await configService.initializeBasic();
    debugPrint('[Main] Basic config initialized');
  } catch (e) {
    debugPrint('[Main] Basic config init failed: $e');
    // Critical error - cannot continue without credentials
    throw Exception('Ne mogu da inicijalizujem osnovne kredencijale: $e');
  }

  // SUPABASE - Inicijalizuj sa osnovnim kredencijalima
  try {
    await Supabase.initialize(
      url: configService.getSupabaseUrl(),
      anonKey: configService.getSupabaseAnonKey(),
    );
    debugPrint('[Main] Supabase initialized');
  } catch (e) {
    debugPrint('[Main] Supabase init failed: $e');
  }

  // 1. Pokreni UI ODMAH (bez cekanja Supabase)
  runApp(const MyApp());

  // 2. Čekaj malo da se UI renderira, pa tek onda inicijalizuj servise
  Future<void>.delayed(const Duration(milliseconds: 500), () {
    unawaited(_doStartupTasks());
  });
}

/// Pozadinske inicijalizacije koje ne smeju da blokiraju UI
Future<void> _doStartupTasks() async {
  debugPrint('[Main] Background tasks started');

  // Wakelock i edge-to-edge UI
  try {
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  } catch (e) {
    debugPrint('[Main] Wakelock/SystemChrome init failed: $e');
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
    // Provera GMS-a sa kratkim timeoutom
    final availability =
        await GoogleApiAvailability.instance.checkGooglePlayServicesAvailability().timeout(const Duration(seconds: 2));

    if (availability == GooglePlayServicesAvailability.success) {
      debugPrint('[Main] Detected GMS (Google Play Services)');
      try {
        await Firebase.initializeApp().timeout(const Duration(seconds: 5));
        await V2FirebaseService.initialize();
        V2FirebaseService.setupFCMListeners();
        unawaited(V2FirebaseService.initializeAndRegisterToken());
        debugPrint('[Main] FCM initialized successfully');
      } catch (e) {
        debugPrint('[Main] FCM initialization failed: $e');
      }
    } else {
      debugPrint('[Main] GMS not available, trying HMS (Huawei Mobile Services)');
      try {
        final hmsToken = await V2HuaweiPushService().initialize().timeout(const Duration(seconds: 5));
        if (hmsToken != null) {
          await V2HuaweiPushService().tryRegisterPendingToken();
          debugPrint('[Main] HMS initialized successfully');
        } else {
          debugPrint('[Main] HMS initialization returned null token');
        }
      } catch (e) {
        debugPrint('[Main] HMS initialization failed: $e');
      }
    }
  } catch (e) {
    debugPrint('[Main] Push services initialization failed: $e');
    // Try HMS as last resort
    try {
      debugPrint('[Main] Last resort: trying HMS');
      await V2HuaweiPushService().initialize().timeout(const Duration(seconds: 2));
    } catch (e2) {
      debugPrint('[Main] All push services failed: $e2');
    }
  }
}

/// Inicijalizacija ostalih servisa
Future<void> _initAppServices() async {
  debugPrint('[Main] Starting app services...');

  // V2 Master Realtime Manager — jedini koji slusa Supabase.
  // On ucitava sve cache-ove (vozaci, kapacitet, settings...) i otvara WebSocket.
  unawaited(V2MasterRealtimeManager.instance.initialize());

  // Weather alerts (bez cekanja)
  unawaited(V2WeatherAlertService.checkAndSendWeatherAlerts());
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
    // Cleanup: zatvori stream controllere
    V2WeatherService.dispose();
    V2RealtimeGpsService.dispose();
    V2StatistikaIstorijaService.dispose();
    V2SlobodnaMestaService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Kada app izadje iz backgrounda, provjeri da li je novi dan i osvjezi cache
      V2MasterRealtimeManager.instance.refreshForNewDay().catchError((Object e) {
        debugPrint('[Main] refreshForNewDay failed: $e');
      });

      // When app is resumed, try registering pending tokens (if any)
      try {
        V2HuaweiPushService().tryRegisterPendingToken();
      } catch (e) {
        debugPrint('[Main] HMS pending token registration failed: $e');
      }
    }
  }

  Future<void> _initializeApp() async {
    try {
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Inicijalizuj V2ThemeManager
      await V2ThemeManager().initialize();
    } catch (e) {
      debugPrint('[Main] App init failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeData>(
      valueListenable: V2ThemeManager().themeNotifier,
      builder: (context, themeData, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'Gavra 013',
          debugShowCheckedModeBanner: false,
          theme: themeData, // Light tema
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en', 'US'),
            Locale('sr'),
            Locale('sr', 'RS'),
            Locale('sr', 'BA'),
            Locale('sr', 'ME'),
          ],
          locale: const Locale('sr'), // Default locale sa dijakritikom
          // Samo jedna tema - nema dark mode
          navigatorObservers: const [],
          home: _buildHome(),
        );
      },
    );
  }

  Widget _buildHome() {
    // Uvek idi direktno na V2WelcomeScreen - bez Loading ekrana
    return const V2WelcomeScreen();
  }
}
