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
import 'services/v2_background_gps_service.dart';
import 'services/v2_firebase_service.dart';
import 'services/v2_huawei_push_service.dart';
import 'services/v2_realtime_gps_service.dart';
import 'services/v2_statistika_istorija_service.dart';
import 'services/v2_theme_manager.dart';
import 'services/v2_weather_alert_service.dart';
import 'services/v2_weather_service.dart';

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
    debugPrint('❌ [main] Supabase.initialize greška: $e');
  }

  // 1. Pokreni UI ODMAH (bez cekanja Supabase)
  runApp(const MyApp());

  // 2. Čekaj malo da se UI renderira, pa tek onda inicijalizuj servise
  unawaited(Future<void>.delayed(const Duration(milliseconds: 500), _doStartupTasks));
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

  // Inicijalizuj background GPS foreground service (registracija, ne pokretanje)
  try {
    await V2BackgroundGpsService.initialize();
  } catch (e) {
    debugPrint('⚠️ [main] BackgroundGpsService init greška: $e');
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
      try {
        await Firebase.initializeApp().timeout(const Duration(seconds: 5));
        await V2FirebaseService.initialize();
        V2FirebaseService.setupFCMListeners();
        unawaited(V2FirebaseService.initializeAndRegisterToken());
      } catch (e) {
        debugPrint('⚠️ [main] Firebase/FCM init greška: $e');
      }
    } else {
      await _tryInitHms(timeout: const Duration(seconds: 5));
    }
  } catch (e) {
    // GMS provjera nije uspjela — probaj HMS kao fallback
    debugPrint('⚠️ [main] GMS provjera greška, pokušavam HMS: $e');
    await _tryInitHms(timeout: const Duration(seconds: 2));
  }
}

/// HMS inicijalizacija (Huawei uređaji bez GMS)
Future<void> _tryInitHms({required Duration timeout}) async {
  try {
    final hmsToken = await V2HuaweiPushService().initialize().timeout(timeout);
    if (hmsToken != null) {
      await V2HuaweiPushService().tryRegisterPendingToken();
    }
  } catch (e) {
    debugPrint('⚠️ [main] HMS init greška: $e');
  }
}

/// Inicijalizacija ostalih servisa
Future<void> _initAppServices() async {
  // V2 Master Realtime Manager — jedini koji slusa Supabase.
  // On ucitava sve cache-ove (vozaci, kapacitet, settings...) i otvara WebSocket.
  unawaited(V2MasterRealtimeManager.instance
      .initialize()
      .catchError((Object e) => debugPrint('❌ [main] MasterRealtimeManager.initialize greška: $e')));

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
    // Cleanup: zatvori stream controllere i WebSocket kanale
    V2WeatherService.dispose();
    V2RealtimeGpsService.dispose();
    V2StatistikaIstorijaService.dispose();
    V2MasterRealtimeManager.instance.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Kada app izadje iz backgrounda, provjeri da li je novi dan i osvjezi cache
      V2MasterRealtimeManager.instance.v2RefreshForNewDay().catchError((Object e) {});

      // Health check — provjeri da li su WebSocket kanali živi nakon buđenja iz backgrounda
      // (mrežne promjene tokom spavanja mogu "zamrznuti" vezu bez TCP reset-a)
      V2MasterRealtimeManager.instance.v2HealthCheck();

      // When app is resumed, try registering pending tokens (if any)
      try {
        V2HuaweiPushService().tryRegisterPendingToken();
      } catch (e) {}
    }
  }

  Future<void> _initializeApp() async {
    try {
      await V2ThemeManager().initialize();
    } catch (e) {
      debugPrint('⚠️ [main] V2ThemeManager.initialize greška: $e');
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
          ],
          locale: const Locale('sr'), // Default locale sa dijakritikom
          home: const V2WelcomeScreen(),
        );
      },
    );
  }
}
