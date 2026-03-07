import 'package:flutter/material.dart';

import '../config/v2_route_config.dart';
import '../globals.dart';
import '../models/v2_putnik.dart';
import '../services/v2_app_settings_service.dart';
import '../services/v2_auth_manager.dart';
import '../services/v2_local_notification_service.dart';
import '../services/v2_pin_zahtev_service.dart';
import '../services/v2_polasci_service.dart';
import '../services/v2_statistika_istorija_service.dart';
import '../services/v2_theme_manager.dart';
import '../services/v2_vozac_service.dart';
import '../theme.dart';
import '../utils/v2_app_snack_bar.dart';
import '../utils/v2_dan_utils.dart';
import '../utils/v2_vozac_cache.dart';
import '../widgets/v2_dug_button.dart';
import 'v2_adrese_screen.dart';
import 'v2_audit_log_screen.dart';
import 'v2_dnevnik_naplate_screen.dart';
import 'v2_dugovi_screen.dart';
import 'v2_finansije_screen.dart';
import 'v2_gorivo_screen.dart';
import 'v2_kapacitet_screen.dart';
import 'v2_odrzavanje_screen.dart';
import 'v2_pin_zahtevi_screen.dart';
import 'v2_putnici_screen.dart';
import 'v2_radnici_zahtevi_screen.dart';
import 'v2_ucenici_zahtevi_screen.dart';
import 'v2_vozac_raspored_screen.dart';
import 'v2_vozac_screen.dart';
import 'v2_vozaci_admin_screen.dart';

class V2AdminScreen extends StatefulWidget {
  const V2AdminScreen({super.key});

  @override
  State<V2AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<V2AdminScreen> {
  static const List<String> _defaultVozaciRedosled = ['Bruda', 'Bilevski', 'Bojan', 'Voja'];

  String? _currentDriver;
  // Izračunato jednom u initState — dan se ne mijenja za života ovog widgeta
  late final String _todayKratica;
  late final Stream<List<V2Putnik>> _streamPutnici;
  late final Stream<Map<String, double>> _streamPazar;
  late final Stream<int> _streamRadniciObrada;
  late final Stream<int> _streamUceniciObrada;
  late final Stream<List<Map<String, dynamic>>> _streamPinZahtevi;
  // Shared broadcast stream za zahteve — jedan poziv, dvije pretplate
  late final Stream<List<dynamic>> _streamZahteviObradaShared;

  @override
  void initState() {
    super.initState();

    // Osvježi lokalne map-ove iz rm.vozaciCache (bez DB upita)
    V2VozacCache.refresh();

    _todayKratica = V2DanUtils.danas();

    final todayIso = DateTime.now().toIso8601String().split('T')[0];
    _streamPutnici = V2PolasciService.v2StreamPutnici();
    _streamPazar = V2StatistikaIstorijaService.streamPazarIzCachea(isoDate: todayIso);
    _streamZahteviObradaShared = V2PolasciService.v2StreamZahteviObrada();
    _streamRadniciObrada = _streamZahteviObradaShared.map((list) => list.where((z) => z.tipPutnika == 'radnik').length);
    _streamUceniciObrada = _streamZahteviObradaShared.map((list) => list.where((z) => z.tipPutnika == 'ucenik').length);

    _streamPinZahtevi = V2PinZahtevService.streamZahteviKojiCekaju();

    _loadCurrentDriver();

    try {
      V2LocalNotificationService.initialize(context);
    } catch (e) {
      // ignore
    }
  }

  /// ?? VOZAC PICKER DIALOG - Admin može da vidi ekran bilo kog vozaca
  void _showVozacPickerDialog(BuildContext context) {
    try {
      final vozaci = V2VozacService.getAllVozaci();

      if (!mounted) return;

      if (vozaci.isEmpty) {
        V2AppSnackBar.error(context, '⚠️ Nema ucitanih vozaca');
        return;
      }

      showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.92,
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              decoration: BoxDecoration(
                gradient: Theme.of(context).backgroundGradient,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 24,
                    spreadRadius: 2,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // HEADER
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                      border: Border(bottom: BorderSide(color: Theme.of(context).glassBorder)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.blue.withValues(alpha: 0.4)),
                          ),
                          child: const Icon(Icons.person_search_outlined, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Izaberi vozača',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.of(dialogContext).pop(),
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                            ),
                            child: const Icon(Icons.close, color: Colors.white, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // LISTA VOZAČA
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: vozaci.length,
                      separatorBuilder: (_, __) => Divider(
                        color: Colors.white.withValues(alpha: 0.08),
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                      ),
                      itemBuilder: (context, index) {
                        final vozac = vozaci[index];
                        final boja = vozac.color ?? const Color(0xFFBDBDBD);
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor: boja,
                            child: Text(
                              vozac.ime[0].toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(
                            vozac.ime,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 14),
                          onTap: () {
                            Navigator.of(dialogContext).pop();
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (context) => V2VozacScreen(previewAsDriver: vozac.ime),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      V2AppSnackBar.error(context, '❌ Greška pri ucitavanju vozaca');
    }
  }

  void _loadCurrentDriver() async {
    try {
      final driver = await V2AuthManager.getCurrentDriver();
      if (mounted) setState(() => _currentDriver = driver);
    } catch (_) {
      if (mounted) setState(() => _currentDriver = null);
    }
  }

  /// ?? DIJALOG ZA GLOBALNO UKLANJANJE POLASKA
  void _showGlobalniBezPolaskaDialog() {
    String selectedGrad = 'BC';
    String selectedVreme = '05:00';
    String selectedDan = V2DanUtils.puniNazivi[DateTime.now().weekday - 1];
    bool isProcessing = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
        // Dohvati vremena za izabrani grad i trenutni režim (zimski/letnji/praznici)
        final navType = navBarTypeNotifier.value;
        List<String> vremena;
        if (selectedGrad == 'BC') {
          if (navType == 'praznici')
            vremena = ['Sva vremena', ...V2RouteConfig.bcVremenaPraznici];
          else if (navType == 'zimski')
            vremena = ['Sva vremena', ...V2RouteConfig.bcVremenaZimski];
          else
            vremena = ['Sva vremena', ...V2RouteConfig.bcVremenaLetnji];
        } else {
          if (navType == 'praznici')
            vremena = ['Sva vremena', ...V2RouteConfig.vsVremenaPraznici];
          else if (navType == 'zimski')
            vremena = ['Sva vremena', ...V2RouteConfig.vsVremenaZimski];
          else
            vremena = ['Sva vremena', ...V2RouteConfig.vsVremenaLetnji];
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
                    ? 'Ova akcija ce SVIM putnicima u izabranom gradu za CEO DAN postaviti status "Bez polaska".'
                    : 'Ova akcija ce svim putnicima u izabranom terminu postaviti status "Bez polaska".',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: selectedDan,
                decoration: const InputDecoration(labelText: 'Dan'),
                items: V2DanUtils.puniNazivi.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
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

                      try {
                        final count = await V2PolasciService.v2GlobalniBezPolaska(
                          dan: selectedDan,
                          grad: selectedGrad,
                          vreme: selectedVreme,
                        );

                        if (mounted) {
                          Navigator.pop(context);
                          V2AppSnackBar.success(
                              context,
                              selectedVreme == 'Sva vremena'
                                  ? '✅ Uspešno uklonjeno $count putnika za ceo dan ($selectedGrad) - $selectedDan'
                                  : '✅ Uspešno uklonjeno $count putnika za $selectedVreme ($selectedGrad) - $selectedDan');
                        }
                      } catch (e) {
                        if (mounted) {
                          setDialogState(() => isProcessing = false);
                          V2AppSnackBar.error(context, '❌ Greška: $e');
                        }
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
                        builder: (context) => const V2FinansijeScreen(),
                      ),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Text('🔧', style: TextStyle(fontSize: 24)),
                  title: const Text('Kolska knjiga'),
                  subtitle: const Text('Servisi, registracija, gume...'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (context) => const V2OdrzavanjeScreen(),
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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: V2ThemeManager().currentGradient,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(165),
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
                          Row(
                            children: [
                              // PUTNICI
                              Expanded(
                                child: InkWell(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (context) => const V2PutniciScreen(),
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
                                      builder: (context) => const V2AdreseScreen(),
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

                              // DNEVNIK NAPLATE
                              Expanded(
                                child: InkWell(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (context) => const V2DnevnikNaplateScreen(),
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
                                          'Dnevnik',
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
                                            const labels = {'zimski': '❄️', 'letnji': '☀️', 'praznici': '🎉'};
                                            return ['zimski', 'letnji', 'praznici'].map((t) {
                                              return Center(
                                                child: Text(
                                                  labels[t] ?? t,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 14,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              );
                                            }).toList();
                                          },
                                          items: const [
                                            DropdownMenuItem(value: 'zimski', child: Center(child: Text('Zimski'))),
                                            DropdownMenuItem(value: 'letnji', child: Center(child: Text('Letnji'))),
                                            DropdownMenuItem(value: 'praznici', child: Center(child: Text('Praznici'))),
                                          ],
                                          onChanged: (value) {
                                            if (value != null) {
                                              V2AppSettingsService.setNavBarType(value);
                                            }
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // TRECI RED - Auth, PIN, Statistike, Dodeli (4 dugmeta)
                          Row(
                            children: [
                              // AUTH
                              Expanded(
                                child: InkWell(
                                  onTap: () => Navigator.push(context,
                                      MaterialPageRoute<void>(builder: (context) => const V2VozaciAdminScreen())),
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
                                child: StreamBuilder<List<Map<String, dynamic>>>(
                                  stream: _streamPinZahtevi,
                                  initialData: const [],
                                  builder: (context, snapshot) {
                                    final broj = snapshot.data?.length ?? 0;
                                    return InkWell(
                                      onTap: () => Navigator.push(context,
                                          MaterialPageRoute<void>(builder: (context) => const V2PinZahteviScreen())),
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
                                                  color: broj > 0 ? Colors.orange : Theme.of(context).glassBorder,
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
                                          if (broj > 0)
                                            Positioned(
                                              right: -4,
                                              top: -4,
                                              child: Container(
                                                padding: const EdgeInsets.all(4),
                                                decoration:
                                                    const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                                                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                                child: Text('$broj',
                                                    style: const TextStyle(
                                                        color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                                    textAlign: TextAlign.center),
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  },
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
                                            fit: BoxFit.scaleDown, child: Text('📊', style: TextStyle(fontSize: 14)))),
                                  ),
                                ),
                              ),

                              // RASPORED VOZACA
                              Expanded(
                                child: InkWell(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (context) => const V2VozacRasporedScreen(),
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
                                      border: Border.all(color: Colors.blue.withValues(alpha: 0.6), width: 1.5),
                                    ),
                                    child: const Center(
                                        child: FittedBox(
                                            fit: BoxFit.scaleDown, child: Text('📅', style: TextStyle(fontSize: 14)))),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // CETVRTI RED - Vozac, Monitor, Mesta (3 dugmeta)
                          Row(
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
                                            child: const Text('Vozac',
                                                style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 14,
                                                    color: Colors.white,
                                                    shadows: [
                                                      Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)
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
                                      builder: (context) => const V2GorivoScreen(),
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
                                      border: Border.all(color: Colors.orange.withValues(alpha: 0.7), width: 1.5),
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
                                                      Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)
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
                                      border: Border.all(color: Colors.red.withValues(alpha: 0.5), width: 1.5),
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
                                                      Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)
                                                    ])))),
                                  ),
                                ),
                              ),

                              // MESTA
                              Expanded(
                                child: InkWell(
                                  onTap: () => Navigator.push(context,
                                      MaterialPageRoute<void>(builder: (context) => const V2KapacitetScreen())),
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
                                                      Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)
                                                    ])))),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // PETI RED - Audit log
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (context) => const V2AuditLogScreen(),
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
                                      border: Border.all(color: Colors.teal.withValues(alpha: 0.6), width: 1.5),
                                    ),
                                    child: const Center(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          '📋 Audit log',
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
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: StreamBuilder<List<V2Putnik>>(
          stream: _streamPutnici,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
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
                        if (mounted) setState(() {});
                      },
                      child: const Text('Pokušaj ponovo'),
                    ),
                  ],
                ),
              );
            }

            final allPutnici = snapshot.data ?? [];

            final filteredPutnici = allPutnici.where((p) => p.dan.toLowerCase() == _todayKratica).toList();

            // Dužnici — pokupljeni, neplaćeni, samo dnevni i posiljke (ne radnici/ucenici)
            final filteredDuznici = filteredPutnici.where((p) {
              if (p.isRadnik || p.isUcenik) return false;
              return p.placeno != true && (p.status?.toLowerCase() != 'otkazano') && p.jePokupljen;
            }).toList();

            return StreamBuilder<Map<String, double>>(
              stream: _streamPazar,
              builder: (context, pazarSnapshot) {
                final pazarMap = pazarSnapshot.data ?? <String, double>{'_ukupno': 0};
                final ukupno = pazarMap['_ukupno'] ?? 0.0;
                final Map<String, double> pazar = Map.from(pazarMap)..remove('_ukupno');

                if (_currentDriver == null) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('⏳ Ucitavanje...'),
                    ),
                  );
                }

                final bool isAdmin = V2AdminSecurityService.isAdmin(_currentDriver!);
                final Map<String, double> filteredPazar = V2AdminSecurityService.filterPazarByPrivileges(
                  _currentDriver!,
                  pazar,
                );
                final double mojUkupanPazar = filteredPazar.values.fold(0.0, (sum, val) => sum + val);

                final Map<String, Color> vozacBoje = V2VozacCache.bojeSync;
                final List<String> vozaciRedosled =
                    V2VozacCache.imenaVozaca.isNotEmpty ? V2VozacCache.imenaVozaca : _defaultVozaciRedosled;

                final List<String> prikazaniVozaci = V2AdminSecurityService.getVisibleDrivers(
                  _currentDriver!,
                  vozaciRedosled,
                );
                return SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).padding.bottom + 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Info box za individualnog vozaca
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
                                    'Prikazuju se samo VAŠE naplate, vozac: $_currentDriver',
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
                                    color: (vozacBoje[vozac] ?? Colors.blueGrey).withValues(alpha: 60 / 255),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: (vozacBoje[vozac] ?? Colors.blueGrey).withValues(alpha: 120 / 255),
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
                        V2DugButton(
                          brojDuznika: filteredDuznici.length,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (context) => V2DugoviScreen(
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
                          height: 76,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(context).glassBorder,
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withValues(alpha: 0.3),
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
                                  Text(
                                    '${(isAdmin ? ukupno : mojUkupanPazar).toStringAsFixed(0)} RSD',
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
                        const SizedBox(height: 8),
                        // RADNICI + UCENICI ZAHTEVI
                        if (isAdmin)
                          Row(
                            children: [
                              Expanded(
                                child: StreamBuilder<int>(
                                  stream: _streamRadniciObrada,
                                  builder: (context, snapshot) {
                                    final count = snapshot.data ?? 0;
                                    return Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        InkWell(
                                          onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute<void>(
                                              builder: (context) => const V2RadniciZahteviScreen(),
                                            ),
                                          ),
                                          borderRadius: BorderRadius.circular(8),
                                          child: Container(
                                            height: 80,
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(8),
                                              border:
                                                  Border.all(color: Colors.green.withValues(alpha: 0.6), width: 1.5),
                                            ),
                                            child: const Center(
                                              child: Text(
                                                'Radnici zahtevi',
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
                                        if (count > 0)
                                          Positioned(
                                            right: 6,
                                            top: 6,
                                            child: Container(
                                              padding: const EdgeInsets.all(5),
                                              decoration:
                                                  const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                              child: Text('$count',
                                                  style: const TextStyle(
                                                      color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                                  textAlign: TextAlign.center),
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: StreamBuilder<int>(
                                  stream: _streamUceniciObrada,
                                  builder: (context, snapshot) {
                                    final count = snapshot.data ?? 0;
                                    return Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        InkWell(
                                          onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute<void>(
                                              builder: (context) => const V2UceniciZahteviScreen(),
                                            ),
                                          ),
                                          borderRadius: BorderRadius.circular(8),
                                          child: Container(
                                            height: 80,
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                  color: Colors.lightBlue.withValues(alpha: 0.6), width: 1.5),
                                            ),
                                            child: const Center(
                                              child: Text(
                                                'Učenici zahtevi',
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
                                        if (count > 0)
                                          Positioned(
                                            right: 6,
                                            top: 6,
                                            child: Container(
                                              padding: const EdgeInsets.all(5),
                                              decoration:
                                                  const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                              child: Text('$count',
                                                  style: const TextStyle(
                                                      color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                                  textAlign: TextAlign.center),
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
