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
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'globals.dart';
import 'screens/v3_putnik_profil_screen.dart';
import 'screens/v3_welcome_screen.dart';
import 'services/realtime/v3_master_realtime_manager.dart';
import 'services/v2_theme_manager.dart';
import 'services/v3/v3_app_update_service.dart';
import 'services/v3/v3_foreground_gps_service.dart';
import 'services/v3/v3_putnik_service.dart';
import 'services/v3/v3_zahtev_service.dart';

// Globalna instanca za lokalne notifikacije
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
bool _localNotificationsInitialized = false;

Future<void> _ensureLocalNotificationsInitialized() async {
  if (_localNotificationsInitialized) return;

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);

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

        // FCM tap na sistemsku notifikaciju (app u background-u)
        fcm.FirebaseMessaging.onMessageOpenedApp.listen((message) async {
          await _handleNotificationOpenedFromData(message.data);
        });

        // FCM tap na sistemsku notifikaciju (cold start)
        final initialMessage = await fcm.FirebaseMessaging.instance.getInitialMessage();
        if (initialMessage != null) {
          await _handleNotificationOpenedFromData(initialMessage.data);
        }

        debugPrint('✅ [FCM] Handlers konfigurisani');
      }
    } catch (e) {
      debugPrint('⚠️ [FCM] Handler setup greška: $e');
    }

    // 2. HMS Handlers (za Huawei uređaje)
    try {
      // Provjeri da li je GMS dostupan — ako jeste, preskači HMS init
      final gmsCheck = await GoogleApiAvailability.instance
          .checkGooglePlayServicesAvailability()
          .timeout(const Duration(seconds: 2));
      final isGmsDevice = gmsCheck == GooglePlayServicesAvailability.success;

      if (isGmsDevice) {
        debugPrint('⏭️ [HMS] GMS uređaj — HMS init preskočen');
      } else {
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
      }
    } catch (e) {
      debugPrint('⚠️ [HMS] Handler setup greška: $e');
    }

    // 3. Inicijalizuj Local Notifications (za interaktivne gumbe)
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

Future<void> _handleNotificationOpenedFromData(Map<String, dynamic> data) async {
  try {
    final type = (data['type'] as String?)?.trim();
    if (type == 'v3_putnik_eta_start') {
      final putnikId = (data['putnik_id'] as String?)?.trim() ?? '';
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
  final type = (message.data['type'] as String?)?.trim() ?? '';
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
  final type = message.data['type'] as String?;
  final title = (message.notification?.title ?? message.data['title']?.toString() ?? '').trim();
  final body = (message.notification?.body ?? message.data['body']?.toString() ?? '').trim();
  if (type == 'gps_tracking_start') {
    await _handleGpsTrackingStart(message.data);
  } else if (type == 'gps_tracking_complete') {
    await _handleGpsTrackingComplete(message.data);
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
    payload: 'gps_auto_start|$vozacId|$polazakVreme',
  );

  debugPrint('📍 [GPS] Auto start notification prikazana za vozača $vozacId');
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

  try {
    final rawData = message.data;
    if (rawData == null || rawData.isEmpty) return;

    Map<String, dynamic> data;
    if (rawData.startsWith('{')) {
      data = Map<String, dynamic>.from(jsonDecode(rawData) as Map<String, dynamic>);
    } else {
      data = <String, dynamic>{'message': rawData};
    }

    final type = (data['type'] as String?)?.trim() ?? '';
    if (type == 'gps_tracking_start') {
      await _handleGpsTrackingStart(data);
      return;
    }
    if (type == 'gps_tracking_complete') {
      await _handleGpsTrackingComplete(data);
      return;
    }

    if (type.startsWith('v3_')) {
      debugPrint('⏭️ [HMS] Edge-only: lokalni fallback isključen za type=$type');
      return;
    }
  } catch (e) {
    debugPrint('⚠️ [HMS] _handleHmsIncomingMessage parse greška: $e');
  }
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
      await _showActionFeedback('ℹ️ Alternativa', 'Klikni na dugme ✅ ili ❌ u notifikaciji.');
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
    // GPS Auto Start handling
    if ((payload.startsWith('gps_auto_start|') || payload.startsWith('gps_auto_start:')) &&
        actionId == 'auto_start_gps') {
      final parsed = _parseGpsAutoStartPayload(payload);
      if (parsed != null) {
        await _triggerAutoGpsStart(parsed['vozacId']!, parsed['polazakVreme']!);
      } else {
        await _showActionFeedback('⚠️ Greška', 'Neispravan GPS auto-start payload.');
      }
      return;
    }

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
      await V3ZahtevService.prihvatiPonudu(zahtevId, altPre);
      await _showActionFeedback('✅ Alternativa prihvaćena', 'Prihvaćen termin: $altPre');
    } else if (actionId == 'accept_posle' && altPosle.isNotEmpty) {
      await V3ZahtevService.prihvatiPonudu(zahtevId, altPosle);
      await _showActionFeedback('✅ Alternativa prihvaćena', 'Prihvaćen termin: $altPosle');
    } else if (actionId == 'reject') {
      await V3ZahtevService.odbijPonudu(zahtevId);
      await _showActionFeedback('❌ Alternativa odbijena', 'Zahtev je postavljen na odbijeno.');
    } else {
      await _showActionFeedback('⚠️ Akcija nije izvršena', 'Alternativni termin nije prosleđen u notifikaciji.');
    }
  } catch (e) {
    debugPrint('[onNotificationTap] Greška pri obradi akcije: $e');
    await _showActionFeedback('⚠️ Greška', 'Akcija nije uspela: $e');
  }
}

Map<String, String>? _parseGpsAutoStartPayload(String payload) {
  if (payload.startsWith('gps_auto_start|')) {
    final parts = payload.split('|');
    if (parts.length >= 3) {
      final vozacId = parts[1].trim();
      final polazakVreme = parts.sublist(2).join('|').trim();
      if (vozacId.isNotEmpty && polazakVreme.isNotEmpty) {
        return {
          'vozacId': vozacId,
          'polazakVreme': polazakVreme,
        };
      }
    }
    return null;
  }

  if (payload.startsWith('gps_auto_start:')) {
    final rest = payload.substring('gps_auto_start:'.length);
    final firstColon = rest.indexOf(':');
    if (firstColon > 0) {
      final vozacId = rest.substring(0, firstColon).trim();
      final polazakVreme = rest.substring(firstColon + 1).trim();
      if (vozacId.isNotEmpty && polazakVreme.isNotEmpty) {
        return {
          'vozacId': vozacId,
          'polazakVreme': polazakVreme,
        };
      }
    }
  }

  return null;
}

String? _extractTimeToken(String value) {
  final match = RegExp(r'((?:[01]?\d|2[0-3]):[0-5]\d(?:\:[0-5]\d)?)').firstMatch(value);
  return match?.group(1);
}

String _normalizeTimeHHmm(String value) {
  final parts = value.split(':');
  if (parts.length < 2) return value;
  final h = (int.tryParse(parts[0]) ?? 0).toString().padLeft(2, '0');
  final m = (int.tryParse(parts[1]) ?? 0).toString().padLeft(2, '0');
  return '$h:$m';
}

String? _extractGradToken(String value) {
  final up = value.toUpperCase();
  if (up.contains('BC')) return 'BC';
  if (up.contains('VS')) return 'VS';
  return null;
}

DateTime? _combineDatumVreme(dynamic datum, String? vremeHHmm) {
  if (datum == null || vremeHHmm == null || vremeHHmm.isEmpty) return null;
  try {
    final datePart = datum.toString().split('T').first;
    return DateTime.parse('${datePart}T$vremeHHmm:00');
  } catch (_) {
    return null;
  }
}

Future<void> _showActionFeedback(String title, String body) async {
  const androidDetails = AndroidNotificationDetails(
    'gavra_push_v2',
    'Gavra obaveštenja',
    importance: Importance.high,
    priority: Priority.high,
  );

  await flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecondsSinceEpoch.remainder(100000),
    title,
    body,
    const NotificationDetails(android: androidDetails),
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
        polazakVreme: '${result['vreme'] ?? polazakVreme}',
        putnici: [], // Simplified - dodati parsing ako potrebno
        grad: result['grad'] ?? 'BC',
      );

      if (!success) {
        debugPrint('❌ [GPS AutoStart] Failed to start foreground GPS service');
        await _triggerAutoGpsStartFallback(vozacId, polazakVreme);
      }
    } else {
      debugPrint('❌ [GPS AutoStart] SQL function failed: ${result?['message']}');
      await _triggerAutoGpsStartFallback(vozacId, polazakVreme);
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

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final todayIso = today.toIso8601String().split('T').first;
    final tomorrowIso = tomorrow.toIso8601String().split('T').first;

    final rowsRaw = await Supabase.instance.client
        .from('v3_operativna_nedelja')
        .select('datum, grad, dodeljeno_vreme, zeljeno_vreme, status_final, aktivno, putnik_id')
        .eq('vozac_id', vozacId)
        .eq('aktivno', true)
        .gte('datum', todayIso)
        .lte('datum', tomorrowIso);

    final rows = (rowsRaw as List).cast<Map<String, dynamic>>().where((row) {
      final status = (row['status_final']?.toString() ?? '').toLowerCase();
      if (status == 'otkazano' || status == 'odbijeno') return false;
      return row['putnik_id'] != null;
    }).toList();

    if (rows.isEmpty) {
      debugPrint('⚠️ [GPS AutoStart Fallback] Nema aktivnih termina/putnika za vozača $vozacId');
      return;
    }

    final targetGrad = _extractGradToken(polazakVreme);
    final targetTimeRaw = _extractTimeToken(polazakVreme);
    final targetTime = targetTimeRaw != null ? _normalizeTimeHHmm(targetTimeRaw) : null;

    String rowGrad(Map<String, dynamic> row) => (row['grad']?.toString() ?? '').toUpperCase();

    String? rowTime(Map<String, dynamic> row) {
      final raw = row['dodeljeno_vreme']?.toString() ?? row['zeljeno_vreme']?.toString() ?? '';
      final token = _extractTimeToken(raw);
      if (token == null) return null;
      return _normalizeTimeHHmm(token);
    }

    DateTime? rowDateTime(Map<String, dynamic> row) => _combineDatumVreme(row['datum'], rowTime(row));

    List<Map<String, dynamic>> scoped = rows;
    if (targetTime != null) {
      final byTime = scoped.where((r) => rowTime(r) == targetTime).toList();
      if (byTime.isNotEmpty) scoped = byTime;
    }
    if (targetGrad != null) {
      final byGrad = scoped.where((r) => rowGrad(r) == targetGrad).toList();
      if (byGrad.isNotEmpty) scoped = byGrad;
    }

    scoped.sort((a, b) {
      final aDt = rowDateTime(a);
      final bDt = rowDateTime(b);
      if (aDt == null && bDt == null) return 0;
      if (aDt == null) return 1;
      if (bDt == null) return -1;

      final aDiff = aDt.difference(now).inMinutes;
      final bDiff = bDt.difference(now).inMinutes;

      final aScore = aDiff >= 0 ? aDiff : (10000 + aDiff.abs());
      final bScore = bDiff >= 0 ? bDiff : (10000 + bDiff.abs());
      return aScore.compareTo(bScore);
    });

    final selected = scoped.first;
    final selectedGrad = rowGrad(selected).isNotEmpty ? rowGrad(selected) : (targetGrad ?? 'BC');
    final selectedTime = rowTime(selected) ?? targetTime ?? '';
    final selectedDate = selected['datum']?.toString().split('T').first ?? todayIso;

    final putniciCount = scoped.where((r) {
      final sameGrad = rowGrad(r) == selectedGrad;
      final sameTime = rowTime(r) == selectedTime;
      final sameDate = (r['datum']?.toString().split('T').first ?? '') == selectedDate;
      return sameGrad && sameTime && sameDate;
    }).length;

    final success = await V3ForegroundGpsService.startTracking(
      vozacId: vozacId,
      vozacIme: vozacData['ime_prezime']?.toString() ?? 'Vozač',
      polazakVreme: selectedTime,
      putnici: const [],
      grad: selectedGrad,
    );

    if (!success) {
      debugPrint('❌ [GPS AutoStart Fallback] Foreground tracking start failed');
      return;
    }

    await V3ForegroundGpsService.syncTrackingStatus(
      vozacId: vozacId,
      grad: selectedGrad,
      polazakVreme: selectedTime,
      gpsStatus: 'tracking',
      datumIso: selectedDate,
    );

    await flutterLocalNotificationsPlugin.show(
      888,
      '✅ GPS Automatski Pokrenut (fallback)',
      '${vozacData['ime_prezime'] ?? 'Vozač'} - $selectedGrad $selectedTime ($putniciCount putnika)',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'gavra_gps_success',
          'GPS Success',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
    );

    debugPrint('[GPS AutoStart Fallback] Pokrenut: vozac=$vozacId grad=$selectedGrad vreme=$selectedTime');
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

  // Učitaj nav_bar_type iz baze
  try {
    final settings =
        await Supabase.instance.client.from('v3_app_settings').select('nav_bar_type').eq('id', 'global').maybeSingle();

    final navType = settings?['nav_bar_type'] as String?;
    if (navType != null && ['zimski', 'letnji', 'praznici'].contains(navType)) {
      navBarTypeNotifier.value = navType;
      debugPrint('[main] nav_bar_type učitan iz baze: $navType');
    }
  } catch (e) {
    debugPrint('⚠️ [main] Greška pri učitavanju app_settings: $e');
  }

  // Provera da li je dostupna nova verzija aplikacije
  unawaited(V3AppUpdateService.refreshUpdateInfo());
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
