import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/route_config.dart'; // 🕐 RASPORED VREMENA
import '../constants/day_constants.dart';
import '../globals.dart';
import '../models/putnik.dart';
import '../services/admin_security_service.dart'; // 🛡️ ADMIN SECURITY
import '../services/app_settings_service.dart'; // ⚙️ NAV BAR SETTINGS
import '../services/firebase_service.dart';
import '../services/local_notification_service.dart';
import '../services/pin_zahtev_service.dart'; // 🔑 PIN ZAHTEVI
import '../services/putnik_service.dart'; // ⏪ VRAĆEN na stari servis zbog grešaka u novom
import '../services/realtime_notification_service.dart';
import '../services/statistika_service.dart'; // 📊 STATISTIKA
import '../services/theme_manager.dart';
import '../services/vozac_service.dart'; // 🛠️ VOZAC SERVIS
import '../theme.dart';
import '../utils/app_snack_bar.dart';
import '../utils/date_utils.dart' as app_date_utils;
import '../utils/vozac_cache.dart';
import '../widgets/dug_button.dart';
import 'adrese_screen.dart'; // 🏘️ Upravljanje adresama
import 'dugovi_screen.dart';
import 'finansije_screen.dart'; // 💰 Finansijski izveštaj
import 'gorivo_screen.dart'; // ⛽ Pumpa goriva
import 'kapacitet_screen.dart'; // DODANO za kapacitet polazaka
import 'odrzavanje_screen.dart'; // 🚛 Kolska knjiga - vozila
import 'pin_zahtevi_screen.dart'; // 🔑 PIN ZAHTEVI
import 'putnik_action_log_screen.dart'; // 👤 Dnevnik akcija putnika
import 'registrovani_putnici_screen.dart';
import 'vozac_action_log_screen.dart'; // 📋 Dnevnik akcija vozača
import 'vozac_screen.dart';
import 'vozaci_admin_screen.dart'; // Admin panel za upravljanje vozačima

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  String? _currentDriver;
  final PutnikService _putnikService = PutnikService(); // ⏪ VRAĆEN na stari servis zbog grešaka u novom

  // 🔑 PIN ZAHTEVI - broj zahteva koji čekaju
  int _brojPinZahteva = 0;
  // 🕒 TIMER MANAGEMENT - sada koristi TimerManager singleton umesto direktnog Timer-a

  //
  // Statistika pazara

  // Filter za dan - odmah postaviti na trenutni dan
  late String _selectedDan;

  @override
  void initState() {
    super.initState();
    final todayName = app_date_utils.DateUtils.getTodayFullName();
    // Admin screen supports all days now, including weekends
    _selectedDan = todayName;

    // 🗺️ FORSIRANA INICIJALIZACIJA VOZAC MAPIRANJA
    VozacCache.refresh();

    _loadCurrentDriver();
    _loadBrojPinZahteva(); // 🔑 Učitaj broj PIN zahteva

    // Inicijalizuj heads-up i zvuk notifikacije
    try {
      LocalNotificationService.initialize(context);
      // 🔕 UKLONJENO: listener se sada registruje globalno u main.dart
      // RealtimeNotificationService.listenForForegroundNotifications(context);
    } catch (e) {
      // Error handling - logging removed for production
    }

    FirebaseService.getCurrentDriver().then((driver) {
      if (driver != null && driver.isNotEmpty) {
        RealtimeNotificationService.initialize();
      }
    }).catchError((Object e) {
      // Error handling - logging removed for production
    });

    // Supabase realtime se koristi direktno
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Initialize realtime service
      try {
        // Pokreni refresh da osiguramo podatke
        _putnikService.getAllPutnici().then((data) {
          // Successfully retrieved passenger data
        }).catchError((Object e) {
          // Error handling - logging removed for production
        });
      } catch (e) {
        // Error handling - logging removed for production
      }
    });
  }

  @override
  void dispose() {
    // AdminScreen disposed
    super.dispose();
  }

  /// 📋 ACTION LOG PICKER DIALOG - Admin bira vozača za pregled dnevnika akcija
  void _showActionLogDialog(BuildContext context) async {
    try {
      final vozacService = VozacService();
      final vozaci = await vozacService.getAllVozaci();

      if (!mounted) return;

      if (vozaci.isEmpty) {
        AppSnackBar.error(context, '❌ Nema učitanih vozača');
        return;
      }

      if (!mounted) return;

      showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Izaberi vozača za dnevnik'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: vozaci.length,
                itemBuilder: (context, index) {
                  final vozac = vozaci[index];
                  final boja = vozac.color ?? const Color(0xFFBDBDBD);
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: boja,
                      child: Text(
                        vozac.ime[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(vozac.ime),
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (context) => VozacActionLogScreen(
                            vozacIme: vozac.ime,
                            datum: DateTime.now(),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Otkaži'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.error(context, 'Greška: $e');
    }
  }

  /// 👤 VOZAČ PICKER DIALOG - Admin može da vidi ekran bilo kog vozača
  void _showVozacPickerDialog(BuildContext context) async {
    // Asinkrono učitaj vozače iz baze umesto fallback vrednosti
    try {
      final vozacService = VozacService();
      final vozaci = await vozacService.getAllVozaci();

      if (!mounted) return;

      if (vozaci.isEmpty) {
        AppSnackBar.error(context, '❌ Nema učitanih vozača');
        return;
      }

      if (!mounted) return;

      showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Izaberi vozaca'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: vozaci.length,
                itemBuilder: (context, index) {
                  final vozac = vozaci[index];
                  final boja = vozac.color ?? Color(0xFFBDBDBD); // Gray fallback
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: boja,
                      child: Text(
                        vozac.ime[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(vozac.ime),
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (context) => VozacScreen(previewAsDriver: vozac.ime),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Otkaži'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error loading drivers: $e');
      if (!mounted) return;
      AppSnackBar.error(context, '❌ Greška pri učitavanju vozača');
    }
  }

  void _loadCurrentDriver() {
    FirebaseService.getCurrentDriver().then((driver) {
      if (mounted) {
        setState(() {
          _currentDriver = driver;
        });
      }
    }).catchError((Object e) {
      if (mounted) {
        setState(() {
          _currentDriver = null;
        });
      }
    });
  }

  // 🔑 Učitaj broj PIN zahteva koji čekaju
  Future<void> _loadBrojPinZahteva() async {
    try {
      final broj = await PinZahtevService.brojZahtevaKojiCekaju();
      if (mounted) {
        setState(() => _brojPinZahteva = broj);
      }
    } catch (e) {
      // Ignorišemo grešku, badge jednostavno neće prikazati broj
    }
  }

  /// 🚫 DIJALOG ZA GLOBALNO UKLANJANJE POLASKA
  void _showGlobalniBezPolaskaDialog() {
    String selectedGrad = 'BC';
    String selectedVreme = '05:00';
    String selectedDan = _selectedDan; // 🆕 Inicijalno uzmi trenutno izabrani dan
    bool isProcessing = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
        // Dohvati vremena za izabrani grad i trenutni režim (zimski/letnji/praznici)
        final navType = navBarTypeNotifier.value;
        List<String> vremena;
        if (selectedGrad == 'BC') {
          if (navType == 'praznici')
            vremena = ['Sva vremena', ...RouteConfig.bcVremenaPraznici];
          else if (navType == 'zimski')
            vremena = ['Sva vremena', ...RouteConfig.bcVremenaZimski];
          else
            vremena = ['Sva vremena', ...RouteConfig.bcVremenaLetnji];
        } else {
          if (navType == 'praznici')
            vremena = ['Sva vremena', ...RouteConfig.vsVremenaPraznici];
          else if (navType == 'zimski')
            vremena = ['Sva vremena', ...RouteConfig.vsVremenaZimski];
          else
            vremena = ['Sva vremena', ...RouteConfig.vsVremenaLetnji];
        }

        if (!vremena.contains(selectedVreme)) {
          selectedVreme = 'Sva vremena';
        }

        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ukloni polazak svima',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                selectedVreme == 'Sva vremena'
                    ? 'Ova akcija će SVIM putnicima u izabranom gradu za CEO DAN postaviti status "Bez polaska".'
                    : 'Ova akcija će svim putnicima u izabranom terminu postaviti status "Bez polaska".',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: selectedDan,
                decoration: const InputDecoration(labelText: 'Dan'),
                items: DayConstants.dayNamesInternal.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedDan = val);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedGrad,
                decoration: const InputDecoration(labelText: 'Grad'),
                items: [('BC', 'Bela Crkva'), ('VS', 'Vrsac')]
                    .map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedGrad = val);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedVreme,
                decoration: const InputDecoration(labelText: 'Vreme polaska'),
                items: vremena.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedVreme = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isProcessing ? null : () => Navigator.pop(context),
              child: const Text('Otkaži'),
            ),
            ElevatedButton(
              onPressed: isProcessing
                  ? null
                  : () async {
                      setDialogState(() => isProcessing = true);

                      final count = await _putnikService.globalniBezPolaska(
                        dan: selectedDan,
                        grad: selectedGrad,
                        vreme: selectedVreme,
                      );

                      if (mounted) {
                        Navigator.pop(context);
                        AppSnackBar.success(
                            context,
                            selectedVreme == 'Sva vremena'
                                ? '✅ Uspešno uklonjeno $count putnika za ceo dan ($selectedGrad) - $selectedDan'
                                : '✅ Uspešno uklonjeno $count putnika za $selectedVreme ($selectedGrad) - $selectedDan');
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: isProcessing
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('POTVRDI'),
            ),
          ],
        );
      }),
    );
  }

  // 📊 STATISTIKE MENI - otvara BottomSheet sa opcijama
  void _showStatistikeMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '📊 Statistike',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Text('💰', style: TextStyle(fontSize: 24)),
                  title: const Text('Finansije'),
                  subtitle: const Text('Prihodi, troškovi, neto zarada'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (context) => const FinansijeScreen(),
                      ),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Text('🚛', style: TextStyle(fontSize: 24)),
                  title: const Text('Kolska knjiga'),
                  subtitle: const Text('Servisi, registracija, gume...'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (context) => const OdrzavanjeScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Mapiranje punih imena dana u skraćice za filtriranje
  String _getShortDayName(String fullDayName) {
    final dayMapping = {
      'ponedeljak': 'Pon',
      'utorak': 'Uto',
      'sreda': 'Sre',
      'četvrtak': 'Čet',
      'petak': 'Pet',
    };
    final key = fullDayName.trim().toLowerCase();
    return dayMapping[key] ?? (fullDayName.isNotEmpty ? fullDayName.trim() : 'Pon');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: ThemeManager().currentGradient, // Theme-aware gradijent
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent, // Transparentna pozadina
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(147),
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
              // No boxShadow � keep AppBar fully transparent and only glass border
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    // ADMIN PANEL CONTAINER - levo
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            height: 20,
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'A D M I N   P A N E L',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Theme.of(context).colorScheme.onPrimary,
                                    letterSpacing: 1.8,
                                    shadows: const [
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
                          const SizedBox(height: 4),
                          // DRUGI RED - Putnici, Adrese, NavBar, Dropdown (4 dugmeta)
                          LayoutBuilder(
                            builder: (context, constraints) {
                              return Row(
                                children: [
                                  // PUTNICI
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (context) => const RegistrovaniPutniciScreen(),
                                        ),
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        height: 28,
                                        margin: const EdgeInsets.symmetric(horizontal: 1),
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).glassContainer,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
                                        ),
                                        child: const Center(
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              'Putnici',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                                color: Colors.white,
                                                shadows: [
                                                  Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  // ADRESE
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (context) => const AdreseScreen(),
                                        ),
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        height: 28,
                                        margin: const EdgeInsets.symmetric(horizontal: 1),
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).glassContainer,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
                                        ),
                                        child: const Center(
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              'Adrese',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                                color: Colors.white,
                                                shadows: [
                                                  Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  // NAV BAR DROPDOWN
                                  Expanded(
                                    child: ValueListenableBuilder<String>(
                                      valueListenable: navBarTypeNotifier,
                                      builder: (context, navType, _) {
                                        return Container(
                                          height: 28,
                                          margin: const EdgeInsets.symmetric(horizontal: 1),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context).glassContainer,
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
                                          ),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              value: navType,
                                              isExpanded: true,
                                              icon: const SizedBox.shrink(),
                                              dropdownColor: Theme.of(context).colorScheme.primary,
                                              style: const TextStyle(color: Colors.white, fontSize: 11),
                                              selectedItemBuilder: (context) {
                                                return ['zimski', 'letnji', 'praznici'].map((t) {
                                                  String label;
                                                  bool useEmoji = false;
                                                  switch (t) {
                                                    case 'zimski':
                                                      label = '❄️';
                                                      useEmoji = true;
                                                      break;
                                                    case 'letnji':
                                                      label = '☀️';
                                                      useEmoji = true;
                                                      break;
                                                    case 'praznici':
                                                      label = '🎄';
                                                      useEmoji = true;
                                                      break;
                                                    default:
                                                      label = t;
                                                  }
                                                  return Center(
                                                    child: Text(label,
                                                        style: TextStyle(
                                                            fontWeight: FontWeight.w600,
                                                            fontSize: useEmoji ? 14 : 11,
                                                            color: Colors.white)),
                                                  );
                                                }).toList();
                                              },
                                              items: const [
                                                DropdownMenuItem(value: 'zimski', child: Center(child: Text('Zimski'))),
                                                DropdownMenuItem(value: 'letnji', child: Center(child: Text('Letnji'))),
                                                DropdownMenuItem(
                                                    value: 'praznici', child: Center(child: Text('Praznici'))),
                                              ],
                                              onChanged: (value) {
                                                if (value != null) {
                                                  AppSettingsService.setNavBarType(value);
                                                }
                                              },
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),

                                  // DROPDOWN DANA
                                  Expanded(
                                    child: Container(
                                      height: 28,
                                      margin: const EdgeInsets.symmetric(horizontal: 1),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).glassContainer,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: _selectedDan,
                                          isExpanded: true,
                                          icon: const SizedBox.shrink(),
                                          dropdownColor: Theme.of(context).colorScheme.primary,
                                          style: const TextStyle(color: Colors.white),
                                          selectedItemBuilder: (context) {
                                            return DayConstants.dayNamesInternal.map((d) {
                                              return Center(
                                                  child: FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      child: Text(d,
                                                          style: const TextStyle(
                                                              color: Colors.white,
                                                              fontSize: 14,
                                                              fontWeight: FontWeight.w600))));
                                            }).toList();
                                          },
                                          items: DayConstants.dayNamesInternal.map((dan) {
                                            return DropdownMenuItem(
                                                value: dan,
                                                child: Center(
                                                    child: Text(dan,
                                                        style: const TextStyle(
                                                            fontSize: 14, fontWeight: FontWeight.w600))));
                                          }).toList(),
                                          onChanged: (value) {
                                            if (value != null && mounted) {
                                              setState(() => _selectedDan = value);
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 4),
                          // TRECI RED - Auth, PIN, Statistike, Dodeli (4 dugmeta)
                          LayoutBuilder(
                            builder: (context, constraints) {
                              return Row(
                                children: [
                                  // AUTH
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => Navigator.push(context,
                                          MaterialPageRoute<void>(builder: (context) => const VozaciAdminScreen())),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        height: 28,
                                        margin: const EdgeInsets.symmetric(horizontal: 1),
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).glassContainer,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
                                        ),
                                        child: const Center(
                                            child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Icon(Icons.lock, size: 20, color: Colors.white))),
                                      ),
                                    ),
                                  ),

                                  // PIN
                                  Expanded(
                                    child: InkWell(
                                      onTap: () async {
                                        await Navigator.push(context,
                                            MaterialPageRoute<void>(builder: (context) => const PinZahteviScreen()));
                                        _loadBrojPinZahteva();
                                      },
                                      borderRadius: BorderRadius.circular(12),
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Container(
                                            height: 28,
                                            margin: const EdgeInsets.symmetric(horizontal: 1),
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).glassContainer,
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(
                                                  color: _brojPinZahteva > 0
                                                      ? Colors.orange
                                                      : Theme.of(context).glassBorder,
                                                  width: 1.5),
                                            ),
                                            child: const Center(
                                                child: FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    child: Text('PIN',
                                                        style: TextStyle(
                                                            fontWeight: FontWeight.w600,
                                                            fontSize: 14,
                                                            color: Colors.white,
                                                            shadows: [
                                                              Shadow(
                                                                  offset: Offset(1, 1),
                                                                  blurRadius: 3,
                                                                  color: Colors.black54)
                                                            ])))),
                                          ),
                                          if (_brojPinZahteva > 0)
                                            Positioned(
                                              right: -4,
                                              top: -4,
                                              child: Container(
                                                padding: const EdgeInsets.all(4),
                                                decoration:
                                                    const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                                                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                                child: Text('$_brojPinZahteva',
                                                    style: const TextStyle(
                                                        color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                                    textAlign: TextAlign.center),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  // STATISTIKE (otvara meni sa opcijama)
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => _showStatistikeMenu(context),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        height: 28,
                                        margin: const EdgeInsets.symmetric(horizontal: 1),
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).glassContainer,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
                                        ),
                                        child: const Center(
                                            child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text('📊', style: TextStyle(fontSize: 14)))),
                                      ),
                                    ),
                                  ),

                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 4),
                          // CETVRTI RED - Vozac, Monitor, Mesta (3 dugmeta)
                          LayoutBuilder(
                            builder: (context, constraints) {
                              return Row(
                                children: [
                                  // VOZAC - Dropdown za admin preview
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => _showVozacPickerDialog(context),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        height: 28,
                                        margin: const EdgeInsets.symmetric(horizontal: 1),
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).glassContainer,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
                                        ),
                                        child: Center(
                                            child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: const Text('Vozač',
                                                    style: TextStyle(
                                                        fontWeight: FontWeight.w600,
                                                        fontSize: 14,
                                                        color: Colors.white,
                                                        shadows: [
                                                          Shadow(
                                                              offset: Offset(1, 1),
                                                              blurRadius: 3,
                                                              color: Colors.black54)
                                                        ])))),
                                      ),
                                    ),
                                  ),

                                  // DNEVNIK AKCIJA VOZAČA
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => _showActionLogDialog(context),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        height: 28,
                                        margin: const EdgeInsets.symmetric(horizontal: 1),
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).glassContainer,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
                                        ),
                                        child: const Center(
                                            child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text('📋',
                                                    style: TextStyle(
                                                        fontWeight: FontWeight.w600,
                                                        fontSize: 14,
                                                        color: Colors.white,
                                                        shadows: [
                                                          Shadow(
                                                              offset: Offset(1, 1),
                                                              blurRadius: 3,
                                                              color: Colors.black54)
                                                        ])))),
                                      ),
                                    ),
                                  ),

                                  // DNEVNIK AKCIJA PUTNIKA
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (context) => const PutnikActionLogScreen(),
                                        ),
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        height: 28,
                                        margin: const EdgeInsets.symmetric(horizontal: 1),
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).glassContainer,
                                          borderRadius: BorderRadius.circular(12),
                                          border:
                                              Border.all(color: const Color(0xFF5C6BC0).withOpacity(0.6), width: 1.5),
                                        ),
                                        child: const Center(
                                            child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text('👤',
                                                    style: TextStyle(
                                                        fontWeight: FontWeight.w600,
                                                        fontSize: 14,
                                                        color: Colors.white,
                                                        shadows: [
                                                          Shadow(
                                                              offset: Offset(1, 1),
                                                              blurRadius: 3,
                                                              color: Colors.black54)
                                                        ])))),
                                      ),
                                    ),
                                  ),

                                  // PUMPA GORIVA
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (context) => const GorivoScreen(),
                                        ),
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        height: 28,
                                        margin: const EdgeInsets.symmetric(horizontal: 1),
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).glassContainer,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.orange.withOpacity(0.7), width: 1.5),
                                        ),
                                        child: const Center(
                                            child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text('⛽',
                                                    style: TextStyle(
                                                        fontWeight: FontWeight.w600,
                                                        fontSize: 14,
                                                        color: Colors.white,
                                                        shadows: [
                                                          Shadow(
                                                              offset: Offset(1, 1),
                                                              blurRadius: 3,
                                                              color: Colors.black54)
                                                        ])))),
                                      ),
                                    ),
                                  ),

                                  // GLOBAL BEZ POLASKA
                                  Expanded(
                                    child: InkWell(
                                      onTap: _showGlobalniBezPolaskaDialog,
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        height: 28,
                                        margin: const EdgeInsets.symmetric(horizontal: 1),
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).glassContainer,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.red.withOpacity(0.5), width: 1.5),
                                        ),
                                        child: const Center(
                                            child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text('Bez polaska',
                                                    style: TextStyle(
                                                        fontWeight: FontWeight.w600,
                                                        fontSize: 14,
                                                        color: Colors.white,
                                                        shadows: [
                                                          Shadow(
                                                              offset: Offset(1, 1),
                                                              blurRadius: 3,
                                                              color: Colors.black54)
                                                        ])))),
                                      ),
                                    ),
                                  ),

                                  // MESTA
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => Navigator.push(context,
                                          MaterialPageRoute<void>(builder: (context) => const KapacitetScreen())),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        height: 28,
                                        margin: const EdgeInsets.symmetric(horizontal: 1),
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).glassContainer,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
                                        ),
                                        child: const Center(
                                            child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text('Mesta',
                                                    style: TextStyle(
                                                        fontWeight: FontWeight.w600,
                                                        fontSize: 14,
                                                        color: Colors.white,
                                                        shadows: [
                                                          Shadow(
                                                              offset: Offset(1, 1),
                                                              blurRadius: 3,
                                                              color: Colors.black54)
                                                        ])))),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    // NETWORK STATUS - desno
                    const SizedBox(width: 8),
                    const SizedBox.shrink(),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: StreamBuilder<List<Putnik>>(
          stream: _putnikService.streamPutnici(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              // Loading state - add refresh option to prevent infinite loading
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Učitavanje admin panela...'),
                  ],
                ),
              );
            }
            if (snapshot.hasError) {
              // Error handling - logging removed for production
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, color: Colors.red, size: 64),
                    const SizedBox(height: 16),
                    Text('Greška: ${snapshot.error}'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        if (mounted) setState(() {}); // Pokušaj ponovo
                      },
                      child: const Text('Pokušaj ponovo'),
                    ),
                  ],
                ),
              );
            }

            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final allPutnici = snapshot.data!;
            final filteredPutnici = allPutnici.where((putnik) {
              // 🕒 FILTER PO DANU - Samo po danu nedelje
              // Filtriraj po odabranom danu - case insensitive
              final shortDayName = _getShortDayName(_selectedDan).toLowerCase();
              return putnik.dan.toLowerCase() == shortDayName;
            }).toList();
            // 💰 DUŽNICI - putnici sa PLAVOM KARTICOM (nisu mesecni tip) koji nisu platili
            final filteredDuznici = filteredPutnici.where((putnik) {
              final nijeMesecni = !putnik.isMesecniTip;
              if (!nijeMesecni) {
                return false; // ✅ FIX: Plava kartica = nije mesecni tip
              }

              final nijePlatio = putnik.placeno != true; // ✅ FIX: Koristi placeno flag iz voznje_log
              final nijeOtkazan = putnik.status != 'otkazan' && putnik.status != 'Otkazano';
              final pokupljen = putnik.jePokupljen;

              // ✅ SVI (admin i vozači) vide SVE dužnike — vozači mogu naplatiti tuđe dugove
              return nijePlatio && nijeOtkazan && pokupljen;
            }).toList();

            // Izračunaj pazar po vozačima - KORISTI DIREKTNO filteredPutnici UMESTO DATUMA 🕒
            // ✅ ISPRAVKA: Umesto kalkulacije datuma, koristi već filtrirane putnike po danu
            // Ovo omogućava prikaz pazara za odabrani dan (Pon, Uto, itd.) direktno

            // 🕒 KALKULIRAJ DATUM NA OSNOVU DROPDOWN SELEKCIJE

            // Odabran je specifičan dan, pronađi taj dan u trenutnoj nedelji
            final now = DateTime.now();
            final currentWeekday = now.weekday; // 1=Pon, 2=Uto, 3=Sre, 4=Čet, 5=Pet

            // ✅ KORISTI CENTRALNU FUNKCIJU IZ DateUtils
            final targetWeekday = app_date_utils.DateUtils.getDayWeekdayNumber(_selectedDan);

            // 🕒 USKLADI SA DANAS SCREEN: Ako je odabrani dan isti kao danas, koristi današnji datum
            final DateTime targetDate;
            if (targetWeekday == currentWeekday) {
              // Isti dan kao danas - koristi današnji datum (kao danas screen)
              targetDate = now;
            } else {
              // Standardna logika za ostale dane
              final daysFromToday = targetWeekday - currentWeekday;
              targetDate = now.add(Duration(days: daysFromToday));
            }

            final streamFrom = DateTime(targetDate.year, targetDate.month, targetDate.day, 0, 0, 0);
            final streamTo = DateTime(targetDate.year, targetDate.month, targetDate.day, 23, 59, 59);

            // 🛰️ KORISTI StatistikaService.streamPazarZaSveVozace() - BEZ RxDart
            return StreamBuilder<Map<String, double>>(
              stream: StatistikaService.streamPazarZaSveVozace(from: streamFrom, to: streamTo),
              builder: (context, pazarSnapshot) {
                if (!pazarSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final pazarMap = pazarSnapshot.data!;

                // ✅ IDENTIČNA LOGIKA SA DANAS SCREEN: uzmi direktno vrednost iz mape
                final ukupno = pazarMap['_ukupno'] ?? 0.0;

                // Ukloni '_ukupno' ključ za čist prikaz
                final Map<String, double> pazar = Map.from(pazarMap)..remove('_ukupno');

                // 👤 FILTER PO VOZAČU - Prikaži samo naplate trenutnog vozača ili sve za admin
                // 🛡️ KORISTI ADMIN SECURITY SERVICE za filtriranje privilegija
                if (_currentDriver == null) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('⏳ Učitavanje...'),
                    ),
                  );
                }

                final bool isAdmin = AdminSecurityService.isAdmin(_currentDriver!);
                final Map<String, double> filteredPazar = AdminSecurityService.filterPazarByPrivileges(
                  _currentDriver!,
                  pazar,
                );

                final Map<String, Color> vozacBoje = VozacCache.bojeSync;
                final List<String> vozaciRedosled = [
                  'Bruda',
                  'Bilevski',
                  'Bojan',
                  'Voja',
                ];

                // Filter vozace redosled na osnovu trenutnog vozaca
                // ?? KORISTI ADMIN SECURITY SERVICE za filtriranje vozaca
                final List<String> prikazaniVozaci = AdminSecurityService.getVisibleDrivers(
                  _currentDriver!,
                  vozaciRedosled,
                );
                return SingleChildScrollView(
                  // ensure we respect device safe area / system nav bar at the
                  // bottom � some devices (Samsung) have a system bar which can
                  // cause a tiny overflow (2px on some screens). Add extra
                  // bottom padding based on MediaQuery so the content can scroll
                  // clear of system UI on all devices.
                  padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 12),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).padding.bottom + 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        //  Info box za individualnog vozaca
                        if (!isAdmin)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green[200]!),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.person,
                                  color: Colors.green[600],
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Prikazuju se samo VAŠE naplate, vozač: $_currentDriver',
                                    style: TextStyle(
                                      color: Colors.green[700],
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),
                        // 💰 VOZAČI PAZAR (BEZ DEPOZITA)
                        Column(
                          children: prikazaniVozaci
                              .map(
                                (vozac) => Container(
                                  width: double.infinity,
                                  height: 60,
                                  margin: const EdgeInsets.only(bottom: 4),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: (vozacBoje[vozac] ?? Colors.blueGrey).withAlpha(
                                      60,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: (vozacBoje[vozac] ?? Colors.blueGrey).withAlpha(
                                        120,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: vozacBoje[vozac] ?? Colors.blueGrey,
                                        radius: 16,
                                        child: Text(
                                          vozac[0],
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          vozac,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: vozacBoje[vozac] ?? Colors.blueGrey,
                                          ),
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.monetization_on,
                                            color: vozacBoje[vozac] ?? Colors.blueGrey,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            '${(filteredPazar[vozac] ?? 0.0).toStringAsFixed(0)} RSD',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: vozacBoje[vozac] ?? Colors.blueGrey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        DugButton(
                          brojDuznika: filteredDuznici.length,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (context) => DugoviScreen(
                                  // duznici: filteredDuznici,
                                  currentDriver: _currentDriver!,
                                ),
                              ),
                            );
                          },
                          wide: true,
                        ),
                        const SizedBox(height: 4),
                        // UKUPAN PAZAR
                        Container(
                          width: double.infinity,
                          // increased slightly to provide safe headroom across
                          // devices (prevent tiny 1�3px overflows caused by
                          // font metrics / shadows on some phones)
                          height: 76,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2), // Glassmorphism
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(context).glassBorder, // Transparentni border
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.account_balance_wallet,
                                color: Colors.green[700],
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    isAdmin ? 'UKUPAN PAZAR' : 'MOJ UKUPAN PAZAR',
                                    style: TextStyle(
                                      color: Colors.green[800],
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                  // ?? UKUPAN PAZAR (BEZ DEPOZITA)
                                  Text(
                                    '${(isAdmin ? ukupno : filteredPazar.values.fold(0.0, (sum, val) => sum + val)).toStringAsFixed(0)} RSD',
                                    style: TextStyle(
                                      color: Colors.green[900],
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // 📲 SMS TEST DUGME - samo za Bojan
                        if (_currentDriver?.toLowerCase() == 'bojan') ...[
                          // SMS test i debug funkcionalnost uklonjena - servis radi u pozadini
                        ],
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ), // Zatvaranje Scaffold
    ); // Zatvaranje Container
  }

  // (Funkcija za dijalog sa du�nicima je uklonjena - sada se koristi DugoviScreen)
}
