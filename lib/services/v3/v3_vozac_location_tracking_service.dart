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
import '../../utils/v3_status_policy.dart';
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
  /// izvor istine za "kada se šalje GPS/ETA" je `_iosMainTimer` ispod, isti
  /// model kao Android-ov `Timer.periodic(20s)` u background isolate-u. Ovo
  /// eliminiše zavisnost od toga da li GPS stream emituje evente dok vozač
  /// stoji (nije garantovano) — tajmer garantuje tačan tick svakih 20s.
  StreamSubscription<Position>? _iosPositionSub;
  bool _iosInFlight = false;
  Timer? _iosMainTimer;
  static const Duration _iosTickInterval = Duration(seconds: 20);
  FlutterLocalNotificationsPlugin? _iosNotificationsPlugin;
  bool _iosNotificationsInitialized = false;

  // Supabase kredencijali i dalje idu preko SecureStorage (osetljivi podaci).
  // Mora biti identično sa konstantama u v3_background_location_handler.dart
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const String _kStorageSupabaseUrl = 'bg_tracking_supabase_url';
  static const String _kStorageSupabaseAnonKey = 'bg_tracking_supabase_anon_key';

  // JEDAN IZVOR ISTINE za "šta bi background tracking trebalo da radi" —
  // obična SharedPreferences (ne secure storage), jer isti fajl piše i
  // GavraFcmService.kt (native, cold-start bez main isolate-a). Ključevi
  // MORAJU biti identični sa `_kKey*` konstantama u
  // v3_background_location_handler.dart i `KEY_ACTIVE_*` u GavraFcmService.kt.
  static const String _kKeyVozacId = 'bg_active_vozac_id';
  static const String _kKeyDatumIso = 'bg_active_datum_iso';
  static const String _kKeyGrad = 'bg_active_grad';
  static const String _kKeyVreme = 'bg_active_vreme';
  static const String _kKeyStartedAt = 'bg_active_started_at';

  /// Optimizovani redosled putnika (deljen između ekrana)
  final List<String> _optimizedPutnikIds = [];

  /// ETA vrednosti (deljene između ekrana)
  final Map<String, int> _etaSecondsCache = {};

  /// Poziva se nakon svakog uspešnog slanja GPS pozicije (foreground).
  void Function(Position position)? onLocationSent;

  // 🗺️ Realtime broadcast kanal — samo poslednja pozicija vozača, bez čuvanja
  // u bazi. Koristi ga admin ekran da uživo prikaže marker na mapi (besplatno,
  // preko postojećeg Supabase Realtime broadcast-a, nema dodatnih troškova).
  RealtimeChannel? _pozicijaChannel;
  String? _pozicijaChannelVozacId;

  static String pozicijaChannelName(String vozacId) => 'v3-vozac-pozicija-$vozacId';

  Future<void> _broadcastPozicija({
    required String vozacId,
    required double lat,
    required double lng,
  }) async {
    try {
      final supabase = Supabase.instance.client;
      if (_pozicijaChannel == null || _pozicijaChannelVozacId != vozacId) {
        final old = _pozicijaChannel;
        if (old != null) {
          unawaited(supabase.removeChannel(old));
        }
        final channel = supabase.channel(pozicijaChannelName(vozacId));
        _pozicijaChannel = channel;
        _pozicijaChannelVozacId = vozacId;
        channel.subscribe();
        // Kratka pauza da se kanal poveže pre prvog slanja poruke.
        await Future.delayed(const Duration(milliseconds: 300));
      }
      await _pozicijaChannel?.sendBroadcastMessage(
        event: 'pozicija',
        payload: <String, dynamic>{
          'lat': lat,
          'lng': lng,
          'ts': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] broadcast pozicija greška: $e');
      _pozicijaChannel = null;
      _pozicijaChannelVozacId = null;
    }
  }

  bool get isRunning => _isRunning;

  String? get activeVozacId => _activeVozacId.isNotEmpty ? _activeVozacId : null;
  String get activeDatumIso => _activeDatumIso;
  String get activeGrad => _activeGrad;
  String get activeVreme => _activeVreme;
  Position? get lastKnownPosition => _lastSentPosition;
  List<String> get optimizedPutnikIds => List.unmodifiable(_optimizedPutnikIds);
  Map<String, int> get etaSecondsCache => Map.unmodifiable(_etaSecondsCache);

  String _normalizeDateIso(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      final y = parsed.year.toString().padLeft(4, '0');
      final m = parsed.month.toString().padLeft(2, '0');
      final d = parsed.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }
    return value.split('T').first;
  }

  /// Upisuje "željeno stanje" u obični SharedPreferences fajl — JEDINO mesto
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
      // Supabase kredencijali i dalje idu preko SecureStorage (osetljivi podaci),
      // potrebni background isolate-u za cold-start bez main isolate-a.
      unawaited(_secureStorage.write(key: _kStorageSupabaseUrl, value: url));
      unawaited(_secureStorage.write(key: _kStorageSupabaseAnonKey, value: anonKey));
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kKeyVozacId, vozacId);
      await prefs.setString(_kKeyDatumIso, _activeDatumIso);
      await prefs.setString(_kKeyGrad, _activeGrad);
      await prefs.setString(_kKeyVreme, _activeVreme);
      final startedAt = _trackingStartedAt;
      if (startedAt != null) {
        await prefs.setInt(_kKeyStartedAt, startedAt.millisecondsSinceEpoch);
      }
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] Greška pri upisu željenog stanja: $e');
    }
  }

  Future<void> _clearDesiredState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kKeyVozacId);
      await prefs.remove(_kKeyDatumIso);
      await prefs.remove(_kKeyGrad);
      await prefs.remove(_kKeyVreme);
      await prefs.remove(_kKeyStartedAt);
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

  Future<void> startFromPayload({
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
  }

  Future<void> clearEtaForVozac({required String vozacId}) async {
    final normalized = vozacId.trim();
    if (normalized.isEmpty) return;

    try {
      await Supabase.instance.client.from('v3_eta_results').delete().eq('vozac_id', normalized);
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] eta cleanup error: $e');
    }
  }

  /// Proverava da li su svi putnici u aktivnom slotu završeni
  /// (pokupljeni ili otkazani). Vraća false ako nema putnika.
  Future<bool> _allPassengersCompleted() async {
    if (_activeDatumIso.isEmpty || _activeGrad.isEmpty || _activeVreme.isEmpty) {
      return false;
    }

    try {
      final slotRows = await Supabase.instance.client
          .from('v3_trenutna_dodela_slot')
          .select('id, waypoints_json')
          .eq('datum', _activeDatumIso)
          .eq('grad', _activeGrad)
          .eq('vreme', _activeVreme);

      final activeSlot = (slotRows as List<dynamic>?)?.firstOrNull as Map<String, dynamic>?;
      if (activeSlot == null) return false;

      final waypointsJson = activeSlot['waypoints_json'] as Map<String, dynamic>?;
      final passengers = waypointsJson?['passengers'] as List<dynamic>?;
      if (passengers == null || passengers.isEmpty) return false;

      final slotTerminIds = passengers
          .whereType<Map<String, dynamic>>()
          .map((p) => p['termin_id']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .toSet();

      if (slotTerminIds.isEmpty) return false;

      final rows = await Supabase.instance.client
          .from('v3_operativna_nedelja')
          .select('id, pokupljen_at, otkazano_at')
          .inFilter('id', slotTerminIds.toList());

      if (rows.isEmpty) return false;

      for (final row in rows) {
        final pokupljen = V3StatusPolicy.isTimestampSet(row['pokupljen_at']);
        final otkazan = V3StatusPolicy.isTimestampSet(row['otkazano_at']);
        if (!pokupljen && !otkazan) return false;
      }
      return true;
    } catch (e) {
      debugPrint('[V3VozacLocationTrackingService] Greška pri proveri putnika: $e');
      return false;
    }
  }

  Future<void> start({required String vozacId}) async {
    final normalizedVozacId = vozacId.trim();
    if (normalizedVozacId.isEmpty) return;

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
        if (await service.isRunning()) {
          debugPrint(
              '[V3VozacLocationTrackingService] Već aktivno za istog vozača — ažuriram termin: datum=$_activeDatumIso grad=$_activeGrad vreme=$_activeVreme');
          await _writeDesiredState(vozacId: normalizedVozacId);
        }
        return; // finally će resetovati _startInProgress
      }

      // Ako je aktivan bilo koji tracking (isti ili drugi vozač), prvo ga zaustavi.
      if (_isRunning || _activeVozacId.isNotEmpty) {
        await stop();
      }

      _activeVozacId = normalizedVozacId;
      _trackingStartedAt = DateTime.now();

      // Napomena: ove SecureStorage kljuceve i dalje koristi SAMO iOS restore
      // put (_restoreAndResumeIfNeeded) jer iOS nema headless background
      // isolate koji bi mogao da čita unified SharedPreferences stanje kad je
      // app killed — Android koristi isključivo _writeDesiredState ispod.
      if (Platform.isIOS) {
        unawaited(_secureStorage.write(key: 'vozac_tracking_started_at', value: _trackingStartedAt!.toIso8601String()));
        unawaited(_secureStorage.write(key: 'vozac_tracking_vozac_id', value: normalizedVozacId));
        unawaited(_secureStorage.write(key: 'vozac_tracking_datum_iso', value: _activeDatumIso));
        unawaited(_secureStorage.write(key: 'vozac_tracking_grad', value: _activeGrad));
        unawaited(_secureStorage.write(key: 'vozac_tracking_vreme', value: _activeVreme));
      }

      final prereqStatus = await checkLocationPrerequisites();
      if (prereqStatus != V3LocationPrereqStatus.ok) {
        debugPrint('[V3VozacLocationTrackingService] start() prekinut, prereq status=$prereqStatus');
        await stop();
        return; // finally će resetovati _startInProgress
      }

      // Aktiviraj slot red (idempotentan upsert) — jedina implementacija ove
      // logike, deljena i sa background isolate-om (v3_slot_activation.dart).
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
        await _startIosTracking();
        return; // finally će resetovati _startInProgress
      }

      final service = FlutterBackgroundService();
      var isServiceRunning = await service.isRunning();
      if (!isServiceRunning) {
        try {
          await service.startService();
        } catch (e) {
          debugPrint('[V3VozacLocationTrackingService] Failed to start background service: $e');
          await stop();
          return;
        }
        isServiceRunning = await service.isRunning();
        if (!isServiceRunning) {
          debugPrint('[V3VozacLocationTrackingService] Background service did not start.');
          await stop();
          return; // finally će resetovati _startInProgress
        }
      }

      await _writeDesiredState(vozacId: normalizedVozacId);

      _isRunning = true;
    } finally {
      _startInProgress = false;
    }
  }

  Future<void> stop() async {
    final vozacIdToClean = _activeVozacId;
    final datumIsoToClean = _activeDatumIso;
    final gradToClean = _activeGrad;
    final vremeToClean = _activeVreme;
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

    final channelToRemove = _pozicijaChannel;
    _pozicijaChannel = null;
    _pozicijaChannelVozacId = null;
    if (channelToRemove != null) {
      unawaited(Supabase.instance.client.removeChannel(channelToRemove));
    }

    unawaited(_clearDesiredState());
    unawaited(_secureStorage.delete(key: 'vozac_tracking_started_at'));
    unawaited(_secureStorage.delete(key: 'vozac_tracking_vozac_id'));
    unawaited(_secureStorage.delete(key: 'vozac_tracking_datum_iso'));
    unawaited(_secureStorage.delete(key: 'vozac_tracking_grad'));
    unawaited(_secureStorage.delete(key: 'vozac_tracking_vreme'));

    await _iosPositionSub?.cancel();
    _iosPositionSub = null;
    _iosMainTimer?.cancel();
    _iosMainTimer = null;
    if (Platform.isIOS) {
      unawaited(_iosCancelTrackingNotification());
    }

    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke('stop');
    }

    if (vozacIdToClean.isNotEmpty) {
      await clearEtaForVozac(vozacId: vozacIdToClean);
    }
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
    // tick (Timer.periodic 20s) koji šalje poziciju i računa ETA nikad ne
    // radi, iako su same lokacijske dozvole ispravno odobrene (potvrđeno
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
    unawaited(_broadcastPozicija(vozacId: vozacId, lat: lat, lng: lng));
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
    );
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
    try {
      if (_isRunning) return;

      if (!Platform.isIOS) {
        // Na Androidu je background isolate (headless) sam-dovoljan: čita
        // željeno stanje direktno iz SharedPreferences svakih 20s i nastavlja
        // rad i bez učešća main isolate-a. Ovde samo osvežimo lokalni UI-state
        // (_activeVozacId/_isRunning) ako je servis zatečen kao već pokrenut,
        // bez ponovnog upisivanja bilo čega.
        final service = FlutterBackgroundService();
        final isServiceRunning = await service.isRunning();
        if (!isServiceRunning) return;

        try {
          final prefs = await SharedPreferences.getInstance();
          final vozacId = (prefs.getString(_kKeyVozacId) ?? '').trim();
          final datumIso = (prefs.getString(_kKeyDatumIso) ?? '').trim();
          final grad = (prefs.getString(_kKeyGrad) ?? '').trim();
          final vreme = (prefs.getString(_kKeyVreme) ?? '').trim();
          final startedAtMs = prefs.getInt(_kKeyStartedAt) ?? 0;
          if (vozacId.isEmpty || datumIso.isEmpty || grad.isEmpty || vreme.isEmpty) return;

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

      final startedRaw = await _secureStorage.read(key: 'vozac_tracking_started_at');
      if (startedRaw == null || startedRaw.isEmpty) return;

      final startedAt = DateTime.tryParse(startedRaw);
      if (startedAt == null) return;
      _trackingStartedAt = startedAt;

      // Ako je vreme trajanja već isteklo, samo očisti sesiju umesto restarta.
      if (DateTime.now().difference(startedAt) >= v3TrackingMaxDuration) {
        debugPrint(
            '[V3VozacLocationTrackingService] stop reason=timeout source=restore_session duration_minutes=${v3TrackingMaxDuration.inMinutes}');
        await stop();
        return;
      }

      final vozacId = (await _secureStorage.read(key: 'vozac_tracking_vozac_id') ?? '').trim();
      final datumIso = (await _secureStorage.read(key: 'vozac_tracking_datum_iso') ?? '').trim();
      final grad = (await _secureStorage.read(key: 'vozac_tracking_grad') ?? '').trim();
      final vreme = (await _secureStorage.read(key: 'vozac_tracking_vreme') ?? '').trim();

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
  /// slanje GPS-a/ETA obračun ide isključivo preko `_iosMainTimer`
  /// (Timer.periodic 20s) u `_iosTick()` — isti "jedan izvor istine" model
  /// kao Android-ov background isolate tajmer, garantovano na svakih 20s
  /// bez obzira da li stream u međuvremenu emituje evente.
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
    // pozive. Jedini okidač za computeEta()/GPS slanje je _iosMainTimer ispod.
    _iosPositionSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (position) {
        _lastSentPosition = position;
      },
      onError: (Object e) {
        debugPrint('[V3VozacLocationTrackingService][iOS] position stream error: $e');
      },
    );

    // Jedan periodični tajmer (20s) — JEDINI izvor istine za slanje GPS
    // pozicije/ETA na iOS-u, potpuno analogan Android-ovom
    // `Timer.periodic(20s)` u background isolate-u. Ovo garantuje tačan tick
    // svakih 20s bez obzira da li GPS stream emituje evente (npr. dok vozač
    // stoji), za razliku od prethodnog pristupa gde je stream event bio
    // (negarantovan) okidač.
    _iosMainTimer?.cancel();
    unawaited(_iosTick()); // odmah prvi tick, bez čekanja na prvi period
    _iosMainTimer = Timer.periodic(_iosTickInterval, (_) => unawaited(_iosTick()));
  }

  Future<void> _iosTick() async {
    if (_iosInFlight) return;

    final startedAt = _trackingStartedAt;
    if (startedAt != null && DateTime.now().difference(startedAt) >= v3TrackingMaxDuration) {
      debugPrint(
          '[V3VozacLocationTrackingService][iOS] stop reason=timeout source=ios_main_timer duration_minutes=${v3TrackingMaxDuration.inMinutes}');
      await stop();
      return;
    }

    if (_activeVozacId.isEmpty || _activeGrad.isEmpty || _activeVreme.isEmpty || _activeDatumIso.isEmpty) return;

    _iosInFlight = true;
    try {
      var position = _lastSentPosition;
      if (position == null) {
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 12),
            ),
          );
          _lastSentPosition = position;
        } catch (e) {
          debugPrint('[V3VozacLocationTrackingService][iOS] tick position error: $e');
          return;
        }
      }

      final etaResult = await computeEta(
        vozacId: _activeVozacId,
        lat: position.latitude,
        lng: position.longitude,
        grad: _activeGrad,
        vreme: _activeVreme,
        datumIso: _activeDatumIso,
      );
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
    } finally {
      _iosInFlight = false;
    }
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

    String title;
    String body;

    if (order.isEmpty) {
      title = 'GPS Tracking';
      body = 'Nema više putnika za pokupljanje.';
    } else {
      final nextPutnikId = order.first;
      final ime =
          (V3MasterRealtimeManager.instance.putniciCache[nextPutnikId]?['ime_prezime'] as String?)?.trim() ?? '';
      final etaSeconds = etaMap[nextPutnikId];
      final etaMin = etaSeconds != null && etaSeconds >= 0 ? (etaSeconds / 60).round() : null;
      final etaText = etaMin != null ? ' · ETA $etaMin min' : '';
      final putnikLabel = order.length == 1 ? 'putnik' : 'putnika';
      title = 'GPS Tracking — ${order.length} $putnikLabel';
      body = 'Sledeći: ${ime.isNotEmpty ? ime : 'sledeći putnik'}$etaText';
    }

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
  }
}
