import 'package:flutter/material.dart';

import '../config/v2_route_config.dart';
import '../globals.dart';
import '../models/v2_putnik.dart';
import '../services/realtime/v2_master_realtime_manager.dart';
import '../services/v2_audit_log_service.dart';
import '../services/v2_polasci_service.dart';
import '../services/v2_vozac_putnik_service.dart';
import '../services/v2_vozac_raspored_service.dart';
import '../services/v3/v3_kapacitet_service.dart';
import '../theme.dart';
import '../utils/v2_app_snack_bar.dart';
import '../utils/v2_dan_utils.dart';
import '../utils/v2_grad_adresa_validator.dart';
import '../utils/v2_putnik_count_helper.dart';
import '../utils/v2_vozac_cache.dart';
import '../widgets/v2_bottom_nav_bar.dart';

/// Ekran za upravljanje rasporedom vozača
/// Admin može dodijeliti vozača po terminu (vozac_raspored) i po putniku (vozac_putnik).
/// Realtime: automatski osvježava kada se promijeni raspored ili individualna dodjela putnika.
class V2VozacRasporedScreen extends StatefulWidget {
  const V2VozacRasporedScreen({super.key});

  @override
  State<V2VozacRasporedScreen> createState() => _VozacRasporedScreenState();
}

class _VozacRasporedScreenState extends State<V2VozacRasporedScreen> {
  String _selectedGrad = 'BC';
  String _selectedVreme = '';
  String? _selectedDay;

  /// Jedan stream za sve podatke — putnici + raspored + vozacPutnik.
  /// Mijenja se samo kad se promijeni _selectedDay (swap dan).
  late Stream<_RasporedData> _stream;

  List<String> get _days => V2DanUtils.kratice;

  List<String> get _sviPolasci {
    return [
      ...V2RouteConfig.getVremenaByNavType('BC').map((v) => '$v BC'),
      ...V2RouteConfig.getVremenaByNavType('VS').map((v) => '$v VS'),
    ];
  }

  @override
  void initState() {
    super.initState();
    final today = V2DanUtils.odDatuma(DateTime.now());
    _selectedDay = (today == 'sub' || today == 'ned') ? 'pon' : today;
    _autoSelectNajblizeVreme();
    _stream = _buildStream(_selectedDay!);
  }

  /// Kreira stream koji nosi sve podatke za dati dan.
  /// v2StreamFromCache obuhvata sve relevantne tabele i emituje odmah u onListen.
  Stream<_RasporedData> _buildStream(String dan) {
    return V2MasterRealtimeManager.instance.v2StreamFromCache<_RasporedData>(
      tables: const ['v2_polasci', 'v2_vozac_raspored', 'v2_vozac_putnik'],
      build: () => _buildRasporedData(dan),
    );
  }

  _RasporedData _buildRasporedData(String dan) {
    final rm = V2MasterRealtimeManager.instance;
    final putnici = V2PolasciService.fetchPutniciSyncStatic(dan: dan);
    final raspored = rm.rasporedCache.values.map((r) => V2VozacRasporedEntry.fromMap(r)).toList();
    final vozacPutnik = rm.vozacPutnikCache.values.map((r) => V2VozacPutnikEntry.fromMap(r)).toList();
    return _RasporedData(putnici: putnici, raspored: raspored, vozacPutnik: vozacPutnik);
  }

  void _onDayChanged(String day) {
    setState(() {
      _selectedDay = day;
      // Kreira novi stream za novi dan — v2StreamFromCache emituje odmah u onListen.
      _stream = _buildStream(day);
    });
  }

  /// Automatski selektuje najbliže vreme polaska za trenutni čas.
  /// Prioritet: prvo vreme koje je >= sada, fallback na poslednje vreme u listi.
  void _autoSelectNajblizeVreme() {
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;

    // Pokušaj BC prvo (default grad)
    final bcList = V2RouteConfig.getVremenaByNavType('BC');
    String? najblize;
    for (final v in bcList) {
      final parts = v.split(':');
      if (parts.length < 2) continue;
      final vMinutes = (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
      if (vMinutes >= nowMinutes) {
        najblize = v;
        break;
      }
    }
    // Fallback: poslednje vreme u listi
    najblize ??= bcList.isNotEmpty ? bcList.last : '';

    _selectedGrad = 'BC';
    _selectedVreme = najblize;
  }

  void _onPolazakChanged(String grad, String vreme) {
    if (mounted) {
      setState(() {
        _selectedGrad = grad;
        _selectedVreme = vreme;
      });
    }
  }

  Color? _getVozacColorForTermin(String grad, String vreme) =>
      _rasporedGetEntry(grad: grad, vreme: vreme, dan: _selectedDay ?? V2DanUtils.odDatuma(DateTime.now()))
          .let((e) => e != null ? V2VozacCache.getColor(e.vozacId) : null);

  String? _getVozacZaTermin(String grad, String vreme) =>
      _rasporedGetEntry(grad: grad, vreme: vreme, dan: _selectedDay ?? V2DanUtils.odDatuma(DateTime.now()))
          .let((e) => e != null ? V2VozacCache.getImeByUuid(e.vozacId) : null);

  // ═══════════════════════════════════════════════════════════════
  // DIALOZI ZA DODJELU
  // ═══════════════════════════════════════════════════════════════

  /// Dialog: Dodijeli vozača terminu (vozac_raspored)
  Future<void> _showTerminAssignDialog(String grad, String vreme) async {
    final dan = _selectedDay ?? V2DanUtils.odDatuma(DateTime.now());
    final trenutni = _getVozacZaTermin(grad, vreme);
    String? odabranVozac = trenutni;

    final vozaci = V2VozacCache.imenaVozaca;
    if (vozaci.isEmpty) {
      if (mounted) V2AppSnackBar.warning(context, 'Nema registrovanih vozača');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          decoration: BoxDecoration(
            gradient: Theme.of(context).backgroundGradient,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '🗓️ Termin: $grad $vreme — $dan'.toUpperCase(),
                style: const TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1),
              ),
              const SizedBox(height: 8),
              const Text(
                'Dodijeli vozača terminu',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 16),
              ...vozaci.map((ime) => _rasporedVozacTile(
                    ime: ime,
                    isSelected: odabranVozac == ime,
                    color: V2VozacCache.getColor(ime),
                    onTap: () => setSheetState(() => odabranVozac = odabranVozac == ime ? null : ime),
                  )),
              const SizedBox(height: 8),
              if (trenutni != null)
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _ukloniTermin(dan, grad, vreme, trenutni);
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
                  onPressed: odabranVozac == null
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          await _spasiTermin(dan, grad, vreme, odabranVozac!);
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

  // ═══════════════════════════════════════════════════════════════
  // BAZA OPERACIJE
  // ═══════════════════════════════════════════════════════════════

  /// Dialog: Dodijeli vozača pojedinačnom putniku (vozac_putnik individualna dodjela)
  /// Samo dostupno kada termin NEMA vozača u vozac_raspored.
  Future<void> _showPutnikAssignDialog(V2Putnik putnik) async {
    final dan = _selectedDay ?? V2DanUtils.odDatuma(DateTime.now());
    final rm = V2MasterRealtimeManager.instance;
    final sedmica = V2DanUtils.pocetakTekuceSedmice();
    final vozacPutnikList = rm.vozacPutnikCache.values.map((r) => V2VozacPutnikEntry.fromMap(r)).toList();
    // Pronađi trenutnu individualnu dodjelu za ovog putnika, SAMO za ovaj dan+grad+vreme+sedmica
    final trenutniEntry = vozacPutnikList
        .where(
          (e) =>
              e.putnikId == putnik.id?.toString() &&
              e.dan == dan &&
              e.grad.toUpperCase() == _selectedGrad.toUpperCase() &&
              V2GradAdresaValidator.normalizeTime(e.vreme) == V2GradAdresaValidator.normalizeTime(_selectedVreme) &&
              e.datumSedmice == sedmica,
        )
        .firstOrNull;
    final trenutni = trenutniEntry != null ? V2VozacCache.getImeByUuid(trenutniEntry.vozacId) : null;
    String? odabranVozac = trenutni;

    final vozaci = V2VozacCache.imenaVozaca;
    if (vozaci.isEmpty) {
      if (mounted) V2AppSnackBar.warning(context, 'Nema registrovanih vozača');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          decoration: BoxDecoration(
            gradient: Theme.of(context).backgroundGradient,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '👤 ${putnik.ime}'.toUpperCase(),
                style: const TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1),
              ),
              const SizedBox(height: 4),
              Text(
                '$_selectedGrad $_selectedVreme — $dan'.toUpperCase(),
                style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1),
              ),
              const SizedBox(height: 8),
              const Text(
                'Dodijeli vozača putniku',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 16),
              ...vozaci.map((ime) => _rasporedVozacTile(
                    ime: ime,
                    isSelected: odabranVozac == ime,
                    color: V2VozacCache.getColor(ime),
                    onTap: () => setSheetState(() => odabranVozac = odabranVozac == ime ? null : ime),
                  )),
              const SizedBox(height: 8),
              if (trenutni != null)
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final ok = await V2VozacPutnikService.delete(
                      putnikId: putnik.id!.toString(),
                      dan: dan,
                      grad: _selectedGrad,
                      vreme: _selectedVreme,
                    );
                    if (ok) {
                      // Audit log
                      final vozacIdDel = trenutniEntry?.vozacId;
                      V2AuditLogService.log(
                        tip: 'uklonjen_vozac',
                        aktorId: vozacIdDel,
                        aktorIme: trenutni,
                        aktorTip: 'vozac',
                        putnikId: putnik.id?.toString(),
                        putnikIme: putnik.ime,
                        dan: dan,
                        grad: _selectedGrad,
                        vreme: _selectedVreme,
                        staro: {'vozac': trenutni},
                        detalji: 'Individualna dodjela uklonjena: $trenutni ← ${putnik.ime} ($dan)',
                      );
                      if (mounted) V2AppSnackBar.success(context, '🗑️ Individualna dodjela uklonjena');
                    } else {
                      if (mounted) V2AppSnackBar.error(context, '❌ Greška pri brisanju');
                    }
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
                  onPressed: odabranVozac == null
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          final ok = await V2VozacPutnikService.set(
                            putnikId: putnik.id!.toString(),
                            vozacIme: odabranVozac!,
                            dan: dan,
                            grad: _selectedGrad,
                            vreme: _selectedVreme,
                          );
                          if (ok) {
                            // Audit log
                            final vozacIdSet = V2VozacCache.getUuidByIme(odabranVozac!);
                            V2AuditLogService.log(
                              tip: 'dodeljen_vozac',
                              aktorId: vozacIdSet,
                              aktorIme: odabranVozac,
                              aktorTip: 'vozac',
                              putnikId: putnik.id?.toString(),
                              putnikIme: putnik.ime,
                              dan: dan,
                              grad: _selectedGrad,
                              vreme: _selectedVreme,
                              novo: {'vozac': odabranVozac},
                              detalji: 'Individualna dodjela: $odabranVozac → ${putnik.ime} ($dan)',
                            );
                            if (mounted) V2AppSnackBar.success(context, '✅ $odabranVozac → ${putnik.ime}');
                          } else {
                            if (mounted) V2AppSnackBar.error(context, '❌ Greška pri dodjeli');
                          }
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

  Future<void> _spasiTermin(String dan, String grad, String vreme, String vozacIme) async {
    final vozacId = V2VozacCache.getUuidByIme(vozacIme);
    if (vozacId == null) {
      if (mounted) V2AppSnackBar.error(context, '❌ Vozač nije pronađen u sistemu');
      return;
    }
    try {
      await V2VozacRasporedService.upsert(V2VozacRasporedEntry(
        dan: dan,
        grad: grad,
        vreme: vreme,
        vozacId: vozacId,
      ));
      if (mounted) V2AppSnackBar.success(context, '✅ $vozacIme → $grad $vreme ($dan)');

      // Audit log
      V2AuditLogService.log(
        tip: 'dodat_termin',
        aktorId: vozacId,
        aktorIme: vozacIme,
        aktorTip: 'vozac',
        dan: dan,
        grad: grad,
        vreme: vreme,
        novo: {'vozac': vozacIme, 'grad': grad, 'vreme': vreme, 'dan': dan},
        detalji: 'Termin dodan: $vozacIme → $grad $vreme ($dan)',
      );
    } catch (e) {
      if (mounted) V2AppSnackBar.error(context, '❌ Greška: $e');
    }
  }

  Future<void> _ukloniTermin(String dan, String grad, String vreme, String vozacIme) async {
    final vozacId = V2VozacCache.getUuidByIme(vozacIme);
    if (vozacId == null) {
      if (mounted) V2AppSnackBar.error(context, '❌ Vozač nije pronađen u sistemu');
      return;
    }
    try {
      await V2VozacRasporedService.deleteTermin(dan: dan, grad: grad, vreme: vreme, vozacId: vozacId);
      if (mounted) V2AppSnackBar.success(context, '🗑️ Dodjela uklonjena: $grad $vreme ($dan)');

      // Audit log
      V2AuditLogService.log(
        tip: 'uklonjen_termin',
        aktorId: vozacId,
        aktorIme: vozacIme,
        aktorTip: 'vozac',
        dan: dan,
        grad: grad,
        vreme: vreme,
        staro: {'vozac': vozacIme, 'grad': grad, 'vreme': vreme, 'dan': dan},
        detalji: 'Termin uklonjen: $vozacIme ← $grad $vreme ($dan)',
      );
    } catch (e) {
      if (mounted) V2AppSnackBar.error(context, '❌ Greška: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<_RasporedData>(
      stream: _stream,
      builder: (context, snapshot) {
        final data = snapshot.data ?? _buildRasporedData(_selectedDay ?? V2DanUtils.odDatuma(DateTime.now()));
        final allPutnici = data.putnici;
        final targetDay = _selectedDay ?? V2DanUtils.odDatuma(DateTime.now());

        final countHelper = V2PutnikCountHelper.fromPutnici(
          putnici: allPutnici,
          targetDayAbbr: targetDay,
        );

        int getPutnikCount(String grad, String vreme) {
          try {
            return countHelper.getCount(grad, vreme);
          } catch (_) {
            return 0;
          }
        }

        // Filtriraj po gradu, vremenu, danu i statusu (bez otkazanih)
        final filteredByGradVreme = allPutnici.where((p) {
          final gradMatch = _selectedGrad.isEmpty || V2GradAdresaValidator.isGradMatch(p.grad, p.adresa, _selectedGrad);
          final vremeMatch = _selectedVreme.isEmpty || p.polazak == _selectedVreme;
          final danMatch = targetDay.isEmpty || p.dan == targetDay;
          final statusMatch = p.status != 'otkazano';
          return gradMatch && vremeMatch && danMatch && statusMatch;
        }).toList();

        return Scaffold(
          extendBodyBehindAppBar: true,
          extendBody: true,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            centerTitle: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            foregroundColor: Colors.white,
            title: const Text(
              'Raspored vozača',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          body: Container(
            decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
            child: SafeArea(
              child: Column(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: _days.map((day) {
                        final isSelected = _selectedDay == day;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () => _onDayChanged(day),
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                                day.toUpperCase(),
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.6),
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

                  // TERMIN INFO TRAKA: koji vozač je dodeljen selektovanom terminu
                  if (_selectedVreme.isNotEmpty)
                    _rasporedTerminInfoRow(
                      grad: _selectedGrad,
                      vreme: _selectedVreme,
                      vozac: _getVozacZaTermin(_selectedGrad, _selectedVreme),
                      onTap: () => _showTerminAssignDialog(_selectedGrad, _selectedVreme),
                    ),

                  Expanded(
                    child: filteredByGradVreme.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inbox, size: 48, color: Colors.white.withValues(alpha: 0.3)),
                                const SizedBox(height: 12),
                                Text(
                                  _selectedVreme.isEmpty
                                      ? 'Odaberi polazak u donjem meniju'
                                      : 'Nema putnika za ovaj polazak',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 15),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            itemCount: filteredByGradVreme.length,
                            itemBuilder: (_, i) {
                              final p = filteredByGradVreme[i];
                              final terminJeDodeljen = _getVozacZaTermin(_selectedGrad, _selectedVreme) != null;
                              final dan = targetDay;
                              final sedmicaItem = V2DanUtils.pocetakTekuceSedmice();
                              final individualnaEntry = data.vozacPutnik.where((e) {
                                return e.putnikId == p.id?.toString() &&
                                    e.dan == dan &&
                                    e.grad.toUpperCase() == _selectedGrad.toUpperCase() &&
                                    V2GradAdresaValidator.normalizeTime(e.vreme) ==
                                        V2GradAdresaValidator.normalizeTime(_selectedVreme) &&
                                    e.datumSedmice == sedmicaItem;
                              }).firstOrNull;
                              final vozacColor = individualnaEntry != null
                                  ? V2VozacCache.getColorByUuid(individualnaEntry.vozacId)
                                  : _getVozacColorForTermin(_selectedGrad, _selectedVreme);
                              return _PutnikRasporedTile(
                                putnik: p,
                                vozacColor: vozacColor,
                                terminJeDodeljen: terminJeDodeljen,
                                vozacPutnikIme: individualnaEntry != null
                                    ? V2VozacCache.getImeByUuid(individualnaEntry.vozacId)
                                    : null,
                                onTap: () async => await _showPutnikAssignDialog(p),
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
              return _rasporedBottomNavBar(
                sviPolasci: _sviPolasci,
                selectedGrad: _selectedGrad,
                selectedVreme: _selectedVreme,
                getPutnikCount: getPutnikCount,
                onPolazakChanged: _onPolazakChanged,
                selectedDan: targetDay,
                getVozacColor: _getVozacColorForTermin,
              );
            },
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// TOP-LEVEL HELPERI ZA RASPORED EKRAN
// ═══════════════════════════════════════════════════════════════

/// Pronalazi V2VozacRasporedEntry za dati termin iz cache-a.
V2VozacRasporedEntry? _rasporedGetEntry({
  required String grad,
  required String vreme,
  required String dan,
}) {
  return V2MasterRealtimeManager.instance.rasporedCache.values
      .map((r) => V2VozacRasporedEntry.fromMap(r))
      .where((r) => r.dan == dan && r.grad == grad && r.vreme == vreme)
      .firstOrNull;
}

/// Traka ispod day chips-a: vozač za selektovani termin + tap za izmjenu.
Widget _rasporedTerminInfoRow({
  required String grad,
  required String vreme,
  required String? vozac,
  required VoidCallback onTap,
}) {
  final color = vozac != null ? V2VozacCache.getColor(vozac) : Colors.white24;
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
              vozac != null ? 'Vozač: $vozac' : 'Nema dodjele — tap za dodjelu vozača',
              style: TextStyle(
                color: vozac != null ? Colors.white : Colors.white54,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          Text(
            '$grad $vreme',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(width: 8),
          Icon(Icons.edit_outlined, color: color.withValues(alpha: 0.7), size: 16),
        ],
      ),
    ),
  );
}

/// Bottom nav bar za raspored ekran.
Widget _rasporedBottomNavBar({
  required List<String> sviPolasci,
  required String selectedGrad,
  required String selectedVreme,
  required int Function(String, String) getPutnikCount,
  required void Function(String, String) onPolazakChanged,
  required String selectedDan,
  required Color? Function(String, String) getVozacColor,
}) {
  return V2BottomNavBar(
    sviPolasci: sviPolasci,
    selectedGrad: selectedGrad,
    selectedVreme: selectedVreme,
    getPutnikCount: getPutnikCount,
    getKapacitet: V3KapacitetService.getKapacitetSyncValue,
    onPolazakChanged: onPolazakChanged,
    selectedDan: selectedDan,
    showVozacBoja: true,
    getVozacColor: getVozacColor,
  );
}

/// Tile za jednog vozača u bottom sheet dijalogu za dodjelu.
Widget _rasporedVozacTile({
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

/// Dart extension helper za null-safe transform.
extension _NullableExt<T> on T? {
  R? let<R>(R? Function(T?) fn) => fn(this);
}

/// Snapshot svih podataka za raspored ekran — jedan StreamBuilder rebuild.
class _RasporedData {
  final List<V2Putnik> putnici;
  final List<V2VozacRasporedEntry> raspored;
  final List<V2VozacPutnikEntry> vozacPutnik;

  const _RasporedData({
    required this.putnici,
    required this.raspored,
    required this.vozacPutnik,
  });
}

// ═══════════════════════════════════════════════════════════════
// TILE ZA PUTNIKA U RASPORED EKRANU
// ═══════════════════════════════════════════════════════════════

/// Prikazuje jednog putnika u raspored ekranu.
///
/// [terminJeDodeljen] — true ako termin ima vozača u vozac_raspored.
/// - true  → tap je onemogućen, prikazuje se lock ikona
/// - false → tap otvara dialog za individualnu dodjelu (vozac_putnik)
///
/// [vozacPutnikIme] — ime vozača iz individualne dodjele (ako postoji)
/// [onTap] — callback za tap (null ako je termin dodeljen)
class _PutnikRasporedTile extends StatelessWidget {
  const _PutnikRasporedTile({
    required this.putnik,
    this.vozacColor,
    this.terminJeDodeljen = false,
    this.vozacPutnikIme,
    this.onTap,
  });

  final V2Putnik putnik;
  final Color? vozacColor;
  final bool terminJeDodeljen;
  final String? vozacPutnikIme; // individualna dodjela (vozac_putnik)
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = vozacColor ?? Colors.white12;
    final hasIndividualna = vozacPutnikIme != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      putnik.ime,
                      style: TextStyle(
                        color: vozacColor != null ? color : Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      putnik.adresa ?? '${putnik.grad} · ${putnik.polazak}',
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Desna strana: badge vozača (individualna dodjela) ili ikona za dodjelu
              if (hasIndividualna)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person, color: color, size: 13),
                      const SizedBox(width: 4),
                      Text(
                        vozacPutnikIme!,
                        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                )
              else if (!terminJeDodeljen)
                const Icon(Icons.person_add_outlined, color: Colors.white38, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
