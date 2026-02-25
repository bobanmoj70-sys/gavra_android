import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/route_config.dart';
import '../globals.dart';
import '../models/putnik.dart';
import '../services/kapacitet_service.dart';
import '../services/putnik_service.dart';
import '../services/realtime/realtime_manager.dart';
import '../services/vozac_putnik_service.dart';
import '../services/vozac_raspored_service.dart';
import '../theme.dart';
import '../utils/app_snack_bar.dart';
import '../utils/putnik_count_helper.dart';
import '../utils/vozac_cache.dart';
import '../widgets/bottom_nav_bar_letnji.dart';
import '../widgets/bottom_nav_bar_praznici.dart';
import '../widgets/bottom_nav_bar_zimski.dart';

/// 🗓️ Ekran za upravljanje rasporedom vozača
/// Admin može dodijeliti vozača po terminu (vozac_raspored) i po putniku (vozac_putnik).
/// Realtime: automatski osvježava kada se promijeni raspored ili putnik override.
class VozacRasporedScreen extends StatefulWidget {
  const VozacRasporedScreen({super.key});

  @override
  State<VozacRasporedScreen> createState() => _VozacRasporedScreenState();
}

class _VozacRasporedScreenState extends State<VozacRasporedScreen> {
  final _putnikService = PutnikService();
  final _rasporedService = VozacRasporedService();

  String _selectedGrad = 'BC';
  String _selectedVreme = '';
  String? _selectedDay;
  List<VozacRasporedEntry> _rasporedCache = [];
  List<VozacPutnikEntry> _putnikOverridesCache = [];

  // 🔴 Realtime subscriptions
  StreamSubscription<PostgresChangePayload>? _rasporedSub;
  StreamSubscription<PostgresChangePayload>? _putnikOverrideSub;

  final List<String> _days = ['pon', 'uto', 'sre', 'cet', 'pet'];

  List<String> get bcVremena {
    final navType = navBarTypeNotifier.value;
    if (navType == 'praznici') return RouteConfig.bcVremenaPraznici;
    if (navType == 'zimski') return RouteConfig.bcVremenaZimski;
    return RouteConfig.bcVremenaLetnji;
  }

  List<String> get vsVremena {
    final navType = navBarTypeNotifier.value;
    if (navType == 'praznici') return RouteConfig.vsVremenaPraznici;
    if (navType == 'zimski') return RouteConfig.vsVremenaZimski;
    return RouteConfig.vsVremenaLetnji;
  }

  List<String> get _sviPolasci {
    return [
      ...bcVremena.map((v) => '$v BC'),
      ...vsVremena.map((v) => '$v VS'),
    ];
  }

  @override
  void initState() {
    super.initState();
    final today = _getDayAbbreviation(DateTime.now());
    _selectedDay = (today == 'sub' || today == 'ned') ? 'pon' : today;
    _loadAll();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _rasporedSub?.cancel();
    _putnikOverrideSub?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final rasporedData = await _rasporedService.loadAll();
    final overridesData = await VozacPutnikService().loadAll();
    if (mounted) {
      setState(() {
        _rasporedCache = rasporedData;
        _putnikOverridesCache = overridesData;
      });
    }
  }

  /// 🔴 Realtime: prati vozac_raspored i vozac_putnik tabele
  void _subscribeRealtime() {
    _rasporedSub = RealtimeManager.instance.subscribe('vozac_raspored').listen((_) {
      // Reload iz cache-a pri svakoj promjeni
      final entries =
          RealtimeManager.instance.rasporedCache.values.map((row) => VozacRasporedEntry.fromMap(row)).toList();
      if (mounted) setState(() => _rasporedCache = entries);
    });

    _putnikOverrideSub = RealtimeManager.instance.subscribe('vozac_putnik').listen((_) {
      final entries =
          RealtimeManager.instance.vozacPutnikCache.values.map((row) => VozacPutnikEntry.fromMap(row)).toList();
      if (mounted) setState(() => _putnikOverridesCache = entries);
    });
  }

  String _getWorkingDateIso() {
    final now = DateTime.now();
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return now.add(Duration(days: 8 - now.weekday)).toIso8601String().split('T').first;
    }
    return now.toIso8601String().split('T').first;
  }

  String _getDayAbbreviation(DateTime date) {
    const dani = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
    return dani[date.weekday - 1];
  }

  void _onPolazakChanged(String grad, String vreme) {
    if (mounted)
      setState(() {
        _selectedGrad = grad;
        _selectedVreme = vreme;
      });
  }

  /// 🎨 Vraća boju vozača dodijeljenog terminu (grad+vreme) za selektovani dan
  Color? _getVozacColorForTermin(String grad, String vreme) {
    final dan = _selectedDay ?? _getDayAbbreviation(DateTime.now());
    final entry = _rasporedCache
        .where(
          (r) => r.dan == dan && r.grad == grad && r.vreme == vreme,
        )
        .firstOrNull;
    if (entry == null) return null;
    return VozacCache.getColor(entry.vozacId ?? entry.vozac);
  }

  /// 🚗 Naziv vozača dodijeljenog terminu
  String? _getVozacZaTermin(String grad, String vreme) {
    final dan = _selectedDay ?? _getDayAbbreviation(DateTime.now());
    return _rasporedCache.where((r) => r.dan == dan && r.grad == grad && r.vreme == vreme).firstOrNull?.vozac;
  }

  /// 👤 Naziv vozača za override putnika (null = nema override)
  String? _getVozacOverrideZaPutnika(String putnikId) {
    return _putnikOverridesCache.where((o) => o.putnikId == putnikId).firstOrNull?.vozac;
  }

  // ═══════════════════════════════════════════════════════════════
  // DIALOZI ZA DODJELU
  // ═══════════════════════════════════════════════════════════════

  /// 🗓️ Dialog: Dodijeli vozača terminu (vozac_raspored)
  Future<void> _showTerminAssignDialog(String grad, String vreme) async {
    final dan = _selectedDay ?? _getDayAbbreviation(DateTime.now());
    final trenutni = _getVozacZaTermin(grad, vreme);
    String? odabranVozac = trenutni;

    final vozaci = VozacCache.imenaVozaca;
    if (vozaci.isEmpty) {
      if (mounted) AppSnackBar.warning(context, 'Nema registrovanih vozača');
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
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.4),
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
              // Lista vozača
              ...vozaci.map((ime) {
                final isSelected = odabranVozac == ime;
                final color = VozacCache.getColor(ime);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => setSheetState(() => odabranVozac = isSelected ? null : ime),
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? color.withOpacity(0.25) : Colors.white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? color : Colors.white.withOpacity(0.15),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: color.withOpacity(0.3),
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
              // Ukloni dodjelu
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
              // Potvrdi
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.15),
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

  /// 👤 Bottom sheet: Dodijeli vozača putniku (vozac_putnik override)
  Future<void> _showPutnikAssignSheet(Putnik p) async {
    final trenutni = _getVozacOverrideZaPutnika(p.id?.toString() ?? '');
    String? odabranVozac = trenutni;

    final vozaci = VozacCache.imenaVozaca;
    if (vozaci.isEmpty) {
      if (mounted) AppSnackBar.warning(context, 'Nema registrovanih vozača');
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
            border: Border.all(color: Colors.white.withOpacity(0.2)),
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
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '👤 ${p.ime}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              Text(
                '${p.grad} · ${p.polazak}',
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 4),
              if (trenutni != null)
                Text(
                  'Trenutno: $trenutni',
                  style: TextStyle(color: VozacCache.getColor(trenutni).withOpacity(0.9), fontSize: 13),
                )
              else
                const Text('Nema override-a (prati termin)', style: TextStyle(color: Colors.white38, fontSize: 13)),
              const SizedBox(height: 16),
              ...vozaci.map((ime) {
                final isSelected = odabranVozac == ime;
                final color = VozacCache.getColor(ime);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => setSheetState(() => odabranVozac = isSelected ? null : ime),
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? color.withOpacity(0.25) : Colors.white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? color : Colors.white.withOpacity(0.15),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: color.withOpacity(0.3),
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
                    await _ukloniPutnikOverride(p);
                  },
                  icon: const Icon(Icons.clear, color: Colors.redAccent, size: 18),
                  label: const Text('Ukloni override (prati termin)', style: TextStyle(color: Colors.redAccent)),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.15),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: odabranVozac == null
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          await _spasiPutnikOverride(p, odabranVozac!);
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

  Future<void> _spasiTermin(String dan, String grad, String vreme, String vozacIme) async {
    final vozacId = VozacCache.getUuidByIme(vozacIme);
    try {
      await _rasporedService.upsert(VozacRasporedEntry(
        dan: dan,
        grad: grad,
        vreme: vreme,
        vozac: vozacIme,
        vozacId: vozacId,
      ));
      await _loadAll();
      if (mounted) AppSnackBar.success(context, '✅ $vozacIme → $grad $vreme ($dan)');
    } catch (e) {
      if (mounted) AppSnackBar.error(context, '❌ Greška: $e');
    }
  }

  Future<void> _ukloniTermin(String dan, String grad, String vreme, String vozacIme) async {
    try {
      await _rasporedService.deleteTermin(dan: dan, grad: grad, vreme: vreme, vozac: vozacIme);
      await _loadAll();
      if (mounted) AppSnackBar.success(context, '🗑️ Dodjela uklonjena: $grad $vreme ($dan)');
    } catch (e) {
      if (mounted) AppSnackBar.error(context, '❌ Greška: $e');
    }
  }

  Future<void> _spasiPutnikOverride(Putnik p, String vozacIme) async {
    final dan = _selectedDay ?? _getDayAbbreviation(DateTime.now());
    final success = await VozacPutnikService().set(
      putnikId: p.id?.toString() ?? '',
      vozacIme: vozacIme,
      dan: dan,
      grad: p.grad,
      vreme: p.polazak,
    );
    await _loadAll();
    if (mounted) {
      if (success) {
        AppSnackBar.success(context, '✅ ${p.ime} → $vozacIme');
      } else {
        AppSnackBar.error(context, '❌ Greška pri dodjeli');
      }
    }
  }

  Future<void> _ukloniPutnikOverride(Putnik p) async {
    final success = await VozacPutnikService().delete(putnikId: p.id?.toString() ?? '');
    await _loadAll();
    if (mounted) {
      if (success) {
        AppSnackBar.success(context, '🗑️ Override uklonjen za ${p.ime}');
      } else {
        AppSnackBar.error(context, '❌ Greška');
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Putnik>>(
      stream: _putnikService.streamKombinovaniPutniciFiltered(
        isoDate: _getWorkingDateIso(),
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && snapshot.data == null) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }

        final allPutnici = snapshot.data ?? [];
        final targetDay = _selectedDay ?? _getDayAbbreviation(DateTime.now());

        final countHelper = PutnikCountHelper.fromPutnici(
          putnici: allPutnici,
          targetDateIso: _getWorkingDateIso(),
          targetDayAbbr: targetDay,
        );

        int getPutnikCount(String grad, String vreme) {
          try {
            return countHelper.getCount(grad, vreme);
          } catch (_) {
            return 0;
          }
        }

        // Filtriraj po gradu i vremenu
        final filteredByGradVreme = allPutnici.where((p) {
          final gradMatch = _selectedGrad.isEmpty || p.grad == _selectedGrad;
          final vremeMatch = _selectedVreme.isEmpty || p.polazak == _selectedVreme;
          return gradMatch && vremeMatch;
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
            title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Raspored vozača',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
                // 🟡 Indikator: koliko termina ima dodjelu za selektovani dan
                const SizedBox(width: 8),
                Builder(builder: (_) {
                  final count = _rasporedCache.where((r) => r.dan == targetDay).length;
                  if (count == 0) return const SizedBox.shrink();
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$count', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                  );
                }),
              ],
            ),
          ),
          body: Container(
            decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
            child: SafeArea(
              child: Column(
                children: [
                  // 🗓️ DAY CHIPS
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: _days.map((day) {
                        final isSelected = _selectedDay == day;
                        // Broj dodjela za ovaj dan
                        final dodjeleCount = _rasporedCache.where((r) => r.dan == day).length;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () => setState(() => _selectedDay = day),
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white.withOpacity(0.25)
                                    : Theme.of(context).glassContainer.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? Colors.white.withOpacity(0.7) : Theme.of(context).glassBorder,
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    day.toUpperCase(),
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : Theme.of(context).colorScheme.onPrimary.withOpacity(0.6),
                                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                                      fontSize: 13,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  if (dodjeleCount > 0) ...[
                                    const SizedBox(width: 5),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.25),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '$dodjeleCount',
                                        style: const TextStyle(
                                            fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  // 🗓️ TERMIN INFO TRAKA: koji vozač je dodeljen selektovanom terminu
                  if (_selectedVreme.isNotEmpty) _buildTerminInfoRow(targetDay),

                  // Lista putnika
                  Expanded(
                    child: filteredByGradVreme.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inbox, size: 48, color: Colors.white.withOpacity(0.3)),
                                const SizedBox(height: 12),
                                Text(
                                  _selectedVreme.isEmpty
                                      ? 'Odaberi polazak u donjem meniju'
                                      : 'Nema putnika za ovaj polazak',
                                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 15),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            itemCount: filteredByGradVreme.length,
                            itemBuilder: (ctx, i) {
                              final p = filteredByGradVreme[i];
                              final override = _getVozacOverrideZaPutnika(p.id?.toString() ?? '');
                              final overrideColor = override != null ? VozacCache.getColor(override) : null;
                              return _PutnikRasporedTile(
                                putnik: p,
                                overrideVozac: override,
                                overrideColor: overrideColor,
                                onAssign: () => _showPutnikAssignSheet(p),
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

  /// 🟡 Traka ispod day chips-a: vozač za selektovani termin + tap za izmjenu
  Widget _buildTerminInfoRow(String dan) {
    final vozac = _getVozacZaTermin(_selectedGrad, _selectedVreme);
    final color = vozac != null ? VozacCache.getColor(vozac) : Colors.white24;

    return GestureDetector(
      onTap: () => _showTerminAssignDialog(_selectedGrad, _selectedVreme),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.5), width: 1.5),
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
              '$_selectedGrad $_selectedVreme',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(width: 8),
            Icon(Icons.edit_outlined, color: color.withOpacity(0.7), size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavBar(String navType, int Function(String, String) getPutnikCount, String targetDay) {
    final commonParams = (
      sviPolasci: _sviPolasci,
      selectedGrad: _selectedGrad,
      selectedVreme: _selectedVreme,
      getPutnikCount: getPutnikCount,
      getKapacitet: (String grad, String vreme) => KapacitetService.getKapacitetSync(grad, vreme),
      onPolazakChanged: _onPolazakChanged,
      selectedDan: targetDay,
      showVozacBoja: true,
      getVozacColor: _getVozacColorForTermin,
    );

    switch (navType) {
      case 'praznici':
        return BottomNavBarPraznici(
          sviPolasci: commonParams.sviPolasci,
          selectedGrad: commonParams.selectedGrad,
          selectedVreme: commonParams.selectedVreme,
          getPutnikCount: commonParams.getPutnikCount,
          getKapacitet: commonParams.getKapacitet,
          onPolazakChanged: commonParams.onPolazakChanged,
          selectedDan: commonParams.selectedDan,
          showVozacBoja: commonParams.showVozacBoja,
          getVozacColor: commonParams.getVozacColor,
        );
      case 'zimski':
        return BottomNavBarZimski(
          sviPolasci: commonParams.sviPolasci,
          selectedGrad: commonParams.selectedGrad,
          selectedVreme: commonParams.selectedVreme,
          getPutnikCount: commonParams.getPutnikCount,
          getKapacitet: commonParams.getKapacitet,
          onPolazakChanged: commonParams.onPolazakChanged,
          selectedDan: commonParams.selectedDan,
          showVozacBoja: commonParams.showVozacBoja,
          getVozacColor: commonParams.getVozacColor,
        );
      default:
        return BottomNavBarLetnji(
          sviPolasci: commonParams.sviPolasci,
          selectedGrad: commonParams.selectedGrad,
          selectedVreme: commonParams.selectedVreme,
          getPutnikCount: commonParams.getPutnikCount,
          getKapacitet: commonParams.getKapacitet,
          onPolazakChanged: commonParams.onPolazakChanged,
          selectedDan: commonParams.selectedDan,
          showVozacBoja: commonParams.showVozacBoja,
          getVozacColor: commonParams.getVozacColor,
        );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// TILE ZA PUTNIKA U RASPORED EKRANU
// ═══════════════════════════════════════════════════════════════════

/// Prikazuje jednog putnika sa indikatorom vozač overridea i dugmetom za dodjelu.
class _PutnikRasporedTile extends StatelessWidget {
  const _PutnikRasporedTile({
    required this.putnik,
    required this.onAssign,
    this.overrideVozac,
    this.overrideColor,
  });

  final Putnik putnik;
  final String? overrideVozac;
  final Color? overrideColor;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final hasOverride = overrideVozac != null;
    final borderColor = hasOverride ? overrideColor! : Colors.white12;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: hasOverride ? overrideColor!.withOpacity(0.08) : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: hasOverride ? 1.5 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Boja vozača (lijeva traka)
            if (hasOverride)
              Container(
                width: 4,
                height: 36,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: overrideColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            // Ime putnika
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    putnik.ime,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  if (hasOverride)
                    Text(
                      '→ $overrideVozac',
                      style: TextStyle(
                        color: overrideColor!.withOpacity(0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  else
                    const Text(
                      'Prati termin',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                ],
              ),
            ),
            // 👤 Dugme za dodjelu
            GestureDetector(
              onTap: onAssign,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: hasOverride ? overrideColor!.withOpacity(0.2) : Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: hasOverride ? overrideColor!.withOpacity(0.5) : Colors.white24,
                  ),
                ),
                child: Icon(
                  hasOverride ? Icons.person : Icons.person_add_outlined,
                  color: hasOverride ? overrideColor : Colors.white54,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
