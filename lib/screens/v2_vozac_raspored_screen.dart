import 'package:flutter/material.dart';

import '../config/v2_route_config.dart';
import '../globals.dart';
import '../models/v2_putnik.dart';
import '../services/realtime/v2_master_realtime_manager.dart';
import '../services/v2_audit_log_service.dart';
import '../services/v2_kapacitet_service.dart';
import '../services/v2_polasci_service.dart';
import '../services/v2_vozac_putnik_service.dart';
import '../services/v2_vozac_raspored_service.dart';
import '../theme.dart';
import '../utils/v2_app_snack_bar.dart';
import '../utils/v2_dan_utils.dart';
import '../utils/v2_grad_adresa_validator.dart';
import '../utils/v2_putnik_count_helper.dart';
import '../utils/v2_vozac_cache.dart';
import '../widgets/v2_bottom_nav_bar_letnji.dart';
import '../widgets/v2_bottom_nav_bar_praznici.dart';
import '../widgets/v2_bottom_nav_bar_zimski.dart';

/// Ekran za upravljanje rasporedom vozaÄa
/// Admin moÅ¾e dodijeliti vozaÄa po terminu (vozac_raspored) i po putniku (vozac_putnik).
/// Realtime: automatski osvjeÅ¾ava kada se promijeni raspored ili individualna dodjela putnika.
class V2VozacRasporedScreen extends StatefulWidget {
  const V2VozacRasporedScreen({super.key});

  @override
  State<V2VozacRasporedScreen> createState() => _VozacRasporedScreenState();
}

class _VozacRasporedScreenState extends State<V2VozacRasporedScreen> {
  final _putnikStreamService = V2PutnikStreamService();

  String _selectedGrad = 'BC';
  String _selectedVreme = '';
  String? _selectedDay;

  late Stream<List<V2Putnik>> _putnikStream;

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
    _putnikStream = _putnikStreamService.streamKombinovaniPutniciFiltered(dan: _selectedDay);
  }

  void _onDayChanged(String day) {
    setState(() {
      _selectedDay = day;
      _putnikStream = _putnikStreamService.streamKombinovaniPutniciFiltered(dan: day);
    });
  }

  /// Automatski selektuje najbliÅ¾e vreme polaska za trenutni Äas.
  /// Prioritet: prvo vreme koje je >= sada, fallback na poslednje vreme u listi.
  void _autoSelectNajblizeVreme() {
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;

    // PokuÅ¡aj BC prvo (default grad)
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

  /// Helper: vraca V2VozacRasporedEntry za termin ili null (izbjegava dupliciranu logiku)
  V2VozacRasporedEntry? _getRasporedEntry(String grad, String vreme) {
    final dan = _selectedDay ?? V2DanUtils.odDatuma(DateTime.now());
    final rm = V2MasterRealtimeManager.instance;
    return rm.rasporedCache.values
        .map((r) => V2VozacRasporedEntry.fromMap(r))
        .where((r) => r.dan == dan && r.grad == grad && r.vreme == vreme)
        .firstOrNull;
  }

  /// VraÄ‡a boju vozaÄa dodijeljenog terminu (grad+vreme) za selektovani dan
  Color? _getVozacColorForTermin(String grad, String vreme) {
    final entry = _getRasporedEntry(grad, vreme);
    if (entry == null) return null;
    return V2VozacCache.getColor(entry.vozacId);
  }

  /// Naziv vozaÄa dodijeljenog terminu
  String? _getVozacZaTermin(String grad, String vreme) {
    final entry = _getRasporedEntry(grad, vreme);
    if (entry == null) return null;
    return V2VozacCache.getImeByUuid(entry.vozacId);
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // DIALOZI ZA DODJELU
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  /// Dialog: Dodijeli vozaÄa terminu (vozac_raspored)
  Future<void> _showTerminAssignDialog(String grad, String vreme) async {
    final dan = _selectedDay ?? V2DanUtils.odDatuma(DateTime.now());
    final trenutni = _getVozacZaTermin(grad, vreme);
    String? odabranVozac = trenutni;

    final vozaci = V2VozacCache.imenaVozaca;
    if (vozaci.isEmpty) {
      if (mounted) V2AppSnackBar.warning(context, 'Nema registrovanih vozaÄa');
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
                'ðŸ—“ï¸ Termin: $grad $vreme â€” $dan'.toUpperCase(),
                style: const TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1),
              ),
              const SizedBox(height: 8),
              const Text(
                'Dodijeli vozaÄa terminu',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 16),
              ...vozaci.map((ime) {
                final isSelected = odabranVozac == ime;
                final color = V2VozacCache.getColor(ime);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => setSheetState(() => odabranVozac = isSelected ? null : ime),
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
              }),
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

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // BAZA OPERACIJE
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  /// Dialog: Dodijeli vozaÄa pojedinaÄnom putniku (vozac_putnik individualna dodjela)
  /// Samo dostupno kada termin NEMA vozaÄa u vozac_raspored.
  Future<void> _showPutnikAssignDialog(V2Putnik putnik) async {
    final dan = _selectedDay ?? V2DanUtils.odDatuma(DateTime.now());
    final rm = V2MasterRealtimeManager.instance;
    final vozacPutnikList = rm.vozacPutnikCache.values.map((r) => V2VozacPutnikEntry.fromMap(r)).toList();
    // PronaÄ‘i trenutnu individualnu dodjelu za ovog putnika, SAMO za ovaj dan+grad+vreme
    final trenutniEntry = vozacPutnikList
        .where(
          (e) =>
              e.putnikId == putnik.id?.toString() &&
              e.dan == dan &&
              e.grad.toUpperCase() == _selectedGrad.toUpperCase() &&
              V2GradAdresaValidator.normalizeTime(e.vreme) == V2GradAdresaValidator.normalizeTime(_selectedVreme),
        )
        .firstOrNull;
    final trenutni = trenutniEntry != null ? V2VozacCache.getImeByUuid(trenutniEntry.vozacId) : null;
    String? odabranVozac = trenutni;

    final vozaci = V2VozacCache.imenaVozaca;
    if (vozaci.isEmpty) {
      if (mounted) V2AppSnackBar.warning(context, 'Nema registrovanih vozaÄa');
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
                'ðŸ‘¤ ${putnik.ime}'.toUpperCase(),
                style: const TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1),
              ),
              const SizedBox(height: 4),
              Text(
                '$_selectedGrad $_selectedVreme â€” $dan'.toUpperCase(),
                style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1),
              ),
              const SizedBox(height: 8),
              const Text(
                'Dodijeli vozaÄa putniku',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 16),
              ...vozaci.map((ime) {
                final isSelected = odabranVozac == ime;
                final color = V2VozacCache.getColor(ime);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => setSheetState(() => odabranVozac = isSelected ? null : ime),
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
              }),
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
                        detalji: 'Individualna dodjela uklonjena: $trenutni â† ${putnik.ime} ($dan)',
                      );
                      if (mounted) V2AppSnackBar.success(context, 'ðŸ—‘ï¸ Individualna dodjela uklonjena');
                    } else {
                      if (mounted) V2AppSnackBar.error(context, 'âŒ GreÅ¡ka pri brisanju');
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
                              detalji: 'Individualna dodjela: $odabranVozac â†’ ${putnik.ime} ($dan)',
                            );
                            if (mounted) V2AppSnackBar.success(context, 'âœ… $odabranVozac â†’ ${putnik.ime}');
                          } else {
                            if (mounted) V2AppSnackBar.error(context, 'âŒ GreÅ¡ka pri dodjeli');
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
      if (mounted) V2AppSnackBar.error(context, 'âŒ VozaÄ nije pronaÄ‘en u sistemu');
      return;
    }
    try {
      await V2VozacRasporedService.upsert(V2VozacRasporedEntry(
        dan: dan,
        grad: grad,
        vreme: vreme,
        vozacId: vozacId,
      ));
      if (mounted) V2AppSnackBar.success(context, 'âœ… $vozacIme â†’ $grad $vreme ($dan)');

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
        detalji: 'Termin dodan: $vozacIme â†’ $grad $vreme ($dan)',
      );
    } catch (e) {
      if (mounted) V2AppSnackBar.error(context, 'âŒ GreÅ¡ka: $e');
    }
  }

  Future<void> _ukloniTermin(String dan, String grad, String vreme, String vozacIme) async {
    final vozacId = V2VozacCache.getUuidByIme(vozacIme);
    if (vozacId == null) {
      if (mounted) V2AppSnackBar.error(context, 'âŒ VozaÄ nije pronaÄ‘en u sistemu');
      return;
    }
    try {
      await V2VozacRasporedService.deleteTermin(dan: dan, grad: grad, vreme: vreme, vozacId: vozacId);
      if (mounted) V2AppSnackBar.success(context, 'ðŸ—‘ï¸ Dodjela uklonjena: $grad $vreme ($dan)');

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
        detalji: 'Termin uklonjen: $vozacIme â† $grad $vreme ($dan)',
      );
    } catch (e) {
      if (mounted) V2AppSnackBar.error(context, 'âŒ GreÅ¡ka: $e');
    }
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // BUILD
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<V2Putnik>>(
      stream: _putnikStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && snapshot.data == null) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }

        final allPutnici = snapshot.data ?? [];
        final targetDay = _selectedDay ?? V2DanUtils.odDatuma(DateTime.now());

        final countHelper = V2PutnikCountHelper.fromPutnici(
          putnici: allPutnici,
          targetDayAbbr: targetDay,
        );

        int getPutnikCount(String grad, String vreme) {
          try {
            return countHelper.getCount(grad, vreme);
          } catch (e) {
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

                  // TERMIN INFO TRAKA: koji vozaÄ je dodeljen selektovanom terminu
                  if (_selectedVreme.isNotEmpty) _buildTerminInfoRow(targetDay),

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
                              // Da li je termin dodeljen (vozac_raspored)?
                              final terminJeDodeljen = _getVozacZaTermin(_selectedGrad, _selectedVreme) != null;
                              // Individualna dodjela putnika za OVAJ dan+grad+vreme (vozac_putnik)
                              final dan = targetDay;
                              final rmCache = V2MasterRealtimeManager.instance.vozacPutnikCache;
                              final individualnaEntry =
                                  rmCache.values.map((r) => V2VozacPutnikEntry.fromMap(r)).where((e) {
                                return e.putnikId == p.id?.toString() &&
                                    e.dan == dan &&
                                    e.grad.toUpperCase() == _selectedGrad.toUpperCase() &&
                                    V2GradAdresaValidator.normalizeTime(e.vreme) ==
                                        V2GradAdresaValidator.normalizeTime(_selectedVreme);
                              }).firstOrNull;
                              // Boja: individualna dodjela ima prioritet nad termin bojom
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
              return _buildBottomNavBar(navType, getPutnikCount, targetDay);
            },
          ),
        );
      },
    );
  }

  /// Traka ispod day chips-a: vozaÄ za selektovani termin + tap za izmjenu
  Widget _buildTerminInfoRow(String dan) {
    final vozac = _getVozacZaTermin(_selectedGrad, _selectedVreme);
    final color = vozac != null ? V2VozacCache.getColor(vozac) : Colors.white24;

    return GestureDetector(
      onTap: () async {
        await _showTerminAssignDialog(_selectedGrad, _selectedVreme);
      },
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
                vozac != null ? 'VozaÄ: $vozac' : 'Nema dodjele â€” tap za dodjelu vozaÄa',
                style: TextStyle(
                  color: vozac != null ? Colors.white : Colors.white54,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            Text(
              '$_selectedGrad $_selectedVreme',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(width: 8),
            Icon(Icons.edit_outlined, color: color.withValues(alpha: 0.7), size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavBar(String navType, int Function(String, String) getPutnikCount, String targetDay) {
    int getKapacitet(String grad, String vreme) => V2KapacitetService.getKapacitetSync(grad, vreme);

    switch (navType) {
      case 'praznici':
        return V2BottomNavBarPraznici(
          sviPolasci: _sviPolasci,
          selectedGrad: _selectedGrad,
          selectedVreme: _selectedVreme,
          getPutnikCount: getPutnikCount,
          getKapacitet: getKapacitet,
          onPolazakChanged: _onPolazakChanged,
          selectedDan: targetDay,
          showVozacBoja: true,
          getVozacColor: _getVozacColorForTermin,
        );
      case 'zimski':
        return V2BottomNavBarZimski(
          sviPolasci: _sviPolasci,
          selectedGrad: _selectedGrad,
          selectedVreme: _selectedVreme,
          getPutnikCount: getPutnikCount,
          getKapacitet: getKapacitet,
          onPolazakChanged: _onPolazakChanged,
          selectedDan: targetDay,
          showVozacBoja: true,
          getVozacColor: _getVozacColorForTermin,
        );
      default:
        return V2BottomNavBarLetnji(
          sviPolasci: _sviPolasci,
          selectedGrad: _selectedGrad,
          selectedVreme: _selectedVreme,
          getPutnikCount: getPutnikCount,
          getKapacitet: getKapacitet,
          onPolazakChanged: _onPolazakChanged,
          selectedDan: targetDay,
          showVozacBoja: true,
          getVozacColor: _getVozacColorForTermin,
        );
    }
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// TILE ZA PUTNIKA U RASPORED EKRANU
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

/// Prikazuje jednog putnika u raspored ekranu.
///
/// [terminJeDodeljen] â€” true ako termin ima vozaÄa u vozac_raspored.
/// - true  â†’ tap je onemoguÄ‡en, prikazuje se lock ikona
/// - false â†’ tap otvara dialog za individualnu dodjelu (vozac_putnik)
///
/// [vozacPutnikIme] â€” ime vozaÄa iz individualne dodjele (ako postoji)
/// [onTap] â€” callback za tap (null ako je termin dodeljen)
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
                      putnik.adresa ?? '${putnik.grad} Â· ${putnik.polazak}',
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Desna strana: badge vozaÄa (individualna dodjela) ili ikona za dodjelu
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
