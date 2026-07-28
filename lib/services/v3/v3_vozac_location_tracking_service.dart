import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../globals.dart';
import '../../utils/v3_date_utils.dart';
import '../../utils/v3_time_utils.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'v3_slot_activation.dart';
import 'v3_tracking_config.dart';

enum V3LocationPrereqStatus {
  ok,
  serviceDisabled,
  denied,
}

/// iOS ekvivalent Android-ove foreground notifikacije koja se ažurira sa
/// imenom sledećeg putnika + ETA. iOS nema pravi "ongoing" foreground-service
/// koncept, pa se koristi obična lokalna notifikacija sa FIKSNIM id-jem —
/// svaki `show()` poziv sa istim id-jem zamenjuje prethodnu (iOS notification
/// center tretira to kao update, ne kao novu notifikaciju), uz
/// `interruptionLevel: passive` da se izbegne zvuk/vibracija na svako
/// osvežavanje. Za razliku od Androida, korisnik je može ručno obrisati
/// (swipe) — tracking i dalje radi u pozadini, samo se notifikacija gubi dok
/// je sledeći tick ne prikaže ponovo.
const int _kIosTrackingNotifId = 890;

class V3VozacLocationTrackingService with WidgetsBindingObserver {
  V3VozacLocationTrackingService._();

  static final V3VozacLocationTrackingService instance = V3VozacLocationTrackingService._();

  String _activeVozacId = '';
  String _activeDatumIso = '';
  String _activeGrad = '';
  String _activeVreme = '';
  Position? _lastSentPosition;
  bool _isRunning = false;
  bool _startInProgress = false;

  DateTime? _trackingStartedAt;

  /// iOS nema pravi background isolate (flutter_background_service na iOS-u
  /// se oslanja na retke/negarantovane background fetch pozive). Zato na iOS-u
  /// koristimo Geolocator position stream sa allowsBackgroundLocationUpdates,
  /// koji iOS budi na promenu lokacije čak i kad je app suspendovana. Stream
  /// SAMO osvežava poslednju poznatu poziciju (jeftino, bez mreže) — jedini
  /// izvor istine za "kada se šalje GPS/ETA" je `_iosTicker` ispod
  /// (`V3SelfReschedulingTicker`, isti model kao Android-ov background
  /// isolate tajmer — v3_tracking_config.dart). Ovo eliminiše zavisnost od
  /// toga da li GPS stream emituje evente dok vozač stoji (nije
  /// garantovano) — tajmer garantuje tačan tick svakih
  /// `v3TrackingTickInterval`.
  StreamSubscription<Position>? _iosPositionSub;
  // Interval je JEDAN IZVOR ISTINE deljen sa Android background isolate-om —
  // vidi `v3TrackingTickInterval` u v3_tracking_config.dart.
  V3SelfReschedulingTicker? _iosTicker;
  FlutterLocalNotificationsPlugin? _iosNotificationsPlugin;
  bool _iosNotificationsInitialized = false;

  // Supabase kredencijali i dalje idu preko SecureStorage (osetljivi podaci).
  // Mora biti identično sa konstantama u v3_background_location_handler.dart
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const String _kStorageSupabaseUrl = 'bg_tracking_supabase_url';
  static const String _kStorageSupabaseAnonKey = 'bg_tracking_supabase_anon_key';

  // JEDAN IZVOR ISTINE za iOS-only session SecureStorage kljuceve (koriste ih
  // start()/stop()/_restoreAndResumeIfNeeded() - ranije bili ponovljeni kao
  // string literali na 3 mesta, rizik od typo-a).
  static const String _kIosSessionStartedAt = 'vozac_tracking_started_at';
  static const String _kIosSessionVozacId = 'vozac_tracking_vozac_id';
  static const String _kIosSessionDatumIso = 'vozac_tracking_datum_iso';
  static const String _kIosSessionGrad = 'vozac_tracking_grad';
  static const String _kIosSessionVreme = 'vozac_tracking_vreme';

  // JEDAN IZVOR ISTINE za "šta bi background tracking trebalo da radi" —
  // ključevi (`v3Key*`) su sada deljeni sa Android background isolate-om
  // preko v3_tracking_config.dart (ranije duplirano ovde i u
  // v3_background_location_handler.dart). MORAJU ostati identični sa
  // `KEY_ACTIVE_*` u GavraFcmService.kt (Kotlin ne može da uveze Dart fajl).

  /// Optimizovani redosled putnika (deljen između ekrana)
  final List<String> _optimizedPutnikIds = [];

  /// ETA vrednosti (deljene između ekrana)
  final Map<String, int> _etaSecondsCache = {};

  /// Poziva se nakon svakog uspešnog slanja GPS pozicije (foreground).
  void Function(Position position)? onLocationSent;

  // 🗺️ Realtime broadcast kanal — samo poslednja pozicija vozača, bez čuvanja
  // u bazi. Koristi ga admin ekran da uživo prikaže marker na mapi (besplatno,
  // preko postojećeg Supabase Realtime broadcast-a, nema dodatnih troškova).
  // JEDAN IZVOR ISTINE za broadcast poslednje GPS pozicije (bez čuvanja u
  // bazi) — deljeno sa Android background isolate-om preko
  // `V3PozicijaBroadcaster` u v3_tracking_config.dart (ranije duplirana
  // logika ovde i u `_bgBroadcastPozicija` u
  // v3_background_location_handler.dart).
  final V3PozicijaBroadcaster _pozicijaBroadcaster = V3PozicijaBroadcaster();

  /// Zadržano radi kompatibilnosti sa postojećim pozivaocima
  /// (`v3_admin_vozac_pozicija_screen.dart`) — delegira na deljenu
  /// implementaciju kanala.
  static String pozicijaChannelName(String vozacId) => V3PozicijaBroadcaster.channelName(vozacId);

  bool get isRunning => _isRunning;

  String? get activeVozacId => _activeVozacId.isNotEmpty ? _activeVozacId : null;
  String get activeDatumIso => _activeDatumIso;
  String get activeGrad => _activeGrad;
  String get activeVreme => _activeVreme;
  Position? get lastKnownPosition => _lastSentPosition;
  List<String> get optimizedPutnikIds => List.unmodifiable(_optimizedPutnikIds);
  Map<String, int> get etaSecondsCache => Map.unmodifiable(_etaSecondsCache);

  /// Delegira na deljeni `V3DateUtils.parseIsoDatePart` (JEDAN IZVOR ISTINE za
  /// normalizaciju ISO datuma na `yyyy-MM-dd`, ranije duplirano ovde kao
  /// privatna, manje robustna kopija bez podrske za timezone offset).
  String _normalizeDateIso(String raw) => V3DateUtils.parseIsoDatePart(raw);

  /// Upisuje "zeljeno stanje"
  /// gde main isolate govori background isolate-u šta treba da prati. Background
  /// isolate (Android) ovo čita svakih 20s (polling), pa nema potrebe za bilo
  /// kakvim `service.invoke()` event-ima za prenos termina/vozača/kredencijala.
  Future<void> _writeDesiredState({required String vozacId}) async {
    if (!configService.isInitialized) {
      await configService.initializeBasic();
    }
    final url = configService.getSupabaseUrl().trim();
    final anonKey = configService.getSupabaseAnonKey().trim();
    if (url.isNotEmpty && anonKey.isNotEmpty) {
      // Supabase kredencijali idu preko SecureStorage (osetljivi podaci),
      // potrebni background isolate-u za cold-start bez main isolate-a.
      // ČEKAMO upis da bismo izbegli race condition gde background servis krene
      // pre nego što kredencijali budu dostupni.
      try {
        await _secureStorage.write(key: _kStorageSupabaseUrl, value: url);
        await _secureStorage.write(key: _kStorageSupabaseAnonKey, value: anonKey);
        debugPrint('[V3VozacLocationTrackingService] Supabase kredencijali upisani u SecureStorage');
      } catch (e) {
        debugPrint('[V3VozacLocationTrackingService] Greška pri upisu Supabase kredencijala: $e');
      }

      // Fallback: upiši i u SharedPreferences jer FlutterSecureStorage ponekad
      // ne radi u headless background isolate-u (npr. zbog enkripcije keystore-a
      // kada app nije u foreground-u).
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kStorageSupabaseUrl, url);
        await prefs.setString(_kStorageSupabaseAnonKey, anonKey);
        debugPrint('[V3VozacLocationTrackingService] Supabase kredencijali upisani u SharedPreferences fallback');
      } catch (e) {
        debugPrint('[V3VozacLocationTrackingService] Greška pri upisu Supabase fallback: $e');
      }
    } else {
      debugPrint(
          '[V3VozacLocationTrackingService] Upozorenje: Supabase URL/anon key su prazni — background isolate neće moći da se inicijalizuje');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(v3KeyVozacId, vozacId);
      await prefs.setString(v3KeyDatumIso, _activeDatumIso);
      await prefs.setString(v3KeyGrad, _activeGrad);
      await prefs.setString(v3KeyVreme, _activeVreme);
      final startedAt = _trackingStartedAt;
      if (startedAt != null) {
        await prefs.setInt(v3KeyStartedAt, startedAt.millisecondsSinceEpoch);
      }
      debugPrint(
          '[V3VozacLocationTrackingService] Željeno stanje upisano u SharedPreferences: vozac=$vozacId datum=$_activeDatumIso grad=$_activeGrad vreme=$_activeVreme');
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] Greška pri upisu željenog stanja: $e');
    }
  }

  Future<void> _clearDesiredState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await v3ClearDesiredState(prefs);
      // Obriši i fallback Supabase kredencijale
      await prefs.remove(_kStorageSupabaseUrl);
      await prefs.remove(_kStorageSupabaseAnonKey);
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] Greška pri brisanju željenog stanja: $e');
    }
  }

  void setActiveTermin({required String datumIso, required String grad, required String vreme}) {
    _activeDatumIso = _normalizeDateIso(datumIso);
    _activeGrad = grad.trim().toUpperCase();
    _activeVreme = V3TimeUtils.normalizeToHHmm(vreme);

    // Očisti deljene ETA/redosled keševe jer je termin promenjen
    _optimizedPutnikIds.clear();
    _etaSecondsCache.clear();

    if (_isRunning && _activeVozacId.isNotEmpty) {
      unawaited(_writeDesiredState(vozacId: _activeVozacId));
    }
  }

  /// Upisuje samo "željeno stanje" bez pokretanja servisa.
  /// Koristi se na iOS-u iz background push handler-a, gde background
  /// execution traje kratko i ne može pouzdano da pokrene pun tracking.
  /// Pravi tracking se nastavlja kada app dođe u foreground.
  Future<void> writeDesiredStateFromPayload({
    required String vozacId,
    required String datumIso,
    required String grad,
    required String vreme,
  }) async {
    final normalizedVozacId = vozacId.trim();
    final normalizedGrad = grad.trim().toUpperCase();
    final normalizedVreme = V3TimeUtils.normalizeToHHmm(vreme);
    final normalizedDatumIso = _normalizeDateIso(datumIso);

    if (normalizedVozacId.isEmpty || normalizedDatumIso.isEmpty || normalizedGrad.isEmpty || normalizedVreme.isEmpty) {
      return;
    }

    setActiveTermin(
      datumIso: normalizedDatumIso,
      grad: normalizedGrad,
      vreme: normalizedVreme,
    );

    _activeVozacId = normalizedVozacId;
    // Resetuj timer samo ako je u pitanju novi vozač ili nema aktive sesije —
    // isto kao u start(). Ako isti vozač već ima aktivan tracking, zadrži
    // postojeći startedAt da se ne produži max trajanje sesije.
    if (_activeVozacId != normalizedVozacId || !_isRunning) {
      _trackingStartedAt = DateTime.now();
    }

    if (Platform.isIOS) {
      unawaited(_secureStorage.write(key: _kIosSessionStartedAt, value: _trackingStartedAt!.toIso8601String()));
      unawaited(_secureStorage.write(key: _kIosSessionVozacId, value: normalizedVozacId));
      unawaited(_secureStorage.write(key: _kIosSessionDatumIso, value: _activeDatumIso));
      unawaited(_secureStorage.write(key: _kIosSessionGrad, value: _activeGrad));
      unawaited(_secureStorage.write(key: _kIosSessionVreme, value: _activeVreme));
    }

    await _writeDesiredState(vozacId: normalizedVozacId);
  }

  Future<void> startFromPayload({
    required String vozacId,
    required String datumIso,
    required String grad,
    required String vreme,
  }) async {
    if (_startInProgress) {
      debugPrint('[V3VozacLocationTrackingService] startFromPayload u toku, preskačem');
      return;
    }
    _startInProgress = true;

    try {
      final normalizedVozacId = vozacId.trim();
      final normalizedGrad = grad.trim().toUpperCase();
      final normalizedVreme = V3TimeUtils.normalizeToHHmm(vreme);
      final normalizedDatumIso = _normalizeDateIso(datumIso);

      if (normalizedVozacId.isEmpty ||
          normalizedDatumIso.isEmpty ||
          normalizedGrad.isEmpty ||
          normalizedVreme.isEmpty) {
        debugPrint(
            '[V3VozacLocationTrackingService] startFromPayload skipped: invalid payload vozac=$normalizedVozacId datum=$normalizedDatumIso grad=$normalizedGrad vreme=$normalizedVreme');
        return;
      }

      setActiveTermin(
        datumIso: normalizedDatumIso,
        grad: normalizedGrad,
        vreme: normalizedVreme,
      );

      await start(vozacId: normalizedVozacId);
    } finally {
      _startInProgress = false;
    }
  }

  Future<void> clearEtaForVozac({required String vozacId}) {
    return v3ClearEtaForVozac(
      client: Supabase.instance.client,
      vozacId: vozacId,
      logTag: '[V3VozacLocationTrackingService]',
    );
  }

  /// Proverava da li su svi putnici u aktivnom slotu završeni (pokupljeni ili
  /// otkazani). Delegira na `v3AllPassengersCompleted` (JEDAN IZVOR ISTINE,
  /// deljen sa Android background isolate-om) — ranije duplirana upitna
  /// logika u v3_tracking_config.dart.
  Future<bool> _allPassengersCompleted() {
    return v3AllPassengersCompleted(
      client: Supabase.instance.client,
      datumIso: _activeDatumIso,
      grad: _activeGrad,
      vreme: _activeVreme,
      logTag: '[V3VozacLocationTrackingService]',
    );
  }

  Future<void> start({required String vozacId}) async {
    final normalizedVozacId = vozacId.trim();
    debugPrint('[V3VozacLocationTrackingService] start() pozvan za vozac=$normalizedVozacId');
    if (normalizedVozacId.isEmpty) {
      debugPrint('[V3VozacLocationTrackingService] start() prekinut: prazan vozacId');
      return;
    }

    // Guard: sprečava race condition kada i main isolate i headless BG isolate
    // pokušaju start() istovremeno (npr. foreground push — oba puta async).
    if (_startInProgress) {
      debugPrint('[V3VozacLocationTrackingService] start() u toku, preskačem duplikat za vozač=$normalizedVozacId');
      return;
    }
    _startInProgress = true;

    try {
      // Jedan vozač može imati samo jedan aktivan tracking.
      // Ako je već aktivan za istog vozača, samo ažuriraj termin u background servisu.
      if (_activeVozacId == normalizedVozacId && _isRunning) {
        final service = FlutterBackgroundService();
        final running = await service.isRunning();
        debugPrint('[V3VozacLocationTrackingService] Već aktivno za istog vozača — servis running=$running');
        if (running) {
          debugPrint(
              '[V3VozacLocationTrackingService] Već aktivno za istog vozača — ažuriram termin: datum=$_activeDatumIso grad=$_activeGrad vreme=$_activeVreme');
          await _writeDesiredState(vozacId: normalizedVozacId);
        }
        return; // finally će resetovati _startInProgress
      }

      // Ako je aktivan bilo koji tracking (isti ili drugi vozač), prvo ga zaustavi.
      if (_isRunning || _activeVozacId.isNotEmpty) {
        debugPrint('[V3VozacLocationTrackingService] Zaustavljam prethodni tracking pre starta');
        await stop();
      }

      _activeVozacId = normalizedVozacId;
      _trackingStartedAt = DateTime.now();
      debugPrint('[V3VozacLocationTrackingService] Novi tracking startedAt=$_trackingStartedAt');

      // Napomena: ove SecureStorage kljuceve i dalje koristi SAMO iOS restore
      // put (_restoreAndResumeIfNeeded) jer iOS nema headless background
      // isolate koji bi mogao da čita unified SharedPreferences stanje kad je
      // app killed — Android koristi isključivo _writeDesiredState ispod.
      if (Platform.isIOS) {
        debugPrint('[V3VozacLocationTrackingService] Upisujem iOS session u SecureStorage');
        unawaited(_secureStorage.write(key: _kIosSessionStartedAt, value: _trackingStartedAt!.toIso8601String()));
        unawaited(_secureStorage.write(key: _kIosSessionVozacId, value: normalizedVozacId));
        unawaited(_secureStorage.write(key: _kIosSessionDatumIso, value: _activeDatumIso));
        unawaited(_secureStorage.write(key: _kIosSessionGrad, value: _activeGrad));
        unawaited(_secureStorage.write(key: _kIosSessionVreme, value: _activeVreme));
      }

      final prereqStatus = await checkLocationPrerequisites();
      debugPrint('[V3VozacLocationTrackingService] checkLocationPrerequisites status=$prereqStatus');
      if (prereqStatus != V3LocationPrereqStatus.ok) {
        debugPrint('[V3VozacLocationTrackingService] start() prekinut, prereq status=$prereqStatus');
        await stop();
        return; // finally će resetovati _startInProgress
      }

      // Aktiviraj slot red (idempotentan upsert) — jedina implementacija ove
      // logike, deljena i sa background isolate-om (v3_slot_activation.dart).
      debugPrint(
          '[V3VozacLocationTrackingService] Aktiviram slot: datum=$_activeDatumIso grad=$_activeGrad vreme=$_activeVreme');
      unawaited(activateSlotWithRetry(
        client: Supabase.instance.client,
        vozacId: normalizedVozacId,
        datumIso: _activeDatumIso,
        grad: _activeGrad,
        vreme: _activeVreme,
        logTag: '[V3VozacLocationTrackingService]',
        log: debugPrint,
      ));

      if (Platform.isIOS) {
        debugPrint('[V3VozacLocationTrackingService] Pokrećem iOS tracking');
        await _startIosTracking();
        return; // finally će resetovati _startInProgress
      }

      // Upiši željeno stanje PRE pokretanja background servisa, tako da
      // headless isolate odmah pri prvom tick-u zna ko se prati. Ako bude
      // upisano posle startService(), prvi tick bi mogao da pročita prazno
      // stanje i odloži prvo slanje lokacije za dodatnih ~20s.
      debugPrint('[V3VozacLocationTrackingService] Upisujem željeno stanje pre startService()');
      await _writeDesiredState(vozacId: normalizedVozacId);
      debugPrint('[V3VozacLocationTrackingService] Željeno stanje upisano');

      final service = FlutterBackgroundService();
      var isServiceRunning = await service.isRunning();
      debugPrint('[V3VozacLocationTrackingService] Background service running=$isServiceRunning');
      if (!isServiceRunning) {
        try {
          debugPrint('[V3VozacLocationTrackingService] Pozivam service.startService()');
          await service.startService();
        } catch (e) {
          debugPrint('[V3VozacLocationTrackingService] Failed to start background service: $e');
          await stop();
          return;
        }
        isServiceRunning = await service.isRunning();
        debugPrint(
            '[V3VozacLocationTrackingService] Background service running nakon startService()=$isServiceRunning');
        if (!isServiceRunning) {
          debugPrint('[V3VozacLocationTrackingService] Background service did not start.');
          await stop();
          return; // finally će resetovati _startInProgress
        }
      }

      _isRunning = true;
      debugPrint('[V3VozacLocationTrackingService] Tracking označen kao aktivan (_isRunning=true)');
    } finally {
      _startInProgress = false;
    }
  }

  Future<void> stop() async {
    debugPrint('[V3VozacLocationTrackingService] stop() pozvan');
    final vozacIdToClean = _activeVozacId;
    _activeVozacId = '';
    _activeDatumIso = '';
    _activeGrad = '';
    _activeVreme = '';
    _lastSentPosition = null;
    _isRunning = false;
    _trackingStartedAt = null;
    onLocationSent = null;
    _optimizedPutnikIds.clear();
    _etaSecondsCache.clear();

    final channelToRemove = _pozicijaBroadcaster;
    channelToRemove.dispose(Supabase.instance.client);

    unawaited(_clearDesiredState());
    unawaited(_secureStorage.delete(key: _kIosSessionStartedAt));
    unawaited(_secureStorage.delete(key: _kIosSessionVozacId));
    unawaited(_secureStorage.delete(key: _kIosSessionDatumIso));
    unawaited(_secureStorage.delete(key: _kIosSessionGrad));
    unawaited(_secureStorage.delete(key: _kIosSessionVreme));

    await _iosPositionSub?.cancel();
    _iosPositionSub = null;
    _iosTicker?.cancel();
    _iosTicker = null;
    if (Platform.isIOS) {
      unawaited(_iosCancelTrackingNotification());
    }

    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      debugPrint('[V3VozacLocationTrackingService] Šaljem stop event background servisu');
      service.invoke('stop');
    }

    if (vozacIdToClean.isNotEmpty) {
      debugPrint('[V3VozacLocationTrackingService] Brišem ETA za vozača=$vozacIdToClean');
      await clearEtaForVozac(vozacId: vozacIdToClean);
    }
    debugPrint('[V3VozacLocationTrackingService] stop() završen');
  }

  /// Dobavi trenutnu GPS poziciju i odmah izračunaj ETA.
  /// Ispravka: _lastSentPosition nije mogao biti setovan iz background isolate-a,
  /// pa se GPS pozicija sada dobavlja direktno.
  Future<({Map<String, int> etaMap, List<String> order})> fetchPositionAndComputeEta() async {
    if (_activeVozacId.isEmpty || _activeGrad.isEmpty || _activeVreme.isEmpty || _activeDatumIso.isEmpty) {
      return (etaMap: <String, int>{}, order: <String>[]);
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      _lastSentPosition = position;
      return await computeEta(
        vozacId: _activeVozacId,
        lat: position.latitude,
        lng: position.longitude,
        grad: _activeGrad,
        vreme: _activeVreme,
        datumIso: _activeDatumIso,
      );
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] fetchPositionAndComputeEta error: $e');
      _optimizedPutnikIds.clear();
      _etaSecondsCache.clear();
      return (etaMap: <String, int>{}, order: <String>[]);
    }
  }

  Future<V3LocationPrereqStatus> checkLocationPrerequisites() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return V3LocationPrereqStatus.serviceDisabled;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      return V3LocationPrereqStatus.denied;
    }

    if (permission == LocationPermission.denied) {
      return V3LocationPrereqStatus.denied;
    }

    // Android: bez izuzeća od battery optimization / Doze, proizvođači
    // telefona (posebno Huawei/Xiaomi/Samsung sa agresivnim "app launch
    // management") ubijaju flutter_background_service headless isolate čim
    // app ode u pozadinu — GPS foreground servis se nikad ne pokrene, pa
    // tick (svakih `v3TrackingTickInterval`, preko `V3SelfReschedulingTicker`)
    // koji šalje poziciju i računa ETA nikad ne radi, iako su same
    // lokacijske dozvole ispravno odobrene (potvrđeno
    // preko `dumpsys appops`/`dumpsys deviceidle whitelist` na test uređaju).
    // Ne blokiramo start() ako korisnik odbije ovaj dijalog (best-effort) —
    // samo pokušavamo da povećamo šansu da OS ne ubije servis.
    if (Platform.isAndroid) {
      try {
        final status = await ph.Permission.ignoreBatteryOptimizations.status;
        if (!status.isGranted) {
          await ph.Permission.ignoreBatteryOptimizations.request();
        }
      } catch (e) {
        debugPrint('[V3VozacLocationTrackingService] ignoreBatteryOptimizations greška: $e');
      }
    }

    return V3LocationPrereqStatus.ok;
  }

  Future<({Map<String, int> etaMap, List<String> order})> computeEta({
    required String vozacId,
    required double lat,
    required double lng,
    required String grad,
    required String vreme,
    String? datumIso,
  }) async {
    final supabase = Supabase.instance.client;
    unawaited(_pozicijaBroadcaster.broadcast(
      client: supabase,
      vozacId: vozacId,
      lat: lat,
      lng: lng,
      logTag: '[V3VozacLocationTrackingService]',
    ));
    final response = await supabase.functions.invoke(
      'v3-compute-eta',
      body: <String, dynamic>{
        'vozac_id': vozacId,
        'lat': lat,
        'lng': lng,
        'grad': grad,
        'vreme': vreme,
        if (datumIso != null && datumIso.isNotEmpty) 'datum_iso': datumIso,
      },
    )
        // Zaštita od beskonačnog čekanja — `functions_client` nema sopstveni
        // timeout, pa na lošoj mreži poziv ume da "visi" bez kraja (vidi
        // napomenu uz `v3ComputeEtaNetworkTimeout` u v3_tracking_config.dart).
        .timeout(v3ComputeEtaNetworkTimeout);
    debugPrint('[V3VozacLocationTrackingService] computeEta response: ${response.data}');

    final etaMap = <String, int>{};
    final order = <String>[];
    final data = response.data;
    if (data is Map && data['ok'] == true) {
      final etaList = data['eta_results'];
      if (etaList is List) {
        for (final item in etaList) {
          if (item is Map) {
            final pid = item['putnik_id']?.toString();
            final sec = (item['eta_seconds'] as num?)?.toInt();
            if (pid != null && pid.isNotEmpty && sec != null) {
              etaMap[pid] = sec;
            }
          }
        }
      }
      // Koristi eksplicitni optimizovani redosled iz OSRM
      final optimizedOrder = data['optimized_order'];
      if (optimizedOrder is List) {
        for (final pid in optimizedOrder) {
          if (pid is String && pid.isNotEmpty) {
            order.add(pid);
          }
        }
      }

      // Čuvaj u zajednički cache za sve ekrane
      _optimizedPutnikIds
        ..clear()
        ..addAll(order);
      _etaSecondsCache
        ..clear()
        ..addAll(etaMap);
    } else {
      _optimizedPutnikIds.clear();
      _etaSecondsCache.clear();
    }
    return (etaMap: etaMap, order: order);
  }

  /// Registruje lifecycle observer za background tracking servis.
  void initialize() {
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restoreAndResumeIfNeeded());
  }

  /// Ako je app bila prisilno ugašena dok je tracking bio aktivan,
  /// ovde pokušavamo da automatski obnovimo tracking na osnovu sačuvane
  /// sesije (vozacId/grad/vreme/datum + started_at), bez potrebe za ručnim startom.
  Future<void> _restoreAndResumeIfNeeded() async {
    debugPrint('[V3VozacLocationTrackingService] _restoreAndResumeIfNeeded() početak');
    try {
      if (_isRunning) {
        debugPrint('[V3VozacLocationTrackingService] Već aktivan, preskačem restore');
        return;
      }

      if (!Platform.isIOS) {
        // Na Androidu je background isolate (headless) sam-dovoljan: čita
        // željeno stanje direktno iz SharedPreferences svakih 20s i nastavlja
        // rad i bez učešća main isolate-a. Ovde samo osvežimo lokalni UI-state
        // (_activeVozacId/_isRunning) ako je servis zatečen kao već pokrenut,
        // bez ponovnog upisivanja bilo čega.
        final service = FlutterBackgroundService();
        final isServiceRunning = await service.isRunning();
        debugPrint('[V3VozacLocationTrackingService][Android] Servis running=$isServiceRunning');
        if (!isServiceRunning) {
          debugPrint('[V3VozacLocationTrackingService][Android] Servis ne radi, nema šta da se restore-uje');
          return;
        }

        try {
          final prefs = await SharedPreferences.getInstance();
          final vozacId = (prefs.getString(v3KeyVozacId) ?? '').trim();
          final datumIso = (prefs.getString(v3KeyDatumIso) ?? '').trim();
          final grad = (prefs.getString(v3KeyGrad) ?? '').trim();
          final vreme = (prefs.getString(v3KeyVreme) ?? '').trim();
          final startedAtMs = prefs.getInt(v3KeyStartedAt) ?? 0;
          debugPrint(
              '[V3VozacLocationTrackingService][Android] Pročitano iz Prefs: vozac=$vozacId datum=$datumIso grad=$grad vreme=$vreme');
          if (vozacId.isEmpty || datumIso.isEmpty || grad.isEmpty || vreme.isEmpty) {
            debugPrint('[V3VozacLocationTrackingService][Android] Prefs nisu kompletne');
            return;
          }

          _activeVozacId = vozacId;
          _activeDatumIso = datumIso;
          _activeGrad = grad;
          _activeVreme = vreme;
          _trackingStartedAt = startedAtMs > 0 ? DateTime.fromMillisecondsSinceEpoch(startedAtMs) : DateTime.now();
          _isRunning = true;
          debugPrint(
              '[V3VozacLocationTrackingService][Android] Zatečen aktivan BG servis: vozac=$vozacId grad=$grad vreme=$vreme');
        } catch (e) {
          debugPrint('[V3VozacLocationTrackingService][Android] Greška pri čitanju stanja: $e');
        }
        return;
      }

      final startedRaw = await _secureStorage.read(key: _kIosSessionStartedAt);
      debugPrint('[V3VozacLocationTrackingService][iOS] startedRaw=$startedRaw');
      if (startedRaw == null || startedRaw.isEmpty) return;

      final startedAt = DateTime.tryParse(startedRaw);
      if (startedAt == null) return;
      _trackingStartedAt = startedAt;

      // Ako je vreme trajanja već isteklo, samo očisti sesiju umesto restarta.
      if (v3TrackingTimedOut(startedAt)) {
        debugPrint(
            '[V3VozacLocationTrackingService] stop reason=timeout source=restore_session duration_minutes=${v3TrackingMaxDuration.inMinutes}');
        await stop();
        return;
      }

      final vozacId = (await _secureStorage.read(key: _kIosSessionVozacId) ?? '').trim();
      final datumIso = (await _secureStorage.read(key: _kIosSessionDatumIso) ?? '').trim();
      final grad = (await _secureStorage.read(key: _kIosSessionGrad) ?? '').trim();
      final vreme = (await _secureStorage.read(key: _kIosSessionVreme) ?? '').trim();
      debugPrint(
          '[V3VozacLocationTrackingService][iOS] Pročitano iz SecureStorage: vozac=$vozacId datum=$datumIso grad=$grad vreme=$vreme');

      if (vozacId.isEmpty || datumIso.isEmpty || grad.isEmpty || vreme.isEmpty) return;

      _activeDatumIso = datumIso;
      _activeGrad = grad;
      _activeVreme = vreme;

      // Napomena: timeout je već proveren gore (odmah nakon parsiranja
      // startedAt) — druga identična provera ovde je bila mrtav kod (isti
      // startedAt, praktično isti `now`), uklonjena kao suvišan fallback.
      debugPrint(
          '[V3VozacLocationTrackingService][iOS] Nastavljam sačuvanu sesiju: vozac=$vozacId grad=$grad vreme=$vreme');
      await start(vozacId: vozacId);
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] restore/resume error: $e');
    }
  }

  /// Pokreće iOS-specifičan tracking preko Geolocator position stream-a sa
  /// allowsBackgroundLocationUpdates. Za razliku od Androida, ovde nema
  /// pravog background isolate-a — GPS updates i ETA se računaju u main isolate-u,
  /// koji iOS budi na promenu lokacije čak i kad je app suspendovana.
  ///
  /// distanceFilter: 0 znači da GPS hardware/OS ne filtrira update-e po
  /// pomaku — stream samo osvežava _lastSentPosition (jeftino). Stvarno
  /// slanje GPS-a/ETA obračun ide isključivo preko `_iosTicker`
  /// (`V3SelfReschedulingTicker`) u `_iosTick()` — isti "jedan izvor istine"
  /// model kao Android-ov background isolate tajmer, garantovano na svakih
  /// `v3TrackingTickInterval` bez obzira da li stream u međuvremenu emituje
  /// evente.
  Future<void> _startIosTracking() async {
    await _iosPositionSub?.cancel();
    _isRunning = true;

    final locationSettings = AppleSettings(
      accuracy: LocationAccuracy.high,
      activityType: ActivityType.automotiveNavigation,
      distanceFilter: 0,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
      allowBackgroundLocationUpdates: true,
    );

    // Stream SAMO osvežava _lastSentPosition (jeftino) — ne pokreće mrežne
    // pozive. Jedini okidač za computeEta()/GPS slanje je _iosTicker ispod.
    _iosPositionSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (position) {
        _lastSentPosition = position;
      },
      onError: (Object e) {
        debugPrint('[V3VozacLocationTrackingService][iOS] position stream error: $e');
      },
    );

    // Sam-zakazujući tajmer (JEDAN IZVOR ISTINE, deljen sa Android background
    // isolate-om preko `V3SelfReschedulingTicker` u v3_tracking_config.dart)
    // — garantuje tačan tick svakih `v3TrackingTickInterval` bez obzira da li
    // GPS stream emituje evente (npr. dok vozač stoji), i bez tihog
    // preskakanja tick-a kad `_iosTick()` (GPS fix + `v3-compute-eta` sa OSRM
    // retry-jima) potraje duže od intervala — sledeći tick se zakazuje TEK
    // nakon što se prethodni završi.
    _iosTicker?.cancel();
    _iosTicker = V3SelfReschedulingTicker(interval: v3TrackingTickInterval, onTick: _iosTick)..start();
  }

  Future<void> _iosTick() async {
    debugPrint('[V3VozacLocationTrackingService][iOS] _iosTick() početak');
    final startedAt = _trackingStartedAt;
    if (v3TrackingTimedOut(startedAt)) {
      debugPrint(
          '[V3VozacLocationTrackingService][iOS] stop reason=timeout source=ios_main_timer duration_minutes=${v3TrackingMaxDuration.inMinutes}');
      await stop();
      return;
    }

    if (_activeVozacId.isEmpty || _activeGrad.isEmpty || _activeVreme.isEmpty || _activeDatumIso.isEmpty) {
      debugPrint(
          '[V3VozacLocationTrackingService][iOS] _iosTick prekinut: nedostaju podaci vozac=$_activeVozacId grad=$_activeGrad vreme=$_activeVreme datum=$_activeDatumIso');
      return;
    }

    try {
      debugPrint('[V3VozacLocationTrackingService][iOS] Dohvatam poziciju...');
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      _lastSentPosition = position;
      debugPrint('[V3VozacLocationTrackingService][iOS] Pozicija: ${position.latitude}, ${position.longitude}');

      debugPrint('[V3VozacLocationTrackingService][iOS] Pozivam computeEta...');
      final etaResult = await computeEta(
        vozacId: _activeVozacId,
        lat: position.latitude,
        lng: position.longitude,
        grad: _activeGrad,
        vreme: _activeVreme,
        datumIso: _activeDatumIso,
      );
      debugPrint(
          '[V3VozacLocationTrackingService][iOS] computeEta završen: order=${etaResult.order.length} etaMap=${etaResult.etaMap.length}');
      onLocationSent?.call(position);

      unawaited(_iosUpdateTrackingNotification(
        order: etaResult.order,
        etaMap: etaResult.etaMap,
      ));

      // Auto-stop: ako su svi putnici pokupljeni/otkazani, zaustavi tracking.
      if (await _allPassengersCompleted()) {
        debugPrint('[V3VozacLocationTrackingService][iOS] stop reason=all_passengers_completed source=ios_main_timer');
        await stop();
      }
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService][iOS] computeEta error: $e');
    }
    debugPrint('[V3VozacLocationTrackingService][iOS] _iosTick() kraj');
  }

  Future<void> _iosEnsureNotifications() async {
    if (_iosNotificationsInitialized) return;
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await plugin.initialize(const InitializationSettings(iOS: iosInit));
      _iosNotificationsPlugin = plugin;
      _iosNotificationsInitialized = true;
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService][iOS] notifications init greška: $e');
    }
  }

  /// Prikazuje/ažurira notifikaciju sa imenom sledećeg putnika + ETA, koristeći
  /// FIKSAN id (`_kIosTrackingNotifId`) tako da svaki poziv zameni prethodnu
  /// (isti mehanizam kao Android-ova ongoing notifikacija, samo bez "ongoing"
  /// zaključavanja — iOS to ne podržava za obične lokalne notifikacije).
  Future<void> _iosUpdateTrackingNotification({
    required List<String> order,
    required Map<String, int> etaMap,
  }) async {
    await _iosEnsureNotifications();
    final plugin = _iosNotificationsPlugin;
    if (plugin == null) return;

    // Deljena logika za tekst notifikacije (JEDAN IZVOR ISTINE, ranije
    // duplirana identicno u `_bgUpdateNextPassengerNotification` na Android
    // strani) - vidi `v3BuildTrackingNotificationText` u v3_tracking_config.dart.
    final nextPutnikId = order.isNotEmpty ? order.first : null;
    final ime = nextPutnikId != null
        ? (V3MasterRealtimeManager.instance.putniciCache[nextPutnikId]?['ime_prezime'] as String?)?.trim()
        : null;
    final text = v3BuildTrackingNotificationText(
      nextPutnikId: nextPutnikId,
      nextPutnikIme: ime,
      etaSeconds: nextPutnikId != null ? etaMap[nextPutnikId] : null,
      remainingCount: order.length,
    );
    final title = text.title;
    final body = text.body;

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: false,
      interruptionLevel: InterruptionLevel.passive,
    );

    try {
      await plugin.show(
        _kIosTrackingNotifId,
        title,
        body,
        const NotificationDetails(iOS: iosDetails),
      );
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService][iOS] notifikacija update greška: $e');
    }
  }

  Future<void> _iosCancelTrackingNotification() async {
    try {
      await _iosNotificationsPlugin?.cancel(_kIosTrackingNotifId);
    } catch (_) {
      // ignoriši — nije kritično
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Background servis radi nezavisno od lifecycle stanja.
    // Po potrebi ovde možemo da pauziramo/ponovo pokrećemo foreground taskove.

    // Na iOS-u background push handler samo upisuje željeno stanje (ne može
    // pouzdano da pokrene pravi tracking dok je app suspendovana). Kada
    // korisnik vrati app u foreground, pokušavamo da nastavimo sačuvanu sesiju.
    if (Platform.isIOS && state == AppLifecycleState.resumed) {
      unawaited(_restoreAndResumeIfNeeded());
    }
  }
}
