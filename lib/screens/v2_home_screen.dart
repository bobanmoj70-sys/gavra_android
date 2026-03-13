import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../config/v2_route_config.dart';
import '../globals.dart';
import '../models/v2_putnik.dart';
import '../models/v2_registrovani_putnik.dart';
import '../services/realtime/v2_master_realtime_manager.dart';
import '../services/v2_adresa_supabase_service.dart';
import '../services/v2_auth_manager.dart';
import '../services/v2_cena_obracun_service.dart';
import '../services/v2_haptic_service.dart';
import '../services/v2_kapacitet_service.dart';
import '../services/v2_local_notification_service.dart';
import '../services/v2_polasci_service.dart';
import '../services/v2_printing_service.dart';
import '../services/v2_racun_service.dart';
import '../services/v2_realtime_notification_service.dart';
import '../services/v2_statistika_istorija_service.dart';
import '../services/v2_theme_manager.dart';
import '../services/v2_vozac_raspored_service.dart';
import '../theme.dart';
import '../utils/v2_app_snack_bar.dart';
import '../utils/v2_dan_utils.dart';
import '../utils/v2_grad_adresa_validator.dart';
import '../utils/v2_page_transitions.dart';
import '../utils/v2_putnik_count_helper.dart';
import '../utils/v2_text_utils.dart';
import '../utils/v2_vozac_cache.dart';
import '../widgets/v2_bottom_nav_bar.dart';
import '../widgets/v2_putnik_list.dart';
import '../widgets/v2_registracija_countdown_widget.dart';
import 'v2_admin_screen.dart';
import 'v2_polasci_screen.dart';
import 'v2_vozac_screen.dart';
import 'v2_welcome_screen.dart';

class V2HomeScreen extends StatefulWidget {
  const V2HomeScreen({super.key});

  @override
  State<V2HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<V2HomeScreen> with TickerProviderStateMixin {
  bool _isLoading = true;
  String _selectedDay = 'pon'; // kratica: 'pon','uto','sre','cet','pet' â€” postavlja se u initState
  String _selectedGrad = 'BC';
  String _selectedVreme = '05:00'; // inicijalna vrednost, overriduje se u initState

  String? _currentDriver;

  late final Stream<int> _streamBrojZahteva;
  late Stream<List<V2Putnik>> _putniciStream;

  late final List<String> _sviPolasci;

  /// Automatski selektuje najbliÅ¾e vreme polaska za trenutni cas (BC grad).

  @override
  void initState() {
    super.initState();
    final bcList = V2RouteConfig.getVremenaByNavType('BC').map((v) => '$v BC').toList();
    final vsList = V2RouteConfig.getVremenaByNavType('VS').map((v) => '$v VS').toList();
    _sviPolasci = [...bcList, ...vsList];
    final today = DateTime.now().weekday;
    // Vikend â†’ defaultuj na Ponedeljak (firma ne radi vikendom)
    _selectedDay = (today == DateTime.saturday || today == DateTime.sunday) ? 'pon' : V2DanUtils.danas();
    _streamBrojZahteva = V2PolasciService.v2StreamBrojZahteva();
    // Jedan stream po trenutnom danu â€” v2StreamFromCache u RM-u ne zatvara controller
    // kad nema listenera, pa swap dana u _onDayChanged kreira novi .map() wrapper
    // koji se zakaÄi na isti aktivni RM broadcast.
    _putniciStream = V2PolasciService.streamPutniciZaDan(_selectedDay);
    _initializeData();
  }

  void _onDayChanged(String day) {
    setState(() {
      _selectedDay = day;
      // Kreira novi .map() wrapper na isti RM broadcast stream â€” 0 DB upita, 0 WebSocket konekcija.
      _putniciStream = V2PolasciService.streamPutniciZaDan(day);
    });
  }

  Future<void> _initializeData() async {
    try {
      await _initializeCurrentDriver();
      // PreskoÄiti redirect ako V2VozacCache joÅ¡ nije inicijalizovan (race condition)
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

      if (mounted) {
        V2LocalNotificationService.initialize(context);
      }

      final notifDriver = _currentDriver;
      if (mounted && notifDriver != null && notifDriver.isNotEmpty) {
        await V2RealtimeNotificationService.requestNotificationPermissions();
        if (mounted) {
          await V2RealtimeNotificationService.initialize();
          if (mounted) {
            V2RealtimeNotificationService.subscribeToDriverTopics(notifDriver);
          }
        }
      }

      if (mounted) {
        setState(() {
          _selectClosestDeparture();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _initializeCurrentDriver() async {
    final driver = await V2AuthManager.getCurrentDriver();
    if (mounted) _currentDriver = driver;
  }

  /// ?? Bira polazak koji je najbliÅ¾i trenutnom vremenu (bez setState â€” poziva se unutar setState bloka)
  void _selectClosestDeparture() {
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

      final diff = (polazakMinutes - currentMinutes).abs();

      if (diff < minDifference) {
        minDifference = diff;
        closestVreme = timeStr;
        closestGrad = gradStr;
      }
    }

    if (closestVreme != null && closestGrad != null) {
      _selectedVreme = closestVreme;
      _selectedGrad = closestGrad;
    }
  }

  Future<void> _showRacunDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => const _RacunDialog(),
    );
  }

  void _showNoviRacunDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => const _NoviRacunDialog(),
    );
  }

  Future<void> _showAddPutnikDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DodajPutnikDialog(
        selectedGrad: _selectedGrad,
        selectedVreme: _selectedVreme,
        selectedDay: _selectedDay,
        currentDriver: _currentDriver,
        onPutnikDodat: (novoVreme) {
          if (mounted) setState(() => _selectedVreme = novoVreme);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: StreamBuilder<List<V2Putnik>>(
        stream: _putniciStream,
        builder: (context, snapshot) {
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
              body: Center(
                child: Text(
                  'GreÅ¡ka pri uÄitavanju: ${snapshot.error}',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final allPutnici = snapshot.data ?? [];
          final normalizedVreme = V2GradAdresaValidator.normalizeTime(_selectedVreme);
          final Map<String, V2Putnik> uniqueZaDan = {};
          final Map<String, V2Putnik> uniqueZaPrikaz = {};

          for (final p in allPutnici) {
            // Dan je veÄ‡ filtriran u streamPutniciZaDan â€” svi putnici su za _selectedDay
            final key = '${p.id}_${p.polazak}_${p.dan}';
            uniqueZaDan[key] = p;
            final normalizedStatus = V2TextUtils.normalizeText(p.status ?? '');
            if (normalizedStatus == 'obrada') continue;
            if (p.polazak.toString().trim().isEmpty) continue;
            if (p.grad.toString().trim().isEmpty) continue;
            if (!V2GradAdresaValidator.isGradMatch(p.grad, p.adresa, _selectedGrad)) continue;
            if (V2GradAdresaValidator.normalizeTime(p.polazak) != normalizedVreme) continue;
            uniqueZaPrikaz[key] = p;
          }

          final putniciZaPrikaz = uniqueZaPrikaz.values.toList();
          final countHelper = V2PutnikCountHelper.fromPutnici(
            putnici: uniqueZaDan.values.toList(),
            targetDayAbbr: _selectedDay,
          );

          int getPutnikCount(String grad, String vreme) => countHelper.getCount(grad, vreme);

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
                                                V2DanUtils.puniNaziv(_selectedDay),
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
                                      items: V2DanUtils.kratice
                                          .map(
                                            (dan) => DropdownMenuItem(
                                              value: dan,
                                              child: Center(
                                                child: Text(
                                                  V2DanUtils.puniNaziv(dan),
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
                                        if (value == null || !mounted) return;
                                        _onDayChanged(value);
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
                          child: _StampajMenuButton(
                            onPrintSpisak: () => V2PrintingService.printPutniksList(
                              _selectedDay,
                              _selectedVreme,
                              _selectedGrad,
                              context,
                            ),
                            onRacunPostojeci: _showRacunDialog,
                            onRacunNovi: _showNoviRacunDialog,
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
                            currentDriver: _currentDriver ?? '',
                            selectedGrad: _selectedGrad,
                            selectedVreme: _selectedVreme,
                            selectedDay: _selectedDay,
                            bcVremena: V2RouteConfig.getVremenaByNavType('BC'),
                            vsVremena: V2RouteConfig.getVremenaByNavType('VS'),
                          ),
                  ),
                ],
              ),
              bottomNavigationBar: ValueListenableBuilder<String>(
                valueListenable: navBarTypeNotifier,
                builder: (context, navType, _) {
                  return V2BottomNavBar(
                    sviPolasci: _sviPolasci,
                    selectedGrad: _selectedGrad,
                    selectedVreme: _selectedVreme,
                    getPutnikCount: getPutnikCount,
                    getKapacitet: (grad, vreme) => V2KapacitetService.getKapacitetSync(grad, vreme),
                    onPolazakChanged: (grad, vreme) {
                      if (mounted)
                        setState(() {
                          _selectedGrad = grad;
                          _selectedVreme = vreme;
                        });
                    },
                    selectedDan: _selectedDay,
                    showVozacBoja: true,
                    getVozacColor: _getVozacColorForTermin,
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Color? _getVozacColorForTermin(String grad, String vreme) {
    final dan = _selectedDay;
    final entry = V2MasterRealtimeManager.instance.rasporedCache.values
        .map((row) => V2VozacRasporedEntry.fromMap(row))
        .where((r) => r.dan == dan && r.grad == grad && r.vreme == vreme)
        .firstOrNull;
    if (entry == null) return null;
    return V2VozacCache.getColor(entry.vozacId);
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
          // no boxShadow Å¾ keep transparent glass + border only
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

Widget _homeGlassStatRow(String label, String value) {
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

// â”€â”€â”€ _StampajMenuButton â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _StampajMenuButton extends StatelessWidget {
  const _StampajMenuButton({
    required this.onPrintSpisak,
    required this.onRacunPostojeci,
    required this.onRacunNovi,
  });
  final VoidCallback onPrintSpisak;
  final VoidCallback onRacunPostojeci;
  final VoidCallback onRacunNovi;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Å¡tampaj',
      offset: const Offset(0, -150),
      onSelected: (value) {
        if (value == 'spisak')
          onPrintSpisak();
        else if (value == 'racun_postojeci')
          onRacunPostojeci();
        else if (value == 'racun_novi') onRacunNovi();
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'spisak',
          child: Row(children: [Icon(Icons.list_alt, color: Colors.blue), SizedBox(width: 8), Text('Å¡tampaj spisak')]),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'racun_postojeci',
          child:
              Row(children: [Icon(Icons.people, color: Colors.green), SizedBox(width: 8), Text('Racun - postojeci')]),
        ),
        PopupMenuItem(
          value: 'racun_novi',
          child:
              Row(children: [Icon(Icons.person_add, color: Colors.orange), SizedBox(width: 8), Text('Racun - novi')]),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Theme.of(context).glassContainer,
          border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.print, color: Theme.of(context).colorScheme.onPrimary, size: 18),
            const SizedBox(height: 4),
            const SizedBox(
              height: 16,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child:
                    Text('Å¡tampaj', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€â”€ _RacunDialog â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _RacunDialog extends StatefulWidget {
  const _RacunDialog();

  @override
  State<_RacunDialog> createState() => _RacunDialogState();
}

class _RacunDialogState extends State<_RacunDialog> {
  late List<V2RegistrovaniPutnik> _putnici;
  late Map<String, bool> _selected;
  late Map<String, int> _brojDana;
  late Map<String, TextEditingController> _ctrls;
  DateTime _selectedDate = DateTime.now();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final svi = V2StatistikaIstorijaService.getAllAktivniKaoModel();
    _putnici = svi.where((p) => p.trebaRacun).toList();
    _selected = {for (var p in _putnici) p.id: true};
    _brojDana = {for (var p in _putnici) p.id: 0};
    _ctrls = {for (var p in _putnici) p.id: TextEditingController(text: '0')};
    _ucitaj();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) c.dispose();
    super.dispose();
  }

  Future<void> _ucitaj() async {
    if (_putnici.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final counts = await V2CenaObracunService.prebrojJediniceMasovno(
      putnici: _putnici,
      mesec: _selectedDate.month,
      godina: _selectedDate.year,
    );
    if (!mounted) return;
    setState(() {
      for (var p in _putnici) {
        _brojDana[p.id] = counts[p.id] ?? 0;
        _ctrls[p.id]?.text = (counts[p.id] ?? 0).toString();
      }
      _loading = false;
    });
  }

  Future<void> _promeniMesec(int delta) async {
    setState(() {
      _loading = true;
      _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + delta);
    });
    await _ucitaj();
  }

  @override
  Widget build(BuildContext context) {
    if (_putnici.isEmpty && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
        V2AppSnackBar.warning(context, 'Nema putnika kojima treba racun');
      });
      return const SizedBox.shrink();
    }

    double ukupno = 0;
    for (var p in _putnici) {
      if (_selected[p.id] == true) {
        ukupno += V2CenaObracunService.getCenaPoDanu(p) * (_brojDana[p.id] ?? 0);
      }
    }
    final mesecStr = DateFormat('MMMM yyyy', 'sr_Latn').format(_selectedDate);

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
          border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.2), blurRadius: 15, spreadRadius: 2, offset: const Offset(0, 8))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Zaglavlje
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).glassContainer,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(bottom: BorderSide(color: Theme.of(context).glassBorder)),
              ),
              child: Column(
                children: [
                  const Row(children: [
                    Icon(Icons.receipt_long, color: Colors.white),
                    SizedBox(width: 8),
                    Expanded(
                        child: Text('Racuni za Å¡tampanje',
                            style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold))),
                  ]),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left, color: Colors.white),
                        onPressed: _loading ? null : () => _promeniMesec(-1),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(mesecStr,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right, color: Colors.white),
                        onPressed: _loading ? null : () => _promeniMesec(1),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Lista putnika
            Flexible(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ..._putnici.map((p) {
                            final cena = V2CenaObracunService.getCenaPoDanu(p);
                            final dana = _brojDana[p.id] ?? 0;
                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: _selected[p.id],
                                      activeColor: Colors.white,
                                      checkColor: Theme.of(context).colorScheme.primary,
                                      side: const BorderSide(color: Colors.white70),
                                      onChanged: (val) => setState(() => _selected[p.id] = val ?? false),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(p.ime,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis),
                                          Text(
                                              '${cena.toStringAsFixed(0)} RSD Ã— $dana dana = ${(cena * dana).toStringAsFixed(0)} RSD',
                                              style: const TextStyle(fontSize: 11, color: Colors.white70)),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: 55,
                                      child: Column(
                                        children: [
                                          const Text('Dana', style: TextStyle(fontSize: 10, color: Colors.white70)),
                                          TextField(
                                            keyboardType: TextInputType.number,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                                            decoration: const InputDecoration(
                                              isDense: true,
                                              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                                              border:
                                                  UnderlineInputBorder(borderSide: BorderSide(color: Colors.white70)),
                                              enabledBorder:
                                                  UnderlineInputBorder(borderSide: BorderSide(color: Colors.white70)),
                                              focusedBorder:
                                                  UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                                            ),
                                            controller: _ctrls[p.id],
                                            onChanged: (val) =>
                                                setState(() => _brojDana[p.id] = int.tryParse(val) ?? 0),
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('UKUPNO:',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                              Text('${ukupno.toStringAsFixed(0)} RSD',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 18, color: Colors.greenAccent)),
                            ],
                          ),
                        ],
                      ),
                    ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).glassContainer,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('OtkaÅ¾i', style: TextStyle(color: Colors.white70)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.print),
                    label: const Text('Å¡tampaj sve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      final racuniPodaci = <Map<String, dynamic>>[];
                      for (var p in _putnici) {
                        if (_selected[p.id] == true) {
                          final cena = V2CenaObracunService.getCenaPoDanu(p);
                          final dana = _brojDana[p.id] ?? 0;
                          racuniPodaci
                              .add({'V2Putnik': p, 'brojDana': dana, 'cenaPoDanu': cena, 'ukupno': cena * dana});
                        }
                      }
                      if (racuniPodaci.isEmpty) {
                        V2AppSnackBar.warning(context, 'Izaberite bar jednog putnika');
                        return;
                      }
                      Navigator.pop(context);
                      await V2RacunService.stampajRacuneZaFirme(
                        racuniPodaci: racuniPodaci,
                        context: context,
                        datumPrometa: _selectedDate,
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
  }
}

// â”€â”€â”€ _NoviRacunDialog â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _NoviRacunDialog extends StatefulWidget {
  const _NoviRacunDialog();

  @override
  State<_NoviRacunDialog> createState() => _NoviRacunDialogState();
}

class _NoviRacunDialogState extends State<_NoviRacunDialog> {
  final _imeCtrl = TextEditingController();
  final _iznosCtrl = TextEditingController();
  final _opisCtrl = TextEditingController(text: 'Usluga prevoza putnika');
  String _jm = 'usluga';

  @override
  void dispose() {
    _imeCtrl.dispose();
    _iznosCtrl.dispose();
    _opisCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.receipt_long, color: Colors.orange),
        SizedBox(width: 8),
        Text('Novi racun'),
      ]),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _imeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ime i prezime kupca *',
                  hintText: 'npr. Marko Markovic',
                  prefixIcon: Icon(Icons.person),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _opisCtrl,
                decoration: const InputDecoration(
                  labelText: 'Opis usluge *',
                  hintText: 'npr. Prevoz Beograd-Vrsac',
                  prefixIcon: Icon(Icons.description),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _jm,
                decoration: const InputDecoration(labelText: 'Jedinica mere', prefixIcon: Icon(Icons.straighten)),
                items: const [
                  DropdownMenuItem(value: 'usluga', child: Text('usluga')),
                  DropdownMenuItem(value: 'dan', child: Text('dan')),
                  DropdownMenuItem(value: 'kom', child: Text('kom')),
                  DropdownMenuItem(value: 'sat', child: Text('sat')),
                  DropdownMenuItem(value: 'km', child: Text('km')),
                ],
                onChanged: (val) => setState(() => _jm = val ?? 'usluga'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _iznosCtrl,
                decoration: const InputDecoration(
                  labelText: 'Iznos (RSD) *',
                  hintText: 'npr. 5000',
                  prefixIcon: Icon(Icons.attach_money),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              const Text('* Obavezna polja', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OtkaÅ¾i'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.print),
          label: const Text('Å¡tampaj'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          onPressed: () async {
            if (_imeCtrl.text.trim().isEmpty) {
              V2AppSnackBar.warning(context, 'Unesite ime kupca');
              return;
            }
            if (_opisCtrl.text.trim().isEmpty) {
              V2AppSnackBar.warning(context, 'Unesite opis usluge');
              return;
            }
            final iznos = double.tryParse(_iznosCtrl.text.trim().replaceAll(',', '.'));
            if (iznos == null || iznos <= 0) {
              V2AppSnackBar.warning(context, 'Unesite validan iznos');
              return;
            }
            final ime = _imeCtrl.text.trim();
            final opis = _opisCtrl.text.trim();
            final jm = _jm;
            final ctx = context;
            Navigator.pop(context);
            final brojRacuna = await V2RacunService.getNextBrojRacuna();
            if (!ctx.mounted) return;
            await V2RacunService.stampajRacun(
              brojRacuna: brojRacuna,
              imePrezimeKupca: ime,
              adresaKupca: '',
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
  }
}

// â”€â”€â”€ _DodajPutnikDialog â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _DodajPutnikDialog extends StatefulWidget {
  const _DodajPutnikDialog({
    required this.selectedGrad,
    required this.selectedVreme,
    required this.selectedDay,
    required this.currentDriver,
    required this.onPutnikDodat,
  });
  final String selectedGrad;
  final String selectedVreme;
  final String selectedDay;
  final String? currentDriver;
  final void Function(String novoVreme) onPutnikDodat;

  @override
  State<_DodajPutnikDialog> createState() => _DodajPutnikDialogState();
}

class _DodajPutnikDialogState extends State<_DodajPutnikDialog> {
  final _adresaCtrl = TextEditingController();
  final _telefonCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  bool _dialogActive = true;
  V2RegistrovaniPutnik? _selectedPutnik;
  int _brojMesta = 1;
  bool _promeniAdresuSamoDanas = false;
  String? _samoDanasAdresa;
  String? _samoDanasAdresaId;
  bool _isLoading = false;

  late final List<V2RegistrovaniPutnik> _aktivniPutnici;
  late final List<Map<String, String>> _dostupneAdrese;
  late final List<DropdownMenuItem<String>> _adresaDropdownItems;
  static const _brojMestaItems = [
    DropdownMenuItem<int>(value: 1, child: Text('1 mesto', style: TextStyle(fontSize: 16))),
    DropdownMenuItem<int>(value: 2, child: Text('2 mesta', style: TextStyle(fontSize: 16))),
    DropdownMenuItem<int>(value: 3, child: Text('3 mesta', style: TextStyle(fontSize: 16))),
    DropdownMenuItem<int>(value: 4, child: Text('4 mesta', style: TextStyle(fontSize: 16))),
    DropdownMenuItem<int>(value: 5, child: Text('5 mesta', style: TextStyle(fontSize: 16))),
  ];

  @override
  void initState() {
    super.initState();
    final lista = V2StatistikaIstorijaService.getAllAktivniKaoModel();
    _aktivniPutnici = lista.where((p) => p.aktivan).toList()
      ..sort((a, b) => a.ime.toLowerCase().compareTo(b.ime.toLowerCase()));
    final adrese = V2AdresaSupabaseService.getAdreseZaGrad(widget.selectedGrad);
    _dostupneAdrese = adrese.map((a) => {'id': a.id, 'naziv': a.naziv}).toList()
      ..sort((a, b) => (a['naziv'] ?? '').compareTo(b['naziv'] ?? ''));
    _adresaDropdownItems = _dostupneAdrese
        .map((a) => DropdownMenuItem<String>(
              value: a['id'],
              child:
                  Text(a['naziv'] ?? '', overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black)),
            ))
        .toList();
  }

  @override
  void dispose() {
    _dialogActive = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _adresaCtrl.dispose();
      _telefonCtrl.dispose();
      _searchCtrl.dispose();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 24,
        bottom: keyboardHeight > 0 ? 8 : 24,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: keyboardHeight > 0 ? (screenHeight - keyboardHeight) * 0.85 : screenHeight * 0.7,
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        decoration: BoxDecoration(
          gradient: Theme.of(context).backgroundGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.2), blurRadius: 15, spreadRadius: 2, offset: const Offset(0, 8))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Zaglavlje
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).glassContainer,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(bottom: BorderSide(color: Theme.of(context).glassBorder)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Dodaj Putnika',
                        style: TextStyle(
                          fontSize: 22,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
                        )),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            // Tijelo
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Informacije o ruti
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).glassContainer,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Theme.of(context).glassBorder),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 4))
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Informacije o ruti',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                fontSize: 16,
                                shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
                              )),
                          const SizedBox(height: 12),
                          _homeGlassStatRow('â° Vreme:', widget.selectedVreme),
                          _homeGlassStatRow('ðŸ“ Grad:', widget.selectedGrad),
                          _homeGlassStatRow('ðŸ“… Dan:', V2DanUtils.puniNaziv(widget.selectedDay)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Podaci o putniku
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).glassContainer,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Theme.of(context).glassBorder),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 4))
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Podaci o putniku',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                fontSize: 16,
                                shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
                              )),
                          const SizedBox(height: 16),
                          DropdownButtonFormField2<V2RegistrovaniPutnik>(
                            isExpanded: true,
                            value: _selectedPutnik,
                            decoration: InputDecoration(
                              labelText: 'Izaberi putnika',
                              hintText: 'PretraÅ¾i i izaberi...',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              prefixIcon: Icon(Icons.person_search, color: Theme.of(context).colorScheme.primary),
                              fillColor: Colors.white,
                              filled: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            dropdownStyleData: DropdownStyleData(
                              maxHeight: 300,
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.white),
                            ),
                            dropdownSearchData: DropdownSearchData(
                              searchController: _searchCtrl,
                              searchInnerWidgetHeight: 50,
                              searchInnerWidget: Container(
                                height: 50,
                                padding: const EdgeInsets.only(top: 8, bottom: 4, right: 8, left: 8),
                                child: TextFormField(
                                  controller: _searchCtrl,
                                  expands: true,
                                  maxLines: null,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    hintText: 'PretraÅ¾i po imenu...',
                                    hintStyle: const TextStyle(fontSize: 14),
                                    prefixIcon: const Icon(Icons.search, size: 20),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                              searchMatchFn: (item, searchValue) =>
                                  item.value?.ime.toLowerCase().contains(searchValue.toLowerCase()) ?? false,
                            ),
                            items: _aktivniPutnici
                                .map((p) => DropdownMenuItem<V2RegistrovaniPutnik>(
                                      value: p,
                                      child: Row(
                                        children: [
                                          Icon(
                                            p.v2Tabela == 'v2_radnici'
                                                ? Icons.engineering
                                                : p.v2Tabela == 'v2_dnevni'
                                                    ? Icons.today
                                                    : Icons.school,
                                            size: 18,
                                            color: p.v2Tabela == 'v2_radnici'
                                                ? Colors.blue.shade600
                                                : p.v2Tabela == 'v2_dnevni'
                                                    ? Colors.orange.shade600
                                                    : Colors.green.shade600,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(child: Text(p.ime, overflow: TextOverflow.ellipsis)),
                                        ],
                                      ),
                                    ))
                                .toList(),
                            onChanged: (p) async {
                              if (!_dialogActive) return;
                              setState(() {
                                _selectedPutnik = p;
                                _telefonCtrl.text = p?.telefon ?? '';
                                _adresaCtrl.text = 'Ucitavanje...';
                              });
                              if (p != null) {
                                final adresa = p.getAdresaZaSelektovaniGrad(widget.selectedGrad);
                                if (!_dialogActive) return;
                                setState(() {
                                  _adresaCtrl.text = adresa == 'Nema adresa' ? '' : adresa;
                                  _promeniAdresuSamoDanas = false;
                                  _samoDanasAdresa = null;
                                  _samoDanasAdresaId = null;
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _adresaCtrl,
                            readOnly: true,
                            decoration: InputDecoration(
                              labelText: _promeniAdresuSamoDanas ? 'Stalna adresa' : 'Adresa',
                              hintText: 'Automatski se popunjava...',
                              prefixIcon: const Icon(Icons.location_on),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                              fillColor: Colors.grey.shade100,
                            ),
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () => setState(() {
                              _promeniAdresuSamoDanas = !_promeniAdresuSamoDanas;
                              if (!_promeniAdresuSamoDanas) {
                                _samoDanasAdresa = null;
                                _samoDanasAdresaId = null;
                              }
                            }),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: _promeniAdresuSamoDanas,
                                  onChanged: (val) => setState(() {
                                    _promeniAdresuSamoDanas = val ?? false;
                                    if (!_promeniAdresuSamoDanas) {
                                      _samoDanasAdresa = null;
                                      _samoDanasAdresaId = null;
                                    }
                                  }),
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  side: const BorderSide(color: Colors.white, width: 2),
                                  checkColor: Colors.white,
                                  activeColor: Colors.orange,
                                ),
                                const Expanded(
                                    child: Text('Promeni adresu samo za danas',
                                        style: TextStyle(fontSize: 14, color: Colors.white))),
                              ],
                            ),
                          ),
                          if (_promeniAdresuSamoDanas) ...[
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _samoDanasAdresaId,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Adresa samo za danas',
                                labelStyle: TextStyle(color: Colors.grey.shade700),
                                prefixIcon: const Icon(Icons.edit_location_alt, color: Colors.orange),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Colors.orange)),
                                enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.orange.shade300)),
                                focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Colors.orange, width: 2)),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              dropdownColor: Colors.white,
                              style: const TextStyle(color: Colors.black),
                              items: _adresaDropdownItems,
                              onChanged: (val) => setState(() {
                                _samoDanasAdresaId = val;
                                _samoDanasAdresa =
                                    _dostupneAdrese.firstWhere((a) => a['id'] == val, orElse: () => {})['naziv'];
                              }),
                              hint: Text('Izaberi adresu', style: TextStyle(color: Colors.grey.shade600)),
                            ),
                          ],
                          const SizedBox(height: 12),
                          TextField(
                            controller: _telefonCtrl,
                            readOnly: true,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: 'Telefon',
                              hintText: 'Automatski se popunjava...',
                              prefixIcon: const Icon(Icons.phone),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                              fillColor: Colors.grey.shade100,
                            ),
                          ),
                          const SizedBox(height: 12),
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
                                const Flexible(
                                    child: Text('Broj mesta:',
                                        style: TextStyle(fontSize: 16), overflow: TextOverflow.ellipsis)),
                                const SizedBox(width: 8),
                                DropdownButton<int>(
                                  value: _brojMesta,
                                  underline: const SizedBox(),
                                  isDense: true,
                                  items: _brojMestaItems,
                                  onChanged: (v) {
                                    if (v != null) setState(() => _brojMesta = v);
                                  },
                                ),
                              ],
                            ),
                          ),
                          if (_selectedPutnik != null)
                            Container(
                              margin: const EdgeInsets.only(top: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _selectedPutnik!.v2Tabela == 'v2_radnici'
                                    ? Colors.blue.withValues(alpha: 0.15)
                                    : _selectedPutnik!.v2Tabela == 'v2_dnevni'
                                        ? Colors.orange.withValues(alpha: 0.15)
                                        : Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _selectedPutnik!.v2Tabela == 'v2_radnici'
                                      ? Colors.blue.withValues(alpha: 0.4)
                                      : _selectedPutnik!.v2Tabela == 'v2_dnevni'
                                          ? Colors.orange.withValues(alpha: 0.4)
                                          : Colors.green.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _selectedPutnik!.v2Tabela == 'v2_radnici'
                                        ? Icons.engineering
                                        : _selectedPutnik!.v2Tabela == 'v2_dnevni'
                                            ? Icons.today
                                            : Icons.school,
                                    size: 20,
                                    color: _selectedPutnik!.v2Tabela == 'v2_radnici'
                                        ? Colors.blue.shade700
                                        : _selectedPutnik!.v2Tabela == 'v2_dnevni'
                                            ? Colors.orange.shade700
                                            : Colors.green.shade700,
                                  ),
                                  const SizedBox(width: 8),
                                  Text('Tip: ${_selectedPutnik!.v2Tabela.toUpperCase()}',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: _selectedPutnik!.v2Tabela == 'v2_radnici'
                                              ? Colors.blue.shade700
                                              : _selectedPutnik!.v2Tabela == 'v2_dnevni'
                                                  ? Colors.orange.shade700
                                                  : Colors.green.shade700)),
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
            // Footer
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).glassContainer,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                border: Border(top: BorderSide(color: Theme.of(context).glassBorder)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                      ),
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OtkaÅ¾i',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
                            )),
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    flex: 2,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.green.withValues(alpha: 0.6)),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 4))
                        ],
                      ),
                      child: V2HapticElevatedButton(
                        hapticType: HapticType.success,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                        onPressed: _isLoading ? null : _dodajPutnika,
                        child: _isLoading
                            ? const Row(mainAxisSize: MainAxisSize.min, children: [
                                SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                                SizedBox(width: 8),
                                Text('Dodaje...',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
                              ])
                            : const Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.person_add, color: Colors.white, size: 20),
                                SizedBox(width: 8),
                                Text('Dodaj',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                      shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
                                    )),
                              ]),
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
  }

  Future<void> _dodajPutnika() async {
    if (_selectedPutnik == null) {
      V2AppSnackBar.error(context, 'âŒ Morate odabrati putnika iz liste');
      return;
    }
    if (widget.selectedVreme.isEmpty || widget.selectedGrad.isEmpty) {
      V2AppSnackBar.error(context, 'âŒ GreÅ¡ka: Nije odabrano vreme polaska');
      return;
    }
    final driver = widget.currentDriver;
    if (driver == null || driver.isEmpty || !V2VozacCache.isValidIme(driver)) {
      V2AppSnackBar.error(context, 'âŒ GREÅ KA: VozaÄ "$driver" nije registrovan. Molimo ponovo se ulogujte.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final adresa = _promeniAdresuSamoDanas && _samoDanasAdresa != null
          ? _samoDanasAdresa
          : (_adresaCtrl.text.isEmpty ? null : _adresaCtrl.text);
      final adresaId = _promeniAdresuSamoDanas && _samoDanasAdresaId != null ? _samoDanasAdresaId : null;
      await V2PolasciService.v2DodajPutnika(
        putnikId: _selectedPutnik!.id,
        dan: widget.selectedDay,
        vreme: widget.selectedVreme,
        grad: widget.selectedGrad,
        putnikTabela: _selectedPutnik!.v2Tabela,
        adresaId: adresaId,
        brojMesta: _brojMesta,
      );
      if (!mounted) return;
      setState(() => _isLoading = false);
      Navigator.pop(context);
      widget.onPutnikDodat(widget.selectedVreme);
      V2AppSnackBar.success(context, 'âœ… Putnik je uspeÅ¡no dodat');
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      V2AppSnackBar.error(context, 'âŒ GreÅ¡ka pri dodavanju: $e');
    }
  }
}
