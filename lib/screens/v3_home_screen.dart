import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/v2_route_config.dart';
import '../globals.dart';
import '../models/v3_putnik.dart';
import '../models/v3_vozac.dart';
import '../models/v3_zahtev.dart';
import '../services/v2_theme_manager.dart';
import '../services/v3/v3_kapacitet_service.dart';
import '../services/v3/v3_putnik_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../services/v3/v3_zahtev_service.dart';
import '../theme.dart';
import '../utils/v2_app_snack_bar.dart';
import '../widgets/v3_putnik_card.dart';
import 'v3_polasci_screen.dart';
import 'v3_welcome_screen.dart';

class V3HomeScreen extends StatefulWidget {
  const V3HomeScreen({super.key});

  @override
  State<V3HomeScreen> createState() => _V3HomeScreenState();
}

class _V3HomeScreenState extends State<V3HomeScreen> with TickerProviderStateMixin {
  bool _isLoading = true;
  String _selectedDay = 'Ponedeljak';
  String _selectedGrad = 'BC';
  String _selectedVreme = '05:00';

  // Stream za broj pending zahteva (badge na dugmetu)
  late final Stream<int> _streamBrojZahteva;

  static const List<String> _dayNames = ['Ponedeljak', 'Utorak', 'Sreda', 'Cetvrtak', 'Petak', 'Subota', 'Nedelja'];
  static const List<String> _dayAbbrs = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];

  String get _currentDayAbbr => _dayAbbrs[_dayNames.indexOf(_selectedDay)];

  // Dinamična vremena prema tipu nav bara
  List<String> get _bcVremena => V2RouteConfig.getVremenaByNavType('BC');
  List<String> get _vsVremena => V2RouteConfig.getVremenaByNavType('VS');

  List<String> get _sviPolasci => [
        ..._bcVremena.map((v) => '$v BC'),
        ..._vsVremena.map((v) => '$v VS'),
      ];

  @override
  void initState() {
    super.initState();
    final today = DateTime.now().weekday;
    _selectedDay = (today == DateTime.saturday || today == DateTime.sunday) ? 'Ponedeljak' : _dayNames[today - 1];
    _streamBrojZahteva = V3ZahtevService.streamPendingZahteviCount();
    _initData();
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
    if (mounted) {
      _selectClosestDeparture();
      setState(() => _isLoading = false);
    }
  }

  void _selectClosestDeparture() {
    final now = DateTime.now();
    final current = now.hour * 60 + now.minute;
    String? bestVreme;
    String? bestGrad;
    int minDiff = 9999;

    for (final p in _sviPolasci) {
      final parts = p.split(' ');
      if (parts.length < 2) continue;
      final tp = parts[0].split(':');
      if (tp.length != 2) continue;
      final mins = (int.tryParse(tp[0]) ?? 0) * 60 + (int.tryParse(tp[1]) ?? 0);
      final diff = (mins - current).abs();
      if (diff < minDiff) {
        minDiff = diff;
        bestVreme = parts[0];
        bestGrad = parts.sublist(1).join(' ');
      }
    }
    if (bestVreme != null && bestGrad != null) {
      _selectedVreme = bestVreme;
      _selectedGrad = bestGrad;
    }
  }

  bool get _isAdmin {
    final ime = V3VozacService.currentVozac?.imePrezime ?? '';
    // Admin = vozač čije ime počinje sa "Admin" ili je u posebnoj listi
    return ime.toLowerCase().contains('admin');
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
        content: const Text('Da li ste sigurni da se želite odjaviti?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Otkaži')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      V3VozacService.currentVozac = null;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute<void>(builder: (_) => const V3WelcomeScreen()),
        (r) => false,
      );
    }
  }

  /// Dijalog za dodavanje novog zahteva (rezervacije)
  void _showDodajZahtevDialog() {
    V3Putnik? selectedPutnik;
    int brojMesta = 1;
    bool isLoading = false;
    final searchController = TextEditingController();

    // Spoji sve tipove putnika iz V3
    final aktivniPutnici = [
      ...V3PutnikService.getPutniciByTip('radnik'),
      ...V3PutnikService.getPutniciByTip('dnevni'),
      ...V3PutnikService.getPutniciByTip('ucenik'),
      ...V3PutnikService.getPutniciByTip('posiljka'),
    ].where((p) => p.aktivno).toList()
      ..sort((a, b) => a.imePrezime.compareTo(b.imePrezime));

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setS) {
          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.75,
                maxWidth: MediaQuery.of(ctx).size.width * 0.9,
              ),
              decoration: BoxDecoration(
                gradient: Theme.of(ctx).backgroundGradient,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Theme.of(ctx).glassBorder, width: 1.5),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 15, offset: const Offset(0, 8))
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
                      color: Theme.of(ctx).glassContainer,
                      borderRadius:
                          const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
                      border: Border(bottom: BorderSide(color: Theme.of(ctx).glassBorder)),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('Dodaj Rezervaciju',
                              style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(dialogCtx),
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
                  // Content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Info o ruti
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(ctx).glassContainer,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Theme.of(ctx).glassBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Ruta', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                _buildStatRow('⏰ Vreme:', _selectedVreme),
                                _buildStatRow('📍 Grad:', _selectedGrad),
                                _buildStatRow('📅 Dan:', _selectedDay),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Dropdown putnika
                          DropdownButtonFormField2<V3Putnik>(
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Izaberi putnika',
                              prefixIcon: const Icon(Icons.person_search),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            dropdownStyleData: DropdownStyleData(
                              maxHeight: 280,
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.white),
                            ),
                            dropdownSearchData: DropdownSearchData(
                              searchController: searchController,
                              searchInnerWidgetHeight: 50,
                              searchInnerWidget: Container(
                                height: 50,
                                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                                child: TextFormField(
                                  controller: searchController,
                                  expands: true,
                                  maxLines: null,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    hintText: 'Pretraži...',
                                    prefixIcon: const Icon(Icons.search, size: 20),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                              searchMatchFn: (item, val) =>
                                  (item.value?.imePrezime ?? '').toLowerCase().contains(val.toLowerCase()),
                            ),
                            items: aktivniPutnici
                                .map((p) => DropdownMenuItem(
                                      value: p,
                                      child: Text(p.imePrezime, overflow: TextOverflow.ellipsis),
                                    ))
                                .toList(),
                            onChanged: (p) => setS(() => selectedPutnik = p),
                          ),
                          const SizedBox(height: 12),
                          // Broj mesta
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
                                const Text('Broj mesta:', style: TextStyle(fontSize: 16)),
                                const SizedBox(width: 8),
                                DropdownButton<int>(
                                  value: brojMesta,
                                  underline: const SizedBox(),
                                  isDense: true,
                                  items: [1, 2, 3, 4, 5]
                                      .map((v) =>
                                          DropdownMenuItem(value: v, child: Text(v == 1 ? '1 mesto' : '$v mesta')))
                                      .toList(),
                                  onChanged: (v) => setS(() => brojMesta = v ?? 1),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Actions
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).glassContainer,
                      borderRadius:
                          const BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
                      border: Border(top: BorderSide(color: Theme.of(ctx).glassBorder)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(dialogCtx),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.red),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Otkaži'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            icon: isLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.add),
                            label: Text(isLoading ? 'Dodaje...' : 'Dodaj'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.withValues(alpha: 0.7),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: isLoading
                                ? null
                                : () async {
                                    if (selectedPutnik == null) {
                                      V2AppSnackBar.error(ctx, '⚠️ Izaberite putnika');
                                      return;
                                    }
                                    setS(() => isLoading = true);
                                    try {
                                      // Izračunaj datum za selektovani dan
                                      final now = DateTime.now();
                                      final targetDayIdx = _dayNames.indexOf(_selectedDay);
                                      final currentDayIdx = now.weekday - 1;
                                      int daysToAdd = targetDayIdx - currentDayIdx;
                                      if (daysToAdd < 0) daysToAdd += 7;
                                      final targetDate = now.add(Duration(days: daysToAdd));
                                      final isoDate = targetDate.toIso8601String().split('T')[0];

                                      final zahtev = V3Zahtev(
                                        id: '',
                                        putnikId: selectedPutnik!.id,
                                        datum: DateTime.parse(isoDate),
                                        danUSedmici: _currentDayAbbr,
                                        grad: _selectedGrad,
                                        zeljenoVreme: _selectedVreme,
                                        brojMesta: brojMesta,
                                        status: 'odobreno',
                                        aktivno: true,
                                      );
                                      await V3ZahtevService.createZahtev(zahtev);

                                      if (!dialogCtx.mounted) return;
                                      Navigator.pop(dialogCtx);
                                      if (mounted) V2AppSnackBar.success(context, '✅ Rezervacija dodana');
                                    } catch (e) {
                                      setS(() => isLoading = false);
                                      if (ctx.mounted) V2AppSnackBar.error(ctx, '❌ Greška: $e');
                                    }
                                  },
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
    ).then((_) => searchController.dispose());
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, color: Colors.white70)),
          ),
        ],
      ),
    );
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: StreamBuilder<List<V3Zahtev>>(
        stream: V3ZahtevService.streamZahteviByDanAndGrad(_currentDayAbbr, _selectedGrad),
        builder: (context, snapshot) {
          final sviZahtevi = snapshot.data ?? [];

          // Filtriraj po izabranom vremenu za prikaz liste
          final prikazaniZahtevi = sviZahtevi
              .where((z) => z.zeljenoVreme == _selectedVreme && z.status != 'otkazano' && z.status != 'odbijeno')
              .toList()
            ..sort((a, b) => a.zeljenoVreme.compareTo(b.zeljenoVreme));

          // Brojač po gradu/vremenu za bottom nav bar
          int getPutnikCount(String grad, String vreme) {
            return sviZahtevi
                .where((z) =>
                    z.grad == grad && z.zeljenoVreme == vreme && z.status != 'otkazano' && z.status != 'odbijeno')
                .fold(0, (sum, z) => sum + z.brojMesta);
          }

          // Kapacitet
          int getKapacitet(String grad, String vreme) {
            final kap = V3KapacitetService.getKapacitetSync();
            return kap[grad]?[vreme] ?? 8;
          }

          return Container(
            decoration: BoxDecoration(gradient: V2ThemeManager().currentGradient),
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: PreferredSize(
                preferredSize: const Size.fromHeight(93),
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Red 1 - naslov
                          Row(
                            children: [
                              Expanded(
                                child: Center(
                                  child: Text(
                                    'R E Z E R V A C I J E',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: Theme.of(context).colorScheme.onPrimary,
                                      letterSpacing: 1.4,
                                      shadows: const [
                                        Shadow(blurRadius: 12, color: Colors.black87),
                                        Shadow(offset: Offset(2, 2), blurRadius: 6, color: Colors.black54),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Red 2 - vozač, tema, dan
                          Row(
                            children: [
                              // Vozač
                              Expanded(
                                flex: 35,
                                child: Container(
                                  height: 33,
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: _getVozacColor(vozac),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
                                  ),
                                  child: Center(
                                    child: Text(
                                      vozac?.imePrezime ?? '—',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        shadows: const [Shadow(blurRadius: 8, color: Colors.black87)],
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 2),
                              // Tema
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
                                      border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'Tema',
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.onPrimary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 2),
                              // Dan dropdown
                              Expanded(
                                flex: 35,
                                child: Container(
                                  height: 33,
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).glassContainer,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton2<String>(
                                      value: _selectedDay,
                                      customButton: Center(
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
                                      dropdownStyleData: DropdownStyleData(
                                        decoration: BoxDecoration(
                                          gradient: Theme.of(context).backgroundGradient,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
                                        ),
                                        elevation: 8,
                                      ),
                                      items: _dayNames
                                          .map((d) => DropdownMenuItem(
                                                value: d,
                                                child: Center(
                                                  child: Text(
                                                    d,
                                                    style: TextStyle(
                                                      color: Theme.of(context).colorScheme.onPrimary,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                              ))
                                          .toList(),
                                      onChanged: (val) {
                                        if (mounted) setState(() => _selectedDay = val!);
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
                          child: _V3HomeButton(
                            label: 'Dodaj',
                            icon: Icons.person_add,
                            onTap: _showDodajZahtevDialog,
                          ),
                        ),
                        const SizedBox(width: 4),
                        if (_isAdmin) ...[
                          Expanded(
                            child: StreamBuilder<int>(
                              stream: _streamBrojZahteva,
                              builder: (ctx, snap) {
                                final count = snap.data ?? 0;
                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    _V3HomeButton(
                                      label: 'Zahtevi',
                                      icon: Icons.notifications_active,
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const V3PolasciScreen()),
                                      ),
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
                                            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                          ),
                                          constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                          child: Text(
                                            '$count',
                                            style: const TextStyle(
                                                color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: PopupMenuButton<String>(
                            onSelected: (val) {
                              if (val == 'logout') _logout();
                            },
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
                                  Icon(Icons.settings, color: Theme.of(context).colorScheme.onPrimary, size: 18),
                                  const SizedBox(height: 4),
                                  const SizedBox(
                                    height: 16,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text('Opcije',
                                          style: TextStyle(
                                              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            itemBuilder: (_) => [
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
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Lista putnika/zahteva
                  Expanded(
                    child: prikazaniZahtevi.isEmpty
                        ? Center(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(context).glassContainer,
                                border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Nema rezervacija za ovaj polazak.',
                                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            itemCount: prikazaniZahtevi.length,
                            itemBuilder: (ctx, i) {
                              final z = prikazaniZahtevi[i];
                              final p = V3PutnikService.getPutnikById(z.putnikId);
                              if (p == null) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: V3PutnikCard(putnik: p, zahtev: z),
                              );
                            },
                          ),
                  ),
                ],
              ),
              // Bottom nav bar
              bottomNavigationBar: ValueListenableBuilder<String>(
                valueListenable: navBarTypeNotifier,
                builder: (ctx, navType, _) {
                  return _buildBottomNavBar(getPutnikCount, getKapacitet);
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Color _getVozacColor(V3Vozac? vozac) {
    if (vozac == null) return Colors.transparent;
    final boja = vozac.boja;
    if (boja == null || boja.isEmpty) return Colors.blueGrey.withValues(alpha: 0.5);
    try {
      final hex = boja.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.blueGrey.withValues(alpha: 0.5);
    }
  }

  Widget _buildBottomNavBar(int Function(String, String) getPutnikCount, int Function(String, String) getKapacitet) {
    final sviPolasci = _sviPolasci;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).glassContainer,
        border: Border(top: BorderSide(color: Theme.of(context).glassBorder, width: 1.5)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: sviPolasci.map((polazak) {
              final parts = polazak.split(' ');
              final vreme = parts[0];
              final grad = parts.sublist(1).join(' ');
              final isSelected = _selectedVreme == vreme && _selectedGrad == grad;
              final count = getPutnikCount(grad, vreme);
              final kap = getKapacitet(grad, vreme);
              final isFull = count >= kap;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: GestureDetector(
                  onTap: () => setState(() {
                    _selectedVreme = vreme;
                    _selectedGrad = grad;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.8)
                            : (isFull ? Colors.red.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.2)),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          grad,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: isSelected ? 1 : 0.6),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          vreme,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: isSelected ? 1 : 0.7),
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: isFull ? Colors.red.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$count/$kap',
                            style: const TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _V3HomeButton extends StatelessWidget {
  const _V3HomeButton({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
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
            Icon(icon, color: Theme.of(context).colorScheme.onPrimary, size: 18),
            const SizedBox(height: 4),
            SizedBox(
              height: 16,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    shadows: const [
                      Shadow(blurRadius: 8, color: Colors.black87),
                      Shadow(offset: Offset(1, 1), blurRadius: 4, color: Colors.black54),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
