import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/v2_route_config.dart';
import '../globals.dart';
import '../models/v2_putnik.dart';
import '../services/realtime/v2_master_realtime_manager.dart';
import '../services/v2_kapacitet_service.dart';
import '../services/v2_polasci_service.dart';
import '../services/v2_vozac_putnik_service.dart';
import '../services/v2_vozac_raspored_service.dart';
import '../theme.dart';
import '../utils/v2_app_snack_bar.dart';
import '../utils/v2_grad_adresa_validator.dart';
import '../utils/v2_putnik_count_helper.dart';
import '../utils/v2_vozac_cache.dart';
import '../widgets/v2_bottom_nav_bar_letnji.dart';
import '../widgets/v2_bottom_nav_bar_praznici.dart';
import '../widgets/v2_bottom_nav_bar_zimski.dart';

/// Ekran za upravljanje rasporedom vozača
/// Admin može dodijeliti vozača po terminu (vozac_raspored) i po putniku (vozac_putnik).
/// Realtime: automatski osvježava kada se promijeni raspored ili individualna dodjela putnika.
class V2VozacRasporedScreen extends StatefulWidget {
  const V2VozacRasporedScreen({super.key});

  @override
  State<V2VozacRasporedScreen> createState() => _VozacRasporedScreenState();
}

class _VozacRasporedScreenState extends State<V2VozacRasporedScreen> {
  // Write-only servisi (DB mutacije)
  final _rasporedService = V2VozacRasporedService();
  final _vozacPutnikService = V2VozacPutnikService();
  // Stream servis — jednom kreiran, ne ponovo na svakom rebuildu
  final _putnikStreamService = V2PutnikStreamService();

  String _selectedGrad = 'BC';
  String _selectedVreme = '';
  String? _selectedDay;
  List<VozacRasporedEntry> _rasporedCache = [];
  List<VozacPutnikEntry> _vozacPutnikCache = [];

  // Realtime subscriptions
  StreamSubscription<PostgresChangePayload>? _rasporedSub;
  StreamSubscription<PostgresChangePayload>? _vozacPutnikSub;

  final List<String> _days = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];

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
    _autoSelectNajblizeVreme();
    // Odmah ucitaj iz rm.cache (bez DB upita)
    final rm = V2MasterRealtimeManager.instance;
    _rasporedCache = rm.rasporedCache.values.map((r) => VozacRasporedEntry.fromMap(r)).toList();
    _vozacPutnikCache = rm.vozacPutnikCache.values.map((r) => VozacPutnikEntry.fromMap(r)).toList();
    _subscribeRealtime();
  }

  /// Automatski selektuje najbliže vreme polaska za trenutni čas.
  /// Prioritet: prvo vreme koje je >= sada, fallback na poslednje vreme u listi.
  void _autoSelectNajblizeVreme() {
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;

    // Pokušaj BC prvo (default grad)
    final bcList = bcVremena;
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

  @override
  void dispose() {
    _rasporedSub?.cancel();
    _vozacPutnikSub?.cancel();
    super.dispose();
  }

  /// Realtime: prati vozac_raspored i vozac_putnik tabele
  void _subscribeRealtime() {
    final rm = V2MasterRealtimeManager.instance;
    _rasporedSub = rm.subscribe('v2_vozac_raspored').listen((_) {
      if (mounted) {
        setState(() {
          _rasporedCache = rm.rasporedCache.values.map((r) => VozacRasporedEntry.fromMap(r)).toList();
        });
      }
    });
    _vozacPutnikSub = rm.subscribe('v2_vozac_putnik').listen((_) {
      if (mounted) {
        setState(() {
          _vozacPutnikCache = rm.vozacPutnikCache.values.map((r) => VozacPutnikEntry.fromMap(r)).toList();
        });
      }
    });
  }

  /// Vraća ISO datum koji odgovara selektovanom danu u sedmici.
  /// Ako je danas pon a chip je 'sre' → vraća ISO datum za srijedu ove sedmice.
  /// Vikend → koristi sledeću radnu sedmicu.
  String _getIsoDateForSelectedDay() {
    final now = DateTime.now();
    // Baza: ponedeljak ove sedmice (ili sledeće ako je vikend)
    final int todayWeekday = now.weekday; // 1=pon ... 7=ned
    final int daysToMonday = (todayWeekday == 6 || todayWeekday == 7)
        ? (8 - todayWeekday) // vikend → sledeći ponedeljak
        : (1 - todayWeekday); // radni dan → ovaj ponedeljak
    final monday = now.add(Duration(days: daysToMonday));

    const dayOffsets = {'pon': 0, 'uto': 1, 'sre': 2, 'cet': 3, 'pet': 4, 'sub': 5, 'ned': 6};
    final offset = dayOffsets[_selectedDay ?? 'pon'] ?? 0;
    return monday.add(Duration(days: offset)).toIso8601String().split('T').first;
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

  /// Helper: vraca VozacRasporedEntry za termin ili null (izbjegava dupliciranu logiku)
  VozacRasporedEntry? _getRasporedEntry(String grad, String vreme) {
    final dan = _selectedDay ?? _getDayAbbreviation(DateTime.now());
    return _rasporedCache.where((r) => r.dan == dan && r.grad == grad && r.vreme == vreme).firstOrNull;
  }

  /// Vraća boju vozača dodijeljenog terminu (grad+vreme) za selektovani dan
  Color? _getVozacColorForTermin(String grad, String vreme) {
    final entry = _getRasporedEntry(grad, vreme);
    if (entry == null) return null;
    return V2VozacCache.getColor(entry.vozacId);
  }

  /// Naziv vozača dodijeljenog terminu
  String? _getVozacZaTermin(String grad, String vreme) {
    final entry = _getRasporedEntry(grad, vreme);
    if (entry == null) return null;
    return V2VozacCache.getImeByUuid(entry.vozacId);
  }

  // ═══════════════════════════════════════════════════════════════
  // DIALOZI ZA DODJELU
  // ═══════════════════════════════════════════════════════════════

  /// Dialog: Dodijeli vozača terminu (vozac_raspored)
  Future<void> _showTerminAssignDialog(String grad, String vreme) async {
    final dan = _selectedDay ?? _getDayAbbreviation(DateTime.now());
    final trenutni = _getVozacZaTermin(grad, vreme);
    String? odabranVozac = trenutni;

    final vozaci = V2VozacCache.imenaVozaca;
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

  // ═══════════════════════════════════════════════════════════════
  // BAZA OPERACIJE
  // ═══════════════════════════════════════════════════════════════

  /// Dialog: Dodijeli vozača pojedinačnom putniku (vozac_putnik individualna dodjela)
  /// Samo dostupno kada termin NEMA vozača u vozac_raspored.
  Future<void> _showPutnikAssignDialog(V2Putnik putnik) async {
    final dan = _selectedDay ?? _getDayAbbreviation(DateTime.now());
    // Pronađi trenutnu individualnu dodjelu za ovog putnika
    final trenutniEntry = _vozacPutnikCache
        .where(
          (e) => e.putnikId == putnik.id?.toString(),
        )
        .firstOrNull;
    final trenutni = trenutniEntry != null ? V2VozacCache.getImeByUuid(trenutniEntry.vozacId) : null;
    String? odabranVozac = trenutni;

    final vozaci = V2VozacCache.imenaVozaca;
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
              // Lista vozača
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
              // Ukloni individualnu dodjelu
              if (trenutni != null)
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final ok = await _vozacPutnikService.delete(putnikId: putnik.id!.toString());
                    if (ok) {
                      if (mounted) AppSnackBar.success(context, '🗑️ Individualna dodjela uklonjena');
                    } else {
                      if (mounted) AppSnackBar.error(context, '❌ Greška pri brisanju');
                    }
                  },
                  icon: const Icon(Icons.person_remove_outlined, color: Colors.redAccent, size: 18),
                  label: const Text('Ukloni individualnu dodjelu', style: TextStyle(color: Colors.redAccent)),
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
                          final ok = await _vozacPutnikService.set(
                            putnikId: putnik.id!.toString(),
                            vozacIme: odabranVozac!,
                            dan: dan,
                            grad: _selectedGrad,
                            vreme: _selectedVreme,
                          );
                          if (ok) {
                            if (mounted) AppSnackBar.success(context, '✅ $odabranVozac → ${putnik.ime}');
                          } else {
                            if (mounted) AppSnackBar.error(context, '❌ Greška pri dodjeli');
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
      if (mounted) AppSnackBar.error(context, '❌ Vozač nije pronađen u sistemu');
      return;
    }
    try {
      await _rasporedService.upsert(VozacRasporedEntry(
        dan: dan,
        grad: grad,
        vreme: vreme,
        vozacId: vozacId,
      ));
      if (mounted) AppSnackBar.success(context, '✅ $vozacIme → $grad $vreme ($dan)');
    } catch (e) {
      if (mounted) AppSnackBar.error(context, '❌ Greška: $e');
    }
  }

  Future<void> _ukloniTermin(String dan, String grad, String vreme, String vozacIme) async {
    final vozacId = V2VozacCache.getUuidByIme(vozacIme);
    if (vozacId == null) {
      if (mounted) AppSnackBar.error(context, '❌ Vozač nije pronađen u sistemu');
      return;
    }
    try {
      await _rasporedService.deleteTermin(dan: dan, grad: grad, vreme: vreme, vozacId: vozacId);
      if (mounted) AppSnackBar.success(context, '🗑️ Dodjela uklonjena: $grad $vreme ($dan)');
    } catch (e) {
      if (mounted) AppSnackBar.error(context, '❌ Greška: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    // Izracunaj jednom - koristi se za stream, countHelper i filter
    final isoDate = _getIsoDateForSelectedDay();

    return StreamBuilder<List<V2Putnik>>(
      stream: _putnikStreamService.streamKombinovaniPutniciFiltered(
        isoDate: isoDate,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && snapshot.data == null) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }

        final allPutnici = snapshot.data ?? [];
        final targetDay = _selectedDay ?? _getDayAbbreviation(DateTime.now());

        final countHelper = V2PutnikCountHelper.fromPutnici(
          putnici: allPutnici,
          targetDateIso: isoDate,
          targetDayAbbr: targetDay,
        );

        int getPutnikCount(String grad, String vreme) {
          try {
            return countHelper.getCount(grad, vreme);
          } catch (e) {
            debugPrint('[V2VozacRasporedScreen] getPutnikCount error: $e');
            return 0;
          }
        }

        // Filtriraj po gradu, vremenu, danu i statusu (bez otkazanih/bez_polaska)
        final filteredByGradVreme = allPutnici.where((p) {
          final gradMatch = _selectedGrad.isEmpty || GradAdresaValidator.isGradMatch(p.grad, p.adresa, _selectedGrad);
          final vremeMatch = _selectedVreme.isEmpty || p.polazak == _selectedVreme;
          final danMatch = targetDay.isEmpty || p.dan == targetDay;
          final statusMatch = p.status != 'otkazano' && p.status != 'bez_polaska';
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
            title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Raspored vozača',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
          ),
          body: Container(
            decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
            child: SafeArea(
              child: Column(
                children: [
                  // DAY CHIPS
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: _days.map((day) {
                        final isSelected = _selectedDay == day;
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
                              child: Text(
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
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  // TERMIN INFO TRAKA: koji vozač je dodeljen selektovanom terminu
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
                              // Da li je termin dodeljen (vozac_raspored)?
                              final terminJeDodeljen = _getVozacZaTermin(_selectedGrad, _selectedVreme) != null;
                              // Individualna dodjela putnika (vozac_putnik)?
                              final individualnaEntry =
                                  _vozacPutnikCache.where((e) => e.putnikId == p.id?.toString()).firstOrNull;
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
                                onTap: () => _showPutnikAssignDialog(p),
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

  /// Traka ispod day chips-a: vozač za selektovani termin + tap za izmjenu
  Widget _buildTerminInfoRow(String dan) {
    final vozac = _getVozacZaTermin(_selectedGrad, _selectedVreme);
    final color = vozac != null ? V2VozacCache.getColor(vozac) : Colors.white24;

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

// ═══════════════════════════════════════════════════════════════════
// TILE ZA PUTNIKA U RASPORED EKRANU
// ═══════════════════════════════════════════════════════════════════

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

    return GestureDetector(
      onTap: terminJeDodeljen ? null : onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.4), width: 1),
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
                        color: color != Colors.white12 ? color : Colors.white,
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
              // Desna strana: ikona za dodjelu (samo kad termin nema vozača)
              if (!terminJeDodeljen) const Icon(Icons.person_add_outlined, color: Colors.white38, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
