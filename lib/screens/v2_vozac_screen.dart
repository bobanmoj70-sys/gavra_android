import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart'; // ??? Za GPS poziciju

import '../config/v2_route_config.dart';
import '../globals.dart';
import '../models/v2_putnik.dart';
import '../services/realtime/v2_master_realtime_manager.dart'; // Za realtime raspored
import '../services/v2_auth_manager.dart';
import '../services/v2_driver_location_service.dart'; // ?? Za ETA tracking
import '../services/v2_firebase_service.dart'; // ?? Za vozaca
import '../services/v2_kapacitet_service.dart'; // ?? Za broj mesta
import '../services/v2_local_notification_service.dart'; // ?? Za lokalne notifikacije
import '../services/v2_polasci_service.dart';
import '../services/v2_realtime_gps_service.dart'; // ??? Za GPS tracking
import '../services/v2_realtime_notification_service.dart'; // ?? Za realtime notifikacije
import '../services/v2_smart_navigation_service.dart';
import '../services/v2_statistika_istorija_service.dart';
import '../services/v2_theme_manager.dart';
import '../services/v2_vozac_putnik_service.dart';
import '../services/v2_vozac_raspored_service.dart';
import '../utils/v2_app_snack_bar.dart';
import '../utils/v2_grad_adresa_validator.dart'; // ??? Za validaciju gradova
import '../utils/v2_putnik_count_helper.dart'; // ?? Za brojanje putnika po gradu
import '../utils/v2_putnik_helpers.dart'; // ??? Centralizovani helperi
import '../utils/v2_text_utils.dart'; // Za V2TextUtils.isStatusActive
import '../utils/v2_vozac_cache.dart'; // Za validaciju vozaca
import '../widgets/v2_bottom_nav_bar_letnji.dart';
import '../widgets/v2_bottom_nav_bar_praznici.dart';
import '../widgets/v2_bottom_nav_bar_zimski.dart';
import '../widgets/v2_clock_ticker.dart';
import '../widgets/v2_putnik_list.dart';
import '../widgets/v2_shimmer_widgets.dart';
import 'v2_dugovi_screen.dart';
import 'v2_welcome_screen.dart';

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
  StreamSubscription<String>? _rasporedRealtimeSub; // ?? Realtime raspored
  StreamSubscription<String>? _vozacPutnikRealtimeSub; // ?? Realtime vozac_putnik

  Stream<Map<String, double>>? _streamPazar;

  String _selectedGrad = 'BC';
  String _selectedVreme = ''; // Ce biti postavljen u _selectClosestDeparture()

  // ?? OPTIMIZACIJA RUTE - kopirano iz DanasScreen
  bool _isRouteOptimized = false;
  List<V2Putnik> _optimizedRoute = [];
  Map<String, int>? _putniciEta; // ETA po imenu putnika (minuti) nakon optimizacije
  bool _isOptimizing = false; // ? Loading state specificno za optimizaciju rute

  /// ?? HELPER: Vraca radni datum - vikendom vraca naredni ponedeljak
  String _getWorkingDateIso() => V2PutnikHelpers.getWorkingDateIso();

  /// ?? HELPER: Dobij dodeljena vremena za trenutnog vozaca.
  ///
  /// Kombinuje dva izvora:
  /// 1. [_rasporedCache] ž termini dodeljeni vozacu (vozac_raspored), prikazuju se cak i prazni
  /// 2. [sviPutnici] ž vremena iz putnika koji su vec filtrirani za ovog vozaca
  List<Map<String, String>> _rasporedVozaca({List<V2Putnik>? sviPutnici}) {
    if (_currentDriver == null) return [];

    final dodeljena = <Map<String, String>>[];
    final currentVozacId = V2VozacCache.getUuidByIme(_currentDriver ?? '');
    final targetDan = _isoDateToDayAbbr(_getWorkingDateIso());

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

  String? _currentDriver; // ?? Trenutni vozac

  // ??? VOZAC RASPORED - per-termin filter
  List<V2VozacRasporedEntry> _rasporedCache = [];

  // ?? VOZAC V2Putnik - per-V2Putnik individualne dodjele
  List<V2VozacPutnikEntry> _vozacPutnikCache = [];

  // Status varijable
  bool _isListReordered = false;
  bool _isGpsTracking = false; // ??? GPS tracking status

  // ?? LOCK ZA KONKURENTNE REOPTIMIZACIJE

  // ?? DINAMICKA VREMENA - prate navBarTypeNotifier (praznici/zimski/letnji)
  List<String> get _bcVremena {
    final navType = navBarTypeNotifier.value;
    if (navType == 'praznici') {
      return V2RouteConfig.bcVremenaPraznici;
    } else if (navType == 'zimski') {
      return V2RouteConfig.bcVremenaZimski;
    } else {
      return V2RouteConfig.bcVremenaLetnji;
    }
  }

  List<String> get _vsVremena {
    final navType = navBarTypeNotifier.value;
    if (navType == 'praznici') {
      return V2RouteConfig.vsVremenaPraznici;
    } else if (navType == 'zimski') {
      return V2RouteConfig.vsVremenaZimski;
    } else {
      return V2RouteConfig.vsVremenaLetnji;
    }
  }

  List<String> get _sviPolasci {
    final bcList = _bcVremena.map((v) => '$v BC').toList();
    final vsList = _vsVremena.map((v) => '$v VS').toList();
    return [...bcList, ...vsList];
  }

  @override
  void initState() {
    super.initState();
    // ? ODMAH inicijalizuj iz V2MasterRealtimeManager cache-a (vec ucitan pri startu app-a)
    // Sprjecava race condition gdje _rasporedCache ostaje prazan ? filterKombinovan vraca sve putnike
    _rasporedCache =
        V2MasterRealtimeManager.instance.rasporedCache.values.map((row) => V2VozacRasporedEntry.fromMap(row)).toList();
    _initAsync();
  }

  Future<void> _initAsync() async {
    // 1. Inicijalizuj vozaca (ovo ce takode pozvati _selectClosestDeparture)
    await _initializeCurrentDriver();

    // 2. Ucitaj raspored vozaca + subscribe na realtime promjene
    _loadRaspored();
    _subscribeRealtime();

    // 3. Ostalo
    _initializeGpsTracking();
    V2LocalNotificationService.initialize(context);
    V2FirebaseService.getCurrentDriver().then((driver) {
      if (driver != null && driver.isNotEmpty) {
        V2RealtimeNotificationService.initialize();
      }
    });
  }

  Future<void> _loadRaspored() async {
    final rm = V2MasterRealtimeManager.instance;
    final raspored = rm.rasporedCache.values.map((row) => V2VozacRasporedEntry.fromMap(row)).toList();
    final vozacPutnik = rm.vozacPutnikCache.values.map((row) => V2VozacPutnikEntry.fromMap(row)).toList();
    if (mounted) {
      setState(() {
        _rasporedCache = raspored;
        _vozacPutnikCache = vozacPutnik;
      });
    }
  }

  /// Realtime: prati vozac_raspored i vozac_putnik i osvježava lokalne cache-ove
  void _subscribeRealtime() {
    _rasporedRealtimeSub?.cancel();
    _vozacPutnikRealtimeSub?.cancel();
    final rm = V2MasterRealtimeManager.instance;
    _rasporedRealtimeSub = rm.onCacheChanged.where((t) => t == 'v2_vozac_raspored').listen((_) {
      final entries = rm.rasporedCache.values.map((row) => V2VozacRasporedEntry.fromMap(row)).toList();
      if (mounted) setState(() => _rasporedCache = entries);
    });
    _vozacPutnikRealtimeSub = rm.onCacheChanged.where((t) => t == 'v2_vozac_putnik').listen((_) {
      final entries = rm.vozacPutnikCache.values.map((row) => V2VozacPutnikEntry.fromMap(row)).toList();
      if (mounted) setState(() => _vozacPutnikCache = entries);
    });
  }

  // ??? GPS TRACKING INICIJALIZACIJA
  void _initializeGpsTracking() {
    // Start GPS tracking
    V2RealtimeGpsService.startTracking().catchError((Object e) {});

    // Subscribe to driver position updates - auriraj lokaciju u realnom vremenu
    _driverPositionSubscription = V2RealtimeGpsService.positionStream.listen((pos) {
      // ?? Poalji poziciju vozaca u V2DriverLocationService za pracenje uivu
      V2DriverLocationService.instance.forceLocationUpdate(knownPosition: pos);
    });
  }

  @override
  void dispose() {
    _driverPositionSubscription?.cancel();
    _rasporedRealtimeSub?.cancel(); // ?? Realtime raspored
    _vozacPutnikRealtimeSub?.cancel(); // ?? Realtime vozac_putnik
    super.dispose();
  }

  Future<void> _initializeCurrentDriver() async {
    // ?? ADMIN PREVIEW MODE: Ako je prosleden previewAsDriver, koristi ga
    if (widget.previewAsDriver != null && widget.previewAsDriver!.isNotEmpty) {
      _currentDriver = widget.previewAsDriver;
      if (mounted) {
        setState(() {
          _streamPazar ??= V2StatistikaIstorijaService.streamPazarIzCachea(isoDate: _getWorkingDateIso());
        });
        _selectClosestDeparture();
      }
      return;
    }

    _currentDriver = await V2FirebaseService.getCurrentDriver();

    if (mounted) {
      setState(() {
        // Kreira stream tek nakon sto je _currentDriver poznat
        _streamPazar ??= V2StatistikaIstorijaService.streamPazarIzCachea(isoDate: _getWorkingDateIso());
      });
      // ?? Nakon što je vozac inicijalizovan, izaberi najbliži polazak
      _selectClosestDeparture();
    }
  }

  // ??? Konvertuj ISO datum u kraticu dana
  String _isoDateToDayAbbr(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      const dani = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
      return dani[date.weekday - 1];
    } catch (e) {
      return 'pon'; // fallback
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
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const V2WelcomeScreen()),
        (route) => false,
      );
    }
  }

  // ?? REOPTIMIZACIJA RUTE NAKON PROMENE STATUSA PUTNIKA
  Future<void> _reoptimizeAfterStatusChange() async {
    if (!_isRouteOptimized || _optimizedRoute.isEmpty) return;

    // ?? BATCH DOHVATI SVEžE PODATKE IZ BAZE - efikasnije od pojedinacnih poziva
    final ids = _optimizedRoute.where((p) => p.id != null).map((p) => p.id!).toList();
    final targetDan = _isoDateToDayAbbr(_getWorkingDateIso());
    final sveziPutnici = await _putnikService.getPutniciByIds(ids, targetDan: targetDan);

    // Razdvoji pokupljene/otkazane od preostalih
    // Ekran je vec filtriran po vozacu - nema potrebe za dodeljenVozac filterom
    final pokupljeniIOtkazani = sveziPutnici.where((p) {
      return p.jePokupljen || p.jeOtkazan || p.jeOdsustvo || p.jeBezPolaska;
    }).toList();

    final preostaliPutnici = sveziPutnici.where((p) {
      return !p.jePokupljen && !p.jeOtkazan && !p.jeOdsustvo && !p.jeBezPolaska;
    }).toList();

    if (preostaliPutnici.isEmpty) {
      // Svi putnici su pokupljeni ili otkazani - ZADR?I ih u listi

      // ? STOP TRACKING AKO SU SVI GOTOVI
      if (V2DriverLocationService.instance.isTracking) {
        await V2DriverLocationService.instance.updatePutniciEta({});
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

          // ??? REALTIME FIX: Ažuriraj ETA (uklanja pokupljene sa mape)
          if (V2DriverLocationService.instance.isTracking && result.putniciEta != null) {
            await V2DriverLocationService.instance.updatePutniciEta(result.putniciEta!);
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
  void _optimizeCurrentRoute(List<V2Putnik> putnici, {bool isAlreadyOptimized = false}) async {
    // Proveri da li je ulogovan i valjan vozac
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

    // ?? Ako je lista vec optimizovana od strane servisa, koristi je direktno
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
      if (p.jeOtkazan || p.jeBezPolaska) return false;
      // Iskljuci vec pokupljene putnike
      if (p.jePokupljen) return false;
      // Iskljuci odsutne putnike (bolovanje/godisnji)
      if (p.jeOdsustvo) return false;
      // Proveri validnu adresu
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

        // ?? Dodaj putnike BEZ ADRESE na pocetak liste kao podsetnik
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

        // ?? AUTOMATSKI POKRENI GPS TRACKING nakon optimizacije
        if (_currentDriver != null && result.putniciEta != null) {
          await _startGpsTracking();
        }

        final routeString = optimizedPutnici.take(3).map((p) => p.adresa?.split(',').first ?? p.ime).join(' → ');

        // Proveri da li ima preskocenih putnika
        final skipped = result.skippedPutnici;
        final hasSkipped = skipped != null && skipped.isNotEmpty;

        if (mounted) {
          V2AppSnackBar.success(context, '✅ RUTA OPTIMIZOVANA za $_selectedGrad $_selectedVreme!');

          // ? OPTIMIZACIJA 3: Zameni blokirajuci AlertDialog sa Snackbar-om
          // Korisnik vidi notifikaciju ali NIJE BLOKIRAN da nastavi sa akcijama
          if (hasSkipped) {
            // ?? Prika?i preskocene putnike kao SNACKBAR umesto DIALOG-a
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
      final pTime = V2GradAdresaValidator.normalizeTime(p.polazak);
      if (pTime != normFilterTime) return false;
      if (p.jeOtkazan || p.jeBezPolaska || p.jePokupljen || p.jeOdsustvo) return false;
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
          ? () {
              if (_isGpsTracking) {
                _stopGpsTracking(); // async, fire-and-forget je OK ovdje jer je UI odmah
              } else if (_isRouteOptimized) {
                _startGpsTracking();
              } else {
                _optimizeCurrentRoute(filtriraniPutnici, isAlreadyOptimized: false);
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

  // ??? DUGME ZA NAVIGACIJU - OTVARA HERE WeGo SA REDOSLEDOM IZ OPTIMIZOVANE RUTE
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

  // ?? POKRENI GPS TRACKING (ruta je vec optimizovana)
  Future<void> _startGpsTracking() async {
    if (!_isRouteOptimized || _optimizedRoute.isEmpty || _currentDriver == null) {
      return;
    }

    try {
      final smer = _selectedGrad.toLowerCase().contains('bela') ? 'BC_VS' : 'VS_BC';

      // Konvertuj koordinate: Map<V2Putnik, Position> -> Map<String, Position>
      Map<String, Position>? coordsByName;

      // Izvuci redosled imena putnika
      final putniciRedosled = _optimizedRoute.map((p) => p.ime).toList();

      await V2DriverLocationService.instance.startTracking(
        vozacId: V2VozacCache.getUuidByIme(_currentDriver!) ?? _currentDriver!,
        vozacIme: _currentDriver!,
        grad: _selectedGrad,
        vremePolaska: _selectedVreme,
        smer: smer,
        putniciEta: _putniciEta,
        putniciCoordinates: coordsByName,
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
    await V2DriverLocationService.instance.stopTracking();

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
      if (v2Putnik.jePokupljen || v2Putnik.jeOtkazan || v2Putnik.jeOdsustvo || v2Putnik.jeBezPolaska) continue;

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

  // ??? OTVORI HERE WeGo NAVIGACIJU SA OPTIMIZOVANIM REDOSLEDOM
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
        // ?? EGRESS OPT: JEDAN stream ž body i nav bar koriste iste podatke
        stream: _currentDriver == null
            ? const Stream.empty()
            : _putnikService.streamKombinovaniPutniciFiltered(
                isoDate: _getWorkingDateIso(),
                vozacId: V2VozacCache.getUuidByIme(_currentDriver ?? ''),
              ),
        builder: (context, snapshot) {
          // -- Zajednicki podaci za body i nav bar --------------------------
          final sviPutnici = snapshot.data ?? <V2Putnik>[];
          final targetDan = _isoDateToDayAbbr(_getWorkingDateIso());
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
            targetDateIso: _getWorkingDateIso(),
            targetDayAbbr: targetDan,
          );
          int getPutnikCount(String grad, String vreme) => countHelper.getCount(grad, vreme);
          int getKapacitet(String grad, String vreme) => V2KapacitetService.getKapacitetSync(grad, vreme);

          Widget buildNavBarForType(String navType) {
            switch (navType) {
              case 'praznici':
                return V2BottomNavBarPraznici(
                  sviPolasci: _sviPolasci,
                  selectedGrad: _selectedGrad,
                  selectedVreme: _selectedVreme,
                  getPutnikCount: getPutnikCount,
                  getKapacitet: getKapacitet,
                  onPolazakChanged: _onPolazakChanged,
                  bcVremena: bcVremenaToShow,
                  vsVremena: vsVremenaToShow,
                );
              case 'zimski':
                return V2BottomNavBarZimski(
                  sviPolasci: _sviPolasci,
                  selectedGrad: _selectedGrad,
                  selectedVreme: _selectedVreme,
                  getPutnikCount: getPutnikCount,
                  getKapacitet: getKapacitet,
                  onPolazakChanged: _onPolazakChanged,
                  bcVremena: bcVremenaToShow,
                  vsVremena: vsVremenaToShow,
                );
              default:
                return V2BottomNavBarLetnji(
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
                      // PRVI RED - Datum i vreme
                      _buildDigitalDateDisplay(),
                      const SizedBox(height: 8),
                      // DRUGI RED - Dugmad ravnomerno rasporedena
                      Row(
                        children: [
                          // ?? RUTA DUGME
                          Expanded(child: _buildOptimizeButton(mojiPutnici)),
                          const SizedBox(width: 4),
                          // ??? NAV DUGME
                          Expanded(child: _buildMapsButton()),
                          const SizedBox(width: 4),

                          // ??? BRZINOMER
                          Expanded(child: _buildSpeedometerButton()),
                          const SizedBox(width: 4),
                          // Logout
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
                    if (snapshot.connectionState == ConnectionState.waiting && snapshot.data == null) {
                      return Column(
                        children: [
                          V2ShimmerWidgets.vozacHeaderShimmer(context),
                          const SizedBox(height: 8),
                          V2ShimmerWidgets.statistikaShimmer(context),
                          Expanded(child: V2ShimmerWidgets.putnikListShimmer(itemCount: 5)),
                        ],
                      );
                    }
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

                    // ?? FIX: Uvek koristi `filteredByGradVreme` kao izvor istine (iz streama)
                    // Ako je ruta optimizovana, sortiraj po redosledu iz `_optimizedRoute`
                    List<V2Putnik> putnici = filteredByGradVreme;

                    if (_isRouteOptimized && _optimizedRoute.isNotEmpty) {
                      // Proveri da li se lista znacajno promenila (novi ili izbrisani putnici)
                      final trenutniIds = filteredByGradVreme.map((p) => p.id).toSet();
                      final optimizedIds = _optimizedRoute.map((p) => p.id).toSet();

                      // Broj belih putnika (nepokupljenih) u obe liste
                      final trenutniBeli = filteredByGradVreme
                          .where((p) => !p.jePokupljen && !p.jeOtkazan && !p.jeOdsustvo && !p.jeBezPolaska)
                          .map((p) => p.id)
                          .toSet();
                      final optimizedBeli = _optimizedRoute
                          .where((p) => !p.jePokupljen && !p.jeOtkazan && !p.jeOdsustvo && !p.jeBezPolaska)
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
                        // KOCKE - Pazar, Dugovi
                        _buildStatsRow(sviPutnici, mojiPutnici),
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
                                  bcVremena: _bcVremena,
                                  vsVremena: _vsVremena,
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

  // ?? Digitalni datum display
  Widget _buildDigitalDateDisplay() {
    final workingDateIso = _getWorkingDateIso();
    final parts = workingDateIso.split('-');
    final now =
        parts.length == 3 ? DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2])) : DateTime.now();

    final dayNames = ['PONEDELJAK', 'UTORAK', 'SREDA', 'CETVRTAK', 'PETAK', 'SUBOTA', 'NEDELJA'];
    final dayName = dayNames[now.weekday - 1];
    final dayStr = now.day.toString().padLeft(2, '0');
    final monthStr = now.month.toString().padLeft(2, '0');
    final yearStr = now.year.toString().substring(2);

    // ?? Izracunaj boju za dan (ako smo u admin preview modu)
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
            color: driverColor, // ?? Koristi boju vozaca ako je preview
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

  // ?? AppBar dugme
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

  // ?? Statistika kocka
  Widget _buildStatBox(String label, String value, Color color) {
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _getBorderColor(color)),
      ),
      child: Center(
        child: Text(
          label.isEmpty ? value : label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  // ?? Stats row
  Widget _buildStatsRow(List<V2Putnik> sviPutnici, List<V2Putnik> mojiPutnici) {
    final filteredDuzniciRaw = sviPutnici.where((v2Putnik) {
      // Duznici su samo dnevni i posiljke (radnici i ucenici ne duguju po voznji)
      if (v2Putnik.isRadnik || v2Putnik.isUcenik) return false;
      final nijePlatio = v2Putnik.placeno != true; // placeno flag iz v2_polasci srRow
      final nijeOtkazan = !v2Putnik.jeOtkazan && !v2Putnik.jeBezPolaska;
      final pokupljen = v2Putnik.jePokupljen;
      return nijePlatio && nijeOtkazan && pokupljen;
    }).toList();

    final seenIds = <dynamic>{};
    final filteredDuznici = filteredDuzniciRaw.where((p) {
      final key = p.id ?? '${p.ime}_${p.dan}';
      if (seenIds.contains(key)) return false;
      seenIds.add(key);
      return true;
    }).toList();

    // ?? NOVI JEDNOSTAVAN BROJAC POVRATAKA
    // Grupišemo sve polaske po putniku (ID) da vidimo ko ima BC, a ko ima i VS
    final Map<dynamic, Set<String>> putnikSmerovi = {};

    for (var p in sviPutnici) {
      // ISKLJUCUJEMO: otkazano, bez_polaska, odsustvo, obrisan, posiljke
      if (p.jeOtkazan || p.jeBezPolaska || p.jeOdsustvo || p.obrisan) continue;
      if (p.tipPutnika == 'posiljka') continue;

      // SAMO UCENICI za kocku Povratak
      if (p.tipPutnika != 'ucenik') continue;

      // Preskoči otkazano i bez_polaska
      final statusLower = p.status?.toLowerCase() ?? '';
      if (statusLower == 'otkazano' || statusLower == 'bez_polaska') continue;

      final id = p.id;
      if (id == null) continue;

      putnikSmerovi.putIfAbsent(id, () => <String>{});

      if (p.grad == 'BC') {
        putnikSmerovi[id]!.add('bc');
      } else {
        putnikSmerovi[id]!.add('vs');
      }
    }

    int ukupnoPutnika = 0;
    int saObaSmera = 0;

    final List<String> samoJedanSmerImena = [];

    putnikSmerovi.forEach((id, smerovi) {
      ukupnoPutnika++;
      if (smerovi.contains('bc') && smerovi.contains('vs')) {
        saObaSmera++;
      } else {
        final p = sviPutnici.firstWhere((element) => element.id == id, orElse: () => sviPutnici.first);
        if (p.id != id) return; // V2Putnik nije pronaden, preskoci
        final grad = smerovi.contains('bc') ? 'BC' : 'VS';
        samoJedanSmerImena.add('${p.ime} ($grad)');
      }
    });

    return Container(
      margin: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: StreamBuilder<Map<String, double>>(
              stream: _streamPazar,
              builder: (context, snapshot) {
                final pazar = _currentDriver != null ? (snapshot.data?[_currentDriver!] ?? 0.0) : 0.0;
                return InkWell(
                  onTap: () {
                    _showStatPopup(
                      context,
                      'Pazar',
                      pazar.toStringAsFixed(0),
                      Colors.green,
                    );
                  },
                  child: _buildStatBox(
                    'Pazar',
                    pazar.toStringAsFixed(0),
                    Colors.green,
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (context) => V2DugoviScreen(currentDriver: _currentDriver!),
                  ),
                );
              },
              child: _buildStatBox(
                'Dugovi',
                filteredDuznici.length.toString(),
                filteredDuznici.isEmpty ? Colors.blue : Colors.red,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // ?? KOCKA ZA POVRATAK
          Expanded(
            child: InkWell(
              onTap: () {
                _showPovratakStatPopup(
                  context,
                  'Povratak',
                  '$saObaSmera/$ukupnoPutnika',
                  samoJedanSmerImena,
                  Colors.orange,
                );
              },
              child: _buildStatBox(
                'Povratak',
                '$saObaSmera/$ukupnoPutnika',
                Colors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ?? POPUP ZA PRIKAZ POVRATKA SA SPISKOM
  void _showPovratakStatPopup(
    BuildContext context,
    String label,
    String value,
    List<String> putniciJedanSmer,
    Color color,
  ) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.4),
                Colors.black.withValues(alpha: 0.8),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 15,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Divider(color: Colors.white24, height: 24),
              const Text(
                'Samo jedan polazak:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.orangeAccent,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4,
                ),
                child: putniciJedanSmer.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text(
                          'Svi putnici imaju oba smera! 👍',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: putniciJedanSmer.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              children: [
                                const Icon(Icons.person_outline, size: 16, color: Colors.white54),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    putniciJedanSmer[index],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color.withValues(alpha: 0.3),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Zatvori'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ?? POPUP ZA PRIKAZ STATISTIKE
  void _showStatPopup(BuildContext context, String label, String value, Color color) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _getBorderColor(color)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Zatvori',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
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
    return color.withValues(alpha: 0.6);
  }
}
