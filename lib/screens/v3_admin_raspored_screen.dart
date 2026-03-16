import 'package:flutter/material.dart';

import '../config/v2_route_config.dart';
import '../globals.dart';
import '../models/v3_putnik.dart';
import '../models/v3_vozac.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_operativna_nedelja_service.dart';
import '../services/v3/v3_putnik_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../theme.dart';
import '../utils/v2_grad_adresa_validator.dart';
import '../utils/v3_app_snack_bar.dart';
import '../widgets/v3_bottom_nav_bar_letnji.dart';
import '../widgets/v3_bottom_nav_bar_praznici.dart';
import '../widgets/v3_bottom_nav_bar_zimski.dart';

/// V3 ekran za upravljanje rasporedom vozača.
/// Admin dodeljuje vozača terminu (v3_raspored_termin) ili putniku
/// individualno (v3_raspored_putnik).
class V3AdminRasporedScreen extends StatefulWidget {
  const V3AdminRasporedScreen({super.key});

  @override
  State<V3AdminRasporedScreen> createState() => _V3AdminRasporedScreenState();
}

class _V3AdminRasporedScreenState extends State<V3AdminRasporedScreen> {
  String _selectedGrad = 'BC';
  String _selectedVreme = '';
  String _selectedDay = 'Ponedeljak';

  /// ISO datum za izabrani dan — ako je dan prošao, skače u sljedeću sedmicu
  String get _selectedDatumIso => V3DanHelper.datumIsoZaDanPuni(_selectedDay);

  List<String> get _bcVremena => V2RouteConfig.getVremenaByNavType('BC', navBarTypeNotifier.value);
  List<String> get _vsVremena => V2RouteConfig.getVremenaByNavType('VS', navBarTypeNotifier.value);
  List<String> get _sviPolasci => [
        ..._bcVremena.map((v) => '$v BC'),
        ..._vsVremena.map((v) => '$v VS'),
      ];

  @override
  void initState() {
    super.initState();
    _selectedDay = V3DanHelper.defaultDay();
    _autoSelectNajblizeVreme();
  }

  void _autoSelectNajblizeVreme() {
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final bcList = _bcVremena;
    String? najblize;
    for (final v in bcList) {
      final parts = v.split(':');
      if (parts.length < 2) continue;
      final vMin = (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
      if (vMin >= nowMin) {
        najblize = v;
        break;
      }
    }
    najblize ??= bcList.isNotEmpty ? bcList.last : '';
    _selectedGrad = 'BC';
    _selectedVreme = najblize;
  }

  // ─── Cache helpers ────────────────────────────────────────────────────────

  /// Vozač za termin iz v3_raspored_termin
  V3Vozac? _getVozacZaTermin(String grad, String vreme) {
    final rm = V3MasterRealtimeManager.instance;
    final normV = V2GradAdresaValidator.normalizeTime(vreme);
    final datum = _selectedDatumIso;
    for (final row in rm.rasporedTerminCache.values) {
      if ((row['datum'] as String?)?.split('T')[0] == datum &&
          row['grad'] == grad &&
          V2GradAdresaValidator.normalizeTime(row['vreme'] as String? ?? '') == normV) {
        final vozacId = row['vozac_id'] as String?;
        if (vozacId != null) return V3VozacService.getVozacById(vozacId);
      }
    }
    return null;
  }

  /// Vozač za individulanu dodjelu putnika iz v3_raspored_putnik
  V3Vozac? _getVozacZaPutnika(String putnikId, String grad, String vreme) {
    final rm = V3MasterRealtimeManager.instance;
    final normV = V2GradAdresaValidator.normalizeTime(vreme);
    final datum = _selectedDatumIso;
    for (final row in rm.rasporedPutnikCache.values) {
      if (row['putnik_id'] == putnikId &&
          row['grad'] == grad &&
          V2GradAdresaValidator.normalizeTime(row['vreme'] as String? ?? '') == normV &&
          (row['datum'] as String?)?.split('T')[0] == datum) {
        final vozacId = row['vozac_id'] as String?;
        if (vozacId != null) return V3VozacService.getVozacById(vozacId);
      }
    }
    return null;
  }

  String _rasporedPutnikRowId(String putnikId, String grad, String vreme) {
    final rm = V3MasterRealtimeManager.instance;
    final normV = V2GradAdresaValidator.normalizeTime(vreme);
    final datum = _selectedDatumIso;
    for (final entry in rm.rasporedPutnikCache.entries) {
      final row = entry.value;
      if (row['putnik_id'] == putnikId &&
          row['grad'] == grad &&
          V2GradAdresaValidator.normalizeTime(row['vreme'] as String? ?? '') == normV &&
          (row['datum'] as String?)?.split('T')[0] == datum) {
        return entry.key;
      }
    }
    return '';
  }

  String _rasporedTerminRowId(String grad, String vreme) {
    final rm = V3MasterRealtimeManager.instance;
    final normV = V2GradAdresaValidator.normalizeTime(vreme);
    final datum = _selectedDatumIso;
    for (final entry in rm.rasporedTerminCache.entries) {
      final row = entry.value;
      if ((row['datum'] as String?)?.split('T')[0] == datum &&
          row['grad'] == grad &&
          V2GradAdresaValidator.normalizeTime(row['vreme'] as String? ?? '') == normV) {
        return entry.key;
      }
    }
    return '';
  }

  int _getPutnikCount(String grad, String vreme) {
    final normV = V2GradAdresaValidator.normalizeTime(vreme);
    final targetDatum = _selectedDatumIso; // već uračunat skok u sljedeću sedmicu
    return V3MasterRealtimeManager.instance.operativnaNedeljaCache.values.where((r) {
      final datumStr = r['datum'] as String?;
      if (datumStr == null) return false;
      final d = datumStr.split('T')[0];
      return d == targetDatum &&
          r['grad'] == grad &&
          V2GradAdresaValidator.normalizeTime(r['vreme'] as String? ?? '') == normV &&
          r['status_final'] != 'odbijeno' &&
          r['status_final'] != 'otkazano';
    }).fold(0, (sum, r) => sum + ((r['broj_mesta'] as num?)?.toInt() ?? 1));
  }

  Color? _getVozacBoja(String grad, String vreme) {
    final v = _getVozacZaTermin(grad, vreme);
    return v != null ? _parseColor(v.boja) : null;
  }

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return Colors.blueAccent;
    final h = hex.replaceAll('#', '');
    try {
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) {
      return Colors.blueAccent;
    }
  }

  // ─── DB operacije ─────────────────────────────────────────────────────────

  Future<void> _dodelijTermin(String grad, String vreme, V3Vozac vozac) async {
    try {
      final datum = _selectedDatumIso;
      await supabase.from('v3_raspored_termin').delete().eq('datum', datum).eq('grad', grad).eq('vreme', vreme);
      await supabase.from('v3_raspored_termin').insert({
        'datum': datum,
        'grad': grad,
        'vreme': vreme,
        'vozac_id': vozac.id,
      });
      if (mounted) V3AppSnackBar.success(context, '✅ ${vozac.imePrezime} → $grad $vreme ($datum)');
    } catch (e) {
      if (mounted) V3AppSnackBar.error(context, '❌ Greška: $e');
    }
  }

  Future<void> _ukloniTermin(String grad, String vreme) async {
    final rowId = _rasporedTerminRowId(grad, vreme);
    try {
      if (rowId.isNotEmpty) {
        await supabase.from('v3_raspored_termin').delete().eq('id', rowId);
      } else {
        await supabase
            .from('v3_raspored_termin')
            .delete()
            .eq('datum', _selectedDatumIso)
            .eq('grad', grad)
            .eq('vreme', vreme);
      }
      if (mounted) V3AppSnackBar.success(context, '🗑️ Dodjela uklonjena: $grad $vreme ($_selectedDatumIso)');
    } catch (e) {
      if (mounted) V3AppSnackBar.error(context, '❌ Greška: $e');
    }
  }

  Future<void> _dodelijPutniku(String putnikId, V3Vozac vozac, String grad, String vreme) async {
    try {
      final datum = _selectedDatumIso;
      debugPrint('[DODELI] putnikId=$putnikId vozacId=${vozac.id} grad=$grad vreme=$vreme datum=$datum');
      await supabase
          .from('v3_raspored_putnik')
          .delete()
          .eq('putnik_id', putnikId)
          .eq('grad', grad)
          .eq('vreme', vreme)
          .eq('datum', datum);
      debugPrint('[DODELI] delete OK, inserting...');
      await supabase.from('v3_raspored_putnik').insert({
        'putnik_id': putnikId,
        'vozac_id': vozac.id,
        'grad': grad,
        'vreme': vreme,
        'datum': datum,
      });
      debugPrint('[DODELI] insert OK');
      if (mounted) V3AppSnackBar.success(context, '✅ ${vozac.imePrezime} → putnik ($datum)');
    } catch (e, st) {
      debugPrint('[DODELI ERROR] $e\n$st');
      if (mounted) V3AppSnackBar.error(context, '❌ Greška: $e');
    }
  }

  Future<void> _ukloniPutnikDodjelu(String putnikId, String grad, String vreme) async {
    final rowId = _rasporedPutnikRowId(putnikId, grad, vreme);
    try {
      if (rowId.isNotEmpty) {
        await supabase.from('v3_raspored_putnik').delete().eq('id', rowId);
      } else {
        await supabase
            .from('v3_raspored_putnik')
            .delete()
            .eq('putnik_id', putnikId)
            .eq('grad', grad)
            .eq('vreme', vreme)
            .eq('datum', _selectedDatumIso);
      }
      if (mounted) V3AppSnackBar.success(context, '🗑️ Individualna dodjela uklonjena');
    } catch (e) {
      if (mounted) V3AppSnackBar.error(context, '❌ Greška: $e');
    }
  }

  // ─── Dialozi ──────────────────────────────────────────────────────────────

  Future<void> _showTerminAssignDialog(String grad, String vreme) async {
    final trenutni = _getVozacZaTermin(grad, vreme);
    V3Vozac? odabran = trenutni;
    final vozaci = V3VozacService.getAllVozaci().where((v) => v.aktivno).toList();
    if (vozaci.isEmpty) {
      if (mounted) V3AppSnackBar.warning(context, 'Nema registrovanih vozača');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          decoration: BoxDecoration(
            gradient: Theme.of(context).backgroundGradient,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                width: 40,
                height: 4,
                decoration:
                    BoxDecoration(color: Colors.white.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2)),
              )),
              const SizedBox(height: 16),
              Text('🗓️ TERMIN: $grad $vreme — $_selectedDatumIso',
                  style: const TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1)),
              const SizedBox(height: 6),
              const Text('Dodeli vozača terminu',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 16),
              ...vozaci.map((v) => _vozacTile(
                    ime: v.imePrezime,
                    isSelected: odabran?.id == v.id,
                    color: _parseColor(v.boja),
                    onTap: () => setS(() => odabran = odabran?.id == v.id ? null : v),
                  )),
              const SizedBox(height: 8),
              if (trenutni != null)
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _ukloniTermin(grad, vreme);
                  },
                  icon: const Icon(Icons.clear, color: Colors.redAccent, size: 18),
                  label: const Text('Ukloni dodjelu termina', style: TextStyle(color: Colors.redAccent)),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: odabran == null
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          await _dodelijTermin(grad, vreme, odabran!);
                        },
                  child: const Text('Potvrdi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPutnikAssignDialog(V3OperativnaNedeljaEntry zahtev) async {
    final trenutni = _getVozacZaPutnika(zahtev.putnikId, _selectedGrad, _selectedVreme);
    V3Vozac? odabran = trenutni;
    final vozaci = V3VozacService.getAllVozaci().where((v) => v.aktivno).toList();
    if (vozaci.isEmpty) {
      if (mounted) V3AppSnackBar.warning(context, 'Nema registrovanih vozača');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          decoration: BoxDecoration(
            gradient: Theme.of(context).backgroundGradient,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                width: 40,
                height: 4,
                decoration:
                    BoxDecoration(color: Colors.white.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2)),
              )),
              const SizedBox(height: 16),
              Text('👤 ${(zahtev.imePrezime ?? 'Putnik').toUpperCase()}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1)),
              Text('$_selectedGrad $_selectedVreme — $_selectedDatumIso',
                  style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1)),
              const SizedBox(height: 8),
              const Text('Dodeli vozača putniku',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 16),
              ...vozaci.map((v) => _vozacTile(
                    ime: v.imePrezime,
                    isSelected: odabran?.id == v.id,
                    color: _parseColor(v.boja),
                    onTap: () => setS(() => odabran = odabran?.id == v.id ? null : v),
                  )),
              const SizedBox(height: 8),
              if (trenutni != null)
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _ukloniPutnikDodjelu(zahtev.putnikId, _selectedGrad, _selectedVreme);
                  },
                  icon: const Icon(Icons.person_remove_outlined, color: Colors.redAccent, size: 18),
                  label: const Text('Ukloni individualnu dodjelu', style: TextStyle(color: Colors.redAccent)),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: odabran == null
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          await _dodelijPutniku(zahtev.putnikId, odabran!, _selectedGrad, _selectedVreme);
                        },
                  child: const Text('Potvrdi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<V3OperativnaNedeljaEntry>>(
      stream: V3OperativnaNedeljaService.streamOperativnaNedeljaByDatum(_selectedDatumIso),
      builder: (context, snapshot) {
        final sviZapisi = snapshot.data ?? [];
        final vozacTermin = _getVozacZaTermin(_selectedGrad, _selectedVreme);

        // Zapisi iz operativna_nedelja za selektovani grad+vreme (datum već filtriran streamom)
        final zapisi = _selectedVreme.isNotEmpty
            ? (sviZapisi
                .where((z) =>
                    z.grad == _selectedGrad &&
                    V2GradAdresaValidator.normalizeTime(z.vreme ?? '') ==
                        V2GradAdresaValidator.normalizeTime(_selectedVreme) &&
                    z.statusFinal != 'odbijeno')
                .toList()
              ..sort((a, b) {
                final aOtk = a.statusFinal == 'otkazano' ? 1 : 0;
                final bOtk = b.statusFinal == 'otkazano' ? 1 : 0;
                return aOtk.compareTo(bOtk);
              }))
            : <V3OperativnaNedeljaEntry>[];

        return Scaffold(
          extendBodyBehindAppBar: true,
          extendBody: true,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            centerTitle: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              '🚗 Raspored vozača',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          body: Container(
            decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
            child: SafeArea(
              child: Column(
                children: [
                  // ── Dan chips ──────────────────────────────────────────
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      children: V3DanHelper.dayNames.map((day) {
                        final isSelected = _selectedDay == day;
                        final abbr = V3DanHelper.dayAbbrs[V3DanHelper.dayNames.indexOf(day)];
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () => setState(() => _selectedDay = day),
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white.withValues(alpha: 0.25)
                                    : Theme.of(context).glassContainer.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color:
                                      isSelected ? Colors.white.withValues(alpha: 0.7) : Theme.of(context).glassBorder,
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                abbr.toUpperCase(),
                                style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.white60,
                                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                                  fontSize: 13,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  // ── Termin info traka ──────────────────────────────────
                  if (_selectedVreme.isNotEmpty)
                    _terminInfoTraka(
                      grad: _selectedGrad,
                      vreme: _selectedVreme,
                      vozac: vozacTermin,
                      onTap: () => _showTerminAssignDialog(_selectedGrad, _selectedVreme),
                    ),

                  // ── Lista zahteva ──────────────────────────────────────
                  Expanded(
                    child: _selectedVreme.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inbox, size: 48, color: Colors.white.withValues(alpha: 0.3)),
                                const SizedBox(height: 12),
                                Text(
                                  'Odaberi polazak u donjem meniju',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 15),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : zapisi.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.people_outline, size: 48, color: Colors.white.withValues(alpha: 0.3)),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Nema putnika za ovaj polazak',
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 15),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                physics: const BouncingScrollPhysics(),
                                itemCount: zapisi.length,
                                itemBuilder: (_, i) {
                                  final z = zapisi[i];
                                  final terminDodeljen = vozacTermin != null;
                                  final indivVozac = _getVozacZaPutnika(z.putnikId, _selectedGrad, _selectedVreme);
                                  final vozacBoja = indivVozac != null
                                      ? _parseColor(indivVozac.boja)
                                      : (terminDodeljen ? _parseColor(vozacTermin.boja) : null);

                                  return _ZahtevTile(
                                    zapis: z,
                                    vozacBoja: vozacBoja,
                                    terminJeDodeljen: terminDodeljen,
                                    indivVozacIme: indivVozac?.imePrezime,
                                    redniBroj: i + 1,
                                    onTap: z.statusFinal == 'otkazano' ? null : () => _showPutnikAssignDialog(z),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: ValueListenableBuilder<String>(
            valueListenable: navBarTypeNotifier,
            builder: (context, navType, _) {
              final commonProps = _buildNavBarProps();
              if (navType == 'zimski') {
                return V3BottomNavBarZimski(
                  sviPolasci: commonProps.sviPolasci,
                  selectedGrad: commonProps.selectedGrad,
                  selectedVreme: commonProps.selectedVreme,
                  onPolazakChanged: commonProps.onChanged,
                  getPutnikCount: commonProps.getCount,
                  getKapacitet: commonProps.getKapacitet,
                  showVozacBoja: true,
                  getVozacColor: _getVozacBoja,
                );
              } else if (navType == 'praznici') {
                return V3BottomNavBarPraznici(
                  sviPolasci: commonProps.sviPolasci,
                  selectedGrad: commonProps.selectedGrad,
                  selectedVreme: commonProps.selectedVreme,
                  onPolazakChanged: commonProps.onChanged,
                  getPutnikCount: commonProps.getCount,
                  getKapacitet: commonProps.getKapacitet,
                  showVozacBoja: true,
                  getVozacColor: _getVozacBoja,
                );
              } else {
                return V3BottomNavBarLetnji(
                  sviPolasci: commonProps.sviPolasci,
                  selectedGrad: commonProps.selectedGrad,
                  selectedVreme: commonProps.selectedVreme,
                  onPolazakChanged: commonProps.onChanged,
                  getPutnikCount: commonProps.getCount,
                  getKapacitet: commonProps.getKapacitet,
                  showVozacBoja: true,
                  getVozacColor: _getVozacBoja,
                );
              }
            },
          ),
        );
      },
    );
  }

  _NavBarProps _buildNavBarProps() => _NavBarProps(
        sviPolasci: _sviPolasci,
        selectedGrad: _selectedGrad,
        selectedVreme: _selectedVreme,
        onChanged: (grad, vreme) => setState(() {
          _selectedGrad = grad;
          _selectedVreme = vreme;
        }),
        getCount: _getPutnikCount,
        getKapacitet: (grad, vreme) {
          final datum = DateTime.tryParse(_selectedDatumIso) ?? DateTime.now();
          return V3OperativnaNedeljaService.getKapacitetVozila(grad, vreme, datum);
        },
      );

  // ─── Termin info traka ────────────────────────────────────────────────────
  Widget _terminInfoTraka({
    required String grad,
    required String vreme,
    required V3Vozac? vozac,
    required VoidCallback onTap,
  }) {
    final color = vozac != null ? _parseColor(vozac.boja) : Colors.white24;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
        ),
        child: Row(
          children: [
            Icon(Icons.directions_car, color: color, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                vozac != null ? 'Vozač: ${vozac.imePrezime}' : 'Nema dodjele — tap za dodjelu vozača',
                style: TextStyle(
                  color: vozac != null ? Colors.white : Colors.white54,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            Text('$grad $vreme', style: const TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(width: 8),
            Icon(Icons.edit_outlined, color: color.withValues(alpha: 0.7), size: 16),
          ],
        ),
      ),
    );
  }

  // ─── Vozač tile za bottom sheet ───────────────────────────────────────────
  Widget _vozacTile({
    required String ime,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : Colors.white.withValues(alpha: 0.15),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: color.withValues(alpha: 0.3),
                child: Text(
                  ime.isNotEmpty ? ime[0].toUpperCase() : '?',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                ime,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              if (isSelected) Icon(Icons.check_circle, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── NavBar props helper ──────────────────────────────────────────────────────
class _NavBarProps {
  final List<String> sviPolasci;
  final String selectedGrad;
  final String selectedVreme;
  final void Function(String, String) onChanged;
  final int Function(String, String) getCount;
  final int? Function(String, String) getKapacitet;

  const _NavBarProps({
    required this.sviPolasci,
    required this.selectedGrad,
    required this.selectedVreme,
    required this.onChanged,
    required this.getCount,
    required this.getKapacitet,
  });
}

// ─── Zahtev tile ──────────────────────────────────────────────────────────────
class _ZahtevTile extends StatelessWidget {
  const _ZahtevTile({
    required this.zapis,
    this.vozacBoja,
    this.terminJeDodeljen = false,
    this.indivVozacIme,
    this.redniBroj,
    this.onTap,
  });

  final V3OperativnaNedeljaEntry zapis;
  final Color? vozacBoja;
  final bool terminJeDodeljen;
  final String? indivVozacIme;
  final int? redniBroj;
  final VoidCallback? onTap;

  Color _getTipColor(String tip) {
    switch (tip.toLowerCase()) {
      case 'radnik':
        return const Color(0xFF3B7DD8);
      case 'ucenik':
        return const Color(0xFF44A08D);
      case 'posiljka':
        return const Color(0xFFE65C00);
      case 'dnevni':
        return const Color(0xFFFF6B6B);
      default:
        return Colors.green;
    }
  }

  String _getTipLabel(String tip) {
    switch (tip.toLowerCase()) {
      case 'radnik':
        return 'RADNIK';
      case 'ucenik':
        return 'UCENIK';
      case 'posiljka':
        return 'POSILJKA';
      case 'dnevni':
        return 'DNEVNI';
      default:
        return 'PUTNIK';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOtkazan = zapis.statusFinal == 'otkazano';
    final isPokupljen = zapis.pokupljen;
    final hasIndiv = indivVozacIme != null;

    // Status boje kao V3PutnikCard
    final Color textColor;
    final Color secondaryColor;
    final BoxDecoration cardDecoration;

    if (isOtkazan) {
      textColor = const Color(0xFFB71C1C);
      secondaryColor = const Color(0xFFC62828);
      cardDecoration = BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFCDD2), Color(0xFFEF9A9A)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE57373), width: 1.2),
        boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.15), blurRadius: 4, offset: const Offset(0, 2))],
      );
    } else if (isPokupljen) {
      textColor = const Color(0xFF0D47A1);
      secondaryColor = const Color(0xFF1565C0);
      cardDecoration = BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFBBDEFB), Color(0xFF90CAF9)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF64B5F6), width: 1.2),
        boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.15), blurRadius: 4, offset: const Offset(0, 2))],
      );
    } else {
      textColor = Colors.black87;
      secondaryColor = Colors.grey.shade700;
      final borderColor = vozacBoja ?? const Color(0xFFE0E0E0);
      cardDecoration = BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: vozacBoja != null ? 4.0 : 1.0),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 3, offset: const Offset(0, 1))],
      );
    }

    // Putnik iz cache-a za adresu i tip
    final V3Putnik? putnik = V3PutnikService.getPutnikById(zapis.putnikId);
    final String? adresaNaziv = putnik == null
        ? null
        : ((zapis.grad?.toUpperCase() == 'BC')
            ? (putnik.adresaBcNaziv ?? putnik.adresaBcNaziv2)
            : (putnik.adresaVsNaziv ?? putnik.adresaVsNaziv2));
    final String tipPutnika = putnik?.tipPutnika ?? '';
    final bool hasAdresa = adresaNaziv != null && adresaNaziv.isNotEmpty;
    final bool hasTip = tipPutnika.isNotEmpty;
    final Color tipColor = _getTipColor(tipPutnika);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: cardDecoration,
        child: Padding(
          padding: const EdgeInsets.all(6.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Redni broj
              if (redniBroj != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4.0, top: 2),
                  child: Text(
                    '$redniBroj.',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: textColor),
                  ),
                ),

              // Ime + adresa
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      putnik?.imePrezime ?? zapis.imePrezime ?? '?',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w700,
                        fontStyle: FontStyle.italic,
                        fontSize: 14,
                        decoration: isOtkazan ? TextDecoration.lineThrough : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    if (hasAdresa)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          adresaNaziv,
                          style: TextStyle(fontSize: 13, color: secondaryColor, fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),

              // Desna strana: tip badge + vozač badge / person_add
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasTip)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: tipColor.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _getTipLabel(tipPutnika),
                        style:
                            TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: tipColor, letterSpacing: 0.3),
                      ),
                    ),
                  if (!hasIndiv && !terminJeDodeljen)
                    Icon(Icons.person_add_outlined, color: Colors.grey.shade500, size: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
