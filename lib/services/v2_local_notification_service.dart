import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../screens/v2_home_screen.dart';
import '../utils/v2_app_snack_bar.dart';
import '../utils/v2_grad_adresa_validator.dart';
import 'realtime/v2_master_realtime_manager.dart';
import 'v2_notification_navigation_service.dart';
import 'v2_polasci_service.dart';
import 'v2_realtime_notification_service.dart';
import 'v2_statistika_istorija_service.dart';
// V2WakeLockService se nalazi na dnu ovog fajla (spojen sa v2_wake_lock_service.dart)

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) async {
  // 1. Inicijalizuj Supabase jer smo u background isolate-u
  try {
    // U background isolate-u V2ConfigService nije dostupan, učitaj direktno iz .env
    await dotenv.load(fileName: '.env');
    final url = dotenv.env['SUPABASE_URL'] ?? '';
    final anonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
  } catch (e) {
    debugPrint('[V2LocalNotificationService] notificationTapBackground Supabase init greška: $e');
  }
  await V2LocalNotificationService.handleNotificationTap(notificationResponse);
}

class V2LocalNotificationService {
  static final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  static final Map<String, DateTime> _recentNotificationIds = {};
  static final Map<String, bool> _processingLocks = {}; // Lock za deduplikaciju
  static const Duration _dedupeDuration = Duration(seconds: 30);

  static Future<void> initialize(BuildContext context) async {
    // SCREENSHOT MODE - preskoči inicijalizaciju notifikacija
    const isScreenshotMode = bool.fromEnvironment('SCREENSHOT_MODE', defaultValue: false);
    if (isScreenshotMode) {
      return;
    }

    try {
      await flutterLocalNotificationsPlugin.cancelAll();
    } catch (e) {
      debugPrint('[V2LocalNotificationService] initialize cancelAll greška: $e');
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        unawaited(handleNotificationTap(response));
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'gavra_push_v2',
      'Gavra Push Notifikacije',
      description: 'Kanal za push notifikacije sa zvukom i vibracijom',
      importance: Importance.max,
      enableLights: true,
      enableVibration: true,
      playSound: true,
      showBadge: true,
    );

    final androidPlugin =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(channel);

    // Request permission for exact alarms and full-screen intents (Android 12+)
    try {
      // Request permission to show full-screen notifications (for lock screen)
      await androidPlugin?.requestNotificationsPermission();
    } catch (e) {
      // Ignore if not supported
    }
  }

  static Future<void> showRealtimeNotification({
    required String title,
    required String body,
    String? payload,
    bool playCustomSound = false, // ONEMOGUĆENO: Custom zvuk ne radi
  }) async {
    String dedupeKey = ''; // Premesteno izvan try-catch da bude dostupno u finally bloku

    try {
      try {
        if (payload != null && payload.isNotEmpty) {
          final Map<String, dynamic> parsed = jsonDecode(payload);
          if (parsed['notification_id'] != null) {
            dedupeKey = parsed['notification_id'].toString();
          }
        }
      } catch (_) {}
      if (dedupeKey.isEmpty) {
        // fallback: simple hash of title+body (ignoring payload which may contain timestamps)
        // Ovo rešava problem duplih notifikacija kada backend stavi timestamp u payload.
        dedupeKey = '$title|$body';
      }

      // MUTEX LOCK - Sprečava race condition kada Firebase i Huawei primaju istu notifikaciju istovremeno
      if (_processingLocks[dedupeKey] == true) {
        return; // Druga instanca već obrađuje ovu notifikaciju
      }
      _processingLocks[dedupeKey] = true;

      final now = DateTime.now();
      if (_recentNotificationIds.containsKey(dedupeKey)) {
        final last = _recentNotificationIds[dedupeKey]!;
        if (now.difference(last) < _dedupeDuration) {
          _processingLocks.remove(dedupeKey); // Oslobodi lock
          return;
        }
      }
      _recentNotificationIds[dedupeKey] = now;
      _recentNotificationIds.removeWhere((k, v) => now.difference(v) > _dedupeDuration);

      // Pali ekran kada stigne notifikacija (za lock screen)
      try {
        await V2WakeLockService.wakeScreen(durationMs: 5000);
      } catch (e) {
        debugPrint('[V2LocalNotificationService] wakeScreen greška: $e');
      }

      // Specijalna obrada za alternative notifikacije
      if (payload != null) {
        try {
          final Map<String, dynamic> data = jsonDecode(payload);
          if (data['type'] == 'v2_alternativa') {
            // Čitanje iz alternative_1 i alternative_2 umesto JSONB niza
            List<String> parsedAlts = [];
            final alt1 = data['alternative_1']?.toString();
            final alt2 = data['alternative_2']?.toString();

            if (alt1 != null && alt1.isNotEmpty && alt1 != 'null') {
              parsedAlts.add(alt1);
            }
            if (alt2 != null && alt2.isNotEmpty && alt2 != 'null') {
              parsedAlts.add(alt2);
            }

            await showV2AlternativaNotification(
              id: data['id']?.toString() ?? '',
              zeljenoVreme: data['vreme']?.toString() ?? '',
              putnikId: data['putnik_id']?.toString() ?? '',
              grad: data['grad']?.toString() ?? 'BC',
              dan: data['dan']?.toString() ?? '',
              alternatives: parsedAlts,
              body: body,
            );
            _processingLocks.remove(dedupeKey);
            return;
          }
        } catch (e) {
          debugPrint('[V2LocalNotificationService] showRealtimeNotification alternativa parse greška: $e');
        }
      }

      await flutterLocalNotificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'gavra_push_v2',
            'Gavra Push Notifikacije',
            channelDescription: 'Kanal za push notifikacije sa zvukom i vibracijom',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableLights: true,
            enableVibration: true,
            // Vibration pattern kao Viber - pali ekran na Huawei
            vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
            when: DateTime.now().millisecondsSinceEpoch,
            category: AndroidNotificationCategory.message,
            visibility: NotificationVisibility.public,
            ticker: '$title - $body',
            color: const Color(0xFF64CAFB),
            largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
            styleInformation: BigTextStyleInformation(
              body,
              htmlFormatBigText: true,
              contentTitle: title,
              htmlFormatContentTitle: true,
            ),
            // Full-screen intent za lock screen (Android 10+)
            fullScreenIntent: true,
            // Dodatne opcije za garantovano prikazivanje
            channelShowBadge: true,
            onlyAlertOnce: false,
            autoCancel: true,
            ongoing: false,
          ),
        ),
        payload: payload,
      );

      // Oslobodi lock nakon uspešnog slanja
      _processingLocks.remove(dedupeKey);
    } catch (e) {
      // Oslobodi lock i u slučaju greške
      _processingLocks.remove(dedupeKey);
    }
  }

  static Future<void> showNotificationFromBackground({
    required String title,
    required String body,
    String? payload,
  }) async {
    String dedupeKey = ''; // Premesteno izvan try-catch za finally blok

    try {
      if (payload != null && payload.isNotEmpty) {
        try {
          final Map<String, dynamic> data = jsonDecode(payload);

          // Specijalna obrada za alternative u pozadini
          if (data['type'] == 'v2_alternativa') {
            // Čitanje iz alternative_1 i alternative_2 umesto JSONB niza
            List<String> parsedAlts = [];
            final alt1 = data['alternative_1']?.toString();
            final alt2 = data['alternative_2']?.toString();

            if (alt1 != null && alt1.isNotEmpty && alt1 != 'null') {
              parsedAlts.add(alt1);
            }
            if (alt2 != null && alt2.isNotEmpty && alt2 != 'null') {
              parsedAlts.add(alt2);
            }

            await showV2AlternativaNotification(
              id: data['id']?.toString() ?? '',
              zeljenoVreme: data['vreme']?.toString() ?? '',
              putnikId: data['putnik_id']?.toString() ?? '',
              grad: data['grad']?.toString() ?? 'BC',
              dan: data['dan']?.toString() ?? '',
              alternatives: parsedAlts,
              body: body,
            );
            return; // Već je prikazana specijalna notifikacija
          }

          if (data['notification_id'] != null) {
            dedupeKey = data['notification_id'].toString();
          }
        } catch (e) {
          debugPrint('[V2LocalNotificationService] showNotificationFromBackground payload parse greška: $e');
        }
      }

      if (dedupeKey.isEmpty) dedupeKey = '$title|$body|${payload ?? ''}';

      // MUTEX LOCK - Sprečava race condition kada foreground i background handleri rade istovremeno
      if (_processingLocks[dedupeKey] == true) {
        return; // Druga instanca već obrađuje ovu notifikaciju
      }
      _processingLocks[dedupeKey] = true;

      final now = DateTime.now();
      if (_recentNotificationIds.containsKey(dedupeKey)) {
        final last = _recentNotificationIds[dedupeKey]!;
        if (now.difference(last) < _dedupeDuration) {
          _processingLocks.remove(dedupeKey); // Oslobodi lock
          return;
        }
      }
      _recentNotificationIds[dedupeKey] = now;
      _recentNotificationIds.removeWhere((k, v) => now.difference(v) > _dedupeDuration);
      final FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
      );

      await plugin.initialize(
        initializationSettings,
      );

      final androidDetails = AndroidNotificationDetails(
        'gavra_push_v2',
        'Gavra Push Notifikacije',
        channelDescription: 'Kanal za push notifikacije sa zvukom i vibracijom',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        // Vibration pattern kao Viber - pali ekran na Huawei
        vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
        category: AndroidNotificationCategory.message,
        visibility: NotificationVisibility.public,
        // Full-screen intent za lock screen (Android 10+)
        fullScreenIntent: true,
        // Dodatne opcije za garantovano prikazivanje
        channelShowBadge: true,
        onlyAlertOnce: false,
        autoCancel: true,
        ongoing: false,
        enableLights: true,
      );

      final platformChannelSpecifics = NotificationDetails(
        android: androidDetails,
      );

      // Wake screen for lock screen notifications
      await V2WakeLockService.wakeScreen(durationMs: 10000);

      await plugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        platformChannelSpecifics,
        payload: payload,
      );

      // Oslobodi lock nakon uspešnog slanja
      _processingLocks.remove(dedupeKey);
    } catch (e) {
      // Oslobodi lock i u slučaju greške
      _processingLocks.remove(dedupeKey);
    }
  }

  static Future<void> handleNotificationTap(
    NotificationResponse response,
  ) async {
    try {
      // Handle Seat Request alternativa action buttons
      if (response.actionId != null && response.actionId!.startsWith('prihvati_alt_')) {
        await _handleV2AlternativaAction(response);
        return;
      }

      // Handle BC alternativa action buttons
      if (response.actionId != null && response.actionId!.startsWith('prihvati_')) {
        await _handleBcAlternativaAction(response);
        return;
      }

      // Handle VS alternativa action buttons
      if (response.actionId != null && response.actionId!.startsWith('vs_prihvati_')) {
        await _handleVsAlternativaAction(response);
        return;
      }

      // Odustani akcija (BC) - samo zatvori notifikaciju
      if (response.actionId == 'odustani') {
        return;
      }

      // Odustani akcija (VS)
      if (response.actionId == 'vs_odustani') {
        return;
      }

      final context = navigatorKey.currentContext;
      if (context == null) return;

      String? putnikIme;
      String? notificationType;
      String? putnikGrad;
      String? putnikVreme;

      if (response.payload != null) {
        try {
          final Map<String, dynamic> payloadData = jsonDecode(response.payload!) as Map<String, dynamic>;

          // Assign notificationType from payload
          notificationType = payloadData['type'] as String?;

          // BC/VS alternativa ili v2 polazak - otvori profil
          if (notificationType == 'bc_alternativa' ||
              notificationType == 'vs_alternativa' ||
              notificationType == 'v2_alternativa' ||
              notificationType == 'v2_odobreno' ||
              notificationType == 'v2_odbijeno') {
            await V2NotificationNavigationService.navigateToPassengerProfile();
            return;
          }

          // PIN zahtev ili v2 obrada - otvori PIN zahtevi ekran (Admin/Vozac screen)
          if (notificationType == 'pin_zahtev' || notificationType == 'v2_obrada') {
            await V2NotificationNavigationService.navigateToPinZahtevi();
            return;
          }

          final putnikData = payloadData['V2Putnik'];
          if (putnikData is Map<String, dynamic>) {
            putnikIme = (putnikData['ime'] ?? putnikData['name']) as String?;
            putnikGrad = putnikData['grad'] as String?;
            putnikVreme = (putnikData['vreme'] ?? putnikData['polazak']) as String?;
          } else if (putnikData is String) {
            try {
              final putnikMap = jsonDecode(putnikData);
              if (putnikMap is Map<String, dynamic>) {
                putnikIme = (putnikMap['ime'] ?? putnikMap['name']) as String?;
                putnikGrad = putnikMap['grad'] as String?;
                putnikVreme = (putnikMap['vreme'] ?? putnikMap['polazak']) as String?;
              }
            } catch (e) {
              putnikIme = putnikData;
            }
          }

          // Dohvati V2Putnik podatke iz baze ako nisu u payload-u
          if (putnikIme != null && (putnikGrad == null || putnikVreme == null)) {
            try {
              final putnikInfo = await _fetchPutnikFromDatabase(putnikIme);
              if (putnikInfo != null) {
                putnikGrad = putnikGrad ?? putnikInfo['grad'] as String?;
                putnikVreme = putnikVreme ?? (putnikInfo['polazak'] ?? putnikInfo['vreme_polaska']) as String?;
              }
            } catch (_) {}
          }
        } catch (_) {}
      }

      // Handle transport_started notifikacije - otvori putnikov profil
      if (notificationType == 'transport_started') {
        await V2NotificationNavigationService.navigateToPassengerProfile();
        return; // Ne navigiraj dalje
      }

      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const V2HomeScreen(),
          ),
        );
      }

      if (putnikIme != null && context.mounted) {
        String message;
        Color bgColor;

        if (notificationType == 'novi_putnik') {
          message = 'Dodat V2Putnik: $putnikIme';
          bgColor = Colors.green;
        } else if (notificationType == 'otkazan_putnik') {
          message = 'Otkazan V2Putnik: $putnikIme';
          bgColor = Colors.red;
        } else {
          message = 'V2Putnik: $putnikIme';
          bgColor = Colors.blue;
        }

        if (bgColor == Colors.green) {
          V2AppSnackBar.success(context, message);
        } else if (bgColor == Colors.red) {
          V2AppSnackBar.error(context, message);
        } else if (bgColor == Colors.orange) {
          V2AppSnackBar.warning(context, message);
        } else {
          V2AppSnackBar.info(context, message);
        }
      }
    } catch (e) {
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const V2HomeScreen(),
          ),
        );
      }
    }
  }

  /// Dohvata podatke o V2Putniku iz baze po imenu.
  /// Koristi v2_polasci kao izvor istine za termine
  static Future<Map<String, dynamic>?> _fetchPutnikFromDatabase(
    String putnikIme,
  ) async {
    try {
      final danas = DateTime.now();
      const dani = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
      final danKratica = dani[danas.weekday - 1];

      // Traži putnika po imenu iz cache-a — 0 DB querija
      final rm = V2MasterRealtimeManager.instance;
      final cached = rm.v2GetAllPutnici().where((p) => p['ime'] == putnikIme && p['status'] != 'neaktivan').firstOrNull;
      final putnikId = cached?['id'] as String?;
      if (putnikId == null) return null;

      // Nađi njegovu današnju vožnju u v2_polasci
      final polazak = await supabase
          .from('v2_polasci')
          .select('grad, zeljeno_vreme')
          .eq('putnik_id', putnikId)
          .eq('dan', danKratica)
          .inFilter('status', ['obrada', 'odobreno']).maybeSingle();

      if (polazak != null) {
        final gradRaw = polazak['grad']?.toString() ?? '';
        final grad = V2GradAdresaValidator.normalizeGrad(gradRaw);
        final zeljenoVremeStr = polazak['zeljeno_vreme']?.toString() ?? '';
        final vreme = zeljenoVremeStr.length >= 5 ? zeljenoVremeStr.substring(0, 5) : null;

        return {
          'grad': grad,
          'polazak': vreme,
          'dan': _getDanNedelje(DateTime.now().weekday),
          'tip': 'registrovani',
        };
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  static String _getDanNedelje(int weekday) {
    switch (weekday) {
      case 1:
        return 'pon';
      case 2:
        return 'uto';
      case 3:
        return 'sre';
      case 4:
        return 'cet';
      case 5:
        return 'pet';
      case 6:
        return 'sub';
      case 7:
        return 'ned';
      default:
        return 'pon';
    }
  }

  /// Handler za BC alternativa action button - sačuva izabrani termin
  static Future<void> _handleBcAlternativaAction(NotificationResponse response) async {
    try {
      if (response.payload == null || response.actionId == null) return;

      final payloadData = jsonDecode(response.payload!) as Map<String, dynamic>;

      // Izvuci termin iz actionId (format: "prihvati_7:00")
      final termin = response.actionId!.replaceFirst('prihvati_', '');

      final putnikId = payloadData['putnikId'] as String?;
      final dan = payloadData['dan'] as String?;

      if (putnikId == null || dan == null || termin.isEmpty) return;

      // Prihvati alternativu u v2_polasci
      final ok = await V2PolasciService.v2PrihvatiAlternativu(
        putnikId: putnikId,
        novoVreme: termin,
        grad: 'BC',
        dan: dan,
      );
      if (!ok) {
        debugPrint('[V2LocalNotificationService] _handleBcAlternativaAction: prihvatiAlternativu nije uspjelo');
        return;
      }

      // Dohvati tip korisnika iz cache-a
      final putnikData = V2MasterRealtimeManager.instance.v2GetPutnikById(putnikId);
      final userType = putnikData?['_tabela'] ?? 'V2Putnik';

      // LOG
      try {
        await V2StatistikaIstorijaService.logPotvrda(
          putnikId: putnikId,
          dan: dan,
          vreme: termin,
          grad: 'BC',
          tipPutnika: userType,
          detalji: 'Prihvaćen alternativni termin BC (Preko notifikacije)',
        );
      } catch (e) {
        debugPrint('[V2LocalNotificationService] logPotvrda BC alt greška: $e');
      }

      // Pošalji push notifikaciju putniku
      await V2RealtimeNotificationService.sendNotificationToPutnik(
        putnikId: putnikId,
        title: '✅ Mesto osigurano!',
        body: '✅ Mesto osigurano! Vaša rezervacija za $termin je potvrđena. Želimo vam ugodnu vožnju! 🚌',
        data: {'type': 'bc_alternativa_confirmed', 'termin': termin},
      );
    } catch (e) {
      debugPrint('[V2LocalNotificationService] _handleBcAlternativaAction greška: $e');
    }
  }

  /// Handler za VS alternativa action button
  static Future<void> _handleVsAlternativaAction(NotificationResponse response) async {
    try {
      if (response.payload == null || response.actionId == null) return;

      final payloadData = jsonDecode(response.payload!) as Map<String, dynamic>;

      // Izvuci termin iz actionId (format: "vs_prihvati_7:00")
      final termin = response.actionId!.replaceFirst('vs_prihvati_', '');

      final putnikId = payloadData['putnikId'] as String?;
      final dan = payloadData['dan'] as String?;

      if (putnikId == null || dan == null || termin.isEmpty) return;

      // Prihvati alternativu u v2_polasci
      final okVs = await V2PolasciService.v2PrihvatiAlternativu(
        putnikId: putnikId,
        novoVreme: termin,
        grad: 'VS',
        dan: dan,
      );
      if (!okVs) {
        debugPrint('[V2LocalNotificationService] _handleVsAlternativaAction: prihvatiAlternativu nije uspjelo');
        return;
      }

      // Dohvati tip korisnika iz cache-a
      final putnikResult = V2MasterRealtimeManager.instance.v2GetPutnikById(putnikId);
      final userType = putnikResult?['_tabela'] ?? 'V2Putnik';

      // LOG
      try {
        await V2StatistikaIstorijaService.logPotvrda(
          putnikId: putnikId,
          dan: dan,
          vreme: termin,
          grad: 'VS',
          tipPutnika: userType,
          detalji: 'Prihvaćen alternativni termin VS (Preko notifikacije)',
        );
      } catch (e) {
        debugPrint('[V2LocalNotificationService] logPotvrda VS greška: $e');
      }

      // Pošalji push notifikaciju putniku
      await V2RealtimeNotificationService.sendNotificationToPutnik(
        putnikId: putnikId,
        title: '✅ [VS] Termin potvrđen',
        body: '✅ Mesto osigurano! Vaša rezervacija za $termin je potvrđena. Želimo vam ugodnu vožnju! 🚌',
        data: {'type': 'vs_alternativa_confirmed', 'termin': termin},
      );
    } catch (e) {
      debugPrint('[V2LocalNotificationService] _handleVsAlternativaAction greška: $e');
    }
  }

  /// Prikazuje notifikaciju sa alternativnim polascima (+/- 3 sata)
  static Future<void> showV2AlternativaNotification({
    required String id,
    required String zeljenoVreme,
    required String putnikId,
    required String grad,
    required String dan,
    required List<String> alternatives,
    required String body,
  }) async {
    try {
      final payload = jsonEncode({
        'type': 'v2_alternativa',
        'id': id,
        'putnik_id': putnikId,
        'grad': grad,
        'zeljenoVreme': zeljenoVreme,
        'dan': dan,
        'alternatives': alternatives,
      });

      final actions = <AndroidNotificationAction>[];

      // Dodaj prve dve alternative kao dugmiće
      for (int i = 0; i < alternatives.length && i < 2; i++) {
        final alt = alternatives[i];
        final displayTime = alt.contains(':') ? '${alt.split(':')[0]}:${alt.split(':')[1]}' : alt;
        actions.add(AndroidNotificationAction(
          'prihvati_alt_$alt',
          '✅ $displayTime',
          showsUserInterface: true,
        ));
      }

      // Dugme za odbijanje (zatvaranje)
      actions.add(const AndroidNotificationAction(
        'odbij_alt',
        '❌ Odbij',
        cancelNotification: true,
      ));

      await flutterLocalNotificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        '🕐 Termin popunjen',
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'gavra_push_v2',
            'Gavra Push Notifikacije',
            channelDescription: 'Kanal za push notifikacije sa zvukom i vibracijom',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
            actions: actions,
            fullScreenIntent: true,
            autoCancel: true,
            category: AndroidNotificationCategory.message,
            visibility: NotificationVisibility.public,
          ),
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('[V2LocalNotificationService] showV2AlternativaNotification greška: $e');
    }
  }

  static Future<void> _handleV2AlternativaAction(NotificationResponse response) async {
    try {
      if (response.payload == null || response.actionId == null) return;
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      final requestId = data['id']?.toString();
      final putnikId = data['putnik_id']?.toString();
      final grad = data['grad']?.toString() ?? 'BC';
      final dan = data['dan']?.toString();

      if (putnikId == null || dan == null) {
        return;
      }

      final selectedTime = response.actionId!.replaceFirst('prihvati_alt_', '');

      // Prihvati alternativu -> status postaje 'odobreno' -> trigger šalje push potvrde
      final success = await V2PolasciService.v2PrihvatiAlternativu(
        requestId: requestId,
        putnikId: putnikId,
        novoVreme: selectedTime,
        grad: grad,
        dan: dan,
      );

      if (!success) {
        debugPrint('[V2LocalNotificationService] _handleV2AlternativaAction: prihvatiAlternativu nije uspjelo');
      }
    } catch (e) {
      debugPrint('[V2LocalNotificationService] _handleV2AlternativaAction greška: $e');
    }
  }
}

// =============================================================================
// Spojen iz v2_wake_lock_service.dart
// =============================================================================

/// Servis za paljenje ekrana kada stigne notifikacija.
/// Koristi native Android WakeLock API.
class V2WakeLockService {
  V2WakeLockService._();

  static const MethodChannel _wakeLockChannel = MethodChannel('com.gavra013.gavra_android/wakelock');

  /// Pali ekran na određeno vreme (default 5 sekundi).
  /// Koristi se kada stigne push notifikacija dok je telefon zaključan.
  static Future<bool> wakeScreen({int durationMs = 5000}) async {
    try {
      final result = await _wakeLockChannel.invokeMethod<bool>('wakeScreen', {
        'duration': durationMs,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }
}
