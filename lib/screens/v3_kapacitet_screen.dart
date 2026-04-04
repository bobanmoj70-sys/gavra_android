import 'package:flutter/material.dart';

import '../globals.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_kapacitet_slots_service.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_input_utils.dart';
import '../utils/v3_string_utils.dart';
import '../widgets/v3_shimmer_banner.dart';

/// Admin ekran za podešavanje kapaciteta polazaka
class V3KapacitetScreen extends StatefulWidget {
  const V3KapacitetScreen({super.key});
  @override
  State<V3KapacitetScreen> createState() => _V3KapacitetScreenState();
}

class _V3KapacitetScreenState extends State<V3KapacitetScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final Stream<void> _streamTrigger;
  String _selectedDay = V3DanHelper.defaultWorkdayFullName();

  String get _selectedDatumIso =>
      V3DanHelper.datumIsoZaDanPuniUTekucojSedmici(_selectedDay, anchor: V3DanHelper.schedulingWeekAnchor());

  String? get _neradanDanRazlog => getNeradanDanRazlog(datumIso: _selectedDatumIso);
  @override
  void initState() {
    super.initState();
    _selectedDay = V3DanHelper.defaultWorkdayFullName();
    _tabController = TabController(length: 2, vsync: this);
    _streamTrigger = V3MasterRealtimeManager.instance.v3StreamFromCache(
      tables: ['v3_kapacitet_slots'],
      build: () {},
    );
  }

  /// Čita max_mesta iz kapacitetSlotsCache: {grad: {vreme: max_mesta?}}
  Map<String, Map<String, int?>> _getKapacitetSync() {
    final cache = V3MasterRealtimeManager.instance.kapacitetSlotsCache.values;
    final bcVremena = getRasporedVremena('bc', navBarTypeNotifier.value, day: _selectedDay);
    final vsVremena = getRasporedVremena('vs', navBarTypeNotifier.value, day: _selectedDay);
    final datumIso = _selectedDatumIso;
    int? _find(String grad, String vreme) {
      for (final r in cache) {
        if (r['grad'] == grad &&
            V3StringUtils.trimTimeToHhMm(r['vreme'].toString()) == vreme &&
            r['datum'].toString().startsWith(datumIso) &&
            r['aktivno'] == true) {
          return (r['max_mesta'] as num?)?.toInt();
        }
      }
      return null;
    }

    return {
      'BC': {for (final v in bcVremena) v: _find('BC', v)},
      'VS': {for (final v in vsVremena) v: _find('VS', v)},
    };
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _editKapacitet(String grad, String vreme, int? trenutni) async {
    final result = await showDialog<int>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _KapacitetEditDialog(grad: grad, vreme: vreme, trenutni: trenutni ?? 0),
    );
    if (result != null && result != trenutni) {
      final success = await _setKapacitet(grad, vreme, result);
      if (!mounted) return;
      if (success) {
        V3AppSnackBar.success(context, '\u2705 $grad $vreme = $result mesta');
      } else {
        V3AppSnackBar.error(context, '\u274c Greška pri čuvanju');
      }
    }
  }

  /// Upsert max_mesta u v3_kapacitet_slots za dati grad/vreme/datum.
  Future<bool> _setKapacitet(String grad, String vreme, int maxMesta) async {
    try {
      final datumIso = _selectedDatumIso;
      await V3KapacitetSlotsService.upsertSlot(
        grad: grad,
        vreme: vreme,
        datumIso: datumIso,
        maxMesta: maxMesta,
      );
      return true;
    } catch (e) {
      debugPrint('[KapacitetScreen] setKapacitet error: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return V3ContainerUtils.backgroundContainer(
      gradient: Theme.of(context).backgroundGradient,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('🎫 Kapacitet Polazaka', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.green,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: const [
              Tab(text: 'Bela Crkva'),
              Tab(text: 'Vrsac'),
            ],
          ),
        ),
        body: ValueListenableBuilder<String>(
          valueListenable: navBarTypeNotifier,
          builder: (context, sezon, _) {
            return Column(
              children: [
                // ── Dan chips ──────────────────────────────────────────
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    children: V3DanHelper.workdayNames.map((day) {
                      final isSelected = _selectedDay == day;
                      final abbr = V3DanHelper.normalizeToWorkdayAbbr(V3DanHelper.dayAbbrFromFullName(day));
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InkWell(
                          onTap: () => setState(() => _selectedDay = V3DanHelper.normalizeToWorkdayFull(day)),
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
                                color: isSelected ? Colors.white.withValues(alpha: 0.7) : Theme.of(context).glassBorder,
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
                // ── TabBarView ─────────────────────────────────────────
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Padding(
                          padding: EdgeInsets.only(top: _neradanDanRazlog != null ? 52 : 0),
                          child: StreamBuilder<void>(
                            stream: _streamTrigger,
                            builder: (context, snapshot) {
                              final neradanRazlog = _neradanDanRazlog;
                              if (neradanRazlog != null) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    child: Text(
                                      '⛔ Slotovi su zaključani za ovaj datum.\nRazlog: $neradanRazlog',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                );
                              }

                              final data = _getKapacitetSync();
                              final bcVremena = getRasporedVremena('bc', navBarTypeNotifier.value, day: _selectedDay);
                              final vsVremena = getRasporedVremena('vs', navBarTypeNotifier.value, day: _selectedDay);
                              return TabBarView(
                                controller: _tabController,
                                children: [
                                  _kapacitetGradTab('BC', bcVremena, data, _editKapacitet, _selectedDatumIso),
                                  _kapacitetGradTab('VS', vsVremena, data, _editKapacitet, _selectedDatumIso),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      if (_neradanDanRazlog != null)
                        Positioned(
                          top: 0,
                          left: 12,
                          right: 12,
                          child: V3ShimmerBanner(
                            margin: EdgeInsets.zero,
                            borderRadius: 12,
                            child: Text(
                              '📢 Neradan dan ${_selectedDay.toUpperCase()} (${_selectedDatumIso}) — $_neradanDanRazlog',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

Color _kapacitetGetBoja(int mesta) {
  if (mesta >= 8) return Colors.green;
  if (mesta >= 5) return Colors.orange;
  return Colors.red;
}

// ─── top-level tab builder ───────────────────────────────────────────────────
Widget _kapacitetGradTab(
  String grad,
  List<String> vremena,
  Map<String, Map<String, int?>> kapacitet,
  Future<void> Function(String grad, String vreme, int? trenutni) onEdit,
  String datumIso,
) {
  return ListView.builder(
    padding: const EdgeInsets.all(16),
    itemCount: vremena.length,
    itemBuilder: (ctx, index) {
      final vreme = vremena[index];
      final maxMesta = kapacitet[grad]?[vreme];
      return Card(
        color: Theme.of(ctx).glassContainer,
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          title: Text(
            vreme,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            maxMesta != null ? 'Kapacitet: $maxMesta mesta' : 'Kapacitet: nije postavljen',
            style: TextStyle(
              color: maxMesta == null
                  ? Colors.red
                  : maxMesta < 8
                      ? Colors.orange
                      : Colors.white70,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: maxMesta != null && maxMesta > 1
                    ? () async {
                        final newVal = maxMesta - 1;
                        final slotId = _getSlotId(grad, vreme, datumIso);
                        await V3KapacitetSlotsService.upsertSlot(
                          grad: grad,
                          vreme: vreme,
                          datumIso: datumIso,
                          maxMesta: newVal,
                          id: slotId,
                        );
                      }
                    : null,
                icon: const Icon(Icons.remove_circle, color: Colors.red, size: 32),
              ),
              V3ContainerUtils.iconContainer(
                width: V3ContainerUtils.responsiveHeight(ctx, 40),
                height: V3ContainerUtils.responsiveHeight(ctx, 40),
                backgroundColor: maxMesta != null ? _kapacitetGetBoja(maxMesta) : Colors.grey,
                borderRadiusGeometry: BorderRadius.circular(8),
                child: Center(
                  child: Text(
                    maxMesta != null ? '$maxMesta' : '?',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              IconButton(
                onPressed: maxMesta == null || maxMesta < 20
                    ? () async {
                        final newVal = (maxMesta ?? 0) + 1;
                        final slotId = _getSlotId(grad, vreme, datumIso);
                        await V3KapacitetSlotsService.upsertSlot(
                          grad: grad,
                          vreme: vreme,
                          datumIso: datumIso,
                          maxMesta: newVal,
                          id: slotId,
                        );
                      }
                    : null,
                icon: const Icon(Icons.add_circle, color: Colors.green, size: 32),
              ),
            ],
          ),
          onTap: () => onEdit(grad, vreme, maxMesta),
        ),
      );
    },
  );
}

String? _getSlotId(String grad, String vreme, String datumIso) {
  final cache = V3MasterRealtimeManager.instance.kapacitetSlotsCache.values;
  for (final r in cache) {
    if (r['grad'] == grad &&
        V3StringUtils.trimTimeToHhMm(r['vreme'].toString()) == vreme &&
        r['datum'].toString().startsWith(datumIso) &&
        r['aktivno'] == true) {
      return r['id'] as String?;
    }
  }
  return null;
}

// ─── _KapacitetEditDialog ────────────────────────────────────────────────────
class _KapacitetEditDialog extends StatefulWidget {
  const _KapacitetEditDialog({
    required this.grad,
    required this.vreme,
    required this.trenutni,
  });
  final String grad;
  final String vreme;
  final int trenutni;
  @override
  State<_KapacitetEditDialog> createState() => _KapacitetEditDialogState();
}

class _KapacitetEditDialogState extends State<_KapacitetEditDialog> {
  late final TextEditingController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.trenutni.toString());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: V3ContainerUtils.gradientContainer(
        width: 320,
        gradient: Theme.of(context).backgroundGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 10),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Zaglavlje
            V3ContainerUtils.iconContainer(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              backgroundColor: Theme.of(context).glassContainer,
              borderRadiusGeometry: const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(bottom: BorderSide(color: Theme.of(context).glassBorder)),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '🎫 ${widget.grad} - ${widget.vreme}',
                      style: const TextStyle(
                        fontSize: 20,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: V3ContainerUtils.iconContainer(
                      padding: const EdgeInsets.all(8),
                      backgroundColor: Colors.red.withValues(alpha: 0.2),
                      borderRadiusGeometry: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                      child: const Icon(Icons.close, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            // Tijelo
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Unesite maksimalan broj mesta:',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  V3ContainerUtils.iconContainer(
                    backgroundColor: Theme.of(context).glassContainer,
                    borderRadiusGeometry: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).glassBorder),
                    child: V3InputUtils.numberField(
                      controller: _ctrl,
                      label: '',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey.withValues(alpha: 0.5)),
                            ),
                          ),
                          child: const Text('Otkaži', style: TextStyle(color: Colors.grey, fontSize: 16)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: V3ButtonUtils.successButton(
                          onPressed: () {
                            final value = int.tryParse(_ctrl.text);
                            if (value != null && value > 0 && value <= 20) {
                              Navigator.pop(context, value);
                            } else {
                              V3AppSnackBar.error(context, 'Unesite broj između 1 i 20');
                            }
                          },
                          text: 'Sačuvaj',
                        ),
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
}
