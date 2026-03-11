import 'package:flutter/material.dart';

import '../globals.dart';
import '../models/v2_polazak.dart';
import '../models/v2_putnik.dart';
import '../services/realtime/v2_master_realtime_manager.dart';
import '../services/v2_app_settings_service.dart';
import '../services/v2_auth_manager.dart';
import '../services/v2_local_notification_service.dart';
import '../services/v2_pin_zahtev_service.dart';
import '../services/v2_polasci_service.dart';
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
import 'v2_posiljke_zahtevi_screen.dart';
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
  String? _currentDriver;
  // Izračunato jednom u initState — dan se ne mijenja za života ovog widgeta
  late final String _todayKratica;
  late final String _todayIso;
  // Jedan broadcast stream koji sluša sve relevantne tabele
  late final Stream<_AdminData> _stream;

  @override
  void initState() {
    super.initState();

    // Osvježi lokalne map-ove iz rm.vozaciCache (bez DB upita)
    V2VozacCache.refresh();

    _todayKratica = V2DanUtils.danas();
    _todayIso = DateTime.now().toIso8601String().split('T')[0];

    _stream = V2MasterRealtimeManager.instance.v2StreamFromCache<_AdminData>(
      tables: const [
        'v2_polasci',
        'v2_dnevni',
        'v2_radnici',
        'v2_ucenici',
        'v2_posiljke',
        'v2_vozac_raspored',
        'v2_vozac_putnik',
        'v2_statistika_istorija',
        'v2_pin_zahtevi',
      ],
      build: _buildAdminData,
    ).asBroadcastStream();

    _loadCurrentDriver();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          V2LocalNotificationService.initialize(context);
        } catch (_) {}
      }
    });
  }

  /// 🚗 VOZAC PICKER DIALOG - Admin može da vidi ekran bilo kog vozaca
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

  Future<void> _loadCurrentDriver() async {
    try {
      final driver = await V2AuthManager.getCurrentDriver();
      if (mounted) setState(() => _currentDriver = driver);
    } catch (_) {
      if (mounted) setState(() => _currentDriver = null);
    }
  }

  _AdminData _buildAdminData() {
    final rm = V2MasterRealtimeManager.instance;

    // Putnici za danas — sync iz RM cache-a
    final putnici = V2PolasciService.fetchPutniciSyncStatic(dan: _todayKratica);

    // Pazar — sync iz polasciCache
    final today = _todayIso;
    final Map<String, double> pazar = {};
    double ukupnoPazar = 0;
    for (final row in rm.polasciCache.values) {
      final placen = row['placen'];
      if (placen != true && placen.toString() != 'true') continue;
      final datumAkcije = row['datum_akcije']?.toString();
      if (datumAkcije == null || !datumAkcije.startsWith(today)) continue;
      final iznos =
          (row['placen_iznos'] as num?)?.toDouble() ?? (double.tryParse(row['placen_iznos']?.toString() ?? '') ?? 0);
      if (iznos <= 0) continue;
      final vozacIme = row['placen_vozac_ime']?.toString() ?? 'Nepoznat';
      pazar[vozacIme] = (pazar[vozacIme] ?? 0) + iznos;
      ukupnoPazar += iznos;
    }
    pazar['_ukupno'] = ukupnoPazar;

    // Zahtevi u obradi — sync iz polasciCache
    final zahteviObrada = rm.polasciCache.values.where((r) => r['status'] == V2Polazak.statusObrada).map((row) {
      final putnikId = row['putnik_id']?.toString();
      final putnikTabela = row['putnik_tabela']?.toString();
      final putnikRow = putnikId == null
          ? null
          : switch (putnikTabela) {
              'v2_radnici' => rm.radniciCache[putnikId],
              'v2_ucenici' => rm.uceniciCache[putnikId],
              _ => null,
            };
      final enriched = putnikRow == null ? row : {...row, 'putnik_ime': putnikRow['ime']};
      return V2Polazak.fromJson(enriched);
    }).toList();

    // Brojači
    final uceniciObrada = zahteviObrada.where((z) => z.tipPutnika == 'ucenik').length;
    final radniciObrada = zahteviObrada.where((z) => z.tipPutnika == 'radnik').length;

    // PIN zahtevi — sync iz pinCache (public wrapper)
    final pinZahtevi = V2PinZahtevService.buildEnrichedListSync();

    // saVS/ukBC — učenici koji idu u BC sa VS povratkom
    final danKratica = V2DanUtils.odDatuma(DateTime.now());
    final Map<String, Set<String>> smerovi = {};
    for (final sr in rm.polasciCache.values) {
      if (sr['putnik_tabela']?.toString() != 'v2_ucenici') continue;
      final dan = sr['dan']?.toString();
      final datum = sr['datum_akcije']?.toString().split('T')[0];
      if (dan != danKratica && datum != _todayIso) continue;
      final st = sr['status']?.toString().toLowerCase() ?? '';
      if (st == 'otkazano' ||
          st == 'otkazan' ||
          st == 'cancelled' ||
          st == 'bolovanje' ||
          st == 'godišnji' ||
          st == 'godisnji' ||
          st == 'odbijeno') continue;
      final id = sr['putnik_id']?.toString();
      if (id == null) continue;
      final g = (sr['grad']?.toString() ?? '').toUpperCase();
      smerovi.putIfAbsent(id, () => {});
      smerovi[id]!.add(g == 'BC' ? 'bc' : 'vs');
    }
    int ukBC = 0, saVS = 0;
    smerovi.forEach((_, s) {
      if (!s.contains('bc')) return;
      ukBC++;
      if (s.contains('vs')) saVS++;
    });

    return _AdminData(
      putnici: putnici,
      pazar: pazar,
      uceniciObrada: uceniciObrada,
      radniciObrada: radniciObrada,
      pinZahtevi: pinZahtevi,
      saVS: saVS,
      ukBC: ukBC,
    );
  }

  /// ⚠️ DIJALOG ZA GLOBALNO UKLANJANJE POLASKA
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
    return StreamBuilder<_AdminData>(
      stream: _stream,
      initialData: _buildAdminData(),
      builder: (context, snapshot) {
        final data = snapshot.data ?? _buildAdminData();
        return _buildScaffold(context, data);
      },
    );
  }

  Widget _buildScaffold(BuildContext context, _AdminData data) {
    return Container(
      decoration: BoxDecoration(
        gradient: V2ThemeManager().currentGradient,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).glassContainer,
                border: Border.all(
                  color: Theme.of(context).glassBorder,
                  width: 1.5,
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
                            const SizedBox(height: 4),
                            const SizedBox(height: 4),
                            // CETVRTI RED - Vozac, Monitor, Mesta (3 dugmeta)
                            Row(
                              children: [],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // ADRESE + MESTA - ispod AppBara
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Row(
                children: [
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
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.6), width: 1.5),
                        ),
                        child: const Center(
                          child: Text('📍', style: TextStyle(fontSize: 20)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (context) => const V2KapacitetScreen(),
                        ),
                      ),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.6), width: 1.5),
                        ),
                        child: const Center(
                          child: Text('💺', style: TextStyle(fontSize: 20)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _showStatistikeMenu(context),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 40,
                      width: 50,
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.6), width: 1.5),
                      ),
                      child: const Center(
                        child: Text('📊', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (context) => const V2GorivoScreen(),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 40,
                      width: 50,
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.7), width: 1.5),
                      ),
                      child: const Center(
                        child: Text('⛽', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<String>(
                    valueListenable: navBarTypeNotifier,
                    builder: (context, navType, _) {
                      return Container(
                        height: 40,
                        width: 50,
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.6), width: 1.5),
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
                                      fontSize: 20,
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
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute<void>(builder: (context) => const V2VozaciAdminScreen())),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 40,
                      width: 50,
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.6), width: 1.5),
                      ),
                      child: const Center(
                        child: Text('🛡️', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // VOZAC + RASPORED - ispod AppBara
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _showVozacPickerDialog(context),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.6), width: 1.5),
                        ),
                        child: const Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Vozac',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: Colors.white,
                                shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (context) => const V2VozacRasporedScreen(),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 40,
                      width: 50,
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.withValues(alpha: 0.6), width: 1.5),
                      ),
                      child: const Center(
                        child: Text('📅', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
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
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.6), width: 1.5),
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
                                shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // AUDIT LOG + POVRATAK - ispod AppBara
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Row(
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
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.teal.withValues(alpha: 0.15),
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
                                shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
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
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.indigo.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.indigo.withValues(alpha: 0.6), width: 1.5),
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
                                shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildSaVsUkBc(data),
                  ),
                ],
              ),
            ),
            // UCENICI + RADNICI + POSILJKE - isti red
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Row(
                children: [
                  // LEVO: Učenici zahtevi
                  Expanded(child: _buildUceniciButton(data)),
                  const SizedBox(width: 8),
                  // SREDINA: Radnici zahtevi
                  Expanded(child: _buildRadniciButton(data)),
                  const SizedBox(width: 8),
                  // DESNO: Pošiljke zahtevi
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (context) => const V2PosiljkeZahteviScreen(),
                        ),
                      ),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE65C00).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE65C00).withValues(alpha: 0.7), width: 1.5),
                        ),
                        child: const Center(
                          child: Text('📦', style: TextStyle(fontSize: 22)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // DESNO+1: PIN zahtevi
                  Expanded(child: _buildPinButton(data)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: _buildGlavniSadrzaj(context, data),
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────
  // WIDGET HELPERI — primaju data direktno
  // ────────────────────────────────────────────────────────

  Widget _buildGlavniSadrzaj(BuildContext context, _AdminData data) {
    final allPutnici = data.putnici;
    final pazarMap = data.pazar;
    final ukupno = pazarMap['_ukupno'] ?? 0.0;
    final Map<String, double> pazar = Map.from(pazarMap)..remove('_ukupno');

    final filteredPutnici = allPutnici.where((p) => p.dan.toLowerCase() == _todayKratica).toList();

    const iskljuceniStatusiDuznici = {'otkazano', 'otkazan', 'odbijeno', 'cancelled'};
    final filteredDuznici = filteredPutnici.where((p) {
      if (p.isRadnik || p.isUcenik) return false;
      final st = p.status?.toLowerCase() ?? '';
      return p.placeno != true && !iskljuceniStatusiDuznici.contains(st) && p.jePokupljen;
    }).toList();

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
    final List<String> vozaciRedosled = V2VozacCache.imenaVozaca;

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
                    Icon(Icons.person, color: Colors.green[600], size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Prikazuju se samo VAŠE naplate, vozac: $_currentDriver',
                        style: TextStyle(color: Colors.green[700], fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Column(
              children: prikazaniVozaci
                  .map((vozac) => Container(
                        width: double.infinity,
                        height: 60,
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: (vozacBoje[vozac] ?? Colors.blueGrey).withValues(alpha: 60 / 255),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: (vozacBoje[vozac] ?? Colors.blueGrey).withValues(alpha: 120 / 255)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: vozacBoje[vozac] ?? Colors.blueGrey,
                              radius: 16,
                              child: Text(vozac[0],
                                  style:
                                      const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(vozac,
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: vozacBoje[vozac] ?? Colors.blueGrey)),
                            ),
                            Row(
                              children: [
                                Icon(Icons.monetization_on, color: vozacBoje[vozac] ?? Colors.blueGrey, size: 16),
                                const SizedBox(width: 2),
                                Text(
                                  '${(filteredPazar[vozac] ?? 0.0).toStringAsFixed(0)} RSD',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: vozacBoje[vozac] ?? Colors.blueGrey),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
            V2DugButton(
              brojDuznika: filteredDuznici.length,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (context) => V2DugoviScreen(currentDriver: _currentDriver!)),
              ),
              wide: true,
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              height: 76,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
                boxShadow: [
                  BoxShadow(color: Colors.green.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.account_balance_wallet, color: Colors.green[700], size: 20),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isAdmin ? 'UKUPAN PAZAR' : 'MOJ UKUPAN PAZAR',
                        style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                      Text(
                        '${(isAdmin ? ukupno : mojUkupanPazar).toStringAsFixed(0)} RSD',
                        style: TextStyle(color: Colors.green[900], fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUceniciButton(_AdminData data) {
    final count = data.uceniciObrada;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (context) => const V2UceniciZahteviScreen()),
          ),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: Colors.lightBlue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.lightBlue.withValues(alpha: 0.6), width: 1.5),
            ),
            child: const Center(child: Text('🎓', style: TextStyle(fontSize: 22))),
          ),
        ),
        if (count > 0)
          Positioned(
            right: 4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              child: Text('$count',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
            ),
          ),
      ],
    );
  }

  Widget _buildRadniciButton(_AdminData data) {
    final count = data.radniciObrada;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (context) => const V2RadniciZahteviScreen()),
          ),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withValues(alpha: 0.6), width: 1.5),
            ),
            child: const Center(child: Text('👷', style: TextStyle(fontSize: 22))),
          ),
        ),
        if (count > 0)
          Positioned(
            right: 4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              child: Text('$count',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
            ),
          ),
      ],
    );
  }

  Widget _buildPinButton(_AdminData data) {
    final broj = data.pinZahtevi.length;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (context) => const V2PinZahteviScreen()),
          ),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: broj > 0 ? Colors.orange.withValues(alpha: 0.9) : Colors.orange.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: const Center(child: Text('🔐', style: TextStyle(fontSize: 22))),
          ),
        ),
        if (broj > 0)
          Positioned(
            right: 4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              child: Text('$broj',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
            ),
          ),
      ],
    );
  }

  Widget _buildSaVsUkBc(_AdminData data) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Center(
        child: Text(
          '${data.saVS}/${data.ukBC}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.orange,
            shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
          ),
        ),
      ),
    );
  }
}

/// Snapshot svih admin podataka — jedan StreamBuilder rebuild
class _AdminData {
  final List<V2Putnik> putnici;
  final Map<String, double> pazar;
  final int uceniciObrada;
  final int radniciObrada;
  final List<Map<String, dynamic>> pinZahtevi;
  final int saVS;
  final int ukBC;

  const _AdminData({
    required this.putnici,
    required this.pazar,
    required this.uceniciObrada,
    required this.radniciObrada,
    required this.pinZahtevi,
    required this.saVS,
    required this.ukBC,
  });
}
