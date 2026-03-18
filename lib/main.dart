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
    debugPrint('âš ï¸ [main] Wakelock/SystemChrome greÅ¡ka: $e');
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
  await _showAlternativaNotification(message);
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

  if (payload == null || actionId == null) return;

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

  // Akcije za V3 zahtev: accept_pre, accept_posle, reject
  // payload format: "id|altPre|altPosle"
  final parts = payload.split('|');
  final zahtevId = parts[0];
  final altPre = parts.length > 1 ? parts[1] : '';
  final altPosle = parts.length > 2 ? parts[2] : '';

  try {
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

/// Inicijalizacija ostalih servisa
Future<void> _initAppServices() async {
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
