import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../globals.dart';
import '../models/v3_adresa.dart';
import '../models/v3_putnik.dart';
import '../models/v3_vozac.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v2_theme_manager.dart';
import '../services/v3/v3_adresa_service.dart';
import '../services/v3/v3_operativna_nedelja_service.dart';
import '../services/v3/v3_printing_service.dart';
import '../services/v3/v3_putnik_service.dart';
import '../services/v3/v3_racun_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../theme.dart';
import '../utils/v2_grad_adresa_validator.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_input_utils.dart';
import '../utils/v3_navigation_utils.dart';
import '../utils/v3_safe_text.dart';
import '../utils/v3_text_utils.dart';
import '../widgets/v3_bottom_nav_bar_letnji.dart';
import '../widgets/v3_bottom_nav_bar_praznici.dart';
import '../widgets/v3_bottom_nav_bar_zimski.dart';
import '../widgets/v3_live_clock_text.dart';
import '../widgets/v3_putnik_card.dart';
import '../widgets/v3_update_banner.dart';
import 'v3_admin_screen.dart';
import 'v3_vozac_screen.dart';
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

  late Stream<List<V3OperativnaNedeljaEntry>> _operativnaStream;

  /// Vraća ISO datum (yyyy-MM-dd) za izabrani dan u aktivnoj sedmici.
  String get _selectedDatumIso =>
      V3DanHelper.datumIsoZaDanPuniUTekucojSedmici(_selectedDay, anchor: V3DanHelper.schedulingWeekAnchor());

  Stream<List<V3OperativnaNedeljaEntry>> _buildOperativnaStream(String datumIso) {
    return V3MasterRealtimeManager.instance.v3StreamFromCache<List<V3OperativnaNedeljaEntry>>(
      tables: const [
        'v3_operativna_nedelja',
        'v3_putnici',
        'v3_vozaci',
        'v3_adrese',
        'v3_kapacitet_slots',
      ],
      build: () => V3OperativnaNedeljaService.getOperativnaNedeljaByDatum(datumIso),
    );
  }

  // Dinamična vremena prema tipu nav bara (iz baze)
  List<String> get _bcVremena => getRasporedVremena('bc', navBarTypeNotifier.value);
  List<String> get _vsVremena => getRasporedVremena('vs', navBarTypeNotifier.value);

  List<String> get _sviPolasci => [
        ..._bcVremena.map((v) => '$v BC'),
        ..._vsVremena.map((v) => '$v VS'),
      ];

  String _normalizeVreme(String? v) {
    if (v == null || v.isEmpty) return '';
    final parts = v.split(':');
    if (parts.length >= 2) return '${parts[0]}:${parts[1]}';
    return v;
  }

  int _timeToMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return -1;
    final hour = int.tryParse(parts[0]) ?? -1;
    final minute = int.tryParse(parts[1]) ?? -1;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return -1;
    return hour * 60 + minute;
  }

  void _syncSelectedSlotForDatum(String datumIso) {
    final entries = V3OperativnaNedeljaService.getOperativnaNedeljaByDatum(datumIso);
    final validEntries = entries.where((e) {
      if (!e.aktivno) return false;
      if (e.statusFinal == 'odbijeno') return false;
      if (e.statusFinal == 'obrada') return false;
      final grad = (e.grad ?? '').trim();
      final vreme = _normalizeVreme(e.dodeljivoVreme);
      return grad.isNotEmpty && vreme.isNotEmpty;
    }).toList();

    if (validEntries.isEmpty) return;

    final currentVremeNorm = _normalizeVreme(_selectedVreme);
    final hasCurrentSelection = validEntries.any(
      (e) => (e.grad ?? '') == _selectedGrad && _normalizeVreme(e.dodeljivoVreme) == currentVremeNorm,
    );
    if (hasCurrentSelection) return;

    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;
    validEntries.sort((a, b) {
      final aMinutes = _timeToMinutes(_normalizeVreme(a.dodeljivoVreme));
      final bMinutes = _timeToMinutes(_normalizeVreme(b.dodeljivoVreme));
      final aDiff = aMinutes < 0 ? 99999 : (aMinutes - currentMinutes).abs();
      final bDiff = bMinutes < 0 ? 99999 : (bMinutes - currentMinutes).abs();
      if (aDiff != bDiff) return aDiff.compareTo(bDiff);
      final ga = (a.grad ?? '').toUpperCase();
      final gb = (b.grad ?? '').toUpperCase();
      if (ga != gb) return ga.compareTo(gb);
      return _normalizeVreme(a.dodeljivoVreme).compareTo(_normalizeVreme(b.dodeljivoVreme));
    });

    final first = validEntries.first;
    _selectedGrad = first.grad ?? _selectedGrad;
    _selectedVreme = _normalizeVreme(first.dodeljivoVreme);
  }

  @override
  void initState() {
    super.initState();
    _selectedDay = V3DanHelper.defaultDay();
    _operativnaStream = _buildOperativnaStream(_selectedDatumIso);
    _initData();
  }

  Future<void> _initData() async {
    if (V3VozacService.currentVozac == null) {
      if (mounted) {
        V3NavigationUtils.pushAndRemoveUntil<void>(
          context,
          const V3WelcomeScreen(),
        );
      }
      return;
    }
    if (mounted) {
      _selectClosestDeparture();
      _syncSelectedSlotForDatum(_selectedDatumIso);
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
    final lowIme = ime.toLowerCase();
    return lowIme.contains('admin') || lowIme.contains('bojan');
  }

  // ─── Dodjela vozača putniku (admin only) ──────────────────────

  Color _parseVozacColor(String? hex) {
    if (hex == null || hex.isEmpty) return Colors.blueAccent;
    final h = hex.replaceAll('#', '');
    try {
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) {
      return Colors.blueAccent;
    }
  }

  V3Vozac? _getVozacZaPutnika(String putnikId, String grad, String vreme, String datum) {
    final rm = V3MasterRealtimeManager.instance;
    final normV = V2GradAdresaValidator.normalizeTime(vreme);
    for (final row in rm.v3GpsRasporedCache.values) {
      if (row['putnik_id'] == putnikId &&
          row['grad'] == grad &&
          row['aktivno'] == true &&
          V2GradAdresaValidator.normalizeTime(row['vreme'] as String? ?? '') == normV &&
          V3DanHelper.parseIsoDatePart(row['datum'] as String? ?? '') == datum) {
        final vozacId = row['vozac_id'] as String?;
        if (vozacId != null && vozacId.isNotEmpty) {
          return V3VozacService.getVozacById(vozacId);
        }
      }
    }
    return null;
  }

  /// Dijalog za dodavanje novog zahteva (rezervacije)
  void _showDodajZahtevDialog() {
    V3Putnik? selectedPutnik;
    V3Adresa? selectedAdresa; // override adresa (null = koristi putnikovu)
    int brojMesta = 1;
    bool isLoading = false;

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
                border: Border.all(color: Theme.of(ctx).glassBorder, width: 0.8),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 15, offset: const Offset(0, 8))
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  V3ContainerUtils.iconContainer(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Theme.of(ctx).glassContainer,
                    borderRadiusGeometry:
                        const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
                    border: Border(bottom: BorderSide(color: Theme.of(ctx).glassBorder)),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('Dodaj Rezervaciju',
                              style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(dialogCtx),
                          child: V3ContainerUtils.iconContainer(
                            padding: const EdgeInsets.all(8),
                            backgroundColor: Colors.red.withValues(alpha: 0.2),
                            borderRadiusGeometry: BorderRadius.circular(15),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
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
                          V3ContainerUtils.iconContainer(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            backgroundColor: Theme.of(ctx).glassContainer,
                            borderRadiusGeometry: BorderRadius.circular(12),
                            border: Border.all(color: Theme.of(ctx).glassBorder),
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
                              maxHeight: V3ContainerUtils.responsiveHeight(ctx, 280),
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.white),
                            ),
                            dropdownSearchData: DropdownSearchData(
                              searchController: V3TextUtils.searchController,
                              searchInnerWidgetHeight: V3ContainerUtils.responsiveHeight(ctx, 50),
                              searchInnerWidget: V3ContainerUtils.iconContainer(
                                height: V3ContainerUtils.responsiveHeight(ctx, 50),
                                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                                child: TextFormField(
                                  controller: V3TextUtils.searchController,
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
                                      child: V3SafeText.userName(p.imePrezime),
                                    ))
                                .toList(),
                            onChanged: (p) => setS(() {
                              selectedPutnik = p;
                              selectedAdresa = null; // reset adrese kad se promijeni putnik
                            }),
                          ),
                          const SizedBox(height: 12),
                          // Broj mesta
                          V3ContainerUtils.iconContainer(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            backgroundColor: Colors.grey.shade100,
                            borderRadiusGeometry: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade400),
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
                          // Adresa override — samo kad je putnik odabran
                          if (selectedPutnik != null) ...[
                            const SizedBox(height: 12),
                            _buildAdresaOverride(
                              putnik: selectedPutnik!,
                              grad: _selectedGrad,
                              selected: selectedAdresa,
                              onChanged: (a) => setS(() => selectedAdresa = a),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // Actions
                  V3ContainerUtils.iconContainer(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Theme.of(ctx).glassContainer,
                    borderRadiusGeometry:
                        const BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
                    border: Border(top: BorderSide(color: Theme.of(ctx).glassBorder)),
                    child: Row(
                      children: [
                        Expanded(
                          child: V3ButtonUtils.outlinedButton(
                            onPressed: () => Navigator.pop(dialogCtx),
                            text: 'Otkaži',
                            borderColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: V3ButtonUtils.elevatedButton(
                            onPressed: isLoading
                                ? null
                                : () async {
                                    if (selectedPutnik == null) {
                                      V3AppSnackBar.error(ctx, '⚠️ Izaberite putnika');
                                      return;
                                    }
                                    if (selectedPutnik!.id.isEmpty) {
                                      V3AppSnackBar.error(ctx, '⚠️ Putnik nema validan ID');
                                      return;
                                    }
                                    setS(() => isLoading = true);
                                    try {
                                      final isoDate = V3DanHelper.datumIsoZaDanPuniUTekucojSedmici(
                                        _selectedDay,
                                        anchor: V3DanHelper.schedulingWeekAnchor(),
                                      );
                                      final vozacId = V3VozacService.currentVozac?.id ?? 'nepoznat';

                                      // Odredi koristiSekundarnu i adresaIdOverride
                                      bool? koristiSekundarnu;
                                      String? adresaIdOverride;
                                      if (selectedAdresa != null) {
                                        final isBC = _selectedGrad.toUpperCase() == 'BC';
                                        final id1 = isBC ? selectedPutnik!.adresaBcId : selectedPutnik!.adresaVsId;
                                        final id2 = isBC ? selectedPutnik!.adresaBcId2 : selectedPutnik!.adresaVsId2;
                                        if (selectedAdresa!.id == id2) {
                                          koristiSekundarnu = true;
                                        } else if (selectedAdresa!.id == id1) {
                                          koristiSekundarnu = false;
                                        } else {
                                          // "Ostala" adresa — čuvamo ID direktno
                                          adresaIdOverride = selectedAdresa!.id;
                                          koristiSekundarnu = false;
                                        }
                                      }

                                      // Direktan INSERT u v3_operativna_nedelja — bez zahteva
                                      await V3OperativnaNedeljaService.createOrUpdateByVozac(
                                        putnikId: selectedPutnik!.id,
                                        datum: isoDate,
                                        grad: _selectedGrad,
                                        zeljenoVreme: _selectedVreme,
                                        dodeljivoVreme: _selectedVreme,
                                        brojMesta: brojMesta,
                                        createdBy: 'vozac:$vozacId',
                                        koristiSekundarnu: koristiSekundarnu,
                                        adresaIdOverride: adresaIdOverride,
                                      );

                                      if (!dialogCtx.mounted) return;
                                      Navigator.pop(dialogCtx);
                                      if (mounted) V3AppSnackBar.success(context, '✅ Rezervacija dodana');
                                    } catch (e) {
                                      setS(() => isLoading = false);
                                      if (ctx.mounted) V3AppSnackBar.error(ctx, '❌ Greška: $e');
                                    }
                                  },
                            text: isLoading ? 'Dodaje...' : 'Dodaj',
                            icon: Icons.add,
                            backgroundColor: Colors.green.withValues(alpha: 0.7),
                            foregroundColor: Colors.white,
                            isLoading: isLoading,
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
    ).then((_) => V3TextUtils.disposeController('search'));
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

  /// Dropdown za override adrese u dijalogu rezervacije.
  /// Putnikove 2 adrese za grad su na vrhu liste (označene ★), zatim sve ostale.
  Widget _buildAdresaOverride({
    required V3Putnik putnik,
    required String grad,
    required V3Adresa? selected,
    required ValueChanged<V3Adresa?> onChanged,
  }) {
    final isBC = grad.toUpperCase() == 'BC';
    final id1 = isBC ? putnik.adresaBcId : putnik.adresaVsId;
    final id2 = isBC ? putnik.adresaBcId2 : putnik.adresaVsId2;
    final adresa1 = V3AdresaService.getAdresaById(id1);
    final adresa2 = V3AdresaService.getAdresaById(id2);

    // Sve adrese za grad, bez duplikata
    final sve = V3AdresaService.getAdreseZaGrad(grad);
    final putnikoviIds = {if (adresa1 != null) adresa1.id, if (adresa2 != null) adresa2.id};
    final ostale = sve.where((a) => !putnikoviIds.contains(a.id)).toList();

    // Izgradnja stavki: putnikove adrese prve (★), pa separator, pa ostale
    final items = <DropdownMenuItem<V3Adresa?>>[];

    // "default" opcija — bez override
    items.add(const DropdownMenuItem<V3Adresa?>(
      value: null,
      child: Text('— putnikova adresa —', style: TextStyle(fontSize: 13, color: Colors.grey)),
    ));

    if (adresa1 != null) {
      items.add(DropdownMenuItem<V3Adresa?>(
        value: adresa1,
        child: Text('★ ${adresa1.naziv}',
            overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ));
    }
    if (adresa2 != null) {
      items.add(DropdownMenuItem<V3Adresa?>(
        value: adresa2,
        child: Text('★ ${adresa2.naziv}',
            overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ));
    }

    for (final a in ostale) {
      items.add(DropdownMenuItem<V3Adresa?>(
        value: a,
        child: V3SafeText.userAddress(a.naziv, style: const TextStyle(fontSize: 13)),
      ));
    }

    return V3ContainerUtils.iconContainer(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      backgroundColor: Colors.white,
      borderRadiusGeometry: BorderRadius.circular(12),
      border: Border.all(color: selected != null ? Colors.blue.shade400 : Colors.grey.shade400),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: Colors.blueAccent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<V3Adresa?>(
                value: selected,
                isExpanded: true,
                isDense: true,
                hint: const Text('Adresa (opciono)', style: TextStyle(fontSize: 13, color: Colors.grey)),
                items: items,
                onChanged: onChanged,
              ),
            ),
          ),
          if (selected != null)
            GestureDetector(
              onTap: () => onChanged(null),
              child: const Icon(Icons.clear, size: 18, color: Colors.grey),
            ),
        ],
      ),
    );
  }

  // ─── Dialog: Račun za firme (B2B) ────────────────────────────────
  void _showRacunZaFirmeDialog() {
    // Pripremi listu putnika sa aktivnim zahtevima za odabrani dan/grad/vreme
    final putnici = V3PutnikService.getKombinovaniPutniciFiltrirano(
      grad: _selectedGrad,
      vreme: _selectedVreme,
    );

    if (putnici.isEmpty) {
      V3AppSnackBar.warning(context, '⚠️ Nema putnika za odabrani polazak');
      return;
    }

    final selected = <String, bool>{};
    final ceneController = <String, TextEditingController>{};
    final brojVoznjiController = <String, TextEditingController>{};

    for (final p in putnici) {
      final id = (p['id'] ?? p['putnik_id'] ?? '').toString();
      selected[id] = false;
      ceneController[id] = TextEditingController(text: '1500');
      brojVoznjiController[id] = TextEditingController(text: '1');
    }

    DateTime datumPrometa = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFF1A2035),
          title: const Text('Račun za firme', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Datum prometa
                Row(
                  children: [
                    const Text('Datum prometa:', style: TextStyle(color: Colors.white70)),
                    const SizedBox(width: 8),
                    V3ButtonUtils.textButton(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: datumPrometa,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (d != null) setS(() => datumPrometa = d);
                      },
                      text: '${datumPrometa.day}.${datumPrometa.month}.${datumPrometa.year}',
                      foregroundColor: Colors.amber,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Lista putnika
                ...putnici.map((p) {
                  final id = (p['id'] ?? p['putnik_id'] ?? '').toString();
                  final ime = p['ime_prezime']?.toString() ?? p['imePrezime']?.toString() ?? '---';
                  return CheckboxListTile(
                    value: selected[id] ?? false,
                    onChanged: (v) => setS(() => selected[id] = v ?? false),
                    title: Text(ime, style: const TextStyle(color: Colors.white)),
                    subtitle: selected[id] == true
                        ? Row(children: [
                            Expanded(
                              child: V3InputUtils.numberField(
                                controller: brojVoznjiController[id]!,
                                label: 'Dana',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: V3InputUtils.numberField(
                                controller: ceneController[id]!,
                                label: 'Cena/dan',
                              ),
                            ),
                          ])
                        : null,
                    activeColor: Colors.green,
                  );
                }),
              ],
            ),
          ),
          actions: [
            V3ButtonUtils.textButton(
              onPressed: () => Navigator.pop(ctx),
              text: 'Otkaži',
              foregroundColor: Colors.red,
            ),
            V3ButtonUtils.successButton(
              onPressed: () async {
                final odabrani = putnici.where((p) {
                  final id = (p['id'] ?? p['putnik_id'] ?? '').toString();
                  return selected[id] == true;
                }).toList();

                if (odabrani.isEmpty) {
                  V3AppSnackBar.warning(ctx, '⚠️ Odaberite barem jednog putnika');
                  return;
                }

                Navigator.pop(ctx);

                final racuniPodaci = <Map<String, dynamic>>[];
                for (final p in odabrani) {
                  final id = (p['id'] ?? p['putnik_id'] ?? '').toString();
                  final ime = p['ime_prezime']?.toString() ?? p['imePrezime']?.toString() ?? '---';
                  final cena = double.tryParse(ceneController[id]?.text ?? '') ?? 1500;
                  final dana = double.tryParse(brojVoznjiController[id]?.text ?? '') ?? 1;
                  final broj = await V3RacunService.getNextBrojRacuna();
                  racuniPodaci.add({
                    'putnik_id': id,
                    'ime_prezime': ime,
                    'cena_po_voznji': cena,
                    'broj_voznji': dana,
                    'broj_racuna': broj,
                  });
                }

                if (!mounted) return;
                await V3RacunService.stampajRacuneZaFirme(
                  racuniPodaci: racuniPodaci,
                  context: context,
                  datumPrometa: datumPrometa,
                );

                // Oslobodi controllere
                for (final c in ceneController.values) c.dispose();
                for (final c in brojVoznjiController.values) c.dispose();
              },
              text: 'Štampaj',
            ),
          ],
        ),
      ),
    ).then((_) {
      for (final c in ceneController.values) c.dispose();
      for (final c in brojVoznjiController.values) c.dispose();
    });
  }

  // ─── Dialog: Novi račun za fizičko lice ───────────────────────────
  void _showNoviRacunDialog() {
    final kolicinaCtrl = TextEditingController(text: '1');
    String jedMera = 'usluga';
    DateTime datumPrometa = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFF1A2035),
          title: const Text('Novi račun', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogField(V3TextUtils.imeController, 'Ime i prezime kupca'),
                const SizedBox(height: 8),
                _dialogField(V3TextUtils.adresaController, 'Adresa kupca'),
                const SizedBox(height: 8),
                _dialogField(V3TextUtils.opisController, 'Opis usluge'),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _dialogField(V3TextUtils.iznosController, 'Cena', numeric: true)),
                  const SizedBox(width: 8),
                  Expanded(child: _dialogField(kolicinaCtrl, 'Količina', numeric: true)),
                ]),
                const SizedBox(height: 8),
                // Jedinica mjere
                DropdownButtonFormField<String>(
                  value: jedMera,
                  dropdownColor: const Color(0xFF1A2035),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Jedinica mere',
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white30),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'usluga', child: Text('usluga')),
                    DropdownMenuItem(value: 'dan', child: Text('dan')),
                    DropdownMenuItem(value: 'kom', child: Text('kom')),
                    DropdownMenuItem(value: 'sat', child: Text('sat')),
                    DropdownMenuItem(value: 'km', child: Text('km')),
                  ],
                  onChanged: (v) => setS(() => jedMera = v ?? 'usluga'),
                ),
                const SizedBox(height: 8),
                // Datum prometa
                Row(children: [
                  const Text('Datum prometa:', style: TextStyle(color: Colors.white70)),
                  const SizedBox(width: 8),
                  V3ButtonUtils.textButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: datumPrometa,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (d != null) setS(() => datumPrometa = d);
                    },
                    text: '${datumPrometa.day}.${datumPrometa.month}.${datumPrometa.year}',
                    foregroundColor: Colors.amber,
                  ),
                ]),
              ],
            ),
          ),
          actions: [
            V3ButtonUtils.textButton(
              onPressed: () => Navigator.pop(ctx),
              text: 'Otkaži',
              foregroundColor: Colors.red,
            ),
            V3ButtonUtils.successButton(
              onPressed: () async {
                if (V3TextUtils.isEmpty('ime') || V3TextUtils.isEmpty('opis')) {
                  V3AppSnackBar.error(ctx, '⚠️ Popunite ime i opis');
                  return;
                }
                final cena = double.tryParse(V3TextUtils.getControllerText('iznos').trim()) ?? 0;
                final kolicina = double.tryParse(kolicinaCtrl.text.trim()) ?? 1;
                if (cena <= 0) {
                  V3AppSnackBar.error(ctx, '⚠️ Unesite ispravnu cenu');
                  return;
                }

                Navigator.pop(ctx);
                final broj = await V3RacunService.getNextBrojRacuna();
                if (!mounted) return;
                await V3RacunService.stampajRacun(
                  brojRacuna: broj,
                  imePrezimeKupca: V3TextUtils.getControllerText('ime').trim(),
                  adresaKupca: V3TextUtils.getControllerText('adresa').trim(),
                  opisUsluge: V3TextUtils.getControllerText('opis').trim(),
                  cena: cena,
                  kolicina: kolicina,
                  jedinicaMere: jedMera,
                  datumPrometa: datumPrometa,
                  context: context,
                );
              },
              text: 'Štampaj',
            ),
          ],
        ),
      ),
    ).then((_) {
      V3TextUtils.disposeController('ime');
      V3TextUtils.disposeController('adresa');
      V3TextUtils.disposeController('opis');
      V3TextUtils.disposeController('iznos');
      kolicinaCtrl.dispose();
    });
  }

  Widget _dialogField(TextEditingController ctrl, String label, {bool numeric = false}) {
    return numeric
        ? V3InputUtils.numberField(
            controller: ctrl,
            label: label,
          )
        : V3InputUtils.textField(
            controller: ctrl,
            label: label,
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
          body: V3ContainerUtils.gradientContainer(
            gradient: V2ThemeManager().currentGradient,
            child: const Center(child: CircularProgressIndicator(color: Colors.white)),
          ),
        ),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: StreamBuilder<List<V3OperativnaNedeljaEntry>>(
        stream: _operativnaStream,
        builder: (context, snapshot) {
          final sviZapisi = snapshot.data ?? [];

          // Pomoćna funkcija za normalizaciju vremena (HH:mm)
          String normalizeVreme(String? v) {
            if (v == null || v.isEmpty) return '';
            final parts = v.split(':');
            if (parts.length >= 2) return '${parts[0]}:${parts[1]}';
            return v;
          }

          String slotVreme(V3OperativnaNedeljaEntry z) => z.dodeljivoVreme ?? '';

          final selectedVremeNorm = normalizeVreme(_selectedVreme);

          // Lista: datum dolazi iz stream-a, filtriraj samo po gradu i vremenu
          final currentVozacId = V3VozacService.currentVozac?.id;
          final prikazaniZapisi = sviZapisi.where((z) {
            if (!z.aktivno) return false;
            if (z.grad != _selectedGrad) return false;
            if (normalizeVreme(slotVreme(z)) != selectedVremeNorm) return false;
            if (z.statusFinal == 'odbijeno') return false;
            if (z.statusFinal == 'obrada') return false;
            return true;
          }).toList()
            ..sort((a, b) {
              int sortRank(V3OperativnaNedeljaEntry e) {
                if (e.statusFinal == 'otkazano') return 3;
                if (e.pokupljen) return 2;
                // Provjeri da li je putnik dodijeljen logovanom vozaču
                if (currentVozacId != null) {
                  final indiv = _getVozacZaPutnika(e.putnikId, e.grad ?? '', slotVreme(e), _selectedDatumIso);
                  if (indiv != null) {
                    return indiv.id == currentVozacId ? 0 : 1;
                  }
                }
                return 1;
              }

              final aRank = sortRank(a);
              final bRank = sortRank(b);
              if (aRank != bRank) return aRank.compareTo(bRank);
              final aIme = V3PutnikService.getPutnikById(a.putnikId)?.imePrezime ?? '';
              final bIme = V3PutnikService.getPutnikById(b.putnikId)?.imePrezime ?? '';
              return aIme.compareTo(bIme);
            });

          // Brojač po gradu/vremenu za bottom nav bar (nav bar prikazuje oba grada)
          int getPutnikCount(String grad, String vreme) {
            final targetVremeNorm = normalizeVreme(vreme);
            return sviZapisi.where((z) {
              if (!z.aktivno) return false;
              if (z.grad != grad) return false;
              if (normalizeVreme(slotVreme(z)) != targetVremeNorm) return false;
              if (z.statusFinal == 'otkazano' || z.statusFinal == 'odbijeno') return false;
              if (z.statusFinal == 'obrada') return false;
              return true;
            }).fold(0, (sum, z) => sum + z.brojMesta);
          }

          // Kapacitet
          int? getKapacitet(String grad, String vreme) {
            final datum = DateTime.tryParse(_selectedDatumIso) ?? DateTime.now();
            return V3OperativnaNedeljaService.getKapacitetVozila(grad, vreme, datum);
          }

          Color? getVozacColorForTermin(String grad, String vreme) {
            final vremeNorm = V2GradAdresaValidator.normalizeTime(vreme);
            final rm = V3MasterRealtimeManager.instance;
            for (final row in rm.v3GpsRasporedCache.values) {
              if (row['grad'] != grad) continue;
              if (row['aktivno'] != true) continue;
              if (V3DanHelper.parseIsoDatePart(row['datum'] as String? ?? '') != _selectedDatumIso) continue;
              if (V2GradAdresaValidator.normalizeTime(row['vreme'] as String? ?? '') != vremeNorm) continue;
              final vozacId = row['vozac_id'] as String?;
              if (vozacId == null || vozacId.isEmpty) continue;
              final vozac = V3VozacService.getVozacById(vozacId);
              if (vozac != null) {
                return _parseVozacColor(vozac.boja);
              }
            }
            return null;
          }

          final textScaleFactor = MediaQuery.textScalerOf(context).scale(1.0);
          final headerScaleExtra = (textScaleFactor - 1.0).clamp(0.0, 0.6).toDouble();
          final appBarHeight = 106 + (headerScaleExtra * 20);
          final headerControlHeight = 33 + (headerScaleExtra * 8);
          final aktivnaNedeljaAnchor = V3DanHelper.schedulingWeekAnchor();
          final ponedeljak = V3DanHelper.datumZaDanAbbrUTekucojSedmici('pon', anchor: aktivnaNedeljaAnchor);
          final petak = V3DanHelper.datumZaDanAbbrUTekucojSedmici('pet', anchor: aktivnaNedeljaAnchor);
          final aktivnaNedelja =
              'Aktivna nedelja: ${ponedeljak.day.toString().padLeft(2, '0')}.${ponedeljak.month.toString().padLeft(2, '0')} - ${petak.day.toString().padLeft(2, '0')}.${petak.month.toString().padLeft(2, '0')}';

          return V3ContainerUtils.gradientContainer(
            gradient: V2ThemeManager().currentGradient,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: PreferredSize(
                preferredSize: Size.fromHeight(appBarHeight),
                child: V3ContainerUtils.iconContainer(
                  backgroundColor: Theme.of(context).glassContainer,
                  border: Border.all(color: Theme.of(context).glassBorder, width: 0.8),
                  borderRadiusGeometry: const BorderRadius.only(
                    bottomLeft: Radius.circular(25),
                    bottomRight: Radius.circular(25),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          // Red 1 - naslov
                          Row(
                            children: [
                              Expanded(
                                child: Center(
                                  child: Text(
                                    'R E Z E R V A C I J E',
                                    style: TextStyle(
                                      fontSize: 16,
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
                          Text(
                            aktivnaNedelja,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.85),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          // Red 2 - dan
                          Row(
                            children: [
                              // Sat sa sekundama
                              Expanded(
                                child: V3ContainerUtils.iconContainer(
                                  height: headerControlHeight,
                                  padding: const EdgeInsets.all(6),
                                  backgroundColor: Theme.of(context).glassContainer,
                                  borderRadiusGeometry: BorderRadius.circular(14),
                                  border: Border.all(color: Theme.of(context).glassBorder, width: 0.8),
                                  child: Center(
                                    child: V3LiveClockText(
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onPrimary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              // Dan dropdown
                              Expanded(
                                child: V3ContainerUtils.iconContainer(
                                  height: headerControlHeight,
                                  padding: const EdgeInsets.all(6),
                                  backgroundColor: Theme.of(context).glassContainer,
                                  borderRadiusGeometry: BorderRadius.circular(14),
                                  border: Border.all(color: Theme.of(context).glassBorder, width: 0.8),
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
                                          maxLines: 1,
                                          softWrap: false,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      dropdownStyleData: DropdownStyleData(
                                        width: 170,
                                        maxHeight: 320,
                                        decoration: BoxDecoration(
                                          gradient: Theme.of(context).backgroundGradient,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Theme.of(context).glassBorder, width: 0.8),
                                        ),
                                        elevation: 8,
                                      ),
                                      menuItemStyleData: const MenuItemStyleData(
                                        height: 44,
                                      ),
                                      items: V3DanHelper.dayNames
                                          .map((d) => DropdownMenuItem(
                                                value: d,
                                                child: Center(
                                                  child: Text(
                                                    d,
                                                    style: TextStyle(
                                                      color: Theme.of(context).colorScheme.onPrimary,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                    maxLines: 1,
                                                    softWrap: false,
                                                    overflow: TextOverflow.ellipsis,
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                              ))
                                          .toList(),
                                      onChanged: (val) {
                                        setState(() {
                                          _selectedDay = val!;
                                          _syncSelectedSlotForDatum(_selectedDatumIso);
                                          _operativnaStream = _buildOperativnaStream(_selectedDatumIso);
                                        });
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
                  // Update banner (opcioni/obavezni)
                  const V3UpdateBanner(),
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
                        if (!_isAdmin) ...[
                          Expanded(
                            child: _V3HomeButton(
                              label: 'Ja',
                              icon: Icons.person,
                              onTap: () => V3NavigationUtils.pushScreen(
                                context,
                                const V3VozacScreen(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (_isAdmin) ...[
                          Expanded(
                            child: _V3HomeButton(
                              label: 'Admin',
                              icon: Icons.admin_panel_settings,
                              onTap: () => V3NavigationUtils.pushScreen(
                                context,
                                const V3AdminScreen(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: _V3HomeButton(
                              label: 'Ja',
                              icon: Icons.person,
                              onTap: () => V3NavigationUtils.pushScreen(
                                context,
                                const V3VozacScreen(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: PopupMenuButton<String>(
                              tooltip: 'Štampaj',
                              offset: const Offset(0, -150),
                              onSelected: (val) {
                                if (val == 'spisak') {
                                  V3PrintingService.printPutniksList(
                                    datumIso: _selectedDatumIso,
                                    dan: _selectedDay,
                                    vreme: _selectedVreme,
                                    grad: _selectedGrad,
                                    context: context,
                                  );
                                } else if (val == 'racun_postojeci') {
                                  _showRacunZaFirmeDialog();
                                } else if (val == 'racun_novi') {
                                  _showNoviRacunDialog();
                                }
                              },
                              child: V3ContainerUtils.iconContainer(
                                padding: const EdgeInsets.all(6),
                                backgroundColor: Theme.of(context).glassContainer,
                                border: Border.all(color: Theme.of(context).glassBorder, width: 0.8),
                                borderRadiusGeometry: BorderRadius.circular(12),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.print, color: Theme.of(context).colorScheme.onPrimary, size: 18),
                                    const SizedBox(height: 4),
                                    SizedBox(
                                      height: V3ContainerUtils.responsiveHeight(context, 16),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text('Štampaj',
                                            style: TextStyle(
                                                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'spisak',
                                  child: Row(children: [
                                    Icon(Icons.list_alt, color: Colors.blue),
                                    SizedBox(width: 8),
                                    Text('Štampaj spisak'),
                                  ]),
                                ),
                                const PopupMenuDivider(),
                                const PopupMenuItem(
                                  value: 'racun_postojeci',
                                  child: Row(children: [
                                    Icon(Icons.people, color: Colors.green),
                                    SizedBox(width: 8),
                                    Text('Račun - postojeći'),
                                  ]),
                                ),
                                const PopupMenuItem(
                                  value: 'racun_novi',
                                  child: Row(children: [
                                    Icon(Icons.person_add, color: Colors.orange),
                                    SizedBox(width: 8),
                                    Text('Račun - novi'),
                                  ]),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Lista putnika/zahteva
                  Expanded(
                    child: prikazaniZapisi.isEmpty
                        ? Center(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              child: V3ContainerUtils.iconContainer(
                                padding: const EdgeInsets.all(16),
                                backgroundColor: Theme.of(context).glassContainer,
                                border: Border.all(color: Theme.of(context).glassBorder, width: 0.8),
                                borderRadiusGeometry: BorderRadius.circular(12),
                                child: const Text(
                                  'Nema planiranih putnika.',
                                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(top: 4, bottom: 16),
                            itemCount: prikazaniZapisi.length,
                            itemBuilder: (ctx, i) {
                              final z = prikazaniZapisi[i];
                              final p = V3PutnikService.getPutnikById(z.putnikId);
                              if (p == null) return const SizedBox.shrink();

                              final grad = z.grad ?? '';
                              final vreme = slotVreme(z);
                              final indivVozac = _getVozacZaPutnika(z.putnikId, grad, vreme, _selectedDatumIso);
                              final vozacBoja = indivVozac != null
                                  ? _parseVozacColor(indivVozac.boja)
                                  : getVozacColorForTermin(grad, vreme);

                              // Kumulativni redni broj — uzima u obzir broj_mesta prethodnih putnika
                              final redniBroj =
                                  prikazaniZapisi.sublist(0, i).fold(0, (sum, e) => sum + e.brojMesta) + 1;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: V3PutnikCard(
                                  putnik: p,
                                  entry: z,
                                  redniBroj: redniBroj,
                                  vozacBoja: vozacBoja,
                                ),
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
                  return _buildBottomNavBar(getPutnikCount, getKapacitet, getVozacColorForTermin);
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomNavBar(
    int Function(String, String) getPutnikCount,
    int? Function(String, String) getKapacitet,
    Color? Function(String, String) getVozacColor,
  ) {
    return ValueListenableBuilder<String>(
      valueListenable: navBarTypeNotifier,
      builder: (context, navType, _) {
        if (navType == 'zimski') {
          return V3BottomNavBarZimski(
            sviPolasci: _sviPolasci,
            selectedGrad: _selectedGrad,
            selectedVreme: _selectedVreme,
            onPolazakChanged: (grad, vreme) {
              setState(() {
                _selectedGrad = grad;
                _selectedVreme = vreme;
              });
            },
            getPutnikCount: getPutnikCount,
            getKapacitet: getKapacitet,
            showVozacBoja: true,
            getVozacColor: getVozacColor,
            bcVremena: _bcVremena,
            vsVremena: _vsVremena,
          );
        } else if (navType == 'praznici') {
          return V3BottomNavBarPraznici(
            sviPolasci: _sviPolasci,
            selectedGrad: _selectedGrad,
            selectedVreme: _selectedVreme,
            onPolazakChanged: (grad, vreme) {
              setState(() {
                _selectedGrad = grad;
                _selectedVreme = vreme;
              });
            },
            getPutnikCount: getPutnikCount,
            getKapacitet: getKapacitet,
            showVozacBoja: true,
            getVozacColor: getVozacColor,
            bcVremena: _bcVremena,
            vsVremena: _vsVremena,
          );
        } else {
          // Default: letnji
          return V3BottomNavBarLetnji(
            sviPolasci: _sviPolasci,
            selectedGrad: _selectedGrad,
            selectedVreme: _selectedVreme,
            onPolazakChanged: (grad, vreme) {
              setState(() {
                _selectedGrad = grad;
                _selectedVreme = vreme;
              });
            },
            getPutnikCount: getPutnikCount,
            getKapacitet: getKapacitet,
            showVozacBoja: true,
            getVozacColor: getVozacColor,
            bcVremena: _bcVremena,
            vsVremena: _vsVremena,
          );
        }
      },
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
      child: V3ContainerUtils.iconContainer(
        padding: const EdgeInsets.all(6),
        backgroundColor: Theme.of(context).glassContainer,
        border: Border.all(color: Theme.of(context).glassBorder, width: 0.8),
        borderRadiusGeometry: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.onPrimary, size: 18),
            const SizedBox(height: 4),
            SizedBox(
              height: V3ContainerUtils.responsiveHeight(context, 16),
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
