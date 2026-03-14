import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/v2_route_config.dart';
import '../globals.dart';
import '../models/v3_putnik.dart';
import '../models/v3_zahtev.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v2_theme_manager.dart';
import '../services/v3/v3_smart_navigation_service.dart';
import '../services/v3/v3_vozac_lokacija_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../theme.dart';
import '../widgets/v3_bottom_nav_bar_letnji.dart';
import '../widgets/v3_bottom_nav_bar_praznici.dart';
import '../widgets/v3_bottom_nav_bar_zimski.dart';
import '../widgets/v3_putnik_card.dart';
import 'v3_promena_sifre_screen.dart';
import 'v3_welcome_screen.dart';

/// V3VozacScreen — ekran za vozača (Voja).
/// Prikazuje samo putnike iz v3_raspored_putnik dodeljene ovom vozaču,
/// i samo termine iz v3_raspored_termin dodeljene ovom vozaču.
class V3VozacScreen extends StatefulWidget {
  const V3VozacScreen({super.key});

  @override
  State<V3VozacScreen> createState() => _V3VozacScreenState();
}

class _V3VozacScreenState extends State<V3VozacScreen> {
  static const List<String> _dayNames = ['Ponedeljak', 'Utorak', 'Sreda', 'Cetvrtak', 'Petak', 'Subota', 'Nedelja'];
  static const List<String> _dayAbbr = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];

  String _selectedDay = 'Ponedeljak';
  String _selectedGrad = 'BC';
  String _selectedVreme = '';
  bool _isLoading = true;
  bool _isTracking = false;

  StreamSubscription<void>? _realtimeSub;

  // Moji termini (iz v3_raspored_termin) za trenutni dan
  List<Map<String, dynamic>> _mojiTermini = [];

  // Moji putnici (iz v3_raspored_putnik) za trenutni dan/grad/vreme
  List<_PutnikZahtev> _mojiPutnici = [];

  List<String> get _bcVremena => V2RouteConfig.getVremenaByNavType('BC', navBarTypeNotifier.value);
  List<String> get _vsVremena => V2RouteConfig.getVremenaByNavType('VS', navBarTypeNotifier.value);

  List<String> get _sviPolasci => [
        ..._bcVremena.map((v) => '$v BC'),
        ..._vsVremena.map((v) => '$v VS'),
      ];

  @override
  void initState() {
    super.initState();
    final today = DateTime.now().weekday;
    _selectedDay = (today == DateTime.saturday || today == DateTime.sunday) ? 'Ponedeljak' : _dayNames[today - 1];
    _initData();
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  Future<void> _initData() async {
    if (V3VozacService.currentVozac == null) {
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute<void>(builder: (_) => const V3WelcomeScreen()),
          (r) => false,
        );
      }
      return;
    }

    _realtimeSub = V3MasterRealtimeManager.instance.onChange.listen((_) {
      if (mounted) _rebuild();
    });

    if (mounted) {
      _rebuild();
      setState(() => _isLoading = false);
    }
  }

  void _rebuild() {
    final vozac = V3VozacService.currentVozac;
    if (vozac == null) return;
    final rm = V3MasterRealtimeManager.instance;
    final danAbbr = _getDanAbbr(_selectedDay);

    // Pomoćna funkcija za normalizaciju vremena (HH:mm)
    String normalizeV(String? v) {
      if (v == null || v.isEmpty) return '';
      final parts = v.split(':');
      if (parts.length >= 2) return '${parts[0]}:${parts[1]}';
      return v;
    }

    final selectedVNorm = normalizeV(_selectedVreme);

    // 1. Moji termini za ovaj dan (iz v3_raspored_termin)
    _mojiTermini = rm.rasporedTerminCache.values
        .where((r) =>
            r['vozac_id']?.toString() == vozac.id &&
            r['dan']?.toString().toLowerCase() == danAbbr &&
            (r['aktivno'] == true || r['aktivno'] == null))
        .toList();

    // Ako nema selektovanog termina, uzmi prvi koji odgovara
    final terminPostoji = _mojiTermini.any((t) =>
        t['grad']?.toString().toUpperCase() == _selectedGrad && normalizeV(t['vreme']?.toString()) == selectedVNorm);
    if (!terminPostoji && _mojiTermini.isNotEmpty) {
      _selectClosestTermin();
    }

    // 2. Moji putnici za ovaj dan/grad/vreme (iz v3_raspored_putnik)
    final rasporedPutnici = rm.rasporedPutnikCache.values
        .where((r) =>
            r['vozac_id']?.toString() == vozac.id &&
            r['dan']?.toString().toLowerCase() == danAbbr &&
            r['grad']?.toString().toUpperCase() == _selectedGrad &&
            normalizeV(r['vreme']?.toString()) == selectedVNorm &&
            (r['aktivno'] == true || r['aktivno'] == null))
        .toList();

    // 3. Za svakog putnika iz rasporeda, pronađi zahtev iz v3_zahtevi
    final putnici = <_PutnikZahtev>[];
    for (final rp in rasporedPutnici) {
      final putnikId = rp['putnik_id']?.toString();
      if (putnikId == null) continue;

      final putnikData = rm.putniciCache[putnikId];
      if (putnikData == null) continue;
      final putnik = V3Putnik.fromJson(putnikData);

      // Pronađi zahtev za ovog putnika (isti grad/vreme)
      V3Zahtev? zahtev;
      try {
        final zahtevData = rm.zahteviCache.values.firstWhere(
          (z) =>
              z['putnik_id']?.toString() == putnikId &&
              z['grad']?.toString().toUpperCase() == _selectedGrad &&
              normalizeV(z['zeljeno_vreme']?.toString()) == selectedVNorm &&
              z['aktivno'] == true,
        );
        zahtev = V3Zahtev.fromJson(zahtevData);
      } catch (_) {
        // nema zahteva
      }

      putnici.add(_PutnikZahtev(putnik: putnik, zahtev: zahtev));
    }
    putnici.sort((a, b) => a.putnik.imePrezime.compareTo(b.putnik.imePrezime));

    if (mounted) setState(() => _mojiPutnici = putnici);
  }

  void _selectClosestTermin() {
    final now = DateTime.now();
    final current = now.hour * 60 + now.minute;
    String? bestVreme;
    String? bestGrad;
    int minDiff = 9999;

    for (final t in _mojiTermini) {
      final grad = t['grad']?.toString().toUpperCase() ?? '';
      final vreme = t['vreme']?.toString() ?? '';
      if (vreme.isEmpty) continue;
      final tp = vreme.split(':');
      if (tp.length != 2) continue;
      final mins = (int.tryParse(tp[0]) ?? 0) * 60 + (int.tryParse(tp[1]) ?? 0);
      final diff = (mins - current).abs();
      if (diff < minDiff) {
        minDiff = diff;
        bestVreme = vreme;
        bestGrad = grad;
      }
    }
    if (bestVreme != null && bestGrad != null) {
      _selectedVreme = bestVreme;
      _selectedGrad = bestGrad;
    }
  }

  String _getDanAbbr(String danPuni) {
    final idx = _dayNames.indexWhere((d) => d.toLowerCase() == danPuni.toLowerCase());
    return idx >= 0 ? _dayAbbr[idx] : danPuni.toLowerCase().substring(0, 3);
  }

  void _onPolazakChanged(String grad, String vreme) {
    setState(() {
      _selectedGrad = grad;
      _selectedVreme = vreme;
    });
    _rebuild();
  }

  Future<void> _openMapa() async {
    if (_mojiPutnici.isEmpty) {
      final uri = Uri.parse('https://wego.here.com/');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }

    // Napravi multi-stop URL za Here WeGo od liste putnika
    final waypointsBuffer = StringBuffer('https://wego.here.com/directions/drive/');
    bool first = true;
    int idx = 0;
    for (final pz in _mojiPutnici) {
      // Adresa zavisno od smjera (grad iz selektovanog termina)
      final adresa = _selectedGrad.toUpperCase() == 'BC'
          ? (pz.putnik.adresaBcNaziv ?? pz.putnik.adresaVsNaziv ?? '')
          : (pz.putnik.adresaVsNaziv ?? pz.putnik.adresaBcNaziv ?? '');
      if (adresa.isEmpty) continue;
      final encoded = Uri.encodeComponent('$adresa, Serbia');
      waypointsBuffer.write('${first ? '?' : '&'}waypoint$idx=$encoded');
      first = false;
      idx++;
    }

    final uri = Uri.parse(waypointsBuffer.toString());
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Column(
          children: [
            Icon(Icons.logout, color: Colors.red, size: 40),
            SizedBox(height: 12),
            Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text('Da li ste sigurni da želite da se odjavite?', textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Otkaži')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      V3VozacService.currentVozac = null;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const V3WelcomeScreen()),
        (r) => false,
      );
    }
  }

  int _getPutnikCount(String grad, String vreme) {
    final vozac = V3VozacService.currentVozac;
    if (vozac == null) return 0;
    final rm = V3MasterRealtimeManager.instance;
    final danAbbr = _getDanAbbr(_selectedDay);
    return rm.rasporedPutnikCache.values
        .where((r) =>
            r['vozac_id']?.toString() == vozac.id &&
            r['dan']?.toString().toLowerCase() == danAbbr &&
            r['grad']?.toString().toUpperCase() == grad.toUpperCase() &&
            r['vreme']?.toString() == vreme &&
            (r['aktivno'] == true || r['aktivno'] == null))
        .length;
  }

  Future<void> _toggleTracking() async {
    final vozac = V3VozacService.currentVozac;
    if (vozac == null) return;

    if (!_isTracking) {
      // 1. START TRACKING
      setState(() => _isTracking = true);
      await V3VozacLokacijaService.postaviAktivnost(vozac.id, true);

      // Simulišemo lat/lng za početak (Bela Crkva ili Vršac zavisno od grada)
      final startLat = _selectedGrad.toUpperCase() == 'BC' ? 44.8972 : 45.1167;
      final startLng = _selectedGrad.toUpperCase() == 'BC' ? 21.4247 : 21.3036;

      await V3VozacLokacijaService.updateLokacija(V3VozacLokacijaUpdate(
        vozacId: vozac.id,
        lat: startLat,
        lng: startLng,
        grad: _selectedGrad,
        vremePolaska: _selectedVreme,
        aktivno: true,
      ));

      // 2. AUTOMATSKA OPTIMIZACIJA RUTI PREMA GPS-u I PUTNICIMA
      if (_mojiPutnici.isNotEmpty) {
        await _optimizujRutu();
      }
    } else {
      // STOP TRACKING
      setState(() => _isTracking = false);
      await V3VozacLokacijaService.postaviAktivnost(vozac.id, false);
    }
  }

  Future<void> _optimizujRutu() async {
    if (_mojiPutnici.isEmpty) return;

    final data = _mojiPutnici.map((p) => {'putnik': p.putnik, 'zahtev': p.zahtev}).toList();

    // Možemo simulirati trenutni GPS vozača ovde za preciznije sortiranje
    final res = await V3SmartNavigationService.optimizeV3Route(
      data: data,
      fromCity: _selectedGrad,
      driverLat: _selectedGrad.toUpperCase() == 'BC' ? 44.8972 : 45.1167,
      driverLng: _selectedGrad.toUpperCase() == 'BC' ? 21.4247 : 21.3036,
    );

    if (res.success && res.optimizedData != null) {
      setState(() {
        _mojiPutnici = res.optimizedData!.map((d) {
          return _PutnikZahtev(putnik: d['putnik'] as V3Putnik, zahtev: d['zahtev'] as V3Zahtev?);
        }).toList();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.message),
            backgroundColor: Colors.green.withOpacity(0.8),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vozac = V3VozacService.currentVozac;

    if (_isLoading) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Container(
            decoration: BoxDecoration(gradient: V2ThemeManager().currentGradient),
            child: const Center(child: CircularProgressIndicator(color: Colors.white)),
          ),
        ),
      );
    }

    // Termini za BottomNavBar — samo moji iz rasporeda
    final bcVremenaToShow = (_mojiTermini
        .where((t) => t['grad']?.toString().toUpperCase() == 'BC')
        .map((t) => t['vreme']?.toString() ?? '')
        .where((v) => v.isNotEmpty)
        .toList()
      ..sort());
    final vsVremenaToShow = (_mojiTermini
        .where((t) => t['grad']?.toString().toUpperCase() == 'VS')
        .map((t) => t['vreme']?.toString() ?? '')
        .where((v) => v.isNotEmpty)
        .toList()
      ..sort());

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Container(
        decoration: BoxDecoration(gradient: V2ThemeManager().currentGradient),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(88),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).glassContainer,
                border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(25),
                  bottomRight: Radius.circular(25),
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // ── Red 1: Datum | Dan | Sat (V2 digitalni prikaz) ──
                      _buildDigitalDateDisplay(context, vozac),
                      const SizedBox(height: 6),
                      // ── Red 2: Kompaktni gumbi (V2 stil h=30) ──
                      Row(
                        children: [
                          // START / STOP
                          Expanded(
                            flex: 2,
                            child: _buildAppBarBtn(
                              context: context,
                              label: _isTracking ? 'STOP' : 'START',
                              color: _isTracking ? Colors.red : Colors.green,
                              onTap: _toggleTracking,
                            ),
                          ),
                          const SizedBox(width: 4),
                          // MAPA
                          Expanded(
                            flex: 2,
                            child: _buildAppBarBtn(
                              context: context,
                              label: 'MAPA',
                              color: Colors.blue,
                              onTap: _openMapa,
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Dan picker
                          Expanded(
                            flex: 2,
                            child: _buildDanPickerBtn(context),
                          ),
                          const SizedBox(width: 4),
                          // ⚙️ Popup meni — šifra + logout
                          PopupMenuButton<String>(
                            onSelected: (val) {
                              if (val == 'sifra') {
                                if (!mounted || vozac == null) return;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => V3PromenaSifreScreen(vozacIme: vozac.imePrezime),
                                  ),
                                );
                              } else if (val == 'logout') {
                                _logout();
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'sifra',
                                child: Row(children: [
                                  Icon(Icons.lock_reset, color: Colors.blueAccent),
                                  SizedBox(width: 8),
                                  Text('Promeni šifru'),
                                ]),
                              ),
                              PopupMenuItem(
                                value: 'logout',
                                child: Row(children: [
                                  Icon(Icons.logout, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Logout'),
                                ]),
                              ),
                            ],
                            padding: EdgeInsets.zero,
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                              ),
                              child: const Center(
                                child: Icon(Icons.more_vert, color: Colors.white, size: 16),
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
          bottomNavigationBar: ValueListenableBuilder<String>(
            valueListenable: navBarTypeNotifier,
            builder: (context, navType, _) {
              if (navType == 'zimski') {
                return V3BottomNavBarZimski(
                  sviPolasci: _sviPolasci,
                  selectedGrad: _selectedGrad,
                  selectedVreme: _selectedVreme,
                  onPolazakChanged: _onPolazakChanged,
                  getPutnikCount: _getPutnikCount,
                  bcVremena: bcVremenaToShow,
                  vsVremena: vsVremenaToShow,
                  selectedDan: _selectedDay,
                );
              } else if (navType == 'praznici') {
                return V3BottomNavBarPraznici(
                  sviPolasci: _sviPolasci,
                  selectedGrad: _selectedGrad,
                  selectedVreme: _selectedVreme,
                  onPolazakChanged: _onPolazakChanged,
                  getPutnikCount: _getPutnikCount,
                  bcVremena: bcVremenaToShow,
                  vsVremena: vsVremenaToShow,
                  selectedDan: _selectedDay,
                );
              }
              return V3BottomNavBarLetnji(
                sviPolasci: _sviPolasci,
                selectedGrad: _selectedGrad,
                selectedVreme: _selectedVreme,
                onPolazakChanged: _onPolazakChanged,
                getPutnikCount: _getPutnikCount,
                bcVremena: bcVremenaToShow,
                vsVremena: vsVremenaToShow,
                selectedDan: _selectedDay,
              );
            },
          ),
          body: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_mojiTermini.isEmpty) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).glassContainer,
            border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.event_busy, color: Colors.white54, size: 48),
              const SizedBox(height: 12),
              Text(
                'Nema dodeljenih termina za $_selectedDay',
                style: const TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_mojiPutnici.isEmpty) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).glassContainer,
            border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inbox, color: Colors.white54, size: 48),
              const SizedBox(height: 12),
              Text(
                'Nema putnika za $_selectedGrad $_selectedVreme',
                style: const TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Lista putnika
        Expanded(
          child: _mojiPutnici.isEmpty
              ? Center(
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).glassContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text('Nema putnika za ovaj polazak', style: TextStyle(color: Colors.white70)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 4, bottom: 16),
                  itemCount: _mojiPutnici.length,
                  itemBuilder: (context, index) {
                    final pz = _mojiPutnici[index];
                    return V3PutnikCard(putnik: pz.putnik, zahtev: pz.zahtev, redniBroj: index + 1);
                  },
                ),
        ),
      ],
    );
  }

  // ── V2 stil: digitalni datum prikaz ──
  Widget _buildDigitalDateDisplay(BuildContext context, dynamic vozac) {
    final now = DateTime.now();
    final dayNames = ['PONEDELJAK', 'UTORAK', 'SREDA', 'CETVRTAK', 'PETAK', 'SUBOTA', 'NEDELJA'];
    final dayName = dayNames[now.weekday - 1];
    final dateStr = DateFormat('dd.MM.yy').format(now);
    final timeStr = DateFormat('HH:mm').format(now);
    final vozacBoja = _getVozacBojaRaw(vozac);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          dateStr,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onPrimary,
            shadows: const [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
          ),
        ),
        Text(
          dayName,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: vozacBoja,
            shadows: const [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
          ),
        ),
        Text(
          timeStr,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onPrimary,
            shadows: const [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
          ),
        ),
      ],
    );
  }

  // ── Kompaktni AppBar dugme (label, h=30) ──
  Widget _buildAppBarBtn({
    required BuildContext context,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 30,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  // ── Dan picker dugme (AppBar stil) ──
  Widget _buildDanPickerBtn(BuildContext context) {
    return InkWell(
      onTap: _showDanDialog,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 30,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        ),
        child: Center(
          child: Text(
            _selectedDay.substring(0, 3).toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  void _showDanDialog() {
    showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Izaberi dan'),
        children: _dayNames.map((dan) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, dan),
            child: Text(dan, style: TextStyle(fontWeight: dan == _selectedDay ? FontWeight.bold : FontWeight.normal)),
          );
        }).toList(),
      ),
    ).then((dan) {
      if (dan != null && mounted) {
        setState(() => _selectedDay = dan);
        _rebuild();
      }
    });
  }

  // Puna boja vozača (bez alpha skaliranja) — za tekst/border
  Color _getVozacBojaRaw(dynamic v3Vozac) {
    if (v3Vozac == null) return Colors.white;
    final hex = v3Vozac.boja?.toString();
    if (hex == null || hex.isEmpty) return Colors.white;
    try {
      final clean = hex.replaceFirst('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return Colors.white;
    }
  }
}

/// Helper klasa — putnik + njegov zahtev
class _PutnikZahtev {
  final V3Putnik putnik;
  final V3Zahtev? zahtev;
  const _PutnikZahtev({required this.putnik, this.zahtev});
}
