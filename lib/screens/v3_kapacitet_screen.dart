import 'package:flutter/material.dart';

import '../globals.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_kapacitet_slots_service.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dialog_helper.dart';
import '../utils/v3_input_utils.dart';
import '../utils/v3_string_utils.dart';

/// Admin ekran za podešavanje kapaciteta polazaka
class V3KapacitetScreen extends StatefulWidget {
  const V3KapacitetScreen({super.key});
  @override
  State<V3KapacitetScreen> createState() => _V3KapacitetScreenState();
}

class _V3KapacitetScreenState extends State<V3KapacitetScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final Stream<int> _streamTrigger;
  String _selectedDay = V3DanHelper.defaultWorkdayFullName();

  String get _selectedDatumIso =>
      V3DanHelper.datumIsoZaDanPuniUTekucojSedmici(_selectedDay, anchor: V3DanHelper.schedulingWeekAnchor());

  @override
  void initState() {
    super.initState();
    _selectedDay = V3DanHelper.defaultWorkdayFullName();
    _tabController = TabController(length: 2, vsync: this);
    _streamTrigger = V3MasterRealtimeManager.instance.tableRevisionStream('v3_kapacitet_slots');
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Traži red u kešu normalizovanim poređenjem grad/vreme/datum.
  Map<String, dynamic>? _findCacheRow(String grad, String vreme, String datumIso) {
    final gradNorm = grad.trim().toUpperCase();
    final vremeNorm = V3StringUtils.trimTimeToHhMm(vreme);
    final datumNorm = datumIso.trim();
    for (final r in V3MasterRealtimeManager.instance.kapacitetSlotsCache.values) {
      final rGrad = (r['grad']?.toString() ?? '').trim().toUpperCase();
      final rVreme = V3StringUtils.trimTimeToHhMm(r['vreme']?.toString() ?? '');
      final rDatum = (r['datum']?.toString() ?? '').trim();
      if (rGrad == gradNorm && rVreme == vremeNorm && rDatum.startsWith(datumNorm)) {
        return r;
      }
    }
    return null;
  }

  /// Čita max_mesta iz kapacitetSlotsCache: {grad: {vreme: max_mesta?}}
  Map<String, Map<String, int?>> _getKapacitetSync() {
    final datumIso = _selectedDatumIso;
    final bcVremena = getRasporedVremena('bc', navBarTypeNotifier.value, day: _selectedDay);
    final vsVremena = getRasporedVremena('vs', navBarTypeNotifier.value, day: _selectedDay);
    return {
      'BC': {for (final v in bcVremena) v: (_findCacheRow('BC', v, datumIso)?['max_mesta'] as num?)?.toInt()},
      'VS': {for (final v in vsVremena) v: (_findCacheRow('VS', v, datumIso)?['max_mesta'] as num?)?.toInt()},
    };
  }

  Future<void> _upsertKapacitet(String grad, String vreme, int maxMesta) async {
    final datumIso = _selectedDatumIso;
    final slotId = _findCacheRow(grad, vreme, datumIso)?['id'] as String?;
    try {
      await V3KapacitetSlotsService.upsertSlot(
        grad: grad,
        vreme: vreme,
        datumIso: datumIso,
        maxMesta: maxMesta,
        id: slotId,
      );
    } catch (e) {
      debugPrint('[KapacitetScreen] upsertKapacitet error: $e');
      if (mounted) V3AppSnackBar.error(context, '❌ Greška pri čuvanju');
    }
  }

  Future<void> _editKapacitet(String grad, String vreme, int? trenutni) async {
    final result = await V3DialogHelper.showDialogBuilder<int>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _KapacitetEditDialog(grad: grad, vreme: vreme, trenutni: trenutni ?? 0),
    );
    if (result != null && result != trenutni) {
      await _upsertKapacitet(grad, vreme, result);
      if (mounted) V3AppSnackBar.success(context, '✅ $grad $vreme = $result mesta');
    }
  }

  Color _getBoja(int mesta) {
    if (mesta >= 8) return Colors.green;
    if (mesta >= 5) return Colors.orange;
    return Colors.red;
  }

  Widget _buildGradTab(String grad, List<String> vremena, Map<String, int?> kapacitet) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: vremena.length,
      itemBuilder: (ctx, index) {
        final vreme = vremena[index];
        final maxMesta = kapacitet[vreme];
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
                  onPressed:
                      maxMesta != null && maxMesta > 1 ? () => _upsertKapacitet(grad, vreme, maxMesta - 1) : null,
                  icon: const Icon(Icons.remove_circle, color: Colors.red, size: 32),
                ),
                V3ContainerUtils.iconContainer(
                  width: V3ContainerUtils.responsiveHeight(ctx, 40),
                  height: V3ContainerUtils.responsiveHeight(ctx, 40),
                  backgroundColor: maxMesta != null ? _getBoja(maxMesta) : Colors.grey,
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
                      ? () => _upsertKapacitet(grad, vreme, (maxMesta ?? 0) + 1)
                      : null,
                  icon: const Icon(Icons.add_circle, color: Colors.green, size: 32),
                ),
              ],
            ),
            onTap: () => _editKapacitet(grad, vreme, maxMesta),
          ),
        );
      },
    );
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
                      final abbr = V3DanHelper.workdayAbbrFromFullName(day);
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
                  child: StreamBuilder<int>(
                    stream: _streamTrigger,
                    builder: (context, snapshot) {
                      final data = _getKapacitetSync();
                      final bcVremena = getRasporedVremena('bc', navBarTypeNotifier.value, day: _selectedDay);
                      final vsVremena = getRasporedVremena('vs', navBarTypeNotifier.value, day: _selectedDay);
                      return TabBarView(
                        controller: _tabController,
                        children: [
                          _buildGradTab('BC', bcVremena, data['BC'] ?? {}),
                          _buildGradTab('VS', vsVremena, data['VS'] ?? {}),
                        ],
                      );
                    },
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
