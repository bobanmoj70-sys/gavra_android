import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../config/v2_route_config.dart';
import '../globals.dart';
import '../models/v2_putnik.dart';
import '../services/realtime/v2_master_realtime_manager.dart'; // Za realtime raspored
import '../services/v2_audit_log_service.dart';
import '../services/v2_auth_manager.dart';
import '../services/v2_driver_location_service.dart';
import '../services/v2_kapacitet_service.dart';
import '../services/v2_local_notification_service.dart';
import '../services/v2_polasci_service.dart';
import '../services/v2_realtime_gps_service.dart';
import '../services/v2_realtime_notification_service.dart';
import '../services/v2_smart_navigation_service.dart';
import '../services/v2_theme_manager.dart';
import '../services/v2_vozac_putnik_service.dart';
import '../services/v2_vozac_raspored_service.dart';
import '../services/v2_vozac_service.dart';
import '../utils/v2_app_snack_bar.dart';
import '../utils/v2_dan_utils.dart';
import '../utils/v2_grad_adresa_validator.dart';
import '../utils/v2_putnik_count_helper.dart';
import '../utils/v2_putnik_helpers.dart';
import '../utils/v2_text_utils.dart'; // Za V2TextUtils.isStatusActive
import '../utils/v2_vozac_cache.dart'; // Za validaciju vozaca
import '../widgets/v2_bottom_nav_bar.dart';
import '../widgets/v2_clock_ticker.dart';
import '../widgets/v2_putnik_list.dart';

/// ?? VOZAC SCREEN
/// Prikazuje putnike koristeci isti PutnikService stream kao DanasScreen
class V2VozacScreen extends StatefulWidget {
  /// Opcioni parametar - ako je null, koristi trenutnog ulogovanog vozaca
  /// Ako je prosleden, prikazuje ekran kao da je taj vozac ulogovan (admin preview)
  final String? previewAsDriver;

  const V2VozacScreen({super.key, this.previewAsDriver});

  @override
  State<V2VozacScreen> createState() => _VozacScreenState();
}

class _VozacScreenState extends State<V2VozacScreen> {
  final V2PutnikStreamService _putnikService = V2PutnikStreamService();

  StreamSubscription<Position>? _driverPositionSubscription;
  StreamSubscription<String>? _rasporedRealtimeSub;
  StreamSubscription<String>? _vozacPutnikRealtimeSub;
  Timer? _rasporedDebounce;
  Timer? _vozacPutnikDebounce;

  String _selectedGrad = 'BC';
  String _selectedVreme = ''; // Ce biti postavljen u _selectClosestDeparture()

  bool _isRouteOptimized = false;
  List<V2Putnik> _optimizedRoute = [];
  Map<String, int>? _putniciEta; // ETA po imenu putnika (minuti) nakon optimizacije
  bool _isOptimizing = false; // ? Loading state specificno za optimizaciju rute

  /// ?? HELPER: Dobij dodeljena vremena za trenutnog vozaca.
  ///
  /// Kombinuje dva izvora:
  /// 1. [_rasporedCache] ž termini dodeljeni vozacu (vozac_raspored), prikazuju se cak i prazni
  /// 2. [sviPutnici] ž vremena iz putnika koji su vec filtrirani za ovog vozaca
  List<Map<String, String>> _rasporedVozaca({List<V2Putnik>? sviPutnici}) {
    if (_currentDriver == null) return [];

    final dodeljena = <Map<String, String>>[];
    final currentVozacId = V2VozacCache.getUuidByIme(_currentDriver ?? '');
    final targetDan = V2DanUtils.odIso(_workingDateIso);

    // Izvor 1: termini iz raspored cache-a za ovog vozaca i današnji dan
    for (final r in _rasporedCache) {
      if (r.dan != targetDan) continue;
      final isVozacov = currentVozacId != null && r.vozacId == currentVozacId;
      if (!isVozacov) continue;
      final postoji = dodeljena.any((v) => v['grad'] == r.grad && v['vreme'] == r.vreme);
      if (!postoji) dodeljena.add({'grad': r.grad, 'vreme': r.vreme});
    }

    // Izvor 2: termini iz individualno dodijeljenih putnika (vozac_putnik)
    // V2Putnik ima termin koji nije u vozac_raspored ? dodaj termin u nav bar
    if (sviPutnici != null) {
      for (final p in sviPutnici) {
        final postoji = dodeljena.any((v) => v['grad'] == p.grad && v['vreme'] == p.polazak);
        if (!postoji) dodeljena.add({'grad': p.grad, 'vreme': p.polazak});
      }
    }

    // Sortiraj po vremenu
    dodeljena.sort((a, b) => a['vreme']!.compareTo(b['vreme']!));

    return dodeljena;
  }

  String? _currentDriver;

  List<V2VozacRasporedEntry> _rasporedCache = [];

  List<V2VozacPutnikEntry> _vozacPutnikCache = [];

  // Status varijable
  bool _isListReordered = false;
  bool _isGpsTracking = false;

  Stream<List<V2Putnik>>? _streamPutnici; // Inicijalizuje se u _initializeCurrentDriver()
  List<V2Putnik> _latestPutnici = []; // Svježi putnici — osvježava se u StreamBuilder builder
  late final String _workingDateIso; // Radni datum — izracunava se jednom u initState

  List<String> get _sviPolasci {
    final bcList = V2RouteConfig.getVremenaByNavType('BC').map((v) => '$v BC').toList();
    final vsList = V2RouteConfig.getVremenaByNavType('VS').map((v) => '$v VS').toList();
    return [...bcList, ...vsList];
  }

  @override
  void initState() {
    super.initState();
    _workingDateIso = V2PutnikHelpers.getWorkingDateIso();

    // Pre-populiši vozača i putnike odmah iz in-memory cache-a (0 async čekanja)
    // Ovo eliminuje bijeli ekran pri povratku na ekran
    final cachedDriver = widget.previewAsDriver ?? V2AuthManager.cachedDriverName;
    if (cachedDriver != null && cachedDriver.isNotEmpty) {
      _currentDriver = cachedDriver;
      final rm = V2MasterRealtimeManager.instance;
      _rasporedCache = rm.rasporedCache.values.map((row) => V2VozacRasporedEntry.fromMap(row)).toList();
      _vozacPutnikCache = rm.vozacPutnikCache.values.map((row) => V2VozacPutnikEntry.fromMap(row)).toList();
      _streamPutnici = _putnikService.streamKombinovaniPutniciFiltered(
        dan: V2DanUtils.odIso(_workingDateIso),
        vozacId: V2VozacCache.getUuidByIme(_currentDriver ?? ''),
      );
      if (rm.isInitialized) {
        _latestPutnici = _putnikService.fetchPutniciSync(
          dan: V2DanUtils.odIso(_workingDateIso),
          vozacId: V2VozacCache.getUuidByIme(_currentDriver ?? ''),
        );
      }
    }

    _initAsync();
  }

  Future<void> _initAsync() async {
    // 1. Inicijalizuj vozaca (ovo ce takode pozvati _selectClosestDeparture)
    // 2. Ucitaj raspored — oba su awaited da bi setState bio samo jednom (na kraju _initializeCurrentDriver)
    await _loadRaspored();
    await _initializeCurrentDriver();
    _subscribeRealtime();

    // 3. Ostalo
    _initializeGpsTracking();
    if (!mounted) return;
    V2LocalNotificationService.initialize(context);
    // _currentDriver je vec setovan u _initializeCurrentDriver() — nema potrebe za dodatnim Firebase pozivom
    if (_currentDriver != null && _currentDriver!.isNotEmpty) {
      V2RealtimeNotificationService.initialize();
    }
  }

  Future<void> _loadRaspored() async {
    final rm = V2MasterRealtimeManager.instance;
    // Čita direktno iz RM in-memory cache — 0 DB querija
    final raspored = rm.rasporedCache.values.map((row) => V2VozacRasporedEntry.fromMap(row)).toList();
    final vozacPutnik = rm.vozacPutnikCache.values.map((row) => V2VozacPutnikEntry.fromMap(row)).toList();
    // Bez setState — poziva se iz _initAsync koji vec radi setState na kraju
    _rasporedCache = raspored;
    _vozacPutnikCache = vozacPutnik;
  }

  /// Realtime: prati vozac_raspored i vozac_putnik i osvježava lokalne cache-ove
  void _subscribeRealtime() {
    _rasporedRealtimeSub?.cancel();
    _vozacPutnikRealtimeSub?.cancel();
    final rm = V2MasterRealtimeManager.instance;
    _rasporedRealtimeSub = rm.onCacheChanged.where((t) => t == 'v2_vozac_raspored').listen((_) {
      _rasporedDebounce?.cancel();
      _rasporedDebounce = Timer(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        final entries = rm.rasporedCache.values.map((row) => V2VozacRasporedEntry.fromMap(row)).toList();
        setState(() => _rasporedCache = entries);
      });
    });
    _vozacPutnikRealtimeSub = rm.onCacheChanged.where((t) => t == 'v2_vozac_putnik').listen((_) {
      _vozacPutnikDebounce?.cancel();
      _vozacPutnikDebounce = Timer(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        final entries = rm.vozacPutnikCache.values.map((row) => V2VozacPutnikEntry.fromMap(row)).toList();
        setState(() => _vozacPutnikCache = entries);
      });
    });
  }

  void _initializeGpsTracking() {
    V2RealtimeGpsService.startTracking().catchError((Object e) {
      debugPrint('⚠️ [VozacScreen] GPS tracking greška: $e');
      if (mounted) {
        V2AppSnackBar.warning(context, 'GPS nedostupan — provjeri dozvole');
      }
    });

    _driverPositionSubscription = V2RealtimeGpsService.positionStream.listen((pos) {
      V2DriverLocationService.instance.forceLocationUpdate(knownPosition: pos);
    });
  }

  @override
  void dispose() {
    _driverPositionSubscription?.cancel();
    _rasporedRealtimeSub?.cancel();
    _vozacPutnikRealtimeSub?.cancel();
    _rasporedDebounce?.cancel();
    _vozacPutnikDebounce?.cancel();
    super.dispose();
  }

  Future<void> _initializeCurrentDriver() async {
    if (widget.previewAsDriver != null && widget.previewAsDriver!.isNotEmpty) {
      _currentDriver = widget.previewAsDriver;
      _streamPutnici ??= _putnikService.streamKombinovaniPutniciFiltered(
        dan: V2DanUtils.odIso(_workingDateIso),
        vozacId: V2VozacCache.getUuidByIme(_currentDriver ?? ''),
      );
      // Sinhronizovano pre-populiši putnike iz cache-a — prikazuju se odmah,
      // bez čekanja na stream emit(). Stream će ih osvježiti čim emituje.
      final rmPrev = V2MasterRealtimeManager.instance;
      if (rmPrev.isInitialized && _latestPutnici.isEmpty) {
        _latestPutnici = _putnikService.fetchPutniciSync(
          dan: V2DanUtils.odIso(_workingDateIso),
          vozacId: V2VozacCache.getUuidByIme(_currentDriver ?? ''),
        );
      }
      if (mounted) {
        setState(() {});
        _selectClosestDeparture();
      }
      return;
    }

    _currentDriver = await V2AuthManager.getCurrentDriver();

    _streamPutnici ??= _putnikService.streamKombinovaniPutniciFiltered(
      dan: V2DanUtils.odIso(_workingDateIso),
      vozacId: V2VozacCache.getUuidByIme(_currentDriver ?? ''),
    );
    // Sinhronizovano pre-populiši putnike iz cache-a — prikazuju se odmah,
    // bez čekanja na stream emit(). Stream će ih osvježiti čim emituje.
    final rm = V2MasterRealtimeManager.instance;
    if (rm.isInitialized && _latestPutnici.isEmpty) {
      _latestPutnici = _putnikService.fetchPutniciSync(
        dan: V2DanUtils.odIso(_workingDateIso),
        vozacId: V2VozacCache.getUuidByIme(_currentDriver ?? ''),
      );
    }
    if (mounted) {
      setState(() {});
      _selectClosestDeparture();
    }
  }

  // Callback za BottomNavBar
  void _onPolazakChanged(String grad, String vreme) {
    if (mounted) {
      setState(() {
        _selectedGrad = grad;
        _selectedVreme = vreme;
      });
    }
  }

  /// ?? Bira polazak koji je najbliži trenutnom vremenu iz dodeljenih polazaka
  void _selectClosestDeparture() {
    if (!mounted || _currentDriver == null) return;

    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    String? closestVreme;
    String? closestGrad;
    int minDifference = 9999;

    // Uzmi samo dodeljena vremena za ovog vozaca
    final dodeljenaVremena = _rasporedVozaca();
    if (dodeljenaVremena.isEmpty) return;

    for (final v in dodeljenaVremena) {
      final gradStr = v['grad'];
      final timeStr = v['vreme'];
      if (gradStr == null || timeStr == null) continue;

      final timeParts = timeStr.split(':');
      if (timeParts.length != 2) continue;

      final hour = int.tryParse(timeParts[0]) ?? 0;
      final minute = int.tryParse(timeParts[1]) ?? 0;
      final polazakMinutes = hour * 60 + minute;

      // Razlika u minutima
      final diff = (polazakMinutes - currentMinutes).abs();

      if (diff < minDifference) {
        minDifference = diff;
        closestVreme = timeStr;
        closestGrad = gradStr;
      }
    }

    if (closestVreme != null && closestGrad != null) {
      setState(() {
        _selectedVreme = closestVreme!;
        _selectedGrad = closestGrad!;
      });
    }
  }

  Future<void> _logout() async {
    await V2AuthManager.logout(context);
  }

  Future<void> _promeniSifru() async {
    final vozacId = V2VozacCache.getUuidByIme(_currentDriver ?? '');
    if (vozacId == null) {
      V2AppSnackBar.error(context, 'Greška: ne mogu da nađem vozača');
      return;
    }

    // Dohvati trenutnu šifru iz cache-a
    final vozacMap = V2MasterRealtimeManager.instance.vozaciCache[vozacId];
    final trenutnaSifra = vozacMap?['sifra']?.toString() ?? '';

    final staraCtrl = TextEditingController();
    final novaCtrl = TextEditingController();
    final potvrdiCtrl = TextEditingController();
    bool staraVisible = false;
    bool novaVisible = false;
    bool potvrdiVisible = false;

    try {
      final potvrda = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.lock_reset, color: Colors.blueAccent),
                SizedBox(width: 8),
                Text('Promena šifre', style: TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: staraCtrl,
                  obscureText: !staraVisible,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Stara šifra',
                    labelStyle: const TextStyle(color: Colors.white54),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.blueAccent),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(staraVisible ? Icons.visibility_off : Icons.visibility, color: Colors.white38),
                      onPressed: () => setDialogState(() => staraVisible = !staraVisible),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: novaCtrl,
                  obscureText: !novaVisible,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Nova šifra',
                    labelStyle: const TextStyle(color: Colors.white54),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.blueAccent),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(novaVisible ? Icons.visibility_off : Icons.visibility, color: Colors.white38),
                      onPressed: () => setDialogState(() => novaVisible = !novaVisible),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: potvrdiCtrl,
                  obscureText: !potvrdiVisible,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Potvrdi novu šifru',
                    labelStyle: const TextStyle(color: Colors.white54),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.blueAccent),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(potvrdiVisible ? Icons.visibility_off : Icons.visibility, color: Colors.white38),
                      onPressed: () => setDialogState(() => potvrdiVisible = !potvrdiVisible),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Odustani', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () {
                  final stara = staraCtrl.text;
                  final nova = novaCtrl.text;
                  final potvrdi = potvrdiCtrl.text;

                  if (trenutnaSifra.isNotEmpty && stara != trenutnaSifra) {
                    V2AppSnackBar.error(ctx, 'Stara šifra nije ispravna');
                    return;
                  }
                  if (nova.isEmpty) {
                    V2AppSnackBar.warning(ctx, 'Nova šifra ne može biti prazna');
                    return;
                  }
                  if (nova != potvrdi) {
                    V2AppSnackBar.error(ctx, 'Šifre se ne poklapaju');
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                child: const Text('Sačuvaj', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );

      if (potvrda == true && mounted) {
        try {
          await V2VozacService.updateSifra(vozacId, novaCtrl.text);
          // Audit log — promena šifre
          V2AuditLogService.log(
            tip: 'promena_sifre',
            aktorId: vozacId,
            aktorIme: _currentDriver,
            aktorTip: 'vozac',
            detalji: 'Vozač promijenio šifru',
          );
          if (mounted) V2AppSnackBar.success(context, '✅ Šifra uspešno promenjena');
        } catch (e) {
          if (mounted) V2AppSnackBar.error(context, 'Greška pri čuvanju šifre: $e');
        }
      }
    } finally {
      staraCtrl.dispose();
      novaCtrl.dispose();
      potvrdiCtrl.dispose();
    }
  }

  Future<void> _reoptimizeAfterStatusChange() async {
    if (!_isRouteOptimized || _optimizedRoute.isEmpty) return;

    // Koristi podatke iz poslednjeg StreamBuilder snapshot-a (0 DB querija)
    final ids = _optimizedRoute.where((p) => p.id != null).map((p) => p.id).toSet();
    final sveziPutnici = _latestPutnici.where((p) => ids.contains(p.id)).toList();

    // Razdvoji pokupljene/otkazane od preostalih
    // Ekran je vec filtriran po vozacu - nema potrebe za dodeljenVozac filterom
    final pokupljeniIOtkazani = sveziPutnici.where((p) {
      return p.jePokupljen || p.jeOtkazan || p.jeOdsustvo;
    }).toList();

    final preostaliPutnici = sveziPutnici.where((p) {
      return !p.jePokupljen && !p.jeOtkazan && !p.jeOdsustvo;
    }).toList();

    if (preostaliPutnici.isEmpty) {
      // Svi putnici su pokupljeni ili otkazani - ZADR?I ih u listi

      // ? STOP TRACKING AKO SU SVI GOTOVI
      if (V2DriverLocationService.instance.isTracking) {
        await V2DriverLocationService.instance.v2UpdatePutniciEta({});
      }

      if (mounted) {
        setState(() {
          _optimizedRoute = pokupljeniIOtkazani; // ? ZADR?I pokupljene u listi
        });
        V2AppSnackBar.success(context, '✅ Svi putnici su pokupljeni!');
      }
      return;
    }

    // Reoptimizuj rutu od trenutne GPS pozicije
    try {
      final result = await V2SmartNavigationService.optimizeRouteOnly(
        putnici: preostaliPutnici,
        startCity: _selectedGrad.isNotEmpty ? _selectedGrad : 'VS',
      );

      if (result.success && result.optimizedPutnici != null) {
        if (mounted) {
          setState(() {
            // ? KOMBINUJ: optimizovani preostali + pokupljeni/otkazani na kraju
            _optimizedRoute = [...result.optimizedPutnici!, ...pokupljeniIOtkazani];
          });

          if (V2DriverLocationService.instance.isTracking && result.putniciEta != null) {
            await V2DriverLocationService.instance.v2UpdatePutniciEta(result.putniciEta!);
          }

          if (!mounted) return;

          final sledeci = result.optimizedPutnici!.isNotEmpty ? result.optimizedPutnici!.first.ime : 'N/A';
          V2AppSnackBar.info(context, '🔄 Ruta ažurirana! Sledeci: $sledeci (${preostaliPutnici.length} preostalo)');
        }
      }
    } catch (e) {
      debugPrint('❌ Error auto-reoptimizing route: $e');
    }
  }

  // OPTIMIZACIJA RUTE
  Future<void> _optimizeCurrentRoute(List<V2Putnik> putnici, {bool isAlreadyOptimized = false}) async {
    if (_currentDriver == null || !V2VozacCache.isValidIme(_currentDriver)) {
      if (mounted) {
        V2AppSnackBar.warning(context, 'Morate biti ulogovani i ovlašceni da biste koristili optimizaciju rute.');
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isOptimizing = true; // ? USE _isOptimizing INSTEAD OF _isLoading
      });
    }

    if (isAlreadyOptimized) {
      if (putnici.isEmpty) {
        if (mounted) {
          setState(() => _isOptimizing = false);
          V2AppSnackBar.warning(context, '⚠️ Nema putnika sa adresama za reorder');
        }
        return;
      }
      if (mounted) {
        setState(() {
          _optimizedRoute = List<V2Putnik>.from(putnici);
          _isRouteOptimized = true;
          _isListReordered = true;
          _isOptimizing = false;
        });
      }

      final routeString = _optimizedRoute.take(3).map((p) => p.adresa?.split(',').first ?? p.ime).join(' → ');

      if (mounted) {
        V2AppSnackBar.success(context,
            '✅ Lista putnika optimizovana (server) za $_selectedGrad $_selectedVreme!\n➡️ Sledeci: $routeString${_optimizedRoute.length > 3 ? "..." : ""}');
      }
      return;
    }

    // Filter putnika sa validnim adresama i aktivnim statusom
    // Ekran je vec filtriran po vozacu - nema potrebe za dodeljenVozac filterom ovde
    final filtriraniPutnici = putnici.where((p) {
      // Iskljuci otkazane putnike
      if (p.jeOtkazan) return false;
      // Iskljuci vec pokupljene putnike
      if (p.jePokupljen) return false;
      // Iskljuci odsutne putnike (bolovanje/godisnji)
      if (p.jeOdsustvo) return false;
      final hasValidAddress = (p.adresaId != null && p.adresaId!.isNotEmpty) ||
          (p.adresa != null && p.adresa!.isNotEmpty && p.adresa != p.grad);
      return hasValidAddress;
    }).toList();

    if (filtriraniPutnici.isEmpty) {
      if (mounted) {
        setState(() {
          _isOptimizing = false;
        });
        V2AppSnackBar.warning(context, '⚠️ Nema putnika sa adresama za optimizaciju');
      }
      return;
    }

    try {
      final result = await V2SmartNavigationService.optimizeRouteOnly(
        putnici: filtriraniPutnici,
        startCity: _selectedGrad.isNotEmpty ? _selectedGrad : 'VS',
      );

      if (result.success && result.optimizedPutnici != null && result.optimizedPutnici!.isNotEmpty) {
        final optimizedPutnici = result.optimizedPutnici!;

        final skippedPutnici = result.skippedPutnici ?? [];
        final finalRoute = [...skippedPutnici, ...optimizedPutnici];

        if (mounted) {
          setState(() {
            _optimizedRoute = finalRoute; // Preskoceni + optimizovani
            _isRouteOptimized = true;
            _isListReordered = true;
            _isOptimizing = false;
            _putniciEta = result.putniciEta; // Sacuvaj ETA za notifikacije
          });
        }

        if (_currentDriver != null && result.putniciEta != null) {
          await _startGpsTracking();
        }

        final routeString = optimizedPutnici.take(3).map((p) => p.adresa?.split(',').first ?? p.ime).join(' → ');

        final skipped = result.skippedPutnici;
        final hasSkipped = skipped != null && skipped.isNotEmpty;

        if (mounted) {
          V2AppSnackBar.success(context, '✅ RUTA OPTIMIZOVANA za $_selectedGrad $_selectedVreme!');

          // ? OPTIMIZACIJA 3: Zameni blokirajuci AlertDialog sa Snackbar-om
          // Korisnik vidi notifikaciju ali NIJE BLOKIRAN da nastavi sa akcijama
          if (hasSkipped) {
            if (mounted) {
              final skippedNames = skipped.take(5).map((p) => p.ime).join(', ');
              final moreText = skipped.length > 5 ? ' +${skipped.length - 5} više' : '';

              V2AppSnackBar.warning(context, '⚠️ ${skipped.length} putnika BEZ adrese: $skippedNames$moreText');
            }
          }
        }
      } else {
        // ? OSRM/V2SmartNavigationService nije uspeo - NE koristi fallback, prika?i gre?ku
        if (mounted) {
          setState(() {
            _isOptimizing = false;
            // NE postavljaj _isRouteOptimized = true jer ruta NIJE optimizovana!
          });
          V2AppSnackBar.error(context, '❌ Optimizacija neuspešna: ${result.message}');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isOptimizing = false;
          _isRouteOptimized = false;
          _isListReordered = false;
        });
        V2AppSnackBar.error(context, '❌ Greška pri optimizaciji: $e');
      }
    }
  }

  // DUGME ZA GPS TRACKING / OPTIMIZACIJU
  // Prima listu putnika direktno iz glavnog streama - nema duplog streama
  Widget _buildOptimizeButton(List<V2Putnik> mojiAktivniPutnici) {
    final normFilterTime = V2GradAdresaValidator.normalizeTime(_selectedVreme);
    final filtriraniPutnici = mojiAktivniPutnici.where((p) {
      if (normFilterTime.isNotEmpty) {
        final pTime = V2GradAdresaValidator.normalizeTime(p.polazak);
        if (pTime != normFilterTime) return false;
      }
      if (p.jeOtkazan || p.jePokupljen || p.jeOdsustvo) return false;
      if (!V2TextUtils.isStatusActive(p.status)) return false;
      // Iskljuci putnike u obradi (još nisu obrađeni)
      if (p.status?.toLowerCase() == 'obrada') return false;
      return true;
    }).toList();

    final bool isDriverValid = _currentDriver != null && V2VozacCache.isValidIme(_currentDriver);
    final bool canPress = !_isOptimizing && isDriverValid;

    final baseColor = _isGpsTracking ? Colors.orange : (_isRouteOptimized ? Colors.green : Colors.white);

    return InkWell(
      onTap: canPress
          ? () async {
              if (_isGpsTracking) {
                await _stopGpsTracking();
              } else if (_isRouteOptimized) {
                await _startGpsTracking();
              } else {
                await _optimizeCurrentRoute(filtriraniPutnici, isAlreadyOptimized: false);
              }
            }
          : null,
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: 1.0,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: baseColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _getBorderColor(baseColor)),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _isOptimizing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      _isGpsTracking ? 'STOP' : 'START',
                      style: TextStyle(
                        color: baseColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  // ? SPEEDOMETER DUGME U APPBAR-U - IDENTICNO KAO DANAS SCREEN
  Widget _buildSpeedometerButton() {
    return StreamBuilder<double>(
      stream: V2RealtimeGpsService.speedStream,
      builder: (context, speedSnapshot) {
        final speed = speedSnapshot.data ?? 0.0;
        final speedColor = speed >= 90
            ? Colors.red
            : speed >= 60
                ? Colors.orange
                : speed > 0
                    ? Colors.green
                    : Colors.white; // ? Koristi cisto belu, pa cemo je 'uti?ati' sa alpha na pozadini

        return Opacity(
          opacity: 1.0,
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: speedColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _getBorderColor(speedColor)),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      speed.toStringAsFixed(0),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: speedColor,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  if (speed > 0) ...[
                    const SizedBox(width: 2),
                    const Text(
                      'km/h',
                      style: TextStyle(color: Colors.white54, fontSize: 8),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMapsButton() {
    final hasOptimizedRoute = _isRouteOptimized && _optimizedRoute.isNotEmpty;
    final bool isDriverValid = _currentDriver != null && V2VozacCache.isValidIme(_currentDriver);
    final bool canPress = hasOptimizedRoute && isDriverValid;
    final baseColor = hasOptimizedRoute ? Colors.blue : Colors.white;

    return InkWell(
      onTap: canPress ? _openHereWeGoNavigation : null,
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: 1.0,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: baseColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _getBorderColor(baseColor)),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'MAPA',
                style: TextStyle(
                  color: baseColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startGpsTracking() async {
    if (!_isRouteOptimized || _optimizedRoute.isEmpty || _currentDriver == null) {
      return;
    }

    try {
      final smer = _selectedGrad.toLowerCase().contains('bela') ? 'BC_VS' : 'VS_BC';

      // Izvuci redosled imena putnika
      final putniciRedosled = _optimizedRoute.map((p) => p.ime).toList();

      await V2DriverLocationService.instance.v2StartTracking(
        vozacId: V2VozacCache.getUuidByIme(_currentDriver!) ?? _currentDriver!,
        vozacIme: _currentDriver!,
        grad: _selectedGrad,
        vremePolaska: _selectedVreme,
        smer: smer,
        putniciEta: _putniciEta,
        putniciCoordinates: null,
        putniciRedosled: putniciRedosled,
        onAllPassengersPickedUp: () {
          if (mounted) {
            setState(() {
              _isGpsTracking = false;
            });
            V2AppSnackBar.success(context, '✅ Svi putnici pokupljeni! Tracking automatski zaustavljen.');
          }
        },
      );

      if (mounted) {
        setState(() => _isGpsTracking = true);
        V2AppSnackBar.success(context, '📍 GPS tracking pokrenut! Putnici dobijaju realtime lokaciju.');
      }

      // Pošalji push notifikacije putnicima - vozac krenuo + ETA
      _sendVozacKrenulNotifikacije();
    } catch (e) {
      if (mounted) {
        V2AppSnackBar.error(context, '❌ Greška pri pokretanju GPS trackinga: $e');
      }
    }
  }

  // ZAUSTAVI GPS TRACKING
  Future<void> _stopGpsTracking() async {
    await V2DriverLocationService.instance.v2StopTracking();

    if (mounted) {
      setState(() {
        _isGpsTracking = false;
      });
      V2AppSnackBar.warning(context, '⚠️ GPS tracking zaustavljen');
    }
  }

  /// ?? Pošalji push notifikacije putnicima kada vozac startuje rutu
  Future<void> _sendVozacKrenulNotifikacije() async {
    if (_optimizedRoute.isEmpty || _currentDriver == null) return;

    final futures = <Future<void>>[];

    for (final v2Putnik in _optimizedRoute) {
      final putnikId = v2Putnik.id?.toString();
      if (putnikId == null) continue;

      // Ako V2Putnik nema ID ili je vec pokupljen/otkazan, preskoci
      if (v2Putnik.jePokupljen || v2Putnik.jeOtkazan || v2Putnik.jeOdsustvo) continue;

      // ETA za ovog putnika (po imenu)
      final etaMinuta = _putniciEta?[v2Putnik.ime];
      final etaTekst = etaMinuta != null ? 'Dolazak za oko $etaMinuta min.' : 'Vozac je krenuo po vas!';

      futures.add(
        V2RealtimeNotificationService.sendNotificationToPutnik(
          putnikId: putnikId,
          title: '🚌 $_currentDriver krece!',
          body: etaTekst,
          data: {
            'type': 'vozac_krenuo',
            'vozac': _currentDriver!,
            'eta_minuta': etaMinuta?.toString() ?? '',
            'grad': _selectedGrad,
            'vreme': _selectedVreme,
          },
        ),
      );
    }

    // Salji sve notifikacije paralelno - Supabase edge funkcija prima svaki poziv neovisno
    await Future.wait(futures, eagerError: false);
  }

  Future<void> _openHereWeGoNavigation() async {
    if (!_isRouteOptimized || _optimizedRoute.isEmpty) return;

    try {
      final result = await V2SmartNavigationService.startMultiProviderNavigation(
        context: context,
        putnici: _optimizedRoute,
        startCity: _selectedGrad.isNotEmpty ? _selectedGrad : 'VS',
      );

      if (result.success) {
        if (mounted) {
          V2AppSnackBar.success(context, '✅ ${result.message}');
        }
      } else {
        if (mounted) {
          V2AppSnackBar.error(context, '❌ ${result.message}');
        }
      }
    } catch (e) {
      if (mounted) {
        V2AppSnackBar.error(context, '❌ Greška pri otvaranju navigacije: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: V2ThemeManager().currentGradient,
      ),
      child: StreamBuilder<List<V2Putnik>>(
        stream: _streamPutnici,
        builder: (context, snapshot) {
          // Osvježi _latestPutnici iz builder-a — zamjena za ručni StreamSubscription
          if (snapshot.hasData) _latestPutnici = snapshot.data!;
          // -- Zajednicki podaci za body i nav bar --------------------------
          final sviPutnici = snapshot.data ?? <V2Putnik>[];
          final targetDan = V2DanUtils.odIso(_workingDateIso); // jednom, dijeli se svuda
          final currentVozacId = V2VozacCache.getUuidByIme(_currentDriver ?? '');
          final mojiPutnici = _currentDriver == null
              ? sviPutnici
              : V2VozacPutnikService.filterKombinovan<V2Putnik>(
                  sviPutnici: sviPutnici,
                  vozacId: currentVozacId ?? '',
                  targetDan: targetDan,
                  individualneDodjele: _vozacPutnikCache,
                  raspored: _rasporedCache,
                  getId: (p) => p.id?.toString() ?? '',
                  getGrad: (p) => p.grad,
                  getPolazak: (p) => p.polazak,
                );

          // -- Nav bar: samo dodeljena vremena vozaca ------------------------
          final dodeljenaVremena = _rasporedVozaca(sviPutnici: mojiPutnici);
          final bcVremenaToShow =
              (dodeljenaVremena.where((v) => v['grad'] == 'BC').map((v) => v['vreme']!).toList()..sort());
          final vsVremenaToShow =
              (dodeljenaVremena.where((v) => v['grad'] == 'VS').map((v) => v['vreme']!).toList()..sort());

          final countHelper = V2PutnikCountHelper.fromPutnici(
            putnici: mojiPutnici,
            targetDayAbbr: targetDan,
          );
          int getPutnikCount(String grad, String vreme) => countHelper.getCount(grad, vreme);
          int getKapacitet(String grad, String vreme) => V2KapacitetService.getKapacitetSync(grad, vreme);

          Widget buildNavBarForType(String navType) {
            return V2BottomNavBar(
              sviPolasci: _sviPolasci,
              selectedGrad: _selectedGrad,
              selectedVreme: _selectedVreme,
              getPutnikCount: getPutnikCount,
              getKapacitet: getKapacitet,
              onPolazakChanged: _onPolazakChanged,
              bcVremena: bcVremenaToShow,
              vsVremena: vsVremenaToShow,
            );
          }

          // -----------------------------------------------------------------
          return Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              automaticallyImplyLeading: false,
              toolbarHeight: 80,
              flexibleSpace: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildDigitalDateDisplay(),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _buildOptimizeButton(mojiPutnici)),
                          const SizedBox(width: 4),
                          Expanded(child: _buildMapsButton()),
                          const SizedBox(width: 4),
                          Expanded(child: _buildSpeedometerButton()),
                          const SizedBox(width: 4),
                          _buildAppBarButton(
                            icon: Icons.lock_reset,
                            color: Colors.blueAccent,
                            onTap: _promeniSifru,
                          ),
                          const SizedBox(width: 4),
                          _buildAppBarButton(
                            icon: Icons.logout,
                            color: Colors.red.shade400,
                            onTap: _logout,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            bottomNavigationBar: ValueListenableBuilder<String>(
              valueListenable: navBarTypeNotifier,
              builder: (context, navType, _) => buildNavBarForType(navType),
            ),
            body: _currentDriver == null
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : Builder(builder: (context) {
                    final filteredByGradVreme = mojiPutnici.where((p) {
                      // Filter po gradu
                      final gradMatch =
                          _selectedGrad.isEmpty || V2GradAdresaValidator.isGradMatch(p.grad, p.adresa, _selectedGrad);

                      // Filter po vremenu
                      final vremeMatch = _selectedVreme.isEmpty ||
                          V2GradAdresaValidator.normalizeTime(p.polazak) ==
                              V2GradAdresaValidator.normalizeTime(_selectedVreme);

                      // Sakrij putnike u obradi
                      final isObrada = p.status?.toLowerCase() == 'obrada';
                      return gradMatch && vremeMatch && !isObrada;
                    }).toList();

                    // Ako je ruta optimizovana, sortiraj po redosledu iz `_optimizedRoute`
                    List<V2Putnik> putnici = filteredByGradVreme;

                    if (_isRouteOptimized && _optimizedRoute.isNotEmpty) {
                      final trenutniIds = filteredByGradVreme.map((p) => p.id).toSet();
                      final optimizedIds = _optimizedRoute.map((p) => p.id).toSet();

                      // Broj belih putnika (nepokupljenih) u obe liste
                      final trenutniBeli = filteredByGradVreme
                          .where((p) => !p.jePokupljen && !p.jeOtkazan && !p.jeOdsustvo)
                          .map((p) => p.id)
                          .toSet();
                      final optimizedBeli = _optimizedRoute
                          .where((p) => !p.jePokupljen && !p.jeOtkazan && !p.jeOdsustvo)
                          .map((p) => p.id)
                          .toSet();

                      // Ako ima novih belih putnika ili su izbrisani beli putnici, resetuj optimizaciju
                      final imaNoviPutnik = trenutniBeli.difference(optimizedBeli).isNotEmpty;
                      final imaIzbrisan = optimizedBeli.difference(trenutniBeli).isNotEmpty;

                      if (imaNoviPutnik || imaIzbrisan) {
                        // Lista se promenila - resetuj optimizaciju
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          setState(() {
                            _isRouteOptimized = false;
                            _isListReordered = false;
                            _optimizedRoute = [];
                          });
                        });
                        // Koristi nesortirane putnike za ovaj frame
                        putnici = filteredByGradVreme;
                      } else {
                        // Lista je ista - primeni optimizovani redosled
                        final optimizedOrder = <dynamic, int>{};

                        for (int i = 0; i < _optimizedRoute.length; i++) {
                          optimizedOrder[_optimizedRoute[i].id] = i;
                        }

                        putnici.sort((a, b) {
                          final aIndex = optimizedOrder[a.id] ?? 999;
                          final bIndex = optimizedOrder[b.id] ?? 999;
                          return aIndex.compareTo(bIndex);
                        });
                      }
                    }

                    return Column(
                      children: [
                        // Lista putnika - koristi V2PutnikList sa stream-om kao DanasScreen
                        Expanded(
                          child: putnici.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.inbox,
                                        size: 64,
                                        color: Colors.white.withValues(alpha: 0.5),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Nema putnika za izabrani polazak',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.7),
                                          fontSize: 16,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                )
                              : V2PutnikList(
                                  putnici: putnici,
                                  useProvidedOrder: _isListReordered,
                                  currentDriver:
                                      _currentDriver!, // ? FIX: Koristi dinamicki _currentDriver umesto hardkodovanog _vozacIme
                                  selectedGrad: _selectedGrad,
                                  selectedVreme: _selectedVreme,
                                  selectedDay: targetDan,
                                  onPutnikStatusChanged: _reoptimizeAfterStatusChange,
                                  bcVremena: V2RouteConfig.getVremenaByNavType('BC'),
                                  vsVremena: V2RouteConfig.getVremenaByNavType('VS'),
                                ),
                        ),
                      ],
                    );
                  }),
            // -----------------------------------------------------------------
          ); // end Scaffold
        }, // end StreamBuilder builder
      ), // end StreamBuilder
    ); // end Container
  }

  Widget _buildDigitalDateDisplay() {
    final parts = _workingDateIso.split('-');
    final now =
        parts.length == 3 ? DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2])) : DateTime.now();

    final dayNames = ['PONEDELJAK', 'UTORAK', 'SREDA', 'CETVRTAK', 'PETAK', 'SUBOTA', 'NEDELJA'];
    final dayName = dayNames[now.weekday - 1];
    final dayStr = now.day.toString().padLeft(2, '0');
    final monthStr = now.month.toString().padLeft(2, '0');
    final yearStr = now.year.toString().substring(2);

    final isPreview = widget.previewAsDriver != null && widget.previewAsDriver!.isNotEmpty;
    final driverColor =
        isPreview ? V2VozacCache.getColor(widget.previewAsDriver!) : Theme.of(context).colorScheme.onPrimary;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // LEVO - DATUM
        Text(
          '$dayStr.$monthStr.$yearStr',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onPrimary,
            shadows: const [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
          ),
        ),
        // SREDINA - DAN
        Text(
          dayName,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: driverColor,
            shadows: const [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
          ),
        ),
        // DESNO - VREME
        V2ClockTicker(
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onPrimary,
            shadows: const [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
          ),
          showSeconds: true,
        ),
      ],
    );
  }

  Widget _buildAppBarButton({
    String? label,
    IconData? icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _getBorderColor(color)),
        ),
        child: Center(
          child: icon != null
              ? Icon(icon, color: color, size: 14)
              : Text(
                  label ?? '',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }

  // Helper za border boju kao u danas_screen
  Color _getBorderColor(Color color) {
    if (color == Colors.green) return Colors.green[300]!;
    if (color == Colors.purple) return Colors.purple[300]!;
    if (color == Colors.red) return Colors.red[300]!;
    if (color == Colors.orange) return Colors.orange[300]!;
    if (color == Colors.blue) return Colors.blue[300]!;
    return color.withValues(alpha: 0.6);
  }
}
