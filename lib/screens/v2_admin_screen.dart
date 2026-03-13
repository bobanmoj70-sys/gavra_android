import 'package:flutter/material.dart';

import '../globals.dart';
import '../models/v2_polazak.dart';
import '../models/v2_putnik.dart';
import '../services/realtime/v2_master_realtime_manager.dart';
import '../services/v2_app_settings_service.dart';
import '../services/v2_auth_manager.dart';
import '../services/v2_local_notification_service.dart';
import '../services/v2_polasci_service.dart';
import '../services/v2_theme_manager.dart';
import '../services/v3/v3_pin_zahtev_service.dart';
import '../services/v3/v3_vozac_service.dart';
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

// ─────────────────────────────────────────────────────────────────────────────
// HELPER WIDGETS (privatni, file-scoped)
// ─────────────────────────────────────────────────────────────────────────────

/// Dugme h=40 s emoji/tekstom — zamjenjuje ponavljajući InkWell+Container blok.
class _NavBtn extends StatelessWidget {
  const _NavBtn({
    required this.onTap,
    required this.child,
    this.color = Colors.blueGrey,
    this.borderAlpha = 0.6,
    this.width,
  });

  final VoidCallback onTap;
  final Widget child;
  final Color color;
  final double borderAlpha;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 40,
        width: width,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: borderAlpha), width: 1.5),
        ),
        child: Center(child: child),
      ),
    );
  }
}

/// Dugme h=50 s emoji badge-om — zamjenjuje ponavljajući Stack+InkWell+Positioned blok.
class _BadgeBtn extends StatelessWidget {
  const _BadgeBtn({
    required this.onTap,
    required this.emoji,
    required this.color,
    required this.badgeCount,
    this.badgeColor = Colors.red,
  });

  final VoidCallback onTap;
  final String emoji;
  final Color color;
  final int badgeCount;
  final Color badgeColor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: color.withValues(alpha: badgeCount > 0 ? 0.9 : 0.6),
                width: 1.5,
              ),
            ),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
          ),
        ),
        if (badgeCount > 0)
          Positioned(
            right: 4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              child: Text(
                '$badgeCount',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

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

  late final V2ThemeManager _themeManager;

  @override
  void initState() {
    super.initState();
    _themeManager = V2ThemeManager();

    // Osvježi lokalne map-ove iz rm.vozaciCache (bez DB upita)
    V2VozacCache.refresh();

    _todayKratica = V2DanUtils.danas();
    _todayIso = V2DanUtils.today();

    _stream = V2MasterRealtimeManager.instance.v2StreamFromCache<_AdminData>(
      tables: const [
        'v2_polasci',
        'v2_radnici',
        'v2_ucenici',
        'v2_posiljke',
        'v2_vozac_raspored',
        'v2_vozac_putnik',
        'v2_pin_zahtevi',
      ],
      build: _buildAdminData,
    );

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
      final vozaci = V3VozacService.getAllVozaci();

      if (!mounted) return;

      if (vozaci.isEmpty) {
        V2AppSnackBar.error(context, '❌ Nema učitanih vozača');
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
                        Color boja = const Color(0xFFBDBDBD);
                        if (vozac.boja != null && vozac.boja!.isNotEmpty) {
                          try {
                            final hex = vozac.boja!.replaceFirst('#', '');
                            boja = Color(int.parse('FF$hex', radix: 16));
                          } catch (_) {}
                        }
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor: boja,
                            child: Text(
                              vozac.imePrezime.isNotEmpty ? vozac.imePrezime[0].toUpperCase() : '?',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(
                            vozac.imePrezime,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 14),
                          onTap: () {
                            Navigator.of(dialogContext).pop();
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (context) => V2VozacScreen(previewAsDriver: vozac.imePrezime),
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
      V2AppSnackBar.error(context, '❌ Greška pri učitavanju vozača');
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

    // Jedan prolaz kroz polasciCache — pazar + zahteviObrada + saVS/ukBC
    final Map<String, double> pazarPoVozacu = {};
    double ukupnoPazar = 0;
    int uceniciObrada = 0;
    int radniciObrada = 0;
    final Map<String, Set<String>> smerovi = {};
    const iskljuceniSmeroviStatusi = {
      'otkazano',
      'otkazan',
      'cancelled',
      'bolovanje',
      'godišnji',
      'godisnji',
      'odbijeno'
    };

    for (final row in rm.polasciCache.values) {
      // --- PAZAR ---
      final placen = row['placen'];
      if (placen == true || placen.toString() == 'true') {
        final datumAkcije = row['datum_akcije']?.toString();
        if (datumAkcije != null && datumAkcije.startsWith(_todayIso)) {
          final iznos = (row['placen_iznos'] as num?)?.toDouble() ??
              (double.tryParse(row['placen_iznos']?.toString() ?? '') ?? 0);
          if (iznos > 0) {
            final vozacIme = row['placen_vozac_ime']?.toString() ?? 'Nepoznat';
            pazarPoVozacu[vozacIme] = (pazarPoVozacu[vozacIme] ?? 0) + iznos;
            ukupnoPazar += iznos;
          }
        }
      }

      // --- ZAHTEVI U OBRADI ---
      if (row['status'] == V2Polazak.statusObrada) {
        final tip = row['putnik_tabela']?.toString();
        if (tip == 'v2_ucenici') {
          uceniciObrada++;
        } else if (tip == 'v2_radnici') {
          radniciObrada++;
        }
      }

      // --- saVS/ukBC (samo učenici) ---
      if (row['putnik_tabela']?.toString() == 'v2_ucenici') {
        final dan = row['dan']?.toString();
        final datum = row['datum_akcije']?.toString().split('T')[0];
        if (dan == _todayKratica || datum == _todayIso) {
          final st = row['status']?.toString().toLowerCase() ?? '';
          if (!iskljuceniSmeroviStatusi.contains(st)) {
            final id = row['putnik_id']?.toString();
            if (id != null) {
              final g = (row['grad']?.toString() ?? '').toUpperCase();
              smerovi.putIfAbsent(id, () => {});
              smerovi[id]!.add(g == 'BC' ? 'bc' : 'vs');
            }
          }
        }
      }
    }

    // PIN zahtevi — sync iz pinCache (public wrapper)
    final pinZahtevi = V3PinZahtevService.buildEnrichedListSync();

    // saVS/ukBC finalni brojevi
    int ukBC = 0, saVS = 0;
    smerovi.forEach((_, s) {
      if (!s.contains('bc')) return;
      ukBC++;
      if (s.contains('vs')) saVS++;
    });

    return _AdminData(
      putnici: putnici,
      pazarPoVozacu: pazarPoVozacu,
      ukupnoPazar: ukupnoPazar,
      uceniciObrada: uceniciObrada,
      radniciObrada: radniciObrada,
      pinZahtevi: pinZahtevi,
      saVS: saVS,
      ukBC: ukBC,
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
    if (_currentDriver == null) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(gradient: _themeManager.currentGradient),
          child: const SafeArea(child: Center(child: Text('⏳ Ucitavanje...'))),
        ),
      );
    }

    return StreamBuilder<_AdminData>(
      stream: _stream,
      builder: (context, snapshot) {
        final data = snapshot.data ?? _buildAdminData();
        return _buildScaffold(context, data);
      },
    );
  }

  Widget _buildScaffold(BuildContext context, _AdminData data) {
    final currentDriver = _currentDriver!;
    final isAdmin = V2AdminSecurityService.isAdmin(currentDriver);
    final filteredPazar = V2AdminSecurityService.filterPazarByPrivileges(currentDriver, data.pazarPoVozacu);
    final mojUkupanPazar = filteredPazar.values.fold(0.0, (sum, val) => sum + val);
    final vozacBoje = V2VozacCache.bojeSync;
    final prikazaniVozaci = V2AdminSecurityService.getVisibleDrivers(currentDriver, V2VozacCache.imenaVozaca);

    const iskljuceniStatusiDuznici = {'otkazano', 'otkazan', 'odbijeno', 'cancelled'};
    final filteredDuznici = data.putnici.where((p) {
      if (p.isRadnik || p.isUcenik) return false;
      final st = p.status?.toLowerCase() ?? '';
      return p.placeno != true && !iskljuceniStatusiDuznici.contains(st) && p.jePokupljen;
    }).toList();

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: _themeManager.currentGradient),
        child: SafeArea(
          child: Column(
            children: [
              // RED 1: Adrese, Kapacitet, Statistike, Gorivo, Raspored tip, Vozaci admin
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _NavBtn(
                        onTap: () =>
                            Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const V2AdreseScreen())),
                        child: const Text('📍', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _NavBtn(
                        onTap: () =>
                            Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const V2KapacitetScreen())),
                        child: const Text('💺', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _NavBtn(
                      onTap: () => _showStatistikeMenu(context),
                      width: 50,
                      child: const Text('📊', style: TextStyle(fontSize: 20)),
                    ),
                    const SizedBox(width: 8),
                    _NavBtn(
                      onTap: () =>
                          Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const V2GorivoScreen())),
                      color: Colors.orange,
                      borderAlpha: 0.7,
                      width: 50,
                      child: const Text('⛽', style: TextStyle(fontSize: 20)),
                    ),
                    const SizedBox(width: 8),
                    // Dropdown za tip rasporeda
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
                                          fontWeight: FontWeight.w600, fontSize: 20, color: Colors.white),
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
                                if (value != null) V2AppSettingsService.setNavBarType(value);
                              },
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    _NavBtn(
                      onTap: () =>
                          Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const V2VozaciAdminScreen())),
                      width: 50,
                      child: const Text('🛡️', style: TextStyle(fontSize: 20)),
                    ),
                  ],
                ),
              ),
              // RED 2: Vozac picker, Raspored, Putnici
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _NavBtn(
                        onTap: () => _showVozacPickerDialog(context),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Vozac',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Colors.white,
                                  shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)])),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _NavBtn(
                      onTap: () => Navigator.push(
                          context, MaterialPageRoute<void>(builder: (_) => const V2VozacRasporedScreen())),
                      color: Colors.blue,
                      width: 50,
                      child: const Text('📅', style: TextStyle(fontSize: 20)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _NavBtn(
                        onTap: () =>
                            Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const V2PutniciScreen())),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Putnici',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Colors.white,
                                  shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)])),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // RED 3: Audit log, Dnevnik, saVS/ukBC
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _NavBtn(
                        onTap: () =>
                            Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const V2AuditLogScreen())),
                        color: Colors.teal,
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('📋 Audit log',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Colors.white,
                                  shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)])),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _NavBtn(
                        onTap: () => Navigator.push(
                            context, MaterialPageRoute<void>(builder: (_) => const V2DnevnikNaplateScreen())),
                        color: Colors.indigo,
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Dnevnik',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Colors.white,
                                  shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)])),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _adminSaVsUkBc(data)),
                  ],
                ),
              ),
              // RED 4: Učenici, Radnici, Pošiljke, PIN zahtevi
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _BadgeBtn(
                        onTap: () => Navigator.push(
                            context, MaterialPageRoute<void>(builder: (_) => const V2UceniciZahteviScreen())),
                        emoji: '🎓',
                        color: Colors.lightBlue,
                        badgeCount: data.uceniciObrada,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _BadgeBtn(
                        onTap: () => Navigator.push(
                            context, MaterialPageRoute<void>(builder: (_) => const V2RadniciZahteviScreen())),
                        emoji: '👷',
                        color: Colors.green,
                        badgeCount: data.radniciObrada,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _BadgeBtn(
                        onTap: () => Navigator.push(
                            context, MaterialPageRoute<void>(builder: (_) => const V2PosiljkeZahteviScreen())),
                        emoji: '📦',
                        color: const Color(0xFFE65C00),
                        badgeCount: 0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _BadgeBtn(
                        onTap: () => Navigator.push(
                            context, MaterialPageRoute<void>(builder: (_) => const V2PinZahteviScreen())),
                        emoji: '🔐',
                        color: Colors.orange,
                        badgeCount: data.pinZahtevi.length,
                        badgeColor: Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // GLAVNI SADRZAJ
              Expanded(
                child: SingleChildScrollView(
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
                                    'Prikazuju se samo VAŠE naplate, vozac: $currentDriver',
                                    style:
                                        TextStyle(color: Colors.green[700], fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),
                        // LISTA VOZACA S PAZAROM
                        ...prikazaniVozaci.map((vozac) {
                          final boja = vozacBoje[vozac] ?? Colors.blueGrey;
                          return Container(
                            width: double.infinity,
                            height: 60,
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: boja.withValues(alpha: 60 / 255),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: boja.withValues(alpha: 120 / 255)),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: boja,
                                  radius: 16,
                                  child: Text(vozac[0],
                                      style: const TextStyle(
                                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(vozac,
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: boja)),
                                ),
                                Row(
                                  children: [
                                    Icon(Icons.monetization_on, color: boja, size: 16),
                                    const SizedBox(width: 2),
                                    Text(
                                      '${(filteredPazar[vozac] ?? 0.0).toStringAsFixed(0)} RSD',
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: boja),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                        V2DugButton(
                          brojDuznika: filteredDuznici.length,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(builder: (_) => const V2DugoviScreen()),
                          ),
                          wide: true,
                        ),
                        const SizedBox(height: 4),
                        // UKUPAN PAZAR
                        Container(
                          width: double.infinity,
                          height: 76,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.green.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))
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
                                    style: TextStyle(
                                        color: Colors.green[800], fontWeight: FontWeight.bold, letterSpacing: 1),
                                  ),
                                  Text(
                                    '${(isAdmin ? data.ukupnoPazar : mojUkupanPazar).toStringAsFixed(0)} RSD',
                                    style:
                                        TextStyle(color: Colors.green[900], fontWeight: FontWeight.bold, fontSize: 18),
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
            ],
          ),
        ),
      ),
    );
  }
}

Widget _adminSaVsUkBc(_AdminData data) {
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

/// Snapshot svih admin podataka — jedan StreamBuilder rebuild
class _AdminData {
  final List<V2Putnik> putnici;
  final Map<String, double> pazarPoVozacu;
  final double ukupnoPazar;
  final int uceniciObrada;
  final int radniciObrada;
  final List<Map<String, dynamic>> pinZahtevi;
  final int saVS;
  final int ukBC;

  const _AdminData({
    required this.putnici,
    required this.pazarPoVozacu,
    required this.ukupnoPazar,
    required this.uceniciObrada,
    required this.radniciObrada,
    required this.pinZahtevi,
    required this.saVS,
    required this.ukBC,
  });
}
