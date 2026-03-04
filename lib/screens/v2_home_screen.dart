import 'dart:async';

import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../config/v2_route_config.dart';
import '../globals.dart';
import '../models/v2_putnik.dart';
import '../models/v2_registrovani_putnik.dart';
import '../services/realtime/v2_master_realtime_manager.dart';
import '../services/v2_admin_security_service.dart';
import '../services/v2_adresa_supabase_service.dart';
import '../services/v2_auth_manager.dart';
import '../services/v2_cena_obracun_service.dart';
import '../services/v2_firebase_service.dart';
import '../services/v2_haptic_service.dart';
import '../services/v2_kapacitet_service.dart'; // ?? Kapacitet za bottom nav bar
import '../services/v2_local_notification_service.dart';
import '../services/v2_polasci_service.dart';
import '../services/v2_printing_service.dart';
import '../services/v2_racun_service.dart';
import '../services/v2_realtime_notification_service.dart';
import '../services/v2_slobodna_mesta_service.dart'; // ?? Provera kapaciteta
import '../services/v2_statistika_service.dart';
import '../services/v2_theme_manager.dart'; // ?? Tema sistem
import '../services/v2_vozac_raspored_service.dart';
import '../theme.dart'; // ?? Import za prelepe gradijente
import '../utils/v2_app_snack_bar.dart';
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

class V2HomeScreen extends StatefulWidget {
  const V2HomeScreen({super.key});

  @override
  State<V2HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<V2HomeScreen> with TickerProviderStateMixin {
  // Logging using dlog function from logging.dart

  bool _isLoading = true;
  // bool _isAddingPutnik = false; // previously used loading state; now handled local to dialog
  String _selectedDay = 'Ponedeljak'; // Bice postavljeno na današnji dan u initState
  String _selectedGrad = 'BC';
  String _selectedVreme = '05:00'; // inicijalna vrednost, overriduje se u initState

  // Key and overlay entry for custom days dropdown
  // (removed overlay support for now) - will use DropdownButton2 built-in overlay

  String? _currentDriver;

  // ?? Cache-based stream (kreiran jednom u initState, ne unutar build())
  late final Stream<int> _streamBrojZahteva;

  // ?? putnici stream — kreira se samo kad se promeni _selectedDay (ne na svakom rebuildu)
  Stream<List<V2Putnik>>? _streamPutnici;
  String? _cachedPutniciDay;

  // ?? DINAMICKA VREMENA - prate navBarTypeNotifier (praznici/zimski/letnji)
  List<String> get bcVremena {
    final navType = navBarTypeNotifier.value;
    if (navType == 'praznici') {
      return V2RouteConfig.bcVremenaPraznici;
    } else if (navType == 'zimski') {
      return V2RouteConfig.bcVremenaZimski;
    } else {
      return V2RouteConfig.bcVremenaLetnji;
    }
  }

  List<String> get vsVremena {
    final navType = navBarTypeNotifier.value;
    if (navType == 'praznici') {
      return V2RouteConfig.vsVremenaPraznici;
    } else if (navType == 'zimski') {
      return V2RouteConfig.vsVremenaZimski;
    } else {
      return V2RouteConfig.vsVremenaLetnji;
    }
  }

  // ?? DINAMICKA LISTA POLAZAKA za BottomNavBar
  List<String> get _sviPolasci {
    final bcList = bcVremena.map((v) => '$v BC').toList();
    final vsList = vsVremena.map((v) => '$v VS').toList();
    return [...bcList, ...vsList];
  }

  /// Automatski selektuje najbliže vreme polaska za trenutni cas (BC grad).
  static const List<String> _dayNamesInternal = [
    'Ponedeljak',
    'Utorak',
    'Sreda',
    'Cetvrtak',
    'Petak',
    'Subota',
    'Nedelja'
  ];
  static const List<String> _dayAbbreviations = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];

  String _getTodayName() {
    return _dayNamesInternal[DateTime.now().weekday - 1];
  }

  String _getTargetDateIsoFromSelectedDay(String fullDay) {
    final now = DateTime.now();
    final targetDayIndex = _dayNamesInternal.indexOf(fullDay);
    if (targetDayIndex < 0) throw ArgumentError('Nepoznat dan: $fullDay');
    final currentDayIndex = now.weekday - 1;
    if (targetDayIndex == currentDayIndex) return now.toIso8601String().split('T')[0];
    int daysToAdd = targetDayIndex - currentDayIndex;
    if (daysToAdd < 0) daysToAdd += 7;
    final targetDate = now.add(Duration(days: daysToAdd));
    return targetDate.toIso8601String().split('T')[0];
  }

  String _getDayAbbreviation(String fullDayName) {
    final i = _dayNamesInternal.indexOf(fullDayName);
    if (i < 0) throw ArgumentError('Nepoznat dan: $fullDayName');
    return _dayAbbreviations[i];
  }

  /// Kreira/zamjenjuje _streamPutnici za zadani dan. Poziva se iz initState i kad se dan promjeni.
  void _updatePutniciStream(String day) {
    final isoDate = _getTargetDateIsoFromSelectedDay(day);
    _cachedPutniciDay = day;
    _streamPutnici = V2PolasciService.streamKombinovaniPutniciFiltered(isoDate: isoDate);
  }

  @override
  void initState() {
    super.initState();
    final today = DateTime.now().weekday;
    // Vikend → defaultuj na Ponedeljak (firma ne radi vikendom)
    _selectedDay = (today == DateTime.saturday || today == DateTime.sunday) ? 'Ponedeljak' : _getTodayName();
    _streamBrojZahteva = V2PolasciService.v2StreamBrojZahteva();
    _updatePutniciStream(_selectedDay);
    _initializeData();
  }

  void _initializeData() async {
    try {
      await _initializeCurrentDriver();
      // ?? If the current driver is missing or invalid, redirect to welcome/login
      // Preskočiti redirect ako V2VozacCache još nije inicijalizovan (race condition)
      if (_currentDriver == null || (V2VozacCache.isInitialized && !V2VozacCache.isValidIme(_currentDriver))) {
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute<void>(builder: (context) => const V2WelcomeScreen()),
            (route) => false,
          );
        }
        return;
      }

      // StreamBuilder ce automatski ucitati data - ne treba eksplicitno _loadPutnici()

      // Inicijalizuj lokalne notifikacije za heads-up i zvuk
      if (mounted) {
        V2LocalNotificationService.initialize(context);
        // ?? UKLONJENO: listener se sada registruje globalno u main.dart
        // V2RealtimeNotificationService.listenForForegroundNotifications(context);
      }

      // ?? Auto-update removed per request

      // Inicijalizuj realtime notifikacije za aktivnog vozaca
      V2FirebaseService.getCurrentDriver().then((driver) {
        if (driver != null && driver.isNotEmpty) {
          // First request notification permissions
          V2RealtimeNotificationService.requestNotificationPermissions().then((hasPermissions) {
            V2RealtimeNotificationService.initialize().then((_) {
              // Subscribe to Firebase topics for this driver
              V2RealtimeNotificationService.subscribeToDriverTopics(driver);
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
    final driver = await V2FirebaseService.getCurrentDriver();

    if (mounted) {
      setState(() {
        // Inicijalizacija driver-a
        _currentDriver = driver;
      });
    }
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

    // Ucitaj putnike kojima treba racun iz rm cache-a
    final sviPutnici = V2StatistikaService.getAllAktivniKaoModel();
    final putnici = sviPutnici.where((p) => p.trebaRacun).toList();

    if (!mounted) return;

    if (putnici.isEmpty) {
      V2AppSnackBar.warning(context, 'Nema putnika kojima treba racun');
      return;
    }

    // ?? AUTOMATSKI OBRACUN (Inicijalno za tekuci mesec)
    DateTime selectedDate = DateTime.now();
    Map<String, int> counts = await V2CenaObracunService.prebrojJediniceMasovno(
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
            final noviCounts = await V2CenaObracunService.prebrojJediniceMasovno(
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
              final cena = V2CenaObracunService.getCenaPoDanu(p);
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
                    color: Colors.black.withValues(alpha: 0.2),
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
                                color: Colors.white.withValues(alpha: 0.1),
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
                            final cena = V2CenaObracunService.getCenaPoDanu(p);
                            final dana = brojDana[p.id] ?? 0;
                            final iznos = cena * dana;

                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withValues(alpha: 0.1),
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
                                                  color: Colors.black.withValues(alpha: 0.5),
                                                ),
                                                Shadow(
                                                  offset: const Offset(-0.5, -0.5),
                                                  blurRadius: 1,
                                                  color: Colors.white.withValues(alpha: 0.3),
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
                            backgroundColor: Colors.white.withValues(alpha: 0.2),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () async {
                            Navigator.pop(dialogContext);

                            final List<Map<String, dynamic>> racuniPodaci = [];
                            for (var p in putnici) {
                              if (selected[p.id] == true) {
                                final cena = V2CenaObracunService.getCenaPoDanu(p);
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
                              V2AppSnackBar.warning(context, 'Izaberite bar jednog putnika');
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
    ).then((_) {
      for (final c in danaControllers.values) {
        c.dispose();
      }
    });
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
                    V2AppSnackBar.warning(context, 'Unesite ime kupca');
                    return;
                  }
                  if (opisController.text.trim().isEmpty) {
                    V2AppSnackBar.warning(context, 'Unesite opis usluge');
                    return;
                  }
                  final iznos = double.tryParse(iznosController.text.trim());
                  if (iznos == null || iznos <= 0) {
                    V2AppSnackBar.warning(context, 'Unesite validan iznos');
                    return;
                  }

                  // Sacuvaj podatke pre zatvaranja dijaloga
                  final imePrezime = imeController.text.trim();
                  final opis = opisController.text.trim();
                  final jm = jedinicaMere;
                  final ctx = context;

                  Navigator.pop(dialogContext);

                  // Dohvati sledeci broj racuna (uvecava sekvencu)
                  final brojRacuna = await V2RacunService.getNextBrojRacuna();

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
    ).then((_) {
      imeController.dispose();
      iznosController.dispose();
      opisController.dispose();
    });
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
            color: Theme.of(dialogContext).colorScheme.dangerPrimary.withValues(alpha: 0.5),
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
            color: Theme.of(dialogContext).colorScheme.onSurface.withValues(alpha: 0.8),
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
          V2HapticElevatedButton(
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

      // ?? IzVrsi logout
      try {
        await V2AuthManager.logout(context);
      } catch (e) {
        debugPrint('❌ Logout error: $e');
        // Ako logout fail, pokreni navigaciju rucno
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute<void>(builder: (_) => const V2WelcomeScreen()),
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
    bool dialogActive = true; // guard: false nakon dispose
    V2RegistrovaniPutnik? selectedPutnik; // ?? Izabrani V2Putnik iz liste
    int brojMesta = 1; // ?? Broj rezervisanih mesta (default 1)
    bool promeniAdresuSamoDanas = false; // ?? Opcija za promenu adrese samo za danas
    String? samoDanasAdresa; // ?? Adresa samo za danas
    String? samoDanasAdresaId; // ?? ID adrese samo za danas (za brži geocoding)
    List<Map<String, String>> dostupneAdrese = []; // ?? Lista adresa za dropdown

    // Povuci SVE registrovane putnike iz rm cache-a
    final lista = V2StatistikaService.getAllAktivniKaoModel();
    // Filtrirana lista aktivnih putnika za brzu pretragu
    final aktivniPutnici = lista.where((V2RegistrovaniPutnik v2Putnik) => v2Putnik.aktivan).toList()
      ..sort((a, b) => a.ime.toLowerCase().compareTo(b.ime.toLowerCase()));

    // ?? Ucitaj adrese za selektovani grad
    final adreseZaGrad = V2AdresaSupabaseService.getAdreseZaGrad(_selectedGrad);
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
                    color: Colors.black.withValues(alpha: 0.2),
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
                              color: Colors.red.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: Colors.red.withValues(alpha: 0.4),
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
                                  color: Colors.black.withValues(alpha: 0.1),
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
                                  color: Colors.black.withValues(alpha: 0.1),
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
                                DropdownButtonFormField2<V2RegistrovaniPutnik>(
                                  isExpanded: true,
                                  value: aktivniPutnici
                                      .cast<V2RegistrovaniPutnik?>()
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
                                      final v2Putnik = item.value;
                                      if (v2Putnik == null) return false;
                                      return v2Putnik.ime.toLowerCase().contains(searchValue.toLowerCase());
                                    },
                                  ),
                                  items: aktivniPutnici
                                      .map(
                                        (V2RegistrovaniPutnik v2Putnik) => DropdownMenuItem<V2RegistrovaniPutnik>(
                                          value: v2Putnik,
                                          child: Row(
                                            children: [
                                              // Ikonica tipa putnika
                                              Icon(
                                                v2Putnik.v2Tabela == 'v2_radnici'
                                                    ? Icons.engineering
                                                    : v2Putnik.v2Tabela == 'v2_dnevni'
                                                        ? Icons.today
                                                        : Icons.school,
                                                size: 18,
                                                color: v2Putnik.v2Tabela == 'v2_radnici'
                                                    ? Colors.blue.shade600
                                                    : v2Putnik.v2Tabela == 'v2_dnevni'
                                                        ? Colors.orange.shade600
                                                        : Colors.green.shade600,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  v2Putnik.ime,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (V2RegistrovaniPutnik? v2Putnik) async {
                                    if (!dialogActive) return;
                                    setStateDialog(() {
                                      selectedPutnik = v2Putnik;
                                      telefonController.text = v2Putnik?.telefon ?? '';
                                      adresaController.text = 'Ucitavanje...';
                                    });
                                    if (v2Putnik != null) {
                                      // ?? AUTO-POPUNI adresu async - SAMO za selektovani grad
                                      final adresa = v2Putnik.getAdresaZaSelektovaniGrad(_selectedGrad);
                                      if (!dialogActive) return;
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
                                          ? Colors.blue.withValues(alpha: 0.15)
                                          : selectedPutnik!.v2Tabela == 'v2_dnevni'
                                              ? Colors.orange.withValues(alpha: 0.15)
                                              : Colors.green.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: selectedPutnik!.v2Tabela == 'v2_radnici'
                                            ? Colors.blue.withValues(alpha: 0.4)
                                            : selectedPutnik!.v2Tabela == 'v2_dnevni'
                                                ? Colors.orange.withValues(alpha: 0.4)
                                                : Colors.green.withValues(alpha: 0.4),
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
                              color: Colors.red.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: Colors.red.withValues(alpha: 0.4),
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
                              color: Colors.green.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: Colors.green.withValues(alpha: 0.6),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: V2HapticElevatedButton(
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
                                        V2AppSnackBar.error(dialogCtx, '⚠️ Morate odabrati putnika iz liste');
                                        return;
                                      }

                                      if (_selectedVreme.isEmpty || _selectedGrad.isEmpty) {
                                        V2AppSnackBar.error(dialogCtx, '⚠️ Greška: Nije odabrano vreme polaska');
                                        return;
                                      }

                                      try {
                                        // STRIKTNA VALIDACIJA VOZACA - PROVERI NULL, EMPTY I VALID DRIVER
                                        if (_currentDriver == null ||
                                            _currentDriver!.isEmpty ||
                                            !V2VozacCache.isValidIme(_currentDriver)) {
                                          if (!dialogCtx.mounted) return;
                                          V2AppSnackBar.error(dialogCtx,
                                              '❌ GREŠKA: Vozac "$_currentDriver" nije registrovan. Molimo ponovo se ulogujte.');
                                          return;
                                        }

                                        // ? Validacija vozaca koristi V2VozacCache.isValidIme()

                                        // ?? PROVERA KAPACITETA - da li ima slobodnih mesta
                                        // ?? SAMO ZA PUTNIKE - vozaci mogu dodavati bez ogranicenja
                                        final isVozac = V2VozacCache.isValidIme(_currentDriver);
                                        if (!isVozac) {
                                          final imaMesta = await V2SlobodnaMestaService.imaSlobodnihMesta(
                                            _selectedGrad,
                                            _selectedVreme,
                                          );
                                          if (!imaMesta) {
                                            if (!dialogCtx.mounted) return;
                                            V2AppSnackBar.error(dialogCtx,
                                                '⚠️ Termin $_selectedVreme ($_selectedGrad) je PUN! Izaberite drugo vreme.');
                                            return;
                                          }
                                        }

                                        // POKAZI LOADING STATE - lokalno za dijalog
                                        setStateDialog(() {
                                          isDialogLoading = true;
                                        });

                                        // ?? KORISTI SELEKTOVANO VREME SA HOME SCREEN-A
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
                                          vremeDodavanja: DateTime.now(),
                                          dodeljenVozac: _currentDriver!, // Safe non-null assertion nakon validacije
                                          adresa: adresaZaKoristiti,
                                          adresaId: adresaIdZaKoristiti, // ?? Za brži geocoding
                                          brojTelefona: selectedPutnik!.telefon,
                                          brojMesta: brojMesta, // ?? Prosledujemo broj rezervisanih mesta
                                        );

                                        // Duplikat provera se Vrsi u V2PolasciService.v2DodajPutnika()
                                        await V2PolasciService.v2DodajPutnika(
                                          putnikId: selectedPutnik!.id,
                                          dan: noviPutnik.dan,
                                          vreme: noviPutnik.polazak,
                                          grad: noviPutnik.grad,
                                          putnikTabela: selectedPutnik!.v2Tabela,
                                          adresaId: adresaIdZaKoristiti,
                                          brojMesta: brojMesta,
                                        );

                                        // ?? Eksplicitan refresh stream-a da se V2Putnik odmah prikaže
                                        V2PolasciService.refreshAllActiveStreams();

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
                                          V2AppSnackBar.success(rootContext, '✅ Putnik je uspešno dodat');
                                        }
                                      } catch (e) {
                                        // ensure dialog loading is cleared
                                        setStateDialog(() {
                                          isDialogLoading = false;
                                        });

                                        if (!dialogCtx.mounted) return;

                                        V2AppSnackBar.error(dialogCtx, '❌ Greška pri dodavanju: $e');
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
    ).then((_) {
      dialogActive = false;
      // Odlozi dispose za jedan frame da DropdownSearch widget stigne da se unmount-uje
      WidgetsBinding.instance.addPostFrameCallback((_) {
        adresaController.dispose();
        telefonController.dispose();
        searchPutnikController.dispose();
      });
    });
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
                            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.25),
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
              gradient: V2ThemeManager().currentGradient, // ?? Dinamicki gradijent iz tema
            ),
            child: V2ShimmerWidgets.putnikListShimmer(itemCount: 8),
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
        stream: _streamPutnici,
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

          // Jedan prolaz: dedup + split na prikaz vs. bottom-bar brojaci
          final Map<String, V2Putnik> uniqueZaDan = {};
          final Map<String, V2Putnik> uniqueZaPrikaz = {};
          final normalizedDanBaza = V2GradAdresaValidator.normalizeString(_getDayAbbreviation(_selectedDay));
          final normalizedVreme = V2GradAdresaValidator.normalizeTime(_selectedVreme);

          for (final p in allPutnici) {
            if (!p.dan.toLowerCase().contains(targetDayAbbr.toLowerCase())) continue;
            final key = '${p.id}_${p.polazak}_${p.dan}';
            // Za bottom-bar brojace: samo dedup po danu
            uniqueZaDan[key] = p;
            // Za prikaz liste: dodatni filteri
            final normalizedStatus = V2TextUtils.normalizeText(p.status ?? '');
            if (normalizedStatus == 'obrada' || normalizedStatus == 'bez_polaska') continue;
            if (p.polazak.toString().trim().isEmpty) continue;
            if (p.grad.toString().trim().isEmpty) continue;
            if (!V2GradAdresaValidator.normalizeString(p.dan).contains(normalizedDanBaza)) continue;
            if (!V2GradAdresaValidator.isGradMatch(p.grad, p.adresa, _selectedGrad)) continue;
            if (V2GradAdresaValidator.normalizeTime(p.polazak) != normalizedVreme) continue;
            uniqueZaPrikaz[key] = p;
          }

          final sviPutniciBezDuplikata = uniqueZaPrikaz.values.toList();
          final countCandidates = uniqueZaDan.values.toList();

          // REFAKTORISANO: Koristi V2PutnikCountHelper za centralizovano brojanje
          final countHelper = V2PutnikCountHelper.fromPutnici(
            putnici: countCandidates,
            targetDateIso: targetDateIso,
            targetDayAbbr: targetDayAbbr,
          );

          // Uklonjen dupli sort - V2PutnikList sada sortira konzistentno sa V2VozacScreen
          // Sortiranje se vrsi u V2PutnikList widgetu sa istom logikom za sva tri ekrana
          final putniciZaPrikaz = sviPutniciBezDuplikata;

          // Funkcija za brojanje putnika po gradu, vremenu i danu
          int getPutnikCount(String grad, String vreme) {
            try {
              return countHelper.getCount(grad, vreme);
            } catch (e) {
              debugPrint('[V2HomeScreen] getPutnikCount error: $e');
              return 0;
            }
          }

          // (totalFilteredCount removed)

          return Container(
            decoration: BoxDecoration(
              gradient: V2ThemeManager().currentGradient, // Dinamicki gradijent iz tema
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
                              const V2RegistracijaTablicaWidget(),
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
                              const V2RegistracijaBrojacWidget(),
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
                                      color: V2VozacCache.getColor(_currentDriver), // opaque (100%)
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
                                    await V2ThemeManager().nextTheme();
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
                                      items: _dayNamesInternal
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
                                          setState(() {
                                            _selectedDay = value!;
                                            _updatePutniciStream(_selectedDay);
                                          });
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
                        if (_currentDriver != null &&
                            V2VozacCache.imenaVozaca.contains(_currentDriver) &&
                            !V2AdminSecurityService.isAdmin(_currentDriver))
                          Expanded(
                            child: _HomeScreenButton(
                              label: 'Ja',
                              icon: Icons.person,
                              onTap: () {
                                V2AnimatedNavigation.pushSmooth(
                                  context,
                                  V2VozacScreen(previewAsDriver: _currentDriver),
                                );
                              },
                            ),
                          ),
                        if (V2AdminSecurityService.isAdmin(_currentDriver)) ...[
                          const SizedBox(width: 4),
                          Expanded(
                            child: StreamBuilder<int>(
                              stream: _streamBrojZahteva,
                              builder: (context, snapshot) {
                                final count = snapshot.data ?? 0;
                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    _HomeScreenButton(
                                      label: 'Zahtevi',
                                      icon: Icons.notifications_active,
                                      onTap: () {
                                        V2AnimatedNavigation.pushSmooth(
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
                        if (V2AdminSecurityService.isAdmin(_currentDriver))
                          Expanded(
                            child: _HomeScreenButton(
                              label: 'Admin',
                              icon: Icons.admin_panel_settings,
                              onTap: () {
                                V2AnimatedNavigation.pushSmooth(
                                  context,
                                  const V2AdminScreen(),
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
                                await V2PrintingService.printPutniksList(
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
                                final vozac = await V2AuthManager.getCurrentDriver();
                                if (!mounted || vozac == null) return;
                                if (context.mounted) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (ctx) => V2PromenaSifreScreen(vozacIme: vozac),
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
                        : V2PutnikList(
                            putnici: putniciZaPrikaz,
                            currentDriver: _currentDriver!,
                            selectedGrad: _selectedGrad,
                            selectedVreme: _selectedVreme,
                            selectedDay: _getDayAbbreviation(_selectedDay),
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
        .map((row) => V2VozacRasporedEntry.fromMap(row))
        .where((r) => r.dan == dan && r.grad == grad && r.vreme == vreme)
        .firstOrNull;
    if (entry == null) return null;
    return V2VozacCache.getColor(entry.vozacId);
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
        return V2BottomNavBarPraznici(
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
        return V2BottomNavBarZimski(
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
        return V2BottomNavBarLetnji(
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
    // No overlay cleanup needed currently

    // ?? SAFE DISPOSAL ValueNotifier-a
    try {
      // No additional disposals needed
    } catch (e) {
      // Silently ignore
    }
    super.dispose();
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
