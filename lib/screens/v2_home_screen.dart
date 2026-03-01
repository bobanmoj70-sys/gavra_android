import 'dart:async';

import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../config/v2_route_config.dart';
import '../constants/v2_day_constants.dart';
import '../globals.dart';
import '../models/v2_putnik.dart';
import '../models/v2_registrovani_putnik.dart';
import '../services/realtime/v2_master_realtime_manager.dart';
import '../services/v2_admin_security_service.dart';
import '../services/v2_adresa_supabase_service.dart';
import '../services/v2_app_settings_service.dart'; // ?? Update check
import '../services/v2_auth_manager.dart';
import '../services/v2_cena_obracun_service.dart';
import '../services/v2_firebase_service.dart';
import '../services/v2_haptic_service.dart';
import '../services/v2_kapacitet_service.dart'; // ?? Kapacitet za bottom nav bar
import '../services/v2_local_notification_service.dart';
import '../services/v2_polasci_service.dart';
import '../services/v2_printing_service.dart';
import '../services/v2_putnik_service.dart';
import '../services/v2_putnik_stream_service.dart';
import '../services/v2_racun_service.dart';
import '../services/v2_realtime_notification_service.dart';
import '../services/v2_slobodna_mesta_service.dart'; // ?? Provera kapaciteta
import '../services/v2_theme_manager.dart'; // ?? Tema sistem
import '../services/v2_vozac_raspored_service.dart';
import '../theme.dart'; // ?? Import za prelepe gradijente
import '../utils/v2_app_snack_bar.dart';
import '../utils/v2_date_utils.dart' as app_date_utils;
import '../utils/v2_grad_adresa_validator.dart'; // ??? NOVO za validaciju
import '../utils/v2_page_transitions.dart';
import '../utils/v2_putnik_count_helper.dart'; // ?? Za brojanje putnika po gradu
import '../utils/v2_text_utils.dart';
import '../utils/v2_vozac_cache.dart'; // Dodato za centralizovane boje vozaca
import '../widgets/v2_bottom_nav_bar_letnji.dart';
import '../widgets/v2_bottom_nav_bar_praznici.dart';
import '../widgets/v2_bottom_nav_bar_zimski.dart';
import '../widgets/v2_putnik_list.dart';
import '../widgets/v2_registracija_countdown_widget.dart';
import '../widgets/v2_shimmer_widgets.dart';
import 'v2_admin_screen.dart';
import 'v2_polasci_screen.dart';
import 'v2_promena_sifre_screen.dart';
import 'v2_vozac_screen.dart';
import 'v2_welcome_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // Logging using dlog function from logging.dart
  final V2PutnikStreamService _putnikService = V2PutnikStreamService();

  bool _isLoading = true;
  // bool _isAddingPutnik = false; // previously used loading state; now handled local to dialog
  String _selectedDay = 'Ponedeljak'; // Bice postavljeno na današnji dan u initState
  String _selectedGrad = 'BC';
  String _selectedVreme = '05:00'; // inicijalna vrednost, overriduje se u initState

  // Key and overlay entry for custom days dropdown
  // (removed overlay support for now) - will use DropdownButton2 built-in overlay

  String? _currentDriver;

  // Real-time subscription variables
  StreamSubscription<dynamic>? _realtimeSubscription;
  StreamSubscription<dynamic>? _networkStatusSubscription;
  Timer? _dispecerTimer; // ?? Tajmer za digitalnog dispecera

  final List<String> _dani = DayConstants.dayNamesInternal; // Svi dani (Pon-Ned)

  // ?? DINAMICKA VREMENA - prate navBarTypeNotifier (praznici/zimski/letnji)
  List<String> get bcVremena {
    final navType = navBarTypeNotifier.value;
    if (navType == 'praznici') {
      return RouteConfig.bcVremenaPraznici;
    } else if (navType == 'zimski') {
      return RouteConfig.bcVremenaZimski;
    } else {
      return RouteConfig.bcVremenaLetnji;
    }
  }

  List<String> get vsVremena {
    final navType = navBarTypeNotifier.value;
    if (navType == 'praznici') {
      return RouteConfig.vsVremenaPraznici;
    } else if (navType == 'zimski') {
      return RouteConfig.vsVremenaZimski;
    } else {
      return RouteConfig.vsVremenaLetnji;
    }
  }

  // ?? DINAMICKA LISTA POLAZAKA za BottomNavBar
  List<String> get _sviPolasci {
    final bcList = bcVremena.map((v) => '$v BC').toList();
    final vsList = vsVremena.map((v) => '$v VS').toList();
    return [...bcList, ...vsList];
  }

  /// Automatski selektuje najbliže vreme polaska za trenutni cas (BC grad).
  void _autoSelectNajblizeVreme() {
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final list = bcVremena;
    String? najblize;
    for (final v in list) {
      final parts = v.split(':');
      if (parts.length < 2) continue;
      final vMin = (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
      if (vMin >= nowMinutes) {
        najblize = v;
        break;
      }
    }
    najblize ??= list.isNotEmpty ? list.last : '05:00';
    _selectedGrad = 'BC';
    _selectedVreme = najblize;
  }

  // ? KORISTI UTILS FUNKCIJU ZA DROPDOWN DAN
  String _getTodayName() {
    return app_date_utils.DateUtils.getTodayFullName();
  }

  // target date calculation handled elsewhere

  // Convert selected full day name (Ponedeljak) into ISO date string for target week
  // ?? FIX: Uvek idi u buducnost - ako je dan prošao ove nedelje, koristi sledecu nedelju
  // Ovo je konzistentno sa V2Putnik._getDateForDay() koji se koristi za upis u bazu
  String _getTargetDateIsoFromSelectedDay(String fullDay) {
    final now = DateTime.now();

    // Normalizuj dan korišćenjem DayConstants
    final normalizedDay = DayConstants.normalize(fullDay);
    final targetDayIndex = DayConstants.getIndexByName(normalizedDay);

    final currentDayIndex = now.weekday - 1;

    // ?? FIX: Ako je odabrani dan isto što i današnji dan, koristi današnji datum
    if (targetDayIndex == currentDayIndex) {
      return now.toIso8601String().split('T')[0];
    }

    int daysToAdd = targetDayIndex - currentDayIndex;

    // ?? UVEK U BUDUCNOST: Ako je dan vec prošao ove nedelje, idi na sledecu nedelju
    // Ovo je konzistentno sa V2Putnik._getDateForDay() koji se koristi za upis u bazu
    if (daysToAdd < 0) {
      daysToAdd += 7;
    }

    final targetDate = now.add(Duration(days: daysToAdd));
    return targetDate.toIso8601String().split('T')[0];
  }

  // Konvertuj pun naziv dana u kraticu za poredenje sa bazom
  // ? KORISTI CENTRALNU FUNKCIJU IZ DateUtils
  String _getDayAbbreviation(String fullDayName) {
    return app_date_utils.DateUtils.getDayAbbreviation(fullDayName);
  }

  @override
  void initState() {
    super.initState();
    _selectedDay = _getTodayName();
    _autoSelectNajblizeVreme();
    _initializeData();
    _setupRealtimeMonitoring(); // ?? Popravljeno ime metode
    _startDigitalDispecer(); // ?? Pokreni dispecera

    // ?? Slušaj update notifikacije i prikaži dijalog
    updateInfoNotifier.addListener(_onUpdateInfo);
    // Provjeri odmah ako je update vec detektovan
    WidgetsBinding.instance.addPostFrameCallback((_) => _onUpdateInfo());
  }

  /// ?? POKRECE DIGITALNOG DISPECERA
  /// Svakih 5 minuta proverava bazu i "cisti" stare zahteve
  void _startDigitalDispecer() {
    // 1. Odmah okini jednu proveru
    V2PolasciService.v2PokreniDispecera();

    // 2. Postavi periodicnu proveru
    _dispecerTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (mounted) {
        V2PolasciService.v2PokreniDispecera();
      }
    });
  }

  void _initializeData() async {
    try {
      await _initializeCurrentDriver();
      // ?? If the current driver is missing or invalid, redirect to welcome/login
      if (_currentDriver == null || !VozacCache.isValidIme(_currentDriver)) {
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute<void>(builder: (context) => const WelcomeScreen()),
            (route) => false,
          );
        }
        return;
      }

      // ?? Setup realtime monitoring
      _setupRealtimeMonitoring();
      // StreamBuilder ce automatski ucitati data - ne treba eksplicitno _loadPutnici()
      _setupRealtimeListener();

      // Inicijalizuj lokalne notifikacije za heads-up i zvuk
      if (mounted) {
        LocalNotificationService.initialize(context);
        // ?? UKLONJENO: listener se sada registruje globalno u main.dart
        // RealtimeNotificationService.listenForForegroundNotifications(context);
      }

      // ?? Auto-update removed per request

      // Inicijalizuj realtime notifikacije za aktivnog vozaca
      FirebaseService.getCurrentDriver().then((driver) {
        if (driver != null && driver.isNotEmpty) {
          // First request notification permissions
          RealtimeNotificationService.requestNotificationPermissions().then((hasPermissions) {
            RealtimeNotificationService.initialize().then((_) {
              // Subscribe to Firebase topics for this driver
              RealtimeNotificationService.subscribeToDriverTopics(driver);
            });
          });
        }
      });

      // ?? KONACNO UKLONI LOADING STATE
      if (mounted) {
        _selectClosestDeparture();
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      // Ako se dogodi greška, i dalje ukloni loading
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _initializeCurrentDriver() async {
    final driver = await FirebaseService.getCurrentDriver();

    if (mounted) {
      setState(() {
        // Inicijalizacija driver-a
        _currentDriver = driver;
      });
    }
  }

  // ?? Setup realtime monitoring system
  void _setupRealtimeMonitoring() {
    try {
      // No additional monitoring needed
    } catch (e) {
      // Silently ignore timer errors
    }
  }

  void _setupRealtimeListener() {
    // UKLONJEN - PutnikService vec ima realtime listener-e
    // Ne treba dupli listener koji ništa ne radi
    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
  }

  /// ?? Bira polazak koji je najbliži trenutnom vremenu
  void _selectClosestDeparture() {
    if (!mounted) return;

    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    String? closestVreme;
    String? closestGrad;
    int minDifference = 9999;

    final allDepartures = _sviPolasci;
    if (allDepartures.isEmpty) return;

    for (final polazak in allDepartures) {
      final parts = polazak.split(' ');
      if (parts.length < 2) continue;

      final timeStr = parts[0];
      final gradStr = parts.sublist(1).join(' ');

      final timeParts = timeStr.split(':');
      if (timeParts.length != 2) continue;

      final hour = int.tryParse(timeParts[0]) ?? 0;
      final minute = int.tryParse(timeParts[1]) ?? 0;
      final polazakMinutes = hour * 60 + minute;

      // Izracunaj apsolutnu razliku u minutima
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

  Widget _buildGlassStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Prikazuje dijalog sa listom putnika kojima treba racun
  Future<void> _showRacunDialog(BuildContext ctx) async {
    // Sacuvaj reference pre await
    final scaffoldMessenger = ScaffoldMessenger.of(ctx);

    // Ucitaj putnike kojima treba racun
    final sviPutnici = await V2PutnikService().getAllAktivniKaoModel();
    final putnici = sviPutnici.where((p) => p.trebaRacun).toList();

    if (!mounted) return;

    if (putnici.isEmpty) {
      AppSnackBar.warning(context, 'Nema putnika kojima treba racun');
      return;
    }

    // ?? AUTOMATSKI OBRACUN (Inicijalno za tekuci mesec)
    DateTime selectedDate = DateTime.now();
    Map<String, int> counts = await CenaObracunService.prebrojJediniceMasovno(
      putnici: putnici,
      mesec: selectedDate.month,
      godina: selectedDate.year,
    );

    if (!mounted) return;

    // Map za pracenje selektovanih putnika
    final Map<String, bool> selected = {for (var p in putnici) p.id: true};

    // Map za broj dana (sada koristi stvarne podatke iz baze)
    final Map<String, int> brojDana = {for (var p in putnici) p.id: counts[p.id] ?? 0};

    // Map za TextEditingController-e
    final Map<String, TextEditingController> danaControllers = {
      for (var p in putnici) p.id: TextEditingController(text: (counts[p.id] ?? 0).toString())
    };

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Funkcija za osvežavanje podataka kada se promeni mesec
          Future<void> osveziPodatke() async {
            final noviCounts = await CenaObracunService.prebrojJediniceMasovno(
              putnici: putnici,
              mesec: selectedDate.month,
              godina: selectedDate.year,
            );
            if (context.mounted) {
              setDialogState(() {
                counts = noviCounts;
                for (var p in putnici) {
                  brojDana[p.id] = counts[p.id] ?? 0;
                  danaControllers[p.id]?.text = (counts[p.id] ?? 0).toString();
                }
              });
            }
          }

          double ukupno = 0;
          for (var p in putnici) {
            if (selected[p.id] == true) {
              final cena = CenaObracunService.getCenaPoDanu(p);
              ukupno += cena * (brojDana[p.id] ?? 0);
            }
          }

          final mesecGodinaStr = DateFormat('MMMM yyyy', 'sr_Latn').format(selectedDate);

          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
                maxWidth: MediaQuery.of(context).size.width * 0.9,
              ),
              decoration: BoxDecoration(
                gradient: Theme.of(context).backgroundGradient,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Theme.of(context).glassBorder,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 15,
                    spreadRadius: 2,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).glassContainer,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).glassBorder,
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.receipt_long, color: Colors.white),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Racuni za štampanje',
                                style: const TextStyle(
                                  fontSize: 20,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Kontrola meseca
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.chevron_left, color: Colors.white),
                              onPressed: () {
                                setDialogState(() {
                                  selectedDate = DateTime(selectedDate.year, selectedDate.month - 1);
                                });
                                osveziPodatke();
                              },
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                mesecGodinaStr,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.chevron_right, color: Colors.white),
                              onPressed: () {
                                setDialogState(() {
                                  selectedDate = DateTime(selectedDate.year, selectedDate.month + 1);
                                });
                                osveziPodatke();
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Lista putnika
                          ...putnici.map((p) {
                            final cena = CenaObracunService.getCenaPoDanu(p);
                            final dana = brojDana[p.id] ?? 0;
                            final iznos = cena * dana;

                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.3),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withOpacity(0.1),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                child: Row(
                                  children: [
                                    // Checkbox
                                    Checkbox(
                                      value: selected[p.id],
                                      activeColor: Colors.white,
                                      checkColor: Theme.of(context).colorScheme.primary,
                                      side: BorderSide(color: Colors.white70),
                                      onChanged: (val) {
                                        setDialogState(() {
                                          selected[p.id] = val ?? false;
                                        });
                                      },
                                    ),
                                    // Ime i detalji - fleksibilno
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p.ime,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              color: Colors.white,
                                              shadows: [
                                                Shadow(
                                                  offset: const Offset(1, 1),
                                                  blurRadius: 2,
                                                  color: Colors.black.withOpacity(0.5),
                                                ),
                                                Shadow(
                                                  offset: const Offset(-0.5, -0.5),
                                                  blurRadius: 1,
                                                  color: Colors.white.withOpacity(0.3),
                                                ),
                                              ],
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            '${cena.toStringAsFixed(0)} RSD ž $dana dana = ${iznos.toStringAsFixed(0)} RSD',
                                            style: TextStyle(fontSize: 11, color: Colors.white70),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Dana input - fiksna širina
                                    SizedBox(
                                      width: 55,
                                      child: Column(
                                        children: [
                                          Text('Dana', style: TextStyle(fontSize: 10, color: Colors.white70)),
                                          TextField(
                                            keyboardType: TextInputType.number,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                                            decoration: InputDecoration(
                                              isDense: true,
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                                              border:
                                                  UnderlineInputBorder(borderSide: BorderSide(color: Colors.white70)),
                                              enabledBorder:
                                                  UnderlineInputBorder(borderSide: BorderSide(color: Colors.white70)),
                                              focusedBorder:
                                                  UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                                            ),
                                            controller: danaControllers[p.id],
                                            onChanged: (val) {
                                              setDialogState(() {
                                                brojDana[p.id] = int.tryParse(val) ?? 0;
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          const Divider(color: Colors.white30),
                          // Ukupno
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('UKUPNO:',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                              Text(
                                '${ukupno.toStringAsFixed(0)} RSD',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.greenAccent),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Actions
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).glassContainer,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: Text('Otkaži', style: TextStyle(color: Colors.white70)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.print),
                          label: const Text('štampaj sve'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.2),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () async {
                            Navigator.pop(dialogContext);

                            final List<Map<String, dynamic>> racuniPodaci = [];
                            for (var p in putnici) {
                              if (selected[p.id] == true) {
                                final cena = CenaObracunService.getCenaPoDanu(p);
                                final dana = brojDana[p.id] ?? 0;
                                racuniPodaci.add({
                                  'V2Putnik': p,
                                  'brojDana': dana,
                                  'cenaPoDanu': cena,
                                  'ukupno': cena * dana,
                                });
                              }
                            }

                            if (racuniPodaci.isEmpty) {
                              AppSnackBar.warning(context, 'Izaberite bar jednog putnika');
                              return;
                            }

                            await V2RacunService.stampajRacuneZaFirme(
                              racuniPodaci: racuniPodaci,
                              context: context,
                              datumPrometa: selectedDate,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showNoviRacunDialog(BuildContext context) {
    final imeController = TextEditingController();
    final iznosController = TextEditingController();
    final opisController = TextEditingController(text: 'Usluga prevoza putnika');
    String jedinicaMere = 'usluga';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.receipt_long, color: Colors.orange),
                SizedBox(width: 8),
                Text('Novi racun'),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: imeController,
                      decoration: const InputDecoration(
                        labelText: 'Ime i prezime kupca *',
                        hintText: 'npr. Marko Markovic',
                        prefixIcon: Icon(Icons.person),
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: opisController,
                      decoration: const InputDecoration(
                        labelText: 'Opis usluge *',
                        hintText: 'npr. Prevoz Beograd-Vrsac',
                        prefixIcon: Icon(Icons.description),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: jedinicaMere.isNotEmpty ? jedinicaMere : null,
                      decoration: const InputDecoration(
                        labelText: 'Jedinica mere',
                        prefixIcon: Icon(Icons.straighten),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'usluga', child: Text('usluga')),
                        DropdownMenuItem(value: 'dan', child: Text('dan')),
                        DropdownMenuItem(value: 'kom', child: Text('kom')),
                        DropdownMenuItem(value: 'sat', child: Text('sat')),
                        DropdownMenuItem(value: 'km', child: Text('km')),
                      ],
                      onChanged: (val) {
                        setDialogState(() {
                          jedinicaMere = val ?? 'usluga';
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: iznosController,
                      decoration: const InputDecoration(
                        labelText: 'Iznos (RSD) *',
                        hintText: 'npr. 5000',
                        prefixIcon: Icon(Icons.attach_money),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '* Obavezna polja',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Otkaži'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.print),
                label: const Text('štampaj'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: () async {
                  // Validacija
                  if (imeController.text.trim().isEmpty) {
                    AppSnackBar.warning(context, 'Unesite ime kupca');
                    return;
                  }
                  if (opisController.text.trim().isEmpty) {
                    AppSnackBar.warning(context, 'Unesite opis usluge');
                    return;
                  }
                  final iznos = double.tryParse(iznosController.text.trim());
                  if (iznos == null || iznos <= 0) {
                    AppSnackBar.warning(context, 'Unesite validan iznos');
                    return;
                  }

                  // Sacuvaj podatke pre zatvaranja dijaloga
                  final imePrezime = imeController.text.trim();
                  final opis = opisController.text.trim();
                  final jm = jedinicaMere;
                  final ctx = context;

                  Navigator.pop(dialogContext);

                  // Dohvati sledeci broj racuna
                  final brojRacuna = await V2RacunService.getTrenutniBrojRacuna();

                  // Proveri mounted pre korišćenja context-a
                  if (!ctx.mounted) return;

                  // štampaj racun
                  await V2RacunService.stampajRacun(
                    brojRacuna: brojRacuna,
                    imePrezimeKupca: imePrezime,
                    adresaKupca: '', // Fizicko lice bez adrese
                    opisUsluge: opis,
                    cena: iznos,
                    kolicina: 1,
                    jedinicaMere: jm,
                    datumPrometa: DateTime.now(),
                    context: ctx,
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _logout() async {
    // Prikaži confirmation dialog
    final bool? shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(dialogContext).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: Theme.of(dialogContext).colorScheme.dangerPrimary.withOpacity(0.5),
            width: 2,
          ),
        ),
        title: Column(
          children: [
            Icon(
              Icons.logout,
              color: Theme.of(dialogContext).colorScheme.error,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              'Logout',
              style: TextStyle(
                color: Theme.of(dialogContext).colorScheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Da li ste sigurni da se želite odjaviti?',
          style: TextStyle(
            color: Theme.of(dialogContext).colorScheme.onSurface.withOpacity(0.8),
            fontSize: 16,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              'Otkaži',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          HapticElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            hapticType: HapticType.medium,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout == true && mounted) {
      // ?? Prikaži loading spinner
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(ctx).colorScheme.primary,
            ),
          ),
        ),
      );

      // ?? IzVrsi logout
      try {
        await AuthManager.logout(context);
      } catch (e) {
        debugPrint('❌ Logout error: $e');
        // Ako logout fail, pokreni navigaciju rucno
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
            (route) => false,
          );
        }
      }
    }
  }

  void _showAddPutnikDialog() async {
    final adresaController = TextEditingController();
    final telefonController = TextEditingController(); // ?? OPCIONO: Broj telefona
    final searchPutnikController = TextEditingController(); // ?? Za pretragu putnika
    RegistrovaniPutnik? selectedPutnik; // ?? Izabrani V2Putnik iz liste
    int brojMesta = 1; // ?? Broj rezervisanih mesta (default 1)
    bool promeniAdresuSamoDanas = false; // ?? Opcija za promenu adrese samo za danas
    String? samoDanasAdresa; // ?? Adresa samo za danas
    String? samoDanasAdresaId; // ?? ID adrese samo za danas (za brži geocoding)
    List<Map<String, String>> dostupneAdrese = []; // ?? Lista adresa za dropdown

    // Povuci SVE registrovane putnike iz registrovani_putnici tabele (ucenici, radnici, dnevni)
    final lista = await V2PutnikService().getAllAktivniKaoModel();
    // ?? Filtrirana lista aktivnih putnika za brzu pretragu
    final aktivniPutnici = lista.where((RegistrovaniPutnik V2Putnik) => V2Putnik.aktivan).toList()
      ..sort((a, b) => a.ime.toLowerCase().compareTo(b.ime.toLowerCase()));

    // ?? Ucitaj adrese za selektovani grad
    final adreseZaGrad = await V2AdresaSupabaseService.getAdreseZaGrad(_selectedGrad);
    dostupneAdrese = adreseZaGrad.map((a) => {'id': a.id, 'naziv': a.naziv}).toList()
      ..sort((a, b) => (a['naziv'] ?? '').compareTo(b['naziv'] ?? ''));

    if (!mounted) return;

    final rootContext = context; // ?? Cuvamo home screen context pre otvaranja dijaloga
    bool isDialogLoading = false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setStateDialog) {
          // ?? Dinamicki racunaj dostupnu visinu (oduzmi tastatur?)
          final keyboardHeight = MediaQuery.of(dialogCtx).viewInsets.bottom;
          final screenHeight = MediaQuery.of(dialogCtx).size.height;
          final availableHeight = screenHeight - keyboardHeight;

          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 24,
              bottom: keyboardHeight > 0 ? 8 : 24, // Manje padding kad je tastatura
            ),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: keyboardHeight > 0
                    ? availableHeight * 0.85 // Više prostora kad je tastatura
                    : screenHeight * 0.7,
                maxWidth: MediaQuery.of(dialogCtx).size.width * 0.85,
              ),
              decoration: BoxDecoration(
                gradient: Theme.of(dialogCtx).backgroundGradient,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Theme.of(dialogCtx).glassBorder,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 15,
                    spreadRadius: 2,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ?? GLASSMORPHISM HEADER
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(dialogCtx).glassContainer,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(dialogCtx).glassBorder,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Dodaj Putnika',
                            style: TextStyle(
                              fontSize: 22,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(
                                  offset: Offset(1, 1),
                                  blurRadius: 3,
                                  color: Colors.black54,
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Close button
                        GestureDetector(
                          onTap: () => Navigator.pop(dialogCtx),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: Colors.red.withOpacity(0.4),
                              ),
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ?? SCROLLABLE CONTENT
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ?? GLASSMORPHISM INFORMACIJE O RUTI
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Theme.of(dialogCtx).glassContainer,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: Theme.of(dialogCtx).glassBorder,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Informacije o ruti',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: 16,
                                    shadows: [
                                      Shadow(
                                        offset: Offset(1, 1),
                                        blurRadius: 3,
                                        color: Colors.black54,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _buildGlassStatRow('⏰ Vreme:', _selectedVreme),
                                _buildGlassStatRow('📍 Grad:', _selectedGrad),
                                _buildGlassStatRow('📅 Dan:', _selectedDay),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // ?? GLASSMORPHISM PODACI O PUTNIKU
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Theme.of(dialogCtx).glassContainer,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: Theme.of(dialogCtx).glassBorder,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Podaci o putniku',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: 16,
                                    shadows: [
                                      Shadow(
                                        offset: Offset(1, 1),
                                        blurRadius: 3,
                                        color: Colors.black54,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // ?? DROPDOWN ZA IZBOR PUTNIKA IZ LISTE
                                DropdownButtonFormField2<RegistrovaniPutnik>(
                                  isExpanded: true,
                                  value: aktivniPutnici
                                      .cast<RegistrovaniPutnik?>()
                                      .firstWhere((p) => p?.id == selectedPutnik?.id, orElse: () => null),
                                  decoration: InputDecoration(
                                    labelText: 'Izaberi putnika',
                                    hintText: 'Pretraži i izaberi...',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    prefixIcon: Icon(
                                      Icons.person_search,
                                      color: Theme.of(dialogCtx).colorScheme.primary,
                                    ),
                                    fillColor: Colors.white,
                                    filled: true,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                                  ),
                                  dropdownStyleData: DropdownStyleData(
                                    maxHeight: 300,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: Colors.white,
                                    ),
                                  ),
                                  dropdownSearchData: DropdownSearchData(
                                    searchController: searchPutnikController,
                                    searchInnerWidgetHeight: 50,
                                    searchInnerWidget: Container(
                                      height: 50,
                                      padding: const EdgeInsets.only(
                                        top: 8,
                                        bottom: 4,
                                        right: 8,
                                        left: 8,
                                      ),
                                      child: TextFormField(
                                        controller: searchPutnikController,
                                        expands: true,
                                        maxLines: null,
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                          hintText: 'Pretraži po imenu...',
                                          hintStyle: const TextStyle(fontSize: 14),
                                          prefixIcon: const Icon(Icons.search, size: 20),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                      ),
                                    ),
                                    searchMatchFn: (item, searchValue) {
                                      final V2Putnik = item.value;
                                      if (V2Putnik == null) return false;
                                      return V2Putnik.ime.toLowerCase().contains(searchValue.toLowerCase());
                                    },
                                  ),
                                  items: aktivniPutnici
                                      .map(
                                        (RegistrovaniPutnik V2Putnik) => DropdownMenuItem<RegistrovaniPutnik>(
                                          value: V2Putnik,
                                          child: Row(
                                            children: [
                                              // Ikonica tipa putnika
                                              Icon(
                                                V2Putnik.v2Tabela == 'v2_radnici'
                                                    ? Icons.engineering
                                                    : V2Putnik.v2Tabela == 'v2_dnevni'
                                                        ? Icons.today
                                                        : Icons.school,
                                                size: 18,
                                                color: V2Putnik.v2Tabela == 'v2_radnici'
                                                    ? Colors.blue.shade600
                                                    : V2Putnik.v2Tabela == 'v2_dnevni'
                                                        ? Colors.orange.shade600
                                                        : Colors.green.shade600,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  V2Putnik.ime,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (RegistrovaniPutnik? V2Putnik) async {
                                    setStateDialog(() {
                                      selectedPutnik = V2Putnik;
                                      telefonController.text = V2Putnik?.telefon ?? '';
                                      adresaController.text = 'Ucitavanje...';
                                    });
                                    if (V2Putnik != null) {
                                      // ?? AUTO-POPUNI adresu async - SAMO za selektovani grad
                                      final adresa = await V2Putnik.getAdresaZaSelektovaniGrad(_selectedGrad);
                                      setStateDialog(() {
                                        adresaController.text = adresa == 'Nema adresa' ? '' : adresa;
                                        // Ocisti "samo danas" opcije kad se promeni V2Putnik
                                        promeniAdresuSamoDanas = false;
                                        samoDanasAdresa = null;
                                        samoDanasAdresaId = null;
                                      });
                                    }
                                  },
                                ),
                                const SizedBox(height: 12),

                                // ADRESA FIELD (readonly - popunjava se automatski)
                                TextField(
                                  controller: adresaController,
                                  readOnly: true,
                                  decoration: InputDecoration(
                                    labelText: promeniAdresuSamoDanas ? 'Stalna adresa' : 'Adresa',
                                    hintText: 'Automatski se popunjava...',
                                    prefixIcon: const Icon(Icons.location_on),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    filled: true,
                                    fillColor: Colors.grey.shade100,
                                  ),
                                ),

                                // ?? OPCIJA ZA PROMENU ADRESE SAMO ZA DANAS
                                const SizedBox(height: 8),
                                InkWell(
                                  onTap: () {
                                    setStateDialog(() {
                                      promeniAdresuSamoDanas = !promeniAdresuSamoDanas;
                                      if (!promeniAdresuSamoDanas) {
                                        samoDanasAdresa = null;
                                        samoDanasAdresaId = null;
                                      }
                                    });
                                  },
                                  child: Row(
                                    children: [
                                      Checkbox(
                                        value: promeniAdresuSamoDanas,
                                        onChanged: (value) {
                                          setStateDialog(() {
                                            promeniAdresuSamoDanas = value ?? false;
                                            if (!promeniAdresuSamoDanas) {
                                              samoDanasAdresa = null;
                                              samoDanasAdresaId = null;
                                            }
                                          });
                                        },
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                        side: const BorderSide(color: Colors.white, width: 2),
                                        checkColor: Colors.white,
                                        activeColor: Colors.orange,
                                      ),
                                      const Expanded(
                                        child: Text(
                                          'Promeni adresu samo za danas',
                                          style: TextStyle(fontSize: 14, color: Colors.white),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // ?? DROPDOWN ZA IZBOR ADRESE SAMO ZA DANAS
                                if (promeniAdresuSamoDanas) ...[
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    // ignore: deprecated_member_use
                                    value: samoDanasAdresaId,
                                    isExpanded: true, // ? Sprecava overflow
                                    decoration: InputDecoration(
                                      labelText: 'Adresa samo za danas',
                                      labelStyle: TextStyle(color: Colors.grey.shade700),
                                      prefixIcon: const Icon(Icons.edit_location_alt, color: Colors.orange),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: Colors.orange),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: Colors.orange.shade300),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: Colors.orange, width: 2),
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                    ),
                                    dropdownColor: Colors.white, // Bela pozadina dropdown-a
                                    style: const TextStyle(color: Colors.black), // Crni tekst
                                    items: dostupneAdrese.map((adresa) {
                                      return DropdownMenuItem<String>(
                                        value: adresa['id'], // Cuvamo ID kao value
                                        child: Text(
                                          adresa['naziv'] ?? '',
                                          overflow: TextOverflow.ellipsis, // ? Skracuje dugacak tekst
                                          style: const TextStyle(color: Colors.black),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (value) {
                                      setStateDialog(() {
                                        samoDanasAdresaId = value;
                                        // Nadi naziv po ID-u
                                        samoDanasAdresa = dostupneAdrese.firstWhere((a) => a['id'] == value,
                                            orElse: () => {})['naziv'];
                                      });
                                    },
                                    hint: Text(
                                      'Izaberi adresu',
                                      style: TextStyle(color: Colors.grey.shade600),
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 12),

                                // ?? TELEFON FIELD (readonly - popunjava se automatski)
                                TextField(
                                  controller: telefonController,
                                  readOnly: true,
                                  keyboardType: TextInputType.phone,
                                  decoration: InputDecoration(
                                    labelText: 'Telefon',
                                    hintText: 'Automatski se popunjava...',
                                    prefixIcon: const Icon(Icons.phone),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    filled: true,
                                    fillColor: Colors.grey.shade100,
                                  ),
                                ),

                                const SizedBox(height: 12),

                                // ?? BROJ MESTA - dropdown za izbor broja rezervisanih mesta
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.grey.shade400),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.event_seat, color: Colors.grey),
                                      const SizedBox(width: 12),
                                      Flexible(
                                        child: Text(
                                          'Broj mesta:',
                                          style: const TextStyle(fontSize: 16),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      DropdownButton<int>(
                                        value: brojMesta,
                                        underline: const SizedBox(),
                                        isDense: true,
                                        items: [1, 2, 3, 4, 5].map((int value) {
                                          return DropdownMenuItem<int>(
                                            value: value,
                                            child: Text(
                                              value == 1 ? '1 mesto' : '$value mesta',
                                              style: const TextStyle(fontSize: 16),
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (int? newValue) {
                                          if (newValue != null) {
                                            setStateDialog(() {
                                              brojMesta = newValue;
                                            });
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),

                                // ??? PRIKAZ TIPA PUTNIKA (ako je izabran)
                                if (selectedPutnik != null)
                                  Container(
                                    margin: const EdgeInsets.only(top: 12),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: selectedPutnik!.v2Tabela == 'v2_radnici'
                                          ? Colors.blue.withOpacity(0.15)
                                          : selectedPutnik!.v2Tabela == 'v2_dnevni'
                                              ? Colors.orange.withOpacity(0.15)
                                              : Colors.green.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: selectedPutnik!.v2Tabela == 'v2_radnici'
                                            ? Colors.blue.withOpacity(0.4)
                                            : selectedPutnik!.v2Tabela == 'v2_dnevni'
                                                ? Colors.orange.withOpacity(0.4)
                                                : Colors.green.withOpacity(0.4),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          selectedPutnik!.v2Tabela == 'v2_radnici'
                                              ? Icons.engineering
                                              : selectedPutnik!.v2Tabela == 'v2_dnevni'
                                                  ? Icons.today
                                                  : Icons.school,
                                          size: 20,
                                          color: selectedPutnik!.v2Tabela == 'v2_radnici'
                                              ? Colors.blue.shade700
                                              : selectedPutnik!.v2Tabela == 'v2_dnevni'
                                                  ? Colors.orange.shade700
                                                  : Colors.green.shade700,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Tip: ${selectedPutnik!.v2Tabela.toUpperCase()}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: selectedPutnik!.v2Tabela == 'v2_radnici'
                                                ? Colors.blue.shade700
                                                : selectedPutnik!.v2Tabela == 'v2_dnevni'
                                                    ? Colors.orange.shade700
                                                    : Colors.green.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ?? GLASSMORPHISM ACTIONS
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(dialogCtx).glassContainer,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(20),
                      ),
                      border: Border(
                        top: BorderSide(
                          color: Theme.of(dialogCtx).glassBorder,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        // Cancel button
                        Expanded(
                          child: Container(
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: Colors.red.withOpacity(0.4),
                              ),
                            ),
                            child: TextButton(
                              onPressed: () => Navigator.pop(dialogCtx),
                              child: const Text(
                                'Otkaži',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                  shadows: [
                                    Shadow(
                                      offset: Offset(1, 1),
                                      blurRadius: 3,
                                      color: Colors.black54,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 15),
                        // Add button
                        Expanded(
                          flex: 2,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: Colors.green.withOpacity(0.6),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: HapticElevatedButton(
                              hapticType: HapticType.success,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                              onPressed: isDialogLoading
                                  ? null
                                  : () async {
                                      // Validacija - mora biti odabrani V2Putnik
                                      if (selectedPutnik == null) {
                                        AppSnackBar.error(dialogCtx, '⚠️ Morate odabrati putnika iz liste');
                                        return;
                                      }

                                      if (_selectedVreme.isEmpty || _selectedGrad.isEmpty) {
                                        AppSnackBar.error(dialogCtx, '⚠️ Greška: Nije odabrano vreme polaska');
                                        return;
                                      }

                                      try {
                                        // STRIKTNA VALIDACIJA VOZACA - PROVERI NULL, EMPTY I VALID DRIVER
                                        if (_currentDriver == null ||
                                            _currentDriver!.isEmpty ||
                                            !VozacCache.isValidIme(_currentDriver)) {
                                          if (!dialogCtx.mounted) return;
                                          AppSnackBar.error(dialogCtx,
                                              '❌ GREŠKA: Vozac "$_currentDriver" nije registrovan. Molimo ponovo se ulogujte.');
                                          return;
                                        }

                                        // ? Validacija vozaca koristi VozacCache.isValidIme()

                                        // ?? PROVERA KAPACITETA - da li ima slobodnih mesta
                                        // ?? SAMO ZA PUTNIKE - vozaci mogu dodavati bez ogranicenja
                                        final isVozac = VozacCache.isValidIme(_currentDriver);
                                        if (!isVozac) {
                                          final imaMesta = await SlobodnaMestaService.imaSlobodnihMesta(
                                            _selectedGrad,
                                            _selectedVreme,
                                          );
                                          if (!imaMesta) {
                                            if (!dialogCtx.mounted) return;
                                            AppSnackBar.error(dialogCtx,
                                                '⚠️ Termin $_selectedVreme ($_selectedGrad) je PUN! Izaberite drugo vreme.');
                                            return;
                                          }
                                        }

                                        // POKAZI LOADING STATE - lokalno za dijalog
                                        setStateDialog(() {
                                          isDialogLoading = true;
                                        });

                                        // ?? KORISTI SELEKTOVANO VREME SA HOME SCREEN-A
                                        // ? SADA: Mesecna karta = true za SVE tipove (radnik, ucenik, dnevni)
                                        // Svi tipovi koriste istu logiku i registrovani_putnici tabelu
                                        const isMesecnaKarta = true;

                                        // ?? Koristi "samo danas" adresu ako je postavljena, inace stalnu
                                        final adresaZaKoristiti = promeniAdresuSamoDanas && samoDanasAdresa != null
                                            ? samoDanasAdresa
                                            : (adresaController.text.isEmpty ? null : adresaController.text);
                                        // ?? Koristi "samo danas" adresaId ako je postavljen
                                        final adresaIdZaKoristiti = promeniAdresuSamoDanas && samoDanasAdresaId != null
                                            ? samoDanasAdresaId
                                            : null; // Stalna adresa ima adresaId u registrovani_putnici

                                        final noviPutnik = V2Putnik(
                                          ime: selectedPutnik!.ime,
                                          polazak: _selectedVreme,
                                          grad: _selectedGrad,
                                          dan: _getDayAbbreviation(_selectedDay),
                                          mesecnaKarta: isMesecnaKarta,
                                          vremeDodavanja: DateTime.now(),
                                          dodeljenVozac: _currentDriver!, // Safe non-null assertion nakon validacije
                                          adresa: adresaZaKoristiti,
                                          adresaId: adresaIdZaKoristiti, // ?? Za brži geocoding
                                          brojTelefona: selectedPutnik!.telefon,
                                          brojMesta: brojMesta, // ?? Prosledujemo broj rezervisanih mesta
                                        );

                                        // Duplikat provera se Vrsi u PutnikService.v2DodajPutnika()
                                        await _putnikService.v2DodajPutnika(noviPutnik);

                                        // ?? Eksplicitan refresh stream-a da se V2Putnik odmah prikaže
                                        _putnikService.refreshAllActiveStreams();

                                        if (!dialogCtx.mounted) return;

                                        // Ukloni loading state i zatvori dijalog
                                        setStateDialog(() {
                                          isDialogLoading = false;
                                        });

                                        Navigator.pop(dialogCtx);

                                        // ?? PREBACI NA VREME PUTNIKA DA BI BIO VIDLJIV - mora posle pop()
                                        // Koristimo rootContext (home screen) - dijalog context je vec zatvoren
                                        if (mounted) {
                                          setState(() {
                                            _selectedVreme = noviPutnik.polazak;
                                          });
                                        }

                                        // ? Koristimo rootContext jer je dialog context vec pop-ovan
                                        if (rootContext.mounted) {
                                          AppSnackBar.success(rootContext, '✅ Putnik je uspešno dodat');
                                        }
                                      } catch (e) {
                                        // ensure dialog loading is cleared
                                        setStateDialog(() {
                                          isDialogLoading = false;
                                        });

                                        if (!dialogCtx.mounted) return;

                                        AppSnackBar.error(dialogCtx, '❌ Greška pri dodavanju: $e');
                                      }
                                    },
                              child: isDialogLoading
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          decoration: const BoxDecoration(
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black54,
                                                offset: Offset(1, 1),
                                                blurRadius: 3,
                                              ),
                                            ],
                                          ),
                                          child: const Text(
                                            'Dodaje...',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.person_add,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Dodaj',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                            shadows: [
                                              Shadow(
                                                offset: Offset(1, 1),
                                                blurRadius: 3,
                                                color: Colors.black54,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ? PROVERAVAJ LOADING STANJE ODMAH
    if (_isLoading) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(74),
            child: Container(
              decoration: BoxDecoration(
                // Keep appbar fully transparent so underlying gradient shows
                color: Theme.of(context).glassContainer,
                border: Border.all(
                  color: Theme.of(context).glassBorder,
                  width: 1.5,
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(25),
                  bottomRight: Radius.circular(25),
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      // REZERVACIJE - levo
                      Expanded(
                        flex: 3,
                        child: Container(
                          height: 35,
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Rezervacije',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.onPrimary,
                                letterSpacing: 0.5,
                                shadows: const [
                                  Shadow(
                                    offset: Offset(1, 1),
                                    blurRadius: 3,
                                    color: Colors.black54,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // LOADING - sredina
                      Expanded(
                        flex: 2,
                        child: Container(
                          height: 35,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Theme.of(context).colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Ucitavam...',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // PRAZAN PROSTOR - desno
                      Expanded(
                        flex: 3,
                        child: Container(
                          height: 35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          body: Container(
            decoration: BoxDecoration(
              gradient: ThemeManager().currentGradient, // ?? Dinamicki gradijent iz tema
            ),
            child: ShimmerWidgets.putnikListShimmer(itemCount: 8),
          ),
          // ?? DODAJ BOTTOM NAVIGATION BAR I U LOADING STANJU!
          bottomNavigationBar: ValueListenableBuilder<String>(
            valueListenable: navBarTypeNotifier,
            builder: (context, navType, _) {
              return _buildBottomNavBar(navType, (grad, vreme) => 0);
            },
          ),
        ),
      );
    }

    // ?? SUPABASE REALTIME STREAM: streamKombinovaniPutnici()
    // Auto-refresh kada se promeni status putnika (pokupljen/naplacen/otkazan)
    // Use a parametric stream filtered to the currently selected day
    // so monthly passengers (registrovani_putnici) are created for that day
    // and will appear in the list/counts for arbitrary selected day.
    // ? FIX: Ne prosledujemo vreme da bismo dobili SVE putnike za dan (za bottom nav bar brojace)
    // Filtriranje po gradu/vremenu se radi client-side za prikaz liste
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: StreamBuilder<List<V2Putnik>>(
        stream: _putnikService.streamKombinovaniPutniciFiltered(
          isoDate: _getTargetDateIsoFromSelectedDay(_selectedDay),
          // grad i vreme NAMERNO IZOSTAVLJENI - treba nam SVA vremena za bottom nav bar
        ),
        builder: (context, snapshot) {
          // ?? DEBUG: Log state information
          // ?? NOVO: Error handling sa specialized widgets
          if (snapshot.hasError) {
            return Scaffold(
              appBar: PreferredSize(
                preferredSize: const Size.fromHeight(93),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).glassContainer,
                    border: Border.all(
                      color: Theme.of(context).glassBorder,
                      width: 1.5,
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(25),
                      bottomRight: Radius.circular(25),
                    ),
                  ),
                  child: SafeArea(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'REZERVACIJE - ERROR',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.onError,
                            letterSpacing: 1.8,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              body: const Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          // ?? POPRAVLJENO: Prikažemo prazan UI umesto beskonacnog loading-a
          if (snapshot.connectionState == ConnectionState.waiting && snapshot.data == null) {
            // Umesto beskonacnog cekanja, nastavi sa praznom listom
            // StreamBuilder ce se ažurirati kada podaci stignu
          }

          final allPutnici = snapshot.data ?? [];

          // Get target day abbreviation for additional filtering
          final targetDateIso = _getTargetDateIsoFromSelectedDay(_selectedDay);
          final date = DateTime.parse(targetDateIso);
          const dayAbbrs = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
          final targetDayAbbr = dayAbbrs[date.weekday - 1];

          // Additional client-side filtering like danas_screen
          Iterable<V2Putnik> filtered = allPutnici.where((p) {
            // Filtriraj po dan kraticama (v2_polasci nema datum kolonu, samo dan TEXT)
            final dayMatch = p.dan.toLowerCase().contains(targetDayAbbr.toLowerCase());

            return dayMatch;
          });
          // Capture passengers for the selected day (but before applying the
          // selected-time filter). We use this set for counting bottom-bar slots
          // because the bottom counts should reflect the whole day (all times),
          // not just the currently selected time.
          final putniciZaDan = filtered.toList();

          // Additional filters for display (applies time/grad/status and is used
          // to build the visible list). This operates on the putniciZaDan list.
          filtered = putniciZaDan.where((V2Putnik) {
            final normalizedStatus = TextUtils.normalizeText(V2Putnik.status ?? '');
            final imaVreme = V2Putnik.polazak.toString().trim().isNotEmpty;
            final imaGrad = V2Putnik.grad.toString().trim().isNotEmpty;
            final imaDan = V2Putnik.dan.toString().trim().isNotEmpty;
            final danBaza = _selectedDay;
            final normalizedPutnikDan = GradAdresaValidator.normalizeString(V2Putnik.dan);
            final normalizedDanBaza = GradAdresaValidator.normalizeString(_getDayAbbreviation(danBaza));
            final odgovarajuciDan = normalizedPutnikDan.contains(normalizedDanBaza);
            final odgovarajuciGrad = GradAdresaValidator.isGradMatch(
              V2Putnik.grad,
              V2Putnik.adresa,
              _selectedGrad,
            );
            final odgovarajuceVreme = GradAdresaValidator.normalizeTime(V2Putnik.polazak) ==
                GradAdresaValidator.normalizeTime(_selectedVreme);
            // ?? FIX: Dopusti otkazane putnike - PutnikList ce ih sortirati na dno sa crvenom bojom
            // Iskljuci bez_polaska, otkazano - admin ih je eksplicitno uklonio
            final prikazi = imaVreme &&
                imaGrad &&
                imaDan &&
                odgovarajuciDan &&
                odgovarajuciGrad &&
                odgovarajuceVreme &&
                normalizedStatus != 'obrisan' &&
                normalizedStatus != 'obrada' &&
                normalizedStatus != 'bez_polaska' &&
                normalizedStatus != 'otkazano';
            return prikazi;
          });
          final sviPutnici = filtered.toList();

          // DEDUPLIKACIJA PO COMPOSITE KLJUCU: id + polazak + dan
          final Map<String, V2Putnik> uniquePutnici = {};
          for (final p in sviPutnici) {
            final key = '${p.id}_${p.polazak}_${p.dan}';
            uniquePutnici[key] = p;
          }
          final sviPutniciBezDuplikata = uniquePutnici.values.toList();

          // ?? BROJAC PUTNIKA - koristi SVE putnice za SELEKTOVANI DAN (deduplikovane)
          // DEDUPLICIRAJ za racunanje brojaca (id + polazak + dan)
          final Map<String, V2Putnik> uniqueForCounts = {};
          for (final p in putniciZaDan) {
            final key = '${p.id}_${p.polazak}_${p.dan}';
            uniqueForCounts[key] = p;
          }
          final countCandidates = uniqueForCounts.values.toList();

          // ?? REFAKTORISANO: Koristi PutnikCountHelper za centralizovano brojanje
          final countHelper = PutnikCountHelper.fromPutnici(
            putnici: countCandidates,
            targetDateIso: targetDateIso,
            targetDayAbbr: targetDayAbbr,
          );

          // ?? UKLONJEN DUPLI SORT - PutnikList sada sortira konzistentno sa VozacScreen
          // Sortiranje se Vrsi u PutnikList widgetu sa istom logikom za sva tri ekrana
          final putniciZaPrikaz = sviPutniciBezDuplikata;

          // Funkcija za brojanje putnika po gradu, vremenu i danu
          int getPutnikCount(String grad, String vreme) {
            try {
              return countHelper.getCount(grad, vreme);
            } catch (e) {
              if (kDebugMode) {
                debugPrint('❌ [Home] Error in getPutnikCount: $e');
              }
              return 0;
            }
          }

          // (totalFilteredCount removed)

          return Container(
            decoration: BoxDecoration(
              gradient: ThemeManager().currentGradient, // Dinamicki gradijent iz tema
            ),
            child: Scaffold(
              backgroundColor: Colors.transparent, // Transparentna pozadina
              appBar: PreferredSize(
                preferredSize: const Size.fromHeight(93), // Povecano sa 80 na 95 zbog sezonskog indikatora
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).glassContainer, // Transparentni glassmorphism
                    border: Border.all(
                      color: Theme.of(context).glassBorder,
                      width: 1.5,
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(25),
                      bottomRight: Radius.circular(25),
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // PRVI RED - Tablica levo, Rezervacije sredina, Dana desno
                          Row(
                            children: [
                              // LEVO - Tablica vozila (ako istice registracija)
                              const RegistracijaTablicaWidget(),
                              const SizedBox(width: 8),
                              // SREDINA - "R E Z E R V A C I J E"
                              Expanded(
                                child: Container(
                                  height: 28,
                                  alignment: Alignment.center,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'R E Z E R V A C I J E',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: Theme.of(context).colorScheme.onPrimary,
                                        letterSpacing: 1.4,
                                        shadows: [
                                          Shadow(
                                            blurRadius: 12,
                                            color: Colors.black87,
                                          ),
                                          Shadow(
                                            offset: const Offset(2, 2),
                                            blurRadius: 6,
                                            color: Colors.black54,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // DESNO - Brojac dana do isteka registracije
                              const RegistracijaBrojacWidget(),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // DRUGI RED - Driver, Tema, Update i Dropdown
                          Row(
                            children: [
                              // DRIVER - levo
                              if (_currentDriver != null && _currentDriver!.isNotEmpty)
                                Expanded(
                                  flex: 35,
                                  child: Container(
                                    height: 33,
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: VozacCache.getColor(_currentDriver), // opaque (100%)
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Theme.of(context).glassBorder,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        _currentDriver!,
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.onPrimary,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          shadows: [
                                            Shadow(
                                              blurRadius: 8,
                                              color: Colors.black87,
                                            ),
                                            Shadow(
                                              offset: const Offset(1, 1),
                                              blurRadius: 4,
                                              color: Colors.black54,
                                            ),
                                          ],
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                      ),
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 2),
                              // TEMA - levo-sredina
                              Expanded(
                                flex: 25,
                                child: InkWell(
                                  onTap: () async {
                                    await ThemeManager().nextTheme();
                                    if (mounted) setState(() {});
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    height: 33,
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).glassContainer,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Theme.of(context).glassBorder,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'Tema',
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.onPrimary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          shadows: [
                                            Shadow(blurRadius: 8, color: Colors.black87),
                                            Shadow(offset: const Offset(1, 1), blurRadius: 4, color: Colors.black54),
                                          ],
                                        ),
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 2),
                              // DROPDOWN - desno
                              Expanded(
                                flex: 35,
                                child: Container(
                                  height: 33,
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).glassContainer,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Theme.of(context).glassBorder,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton2<String>(
                                      value: _selectedDay,
                                      customButton: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Expanded(
                                            child: Center(
                                              child: Text(
                                                _selectedDay,
                                                style: TextStyle(
                                                  color: Theme.of(context).colorScheme.onPrimary,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      dropdownStyleData: DropdownStyleData(
                                        decoration: BoxDecoration(
                                          gradient: Theme.of(context).backgroundGradient,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: Theme.of(context).glassBorder,
                                            width: 1.5,
                                          ),
                                        ),
                                        elevation: 8,
                                      ),
                                      items: _dani
                                          .map(
                                            (dan) => DropdownMenuItem(
                                              value: dan,
                                              child: Center(
                                                child: Text(
                                                  dan,
                                                  style: TextStyle(
                                                    color: Theme.of(context).colorScheme.onPrimary,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 16,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                  overflow: TextOverflow.ellipsis,
                                                  maxLines: 1,
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (value) {
                                        if (mounted) {
                                          setState(() => _selectedDay = value!);
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              body: Column(
                children: [
                  // Action buttons
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: _HomeScreenButton(
                            label: 'Dodaj',
                            icon: Icons.person_add,
                            onTap: _showAddPutnikDialog,
                          ),
                        ),
                        const SizedBox(width: 4),
                        if (_currentDriver == 'Bruda' || _currentDriver == 'Bilevski' || _currentDriver == 'Voja')
                          Expanded(
                            child: _HomeScreenButton(
                              label: 'Ja',
                              icon: Icons.person,
                              onTap: () {
                                AnimatedNavigation.pushSmooth(
                                  context,
                                  VozacScreen(previewAsDriver: _currentDriver),
                                );
                              },
                            ),
                          ),
                        if (AdminSecurityService.isAdmin(_currentDriver)) ...[
                          const SizedBox(width: 4),
                          Expanded(
                            child: StreamBuilder<int>(
                              stream: V2PolasciService.v2StreamBrojZahteva(),
                              builder: (context, snapshot) {
                                final count = snapshot.data ?? 0;
                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    _HomeScreenButton(
                                      label: 'Zahtevi',
                                      icon: Icons.notifications_active,
                                      onTap: () {
                                        AnimatedNavigation.pushSmooth(
                                          context,
                                          const V2PolasciScreen(),
                                        );
                                      },
                                    ),
                                    if (count > 0)
                                      Positioned(
                                        right: 8,
                                        top: 8,
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: const BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black26,
                                                blurRadius: 4,
                                                offset: Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          constraints: const BoxConstraints(
                                            minWidth: 20,
                                            minHeight: 20,
                                          ),
                                          child: Text(
                                            '$count',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                        const SizedBox(width: 4),
                        if (AdminSecurityService.isAdmin(_currentDriver))
                          Expanded(
                            child: _HomeScreenButton(
                              label: 'Admin',
                              icon: Icons.admin_panel_settings,
                              onTap: () {
                                AnimatedNavigation.pushSmooth(
                                  context,
                                  const AdminScreen(),
                                );
                              },
                            ),
                          ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: PopupMenuButton<String>(
                            tooltip: 'štampaj',
                            offset: const Offset(0, -150),
                            onSelected: (value) async {
                              if (value == 'spisak') {
                                await PrintingService.printPutniksList(
                                  _selectedDay,
                                  _selectedVreme,
                                  _selectedGrad,
                                  context,
                                );
                              } else if (value == 'racun_postojeci') {
                                _showRacunDialog(context);
                              } else if (value == 'racun_novi') {
                                _showNoviRacunDialog(context);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'spisak',
                                child: Row(
                                  children: [
                                    Icon(Icons.list_alt, color: Colors.blue),
                                    SizedBox(width: 8),
                                    Text('štampaj spisak'),
                                  ],
                                ),
                              ),
                              const PopupMenuDivider(),
                              const PopupMenuItem(
                                value: 'racun_postojeci',
                                child: Row(
                                  children: [
                                    Icon(Icons.people, color: Colors.green),
                                    SizedBox(width: 8),
                                    Text('Racun - postojeci'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'racun_novi',
                                child: Row(
                                  children: [
                                    Icon(Icons.person_add, color: Colors.orange),
                                    SizedBox(width: 8),
                                    Text('Racun - novi'),
                                  ],
                                ),
                              ),
                            ],
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Theme.of(context).glassContainer,
                                border: Border.all(
                                  color: Theme.of(context).glassBorder,
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.print,
                                    color: Theme.of(context).colorScheme.onPrimary,
                                    size: 18,
                                  ),
                                  const SizedBox(height: 4),
                                  const SizedBox(
                                    height: 16,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        'štampaj',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: PopupMenuButton<String>(
                            onSelected: (value) async {
                              if (value == 'logout') {
                                _logout();
                              } else if (value == 'sifra') {
                                final vozac = await AuthManager.getCurrentDriver();
                                if (!mounted || vozac == null) return;
                                if (context.mounted) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (ctx) => PromenaSifreScreen(vozacIme: vozac),
                                    ),
                                  );
                                }
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'sifra',
                                child: Row(
                                  children: [
                                    Icon(Icons.lock, color: Colors.amber),
                                    SizedBox(width: 8),
                                    Text('Promeni šifru'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'logout',
                                child: Row(
                                  children: [
                                    Icon(Icons.logout, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('Logout'),
                                  ],
                                ),
                              ),
                            ],
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Theme.of(context).glassContainer,
                                border: Border.all(
                                  color: Theme.of(context).glassBorder,
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.settings,
                                    color: Theme.of(context).colorScheme.onPrimary,
                                    size: 18,
                                  ),
                                  const SizedBox(height: 4),
                                  const SizedBox(
                                    height: 16,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        'Opcije',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Lista putnika
                  Expanded(
                    child: putniciZaPrikaz.isEmpty
                        ? Center(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(context).glassContainer,
                                border: Border.all(
                                  color: Theme.of(context).glassBorder,
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Nema putnika za ovaj polazak.',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          )
                        : PutnikList(
                            putnici: putniciZaPrikaz,
                            currentDriver: _currentDriver!,
                            selectedGrad: _selectedGrad,
                            selectedVreme: _selectedVreme,
                            selectedDay: _getDayAbbreviation(_selectedDay),
                            onPutnikStatusChanged: () {
                              if (mounted) setState(() {});
                            },
                            bcVremena: bcVremena,
                            vsVremena: vsVremena,
                          ),
                  ),
                ],
              ),
              bottomNavigationBar: ValueListenableBuilder<String>(
                valueListenable: navBarTypeNotifier,
                builder: (context, navType, _) {
                  return _buildBottomNavBar(navType, getPutnikCount);
                },
              ),
            ),
          );
        },
      ),
    );
  }

  /// Helper metoda za kreiranje bottom nav bar-a prema tipu
  /// ?? Boja vozaca za termin (za bottom nav bar border)
  Color? _getVozacColorForTermin(String grad, String vreme) {
    final dan = _getDayAbbreviation(_selectedDay);
    final entry = V2MasterRealtimeManager.instance.rasporedCache.values
        .map((row) => VozacRasporedEntry.fromMap(row))
        .where((r) => r.dan == dan && r.grad == grad && r.vreme == vreme)
        .firstOrNull;
    if (entry == null) return null;
    return VozacCache.getColor(entry.vozacId);
  }

  Widget _buildBottomNavBar(String navType, int Function(String, String) getPutnikCount) {
    void onChanged(String grad, String vreme) {
      if (mounted) {
        setState(() {
          _selectedGrad = grad;
          _selectedVreme = vreme;
        });
      }
    }

    switch (navType) {
      case 'praznici':
        return BottomNavBarPraznici(
          sviPolasci: _sviPolasci,
          selectedGrad: _selectedGrad,
          selectedVreme: _selectedVreme,
          getPutnikCount: getPutnikCount,
          getKapacitet: (grad, vreme) => V2KapacitetService.getKapacitetSync(grad, vreme),
          onPolazakChanged: onChanged,
          selectedDan: _selectedDay,
          showVozacBoja: true,
          getVozacColor: _getVozacColorForTermin,
        );
      case 'zimski':
        return BottomNavBarZimski(
          sviPolasci: _sviPolasci,
          selectedGrad: _selectedGrad,
          selectedVreme: _selectedVreme,
          getPutnikCount: getPutnikCount,
          getKapacitet: (grad, vreme) => V2KapacitetService.getKapacitetSync(grad, vreme),
          onPolazakChanged: onChanged,
          selectedDan: _selectedDay,
          showVozacBoja: true,
          getVozacColor: _getVozacColorForTermin,
        );
      default: // 'letnji' ili nepoznato
        return BottomNavBarLetnji(
          sviPolasci: _sviPolasci,
          selectedGrad: _selectedGrad,
          selectedVreme: _selectedVreme,
          getPutnikCount: getPutnikCount,
          getKapacitet: (grad, vreme) => V2KapacitetService.getKapacitetSync(grad, vreme),
          onPolazakChanged: onChanged,
          selectedDan: _selectedDay,
          showVozacBoja: true,
          getVozacColor: _getVozacColorForTermin,
        );
    }
  }

  @override
  void dispose() {
    // ?? CLEANUP REAL-TIME SUBSCRIPTIONS
    try {
      _realtimeSubscription?.cancel();
      _networkStatusSubscription?.cancel();
      _dispecerTimer?.cancel();
    } catch (e) {
      // Silently ignore
    }

    // ?? Update listener cleanup
    updateInfoNotifier.removeListener(_onUpdateInfo);

    // No overlay cleanup needed currently

    // ?? SAFE DISPOSAL ValueNotifier-a
    try {
      // No additional disposals needed
    } catch (e) {
      // Silently ignore
    }
    super.dispose();
  }

  /// ?? Pokrece se kada updateInfoNotifier dobije novu vrednost
  void _onUpdateInfo() {
    final info = updateInfoNotifier.value;
    if (info == null || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: !info.isForced,
      builder: (ctx) => PopScope(
        canPop: !info.isForced,
        child: AlertDialog(
          title: Text(info.isForced ? '🔴 Obavezno ažuriranje' : '🆕 Dostupna nova verzija'),
          content: Text(
            info.isForced
                ? 'Ova verzija aplikacije više nije podržana.\nMolimo ažurirajte na verziju ${info.latestVersion} da biste nastavili sa korišćenjem.'
                : 'Dostupna je nova verzija ${info.latestVersion}.\nPreporucujemo da ažurirate aplikaciju.',
          ),
          actions: [
            if (!info.isForced)
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Kasnije'),
              ),
            ElevatedButton(
              onPressed: () {
                V2AppSettingsService.openStore();
                if (!info.isForced) Navigator.of(ctx).pop();
              },
              child: const Text('Ažuriraj'),
            ),
          ],
        ),
      ),
    );
  }
}

// AnimatedActionButton widget sa hover efektima
class AnimatedActionButton extends StatefulWidget {
  const AnimatedActionButton({
    super.key,
    required this.child,
    required this.onTap,
    required this.width,
    required this.height,
    required this.margin,
    required this.gradientColors,
    required this.boxShadow,
  });
  final Widget child;
  final VoidCallback onTap;
  final double width;
  final double height;
  final EdgeInsets margin;
  final List<Color> gradientColors;
  final List<BoxShadow> boxShadow;

  @override
  State<AnimatedActionButton> createState() => _AnimatedActionButtonState();
}

class _AnimatedActionButtonState extends State<AnimatedActionButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        if (mounted) setState(() => _isPressed = true);
        _controller.forward();
      },
      onTapUp: (_) {
        if (mounted) setState(() => _isPressed = false);
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () {
        if (mounted) setState(() => _isPressed = false);
        _controller.reverse();
      },
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: widget.width,
              height: widget.height,
              margin: widget.margin,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: widget.gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: _isPressed
                    ? widget.boxShadow.map((shadow) {
                        return BoxShadow(
                          color: shadow.color.withOpacity(
                            (shadow.color.opacity * 1.5).clamp(0.0, 1.0),
                          ),
                          blurRadius: shadow.blurRadius * 1.2,
                          offset: shadow.offset,
                        );
                      }).toList()
                    : widget.boxShadow,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {}, // Handled by GestureDetector
                  child: widget.child,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// Originalna _HomeScreenButton klasa sa seksi bojama
class _HomeScreenButton extends StatelessWidget {
  const _HomeScreenButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(6), // Smanjeno sa 12 na 6
        decoration: BoxDecoration(
          color: Theme.of(context).glassContainer, // Transparentni glassmorphism
          border: Border.all(
            color: Theme.of(context).glassBorder,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(12),
          // no boxShadow ž keep transparent glass + border only
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              icon,
              // keep icons consistent with the current theme (onPrimary may be white or themed)
              color: Theme.of(context).colorScheme.onPrimary,
              size: 18, // Smanjeno sa 24 na 18
            ),
            const SizedBox(height: 4), // Smanjeno sa 8 na 4
            // Keep the label to a single centered line; scale down if it's too big for narrow buttons
            SizedBox(
              height: 16,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    shadows: [
                      Shadow(
                        blurRadius: 8,
                        color: Colors.black87,
                      ),
                      Shadow(
                        offset: Offset(1, 1),
                        blurRadius: 4,
                        color: Colors.black54,
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
