import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart'; // 🛰️ Za GPS poziciju

import '../config/route_config.dart';
import '../globals.dart';
import '../models/putnik.dart';
import '../services/auth_manager.dart';
import '../services/driver_location_service.dart'; // 📍 Za ETA tracking
import '../services/firebase_service.dart'; // 👤 Za vozača
import '../services/kapacitet_service.dart'; // 🎫 Za broj mesta
import '../services/local_notification_service.dart'; // 🔔 Za lokalne notifikacije
import '../services/putnik_service.dart';
import '../services/realtime_gps_service.dart'; // 🛰️ Za GPS tracking
import '../services/realtime_notification_service.dart'; // 🔔 Za realtime notifikacije
import '../services/smart_navigation_service.dart';
import '../services/statistika_service.dart';
import '../services/theme_manager.dart';
import '../services/vreme_vozac_service.dart'; // 🕒 Za dodeljena vremena vozača
import '../utils/app_snack_bar.dart';
import '../utils/grad_adresa_validator.dart'; // 🏘️ Za validaciju gradova
import '../utils/putnik_count_helper.dart'; // 🔢 Za brojanje putnika po gradu
import '../utils/putnik_helpers.dart'; // 🛠️ Centralizovani helperi
import '../utils/text_utils.dart'; // 📝 Za TextUtils.isStatusActive
import '../utils/vozac_cache.dart'; // 🎨 Za validaciju vozača
import '../widgets/bottom_nav_bar_letnji.dart';
import '../widgets/bottom_nav_bar_praznici.dart';
import '../widgets/bottom_nav_bar_zimski.dart';
import '../widgets/clock_ticker.dart';
import '../widgets/putnik_list.dart';
import '../widgets/shimmer_widgets.dart';
import 'dugovi_screen.dart';
import 'welcome_screen.dart';

/// 🚛 VOZAČ SCREEN
/// Prikazuje putnike koristeći isti PutnikService stream kao DanasScreen
class VozacScreen extends StatefulWidget {
  /// Opcioni parametar - ako je null, koristi trenutnog ulogovanog vozaca
  /// Ako je prosleden, prikazuje ekran kao da je taj vozac ulogovan (admin preview)
  final String? previewAsDriver;

  const VozacScreen({super.key, this.previewAsDriver});

  @override
  State<VozacScreen> createState() => _VozacScreenState();
}

class _VozacScreenState extends State<VozacScreen> {
  final PutnikService _putnikService = PutnikService();

  StreamSubscription<Position>? _driverPositionSubscription;
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription; // ⚡ ZA AUTOMATSKI POPIS
  StreamSubscription<void>? _vremeVozacSubscription; // 🕒 ZA PROMENE DODELJENIH VREMENA
  StreamSubscription<void>? _putnikVozacSubscription; // 👤 ZA PROMENE INDIVIDUALNIH DODELA PUTNIKA

  String _selectedGrad = 'Bela Crkva';
  String _selectedVreme = '05:00'; // ✅ VRAĆENO NA 05:00 (konzistentno sa RouteConfig)

  // 📍 OPTIMIZACIJA RUTE - kopirano iz DanasScreen
  bool _isRouteOptimized = false;
  List<Putnik> _optimizedRoute = [];
  List<Putnik> _mojiPutnici = []; // Cache za _buildOptimizeButton (iz glavnog streama)
  Map<String, int>? _putniciEta; // ETA po imenu putnika (minuti) nakon optimizacije
  final bool _isLoading = false;
  bool _isOptimizing = false; // ⏳ Loading state specifično za optimizaciju rute

  /// 📅 HELPER: Vraća radni datum - vikendom vraća naredni ponedeljak
  String _getWorkingDateIso() => PutnikHelpers.getWorkingDateIso();

  /// 🕒 HELPER: Dobij dodeljena vremena za trenutnog vozača
  List<Map<String, String>> _getDodeljenaVremena({List<Putnik>? sviPutnici}) {
    if (_currentDriver == null) return [];

    final vozaciZaDan = VremeVozacService().getVozaciZaDanSync(_isoDateToDayAbbr(_getWorkingDateIso()));
    final dodeljena = <Map<String, String>>[];

    // 1. Dodaj vremena iz globalnog rasporeda (VremeVozac table)
    vozaciZaDan.forEach((key, vozac) {
      if (vozac == _currentDriver) {
        final parts = key.split('|');
        if (parts.length == 2) {
          dodeljena.add({
            'grad': parts[0],
            'vreme': parts[1],
          });
        }
      }
    });

    // 2. Dodaj vremena iz individualnih dodela (ako imamo putnike)
    if (sviPutnici != null) {
      for (var p in sviPutnici) {
        if (p.dodeljenVozac == _currentDriver) {
          final pGrad = p.grad;
          final pPolazak = p.polazak;

          // Proveri da li vec imamo ovo vreme u listi
          bool postoji = dodeljena.any((v) => v['grad'] == pGrad && v['vreme'] == pPolazak);
          if (!postoji) {
            dodeljena.add({
              'grad': pGrad,
              'vreme': pPolazak,
            });
          }
        }
      }
    }

    // Sortiraj po vremenu
    dodeljena.sort((a, b) {
      final aTime = a['vreme']!;
      final bTime = b['vreme']!;
      return aTime.compareTo(bTime);
    });

    return dodeljena;
  }

  String? _currentDriver; // 👤 Trenutni vozač

  // Status varijable
  String _navigationStatus = ''; // ignore: unused_field
  int _currentPassengerIndex = 0; // ignore: unused_field
  bool _isListReordered = false;
  bool _isGpsTracking = false; // 🛰️ GPS tracking status

  // 🔐 LOCK ZA KONKURENTNE REOPTIMIZACIJE

  // 🕐 DINAMIČKA VREMENA - prate navBarTypeNotifier (praznici/zimski/letnji)
  List<String> get _bcVremena {
    final navType = navBarTypeNotifier.value;
    if (navType == 'praznici') {
      return RouteConfig.bcVremenaPraznici;
    } else if (navType == 'zimski') {
      return RouteConfig.bcVremenaZimski;
    } else {
      return RouteConfig.bcVremenaLetnji;
    }
  }

  List<String> get _vsVremena {
    final navType = navBarTypeNotifier.value;
    if (navType == 'praznici') {
      return RouteConfig.vsVremenaPraznici;
    } else if (navType == 'zimski') {
      return RouteConfig.vsVremenaZimski;
    } else {
      return RouteConfig.vsVremenaLetnji;
    }
  }

  List<String> get _sviPolasci {
    final bcList = _bcVremena.map((v) => '$v Bela Crkva').toList();
    final vsList = _vsVremena.map((v) => '$v Vrsac').toList();
    return [...bcList, ...vsList];
  }

  @override
  void initState() {
    super.initState();
    _initAsync();
  }

  Future<void> _initAsync() async {
    // 1. Prvo učitaj dodeljena vremena (vreme_vozac tabela)
    await _loadVremeVozacData();

    // 2. Inicijalizuj vozača (ovo će takođe pozvati _selectClosestDeparture)
    await _initializeCurrentDriver();

    // 3. Ostalo
    _initializeNotifications();
    _initializeGpsTracking();

    // 4. 🕒 Slušaj promene dodeljenih vremena I individualnih dodela - jedan listener radi oba posla
    _vremeVozacSubscription = VremeVozacService().onChanges.listen((_) {
      if (mounted) {
        // Osvezi stream putnika jer dodeljenVozac zavisi od vreme_vozac putnik cache-a
        _putnikService.refreshAllActiveStreams();
        setState(() {});
        // Ponovo izaberi najbliži polazak jer se raspored promenio
        _selectClosestDeparture();
      }
    });
    // _putnikVozacSubscription uklonjen - bio je duplikat istog listenera
  }

  // 🕒 UCITAJ VREME VOZAC PODATKE
  Future<void> _loadVremeVozacData() async {
    await VremeVozacService().loadAllVremeVozac();
  }

  // 🛰️ GPS TRACKING INICIJALIZACIJA
  void _initializeGpsTracking() {
    // Start GPS tracking
    RealtimeGpsService.startTracking().catchError((Object e) {});

    // Subscribe to driver position updates - auriraj lokaciju u realnom vremenu
    _driverPositionSubscription = RealtimeGpsService.positionStream.listen((pos) {
      // ?? Poalji poziciju vozaca u DriverLocationService za pracenje uivu
      DriverLocationService.instance.forceLocationUpdate(knownPosition: pos);
    });
  }

  @override
  void dispose() {
    _driverPositionSubscription?.cancel();
    _notificationSubscription?.cancel(); // ⚡ CLEANUP
    _vremeVozacSubscription?.cancel(); // 🕒 CLEANUP
    _putnikVozacSubscription?.cancel(); // 👤 CLEANUP
    super.dispose();
  }

  // ?? INICIJALIZACIJA NOTIFIKACIJA - IDENTICNO KAO DANAS SCREEN
  void _initializeNotifications() {
    // Inicijalizuj heads-up i zvuk notifikacije
    LocalNotificationService.initialize(context);

    // ⚡ LISTEN ZA IN-APP DOGAĐAJE (Automatski Popis)
    _notificationSubscription?.cancel();
    _notificationSubscription = RealtimeNotificationService.notificationStream.listen((data) {
      if (data['type'] == 'automated_popis' && mounted) {
        var stats = data['stats'];
        if (stats != null) {
          if (stats is String) {
            try {
              stats = jsonDecode(stats);
            } catch (e) {
              debugPrint('Greška pri dekodiranju statistike: $e');
              return;
            }
          }
          if (stats is Map) {
            _showAutomatedPopisPopup(Map<String, dynamic>.from(stats));
          }
        }
      }
    });

    // Inicijalizuj realtime notifikacije za vozaca
    FirebaseService.getCurrentDriver().then((driver) {
      if (driver != null && driver.isNotEmpty) {
        RealtimeNotificationService.initialize();
      }
    });
  }

  Future<void> _initializeCurrentDriver() async {
    // ?? ADMIN PREVIEW MODE: Ako je prosleden previewAsDriver, koristi ga
    if (widget.previewAsDriver != null && widget.previewAsDriver!.isNotEmpty) {
      _currentDriver = widget.previewAsDriver;
      if (mounted) {
        setState(() {});
        _selectClosestDeparture();
      }
      return;
    }

    _currentDriver = await FirebaseService.getCurrentDriver();

    if (mounted) {
      setState(() {});
      // 🕒 Nakon što je vozač inicijalizovan, izaberi najbliži polazak
      _selectClosestDeparture();
    }
  }

  // 🗓️ Konvertuj ISO datum u kraticu dana
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

  /// 🕒 Bira polazak koji je najbliži trenutnom vremenu iz dodeljenih polazaka
  void _selectClosestDeparture() {
    if (!mounted || _currentDriver == null) return;

    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    String? closestVreme;
    String? closestGrad;
    int minDifference = 9999;

    // Uzmi samo dodeljena vremena za ovog vozača
    final dodeljenaVremena = _getDodeljenaVremena();
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
    await AuthManager.logout(context);
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const WelcomeScreen()),
        (route) => false,
      );
    }
  }

  // ?? REOPTIMIZACIJA RUTE NAKON PROMENE STATUSA PUTNIKA
  Future<void> _reoptimizeAfterStatusChange() async {
    if (!_isRouteOptimized || _optimizedRoute.isEmpty) return;

    // ?? BATCH DOHVATI SVEŽE PODATKE IZ BAZE - efikasnije od pojedinacnih poziva
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
      // Svi putnici su pokupljeni ili otkazani - ZADR�I ih u listi

      // ? STOP TRACKING AKO SU SVI GOTOVI
      if (DriverLocationService.instance.isTracking) {
        await DriverLocationService.instance.updatePutniciEta({});
      }

      if (mounted) {
        setState(() {
          _optimizedRoute = pokupljeniIOtkazani; // ? ZADR�I pokupljene u listi
          _currentPassengerIndex = 0;
        });
        AppSnackBar.success(context, '✅ Svi putnici su pokupljeni!');
      }
      return;
    }

    // Reoptimizuj rutu od trenutne GPS pozicije
    try {
      final result = await SmartNavigationService.optimizeRouteOnly(
        putnici: preostaliPutnici,
        startCity: _selectedGrad.isNotEmpty ? _selectedGrad : 'Vrsac',
      );

      if (result.success && result.optimizedPutnici != null) {
        if (mounted) {
          setState(() {
            // ? KOMBINUJ: optimizovani preostali + pokupljeni/otkazani na kraju
            _optimizedRoute = [...result.optimizedPutnici!, ...pokupljeniIOtkazani];
            _currentPassengerIndex = 0;
          });

          // 🛠️ REALTIME FIX: Ažuriraj ETA (uklanja pokupljene sa mape)
          if (DriverLocationService.instance.isTracking && result.putniciEta != null) {
            await DriverLocationService.instance.updatePutniciEta(result.putniciEta!);
          }

          if (!mounted) return;

          final sledeci = result.optimizedPutnici!.isNotEmpty ? result.optimizedPutnici!.first.ime : 'N/A';
          AppSnackBar.info(context, '🔄 Ruta ažurirana! Sledeći: $sledeci (${preostaliPutnici.length} preostalo)');
        }
      }
    } catch (e) {
      debugPrint('❌ Error auto-reoptimizing route: $e');
    }
  }

  // OPTIMIZACIJA RUTE
  void _optimizeCurrentRoute(List<Putnik> putnici, {bool isAlreadyOptimized = false}) async {
    // Proveri da li je ulogovan i valjan vozac
    if (_currentDriver == null || !VozacCache.isValidIme(_currentDriver)) {
      if (mounted) {
        AppSnackBar.warning(context, 'Morate biti ulogovani i ovlašćeni da biste koristili optimizaciju rute.');
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
          AppSnackBar.warning(context, '⚠️ Nema putnika sa adresama za reorder');
        }
        return;
      }
      if (mounted) {
        setState(() {
          _optimizedRoute = List<Putnik>.from(putnici);
          _isRouteOptimized = true;
          _isListReordered = true;
          _currentPassengerIndex = 0;
          _isOptimizing = false;
        });
      }

      final routeString = _optimizedRoute.take(3).map((p) => p.adresa?.split(',').first ?? p.ime).join(' ? ');

      if (mounted) {
        AppSnackBar.success(context,
            '📍 Lista putnika optimizovana (server) za $_selectedGrad $_selectedVreme!\n➡️ Sledeći: $routeString${_optimizedRoute.length > 3 ? "..." : ""}');
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
        AppSnackBar.warning(context, '⚠️ Nema putnika sa adresama za optimizaciju');
      }
      return;
    }

    try {
      final result = await SmartNavigationService.optimizeRouteOnly(
        putnici: filtriraniPutnici,
        startCity: _selectedGrad.isNotEmpty ? _selectedGrad : 'Vrsac',
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
            _currentPassengerIndex = 0;
            _isOptimizing = false;
            _putniciEta = result.putniciEta; // Sacuvaj ETA za notifikacije
          });
        }

        // ?? AUTOMATSKI POKRENI GPS TRACKING nakon optimizacije
        if (_currentDriver != null && result.putniciEta != null) {
          await _startGpsTracking();
        }

        final routeString = optimizedPutnici.take(3).map((p) => p.adresa?.split(',').first ?? p.ime).join(' ? ');

        // ?? Proveri da li ima preskocenih putnika
        final skipped = result.skippedPutnici;
        final hasSkipped = skipped != null && skipped.isNotEmpty;

        if (mounted) {
          AppSnackBar.success(context, '📍 RUTA OPTIMIZOVANA za $_selectedGrad $_selectedVreme!');

          // ? OPTIMIZACIJA 3: Zameni blokirajuci AlertDialog sa Snackbar-om
          // Korisnik vidi notifikaciju ali NIJE BLOKIRAN da nastavi sa akcijama
          if (hasSkipped) {
            // ?? Prika�i preskocene putnike kao SNACKBAR umesto DIALOG-a
            if (mounted) {
              final skippedNames = skipped.take(5).map((p) => p.ime).join(', ');
              final moreText = skipped.length > 5 ? ' +${skipped.length - 5} jo�' : '';

              AppSnackBar.warning(context, '⚠️ ${skipped.length} putnika BEZ adrese: $skippedNames$moreText');
            }
          }
        }
      } else {
        // ? OSRM/SmartNavigationService nije uspeo - NE koristi fallback, prika�i gre�ku
        if (mounted) {
          setState(() {
            _isOptimizing = false;
            // NE postavljaj _isRouteOptimized = true jer ruta NIJE optimizovana!
          });
          AppSnackBar.error(context, '❌ Optimizacija neuspešna: ${result.message}');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isOptimizing = false;
          _isRouteOptimized = false;
          _isListReordered = false;
        });
        AppSnackBar.error(context, '❌ Greška pri optimizaciji: $e');
      }
    }
  }

  // DUGME ZA GPS TRACKING / OPTIMIZACIJU
  // Prima listu putnika direktno iz glavnog streama - nema duplog streama
  Widget _buildOptimizeButton(List<Putnik> mojiAktivniPutnici) {
    final normFilterTime = GradAdresaValidator.normalizeTime(_selectedVreme);
    final filtriraniPutnici = mojiAktivniPutnici.where((p) {
      final pTime = GradAdresaValidator.normalizeTime(p.polazak);
      if (pTime != normFilterTime) return false;
      if (p.jeOtkazan || p.jeBezPolaska || p.jePokupljen || p.jeOdsustvo) return false;
      if (!TextUtils.isStatusActive(p.status)) return false;
      // 🛡️ Isključi pending putnike (još nisu obrađeni)
      if (p.status?.toLowerCase() == 'pending') return false;
      return true;
    }).toList();

    final bool isDriverValid = _currentDriver != null && VozacCache.isValidIme(_currentDriver);
    final bool canPress = !_isOptimizing && !_isLoading && isDriverValid;

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
            color: baseColor.withOpacity(0.2),
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
      stream: RealtimeGpsService.speedStream,
      builder: (context, speedSnapshot) {
        final speed = speedSnapshot.data ?? 0.0;
        final speedColor = speed >= 90
            ? Colors.red
            : speed >= 60
                ? Colors.orange
                : speed > 0
                    ? Colors.green
                    : Colors.white; // ? Koristi cisto belu, pa cemo je 'uti�ati' sa alpha na pozadini

        return Opacity(
          opacity: 1.0,
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: speedColor.withOpacity(0.2),
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
    final bool isDriverValid = _currentDriver != null && VozacCache.isValidIme(_currentDriver);
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
            color: baseColor.withOpacity(0.2),
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

      // Konvertuj koordinate: Map<Putnik, Position> -> Map<String, Position>
      Map<String, Position>? coordsByName;

      // Izvuci redosled imena putnika
      final putniciRedosled = _optimizedRoute.map((p) => p.ime).toList();

      await DriverLocationService.instance.startTracking(
        vozacId: _currentDriver!,
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
              _navigationStatus = '';
            });
            AppSnackBar.success(context, '✅ Svi putnici pokupljeni! Tracking automatski zaustavljen.');
          }
        },
      );

      if (mounted) {
        setState(() => _isGpsTracking = true);
        AppSnackBar.success(context, '📍 GPS tracking pokrenut! Putnici dobijaju realtime lokaciju.');
      }

      // Pošalji push notifikacije putnicima - vozač krenuo + ETA
      _sendVozacKrenulNotifikacije();
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, '❌ Greška pri pokretanju GPS trackinga: $e');
      }
    }
  }

  // ZAUSTAVI GPS TRACKING
  Future<void> _stopGpsTracking() async {
    await DriverLocationService.instance.stopTracking();

    if (mounted) {
      setState(() {
        _isGpsTracking = false;
        _navigationStatus = '';
      });
      AppSnackBar.warning(context, '📍 GPS tracking zaustavljen');
    }
  }

  /// 📲 Pošalji push notifikacije putnicima kada vozač startuje rutu
  Future<void> _sendVozacKrenulNotifikacije() async {
    if (_optimizedRoute.isEmpty || _currentDriver == null) return;

    for (final putnik in _optimizedRoute) {
      final putnikId = putnik.id?.toString();
      if (putnikId == null) continue;

      // Ako putnik nema ID ili je već pokupljen/otkazan, preskoči
      if (putnik.jePokupljen || putnik.jeOtkazan || putnik.jeOdsustvo || putnik.jeBezPolaska) continue;

      // ETA za ovog putnika (po imenu)
      final etaMinuta = _putniciEta?[putnik.ime];
      final etaTekst = etaMinuta != null ? 'Dolazak za oko $etaMinuta min.' : 'Vozač je krenuo po vas!';

      await RealtimeNotificationService.sendNotificationToPutnik(
        putnikId: putnikId,
        title: '🚌 $_currentDriver kreće!',
        body: etaTekst,
        data: {
          'type': 'vozac_krenuo',
          'vozac': _currentDriver!,
          'eta_minuta': etaMinuta?.toString() ?? '',
          'grad': _selectedGrad,
          'vreme': _selectedVreme,
        },
      );
    }
  }

  // ??? OTVORI HERE WeGo NAVIGACIJU SA OPTIMIZOVANIM REDOSLEDOM
  Future<void> _openHereWeGoNavigation() async {
    if (!_isRouteOptimized || _optimizedRoute.isEmpty) return;

    try {
      final result = await SmartNavigationService.startMultiProviderNavigation(
        context: context,
        putnici: _optimizedRoute,
        startCity: _selectedGrad.isNotEmpty ? _selectedGrad : 'Vrsac',
      );

      if (result.success) {
        if (mounted) {
          AppSnackBar.success(context, '🗺️ ${result.message}');
        }
      } else {
        if (mounted) {
          AppSnackBar.error(context, '❌ ${result.message}');
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, '❌ Greška pri otvaranju navigacije: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ?? KORISTI RADNI DATUM (Vikendom prebacuje na ponedeljak)
    final workingDateIso = _getWorkingDateIso();
    final parts = workingDateIso.split('-');
    final today =
        parts.length == 3 ? DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2])) : DateTime.now();

    final dayStart = DateTime(today.year, today.month, today.day);
    final dayEnd = DateTime(today.year, today.month, today.day, 23, 59, 59);

    return Container(
      decoration: BoxDecoration(
        gradient: ThemeManager().currentGradient, // ?? Theme-aware gradijent
      ),
      child: Scaffold(
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
                      Expanded(child: _buildOptimizeButton(_mojiPutnici)),
                      const SizedBox(width: 4),
                      // 🗺️ NAV DUGME
                      Expanded(child: _buildMapsButton()),
                      const SizedBox(width: 4),

                      // 🏎️ BRZINOMER
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
        body: _currentDriver == null
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : StreamBuilder<List<Putnik>>(
                stream: _putnikService.streamKombinovaniPutniciFiltered(
                  isoDate: _getWorkingDateIso(),
                  // ? BEZ FILTERA - filtriraj client-side
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Column(
                      children: [
                        ShimmerWidgets.vozacHeaderShimmer(context),
                        const SizedBox(height: 8),
                        ShimmerWidgets.statistikaShimmer(context),
                        Expanded(child: ShimmerWidgets.putnikListShimmer(itemCount: 5)),
                      ],
                    );
                  }

                  // ?? FILTER: Prikaži putnike koji su direktno dodeljeni ILI putnike koji pripadaju dodeljenom terminu
                  final sviPutnici = snapshot.data ?? [];
                  final targetDayAbbr = _isoDateToDayAbbr(_getWorkingDateIso());
                  final mojiPutnici = sviPutnici.where((p) {
                    // 1. Direktno dodeljen ovom vozaču
                    if (p.dodeljenVozac == _currentDriver) return true;

                    // 2. Ako nije dodeljen drugom vozaču, proveri da li mu termin (vreme/grad) pripada globalno
                    bool isAssignedToOther = p.dodeljenVozac != null &&
                        p.dodeljenVozac != 'Nedodeljen' &&
                        p.dodeljenVozac!.isNotEmpty &&
                        p.dodeljenVozac != _currentDriver;

                    if (!isAssignedToOther) {
                      final pGradCanonical = GradAdresaValidator.isVrsac(p.grad) ? 'Vrsac' : 'Bela Crkva';
                      final globalniVozac = VremeVozacService().getVozacZaVremeSync(
                        pGradCanonical,
                        p.polazak,
                        targetDayAbbr,
                      );
                      return globalniVozac == _currentDriver;
                    }

                    return false;
                  }).toList();

                  // Cache za Start dugme (izvan StreamBuilder konteksta)
                  // Koristimo ID listu za poređenje da sprečimo beskonačni rebuild
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    final noviIds = mojiPutnici.map((p) => p.id).toList();
                    final stariIds = _mojiPutnici.map((p) => p.id).toList();
                    if (noviIds.length != stariIds.length || !noviIds.every((id) => stariIds.contains(id))) {
                      setState(() => _mojiPutnici = mojiPutnici);
                    }
                  });
                  final filteredByGradVreme = mojiPutnici.where((p) {
                    // Filter po gradu
                    final gradMatch =
                        _selectedGrad.isEmpty || GradAdresaValidator.isGradMatch(p.grad, p.adresa, _selectedGrad);

                    // Filter po vremenu
                    final vremeMatch = _selectedVreme.isEmpty ||
                        GradAdresaValidator.normalizeTime(p.polazak) ==
                            GradAdresaValidator.normalizeTime(_selectedVreme);

                    // 🛡️ Predlog 3: Sakrij putnike na čekanju (pending)
                    final isPending = p.status?.toLowerCase() == 'pending';

                    return gradMatch && vremeMatch && !isPending;
                  }).toList();

                  // ?? FIX: Uvek koristi `filteredByGradVreme` kao izvor istine (iz streama)
                  // Ako je ruta optimizovana, sortiraj po redosledu iz `_optimizedRoute`
                  List<Putnik> putnici = filteredByGradVreme;

                  if (_isRouteOptimized && _optimizedRoute.isNotEmpty) {
                    // Sortiraj filteredByGradVreme prema redosledu u _optimizedRoute
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

                  return Column(
                    children: [
                      // KOCKE - Pazar, Dugovi
                      _buildStatsRow(sviPutnici, mojiPutnici),
                      // Lista putnika - koristi PutnikList sa stream-om kao DanasScreen
                      Expanded(
                        child: putnici.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.inbox,
                                      size: 64,
                                      color: Colors.white.withOpacity(0.5),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Nema putnika za izabrani polazak',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 16,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              )
                            : PutnikList(
                                putnici: putnici,
                                useProvidedOrder: _isListReordered,
                                currentDriver:
                                    _currentDriver!, // ? FIX: Koristi dinamicki _currentDriver umesto hardkodovanog _vozacIme
                                selectedGrad: _selectedGrad,
                                selectedVreme: _selectedVreme,
                                selectedDay: _isoDateToDayAbbr(_getWorkingDateIso()),
                                onPutnikStatusChanged: _reoptimizeAfterStatusChange,
                                bcVremena: _bcVremena,
                                vsVremena: _vsVremena,
                              ),
                      ),
                    ],
                  );
                },
              ),
        // ?? BOTTOM NAV BAR
        bottomNavigationBar: StreamBuilder<List<Putnik>>(
          stream: _putnikService.streamKombinovaniPutniciFiltered(
            isoDate: _getWorkingDateIso(),
          ),
          builder: (context, snapshot) {
            final allPutnici = snapshot.data ?? <Putnik>[];

            // ?? FILTER: Svi putnici koje je admin dodelio ovom vozacu za izabrani dan
            final mojiPutnici = allPutnici.where((p) {
              return p.dodeljenVozac == _currentDriver;
            }).toList();

            // ?? REFAKTORISANO: Koristi PutnikCountHelper za centralizovano brojanje
            final targetDateIso = _getWorkingDateIso();
            final targetDayAbbr = _isoDateToDayAbbr(targetDateIso);
            final countHelper = PutnikCountHelper.fromPutnici(
              putnici: mojiPutnici,
              targetDateIso: targetDateIso,
              targetDayAbbr: targetDayAbbr,
            );

            int getPutnikCount(String grad, String vreme) {
              return countHelper.getCount(grad, vreme);
            }

            // ?? KAPACITET: Broj mesta za svaki polazak (real-time od admina)
            int getKapacitet(String grad, String vreme) {
              return KapacitetService.getKapacitetSync(grad, vreme);
            }

            // ?? FILTER VREMENA: Samo dodeljena vremena za ovog vozača
            final dodeljenaVremena = _getDodeljenaVremena(sviPutnici: allPutnici);
            final assignedBcTimes =
                dodeljenaVremena.where((v) => v['grad'] == 'Bela Crkva').map((v) => v['vreme']!).toList();
            final assignedVsTimes =
                dodeljenaVremena.where((v) => v['grad'] == 'Vrsac').map((v) => v['vreme']!).toList();

            // Prikaži samo dodeljena vremena
            final bcVremenaToShow = assignedBcTimes.toList()..sort();
            final vsVremenaToShow = assignedVsTimes.toList()..sort();

            // 🚫 SAKRIJ CEO BOTTOM BAR AKO NEMA VOŽNJI
            if (bcVremenaToShow.isEmpty && vsVremenaToShow.isEmpty) {
              return const SizedBox.shrink();
            }

            // Helper funkcija za kreiranje nav bar-a
            Widget buildNavBar(String navType) {
              switch (navType) {
                case 'praznici':
                  return BottomNavBarPraznici(
                    sviPolasci: _sviPolasci,
                    selectedGrad: _selectedGrad,
                    selectedVreme: _selectedVreme,
                    getPutnikCount: getPutnikCount,
                    getKapacitet: getKapacitet,
                    onPolazakChanged: _onPolazakChanged,
                  );
                case 'zimski':
                  return BottomNavBarZimski(
                    sviPolasci: _sviPolasci,
                    selectedGrad: _selectedGrad,
                    selectedVreme: _selectedVreme,
                    getPutnikCount: getPutnikCount,
                    getKapacitet: getKapacitet,
                    onPolazakChanged: _onPolazakChanged,
                    bcVremena: bcVremenaToShow,
                    vsVremena: vsVremenaToShow,
                  );
                default: // 'letnji' ili nepoznato
                  return BottomNavBarLetnji(
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

            return ValueListenableBuilder<String>(
              valueListenable: navBarTypeNotifier,
              builder: (context, navType, _) => buildNavBar(navType),
            );
          },
        ),
      ),
    );
  }

  // 🕒 Digitalni datum display
  Widget _buildDigitalDateDisplay() {
    final workingDateIso = _getWorkingDateIso();
    final parts = workingDateIso.split('-');
    final now =
        parts.length == 3 ? DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2])) : DateTime.now();

    final dayNames = ['PONEDELJAK', 'UTORAK', 'SREDA', 'ČETVRTAK', 'PETAK', 'SUBOTA', 'NEDELJA'];
    final dayName = dayNames[now.weekday - 1];
    final dayStr = now.day.toString().padLeft(2, '0');
    final monthStr = now.month.toString().padLeft(2, '0');
    final yearStr = now.year.toString().substring(2);

    // ?? Izracunaj boju za dan (ako smo u admin preview modu)
    final isPreview = widget.previewAsDriver != null && widget.previewAsDriver!.isNotEmpty;
    final driverColor =
        isPreview ? VozacCache.getColor(widget.previewAsDriver!) : Theme.of(context).colorScheme.onPrimary;

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
        ClockTicker(
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
          color: color.withOpacity(0.2),
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
        color: color.withOpacity(0.2),
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
  Widget _buildStatsRow(List<Putnik> sviPutnici, List<Putnik> mojiPutnici) {
    final dayStart = DateTime.parse('${_getWorkingDateIso()}T00:00:00');
    final dayEnd = DateTime.parse('${_getWorkingDateIso()}T23:59:59');

    final filteredDuzniciRaw = sviPutnici.where((putnik) {
      final nijeMesecni = !putnik.isMesecniTip;
      if (!nijeMesecni) return false;
      final nijePlatio = putnik.placeno != true; // ✅ FIX: Koristi placeno flag iz voznje_log
      final nijeOtkazan = !putnik.jeOtkazan && !putnik.jeBezPolaska;
      final pokupljen = putnik.jePokupljen;
      return nijePlatio && nijeOtkazan && pokupljen;
    }).toList();

    final seenIds = <dynamic>{};
    final filteredDuznici = filteredDuzniciRaw.where((p) {
      final key = p.id ?? '${p.ime}_${p.dan}';
      if (seenIds.contains(key)) return false;
      seenIds.add(key);
      return true;
    }).toList();

    // 🔄 NOVI JEDNOSTAVAN BROJAČ POVRATAKA
    // Grupišemo sve polaske po putniku (ID) da vidimo ko ima BC, a ko ima i VS
    final Map<dynamic, Set<String>> putnikSmerovi = {};

    for (var p in sviPutnici) {
      // ISKLJUCUJEMO: otkazano, bez_polaska, odsustvo, obrisan, posiljke
      if (p.jeOtkazan || p.jeBezPolaska || p.jeOdsustvo || p.obrisan) continue;
      if (p.tipPutnika == 'posiljka') continue;

      // SAMO UCENICI za kocku Povratak
      if (p.tipPutnika != 'ucenik') continue;

      // DODATNA PROVERA: eksplicitno preskoci 'otkazano', 'cancelled', 'bez_polaska' status
      final statusLower = p.status?.toLowerCase() ?? '';
      if (statusLower == 'otkazano' || statusLower == 'cancelled' || statusLower == 'bez_polaska') continue;

      final id = p.id;
      if (id == null) continue;

      putnikSmerovi.putIfAbsent(id, () => <String>{});

      final gradLower = p.grad.toLowerCase();
      if (gradLower.contains('bela crkva') || gradLower == 'bc') {
        putnikSmerovi[id]!.add('bc');
      } else if (gradLower.contains('vrsac') || gradLower == 'vs') {
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
        if (p.id != id) return; // putnik nije pronađen, preskoči
        final grad = smerovi.contains('bc') ? 'BC' : 'VS';
        samoJedanSmerImena.add('${p.ime} ($grad)');
      }
    });

    return Container(
      margin: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: StreamBuilder<double>(
              stream: StatistikaService.streamPazarZaVozaca(
                vozac: _currentDriver!,
                from: dayStart,
                to: dayEnd,
              ),
              builder: (context, snapshot) {
                final pazar = snapshot.data ?? 0.0;
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
                    builder: (context) => DugoviScreen(currentDriver: _currentDriver!),
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
          // 🔄 KOCKA ZA POVRATAK
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

  // 📊 POPUP ZA AUTOMATIZOVANI POPIS (21:00)
  void _showAutomatedPopisPopup(Map<String, dynamic> stats) {
    showDialog(
      context: context,
      barrierDismissible: false, // Mora da klikne Zatvori
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1A237E).withOpacity(0.9), // Tamno plava
                Colors.black.withOpacity(0.95),
              ],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.blueAccent.withOpacity(0.5), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.blueAccent.withOpacity(0.2),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.analytics_outlined, color: Colors.blueAccent, size: 48),
              const SizedBox(height: 12),
              const Text(
                'DNEVNI POPIS',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
              const Text(
                'Automatski izveštaj (21:00h)',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 20),
              _buildPopisItem('Dodati putnici', '${stats['dodati_putnici'] ?? 0}', Colors.greenAccent),
              _buildPopisItem('Otkazani putnici', '${stats['otkazani_putnici'] ?? 0}', Colors.redAccent),
              _buildPopisItem('Pokupljeni putnici', '${stats['pokupljeni_putnici'] ?? 0}', Colors.blueAccent),
              _buildPopisItem('Pošiljke', '${stats['broj_posiljki'] ?? 0}', Colors.orangeAccent),
              const Divider(color: Colors.white12, height: 24),
              _buildPopisItem('Naplaćeni dnevni', '${stats['naplaceni_dnevni'] ?? 0} RSD', Colors.white),
              _buildPopisItem('Naplaćeni mesečni', '${stats['naplaceni_mesecni'] ?? 0} RSD', Colors.white),
              _buildPopisItem('Broj dužnika', '${stats['broj_duznika'] ?? 0}',
                  stats['broj_duznika'] != 0 ? Colors.red : Colors.white70),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'UKUPNO:',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    Text(
                      '${stats['ukupan_pazar'] ?? 0} RSD',
                      style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w900, fontSize: 20),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.1),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Colors.white24),
                    ),
                  ),
                  child: const Text('ZATVORI', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPopisItem(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ],
      ),
    );
  }

  // 📊 POPUP ZA PRIKAZ POVRATKA SA SPISKOM
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
                color.withOpacity(0.4),
                Colors.black.withOpacity(0.8),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color.withOpacity(0.5), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
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
                          'Svi putnici imaju oba smera! 🎉',
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
                  backgroundColor: color.withOpacity(0.3),
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

  // 📊 POPUP ZA PRIKAZ STATISTIKE
  void _showStatPopup(BuildContext context, String label, String value, Color color) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.25),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _getBorderColor(color)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
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
    return color.withOpacity(0.6);
  }
}
