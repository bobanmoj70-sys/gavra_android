import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/v3_kredit.dart';
import '../services/v3/v3_kredit_service.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dialog_helper.dart';
import '../utils/v3_error_utils.dart';
import '../utils/v3_format_utils.dart';
import '../utils/v3_input_utils.dart';
import '../utils/v3_state_utils.dart';

class V3KreditiScreen extends StatefulWidget {
  const V3KreditiScreen({super.key});

  @override
  State<V3KreditiScreen> createState() => _V3KreditiScreenState();
}

class _V3KreditiScreenState extends State<V3KreditiScreen> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<V3Kredit>>(
      stream: V3KreditService.streamKrediti(),
      builder: (context, snapshot) {
        final krediti = snapshot.data ?? V3KreditService.getKrediti();
        final ukupnoPreostalo = krediti.fold<double>(
          0.0,
          (sum, k) => sum + (k.preostalo > 0 ? k.preostalo : 0),
        );

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            automaticallyImplyLeading: false,
            title: const Text('Moji krediti', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          body: V3ContainerUtils.backgroundContainer(
            gradient: Theme.of(context).backgroundGradient,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildUkupnoCard(ukupnoPreostalo),
                    const SizedBox(height: 16),
                    Expanded(
                      child: krediti.isEmpty
                          ? const Center(
                              child: Text(
                                'Nema evidentiranih kredita',
                                style: TextStyle(color: Colors.white70, fontSize: 16),
                              ),
                            )
                          : ListView.builder(
                              itemCount: krediti.length,
                              itemBuilder: (context, index) => _KreditCard(
                                kredit: krediti[index],
                                onUplati: () => _showUplataDialog(krediti[index]),
                                onIzmeni: () => _showKreditDialog(krediti[index]),
                                onObrisi: () => _obrisiKredit(krediti[index]),
                                onIstorija: () => _showIstorijaDialog(krediti[index]),
                              ),
                            ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: V3ButtonUtils.successButton(
                        onPressed: () => _showKreditDialog(null),
                        text: 'Dodaj kredit',
                        icon: Icons.add_circle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildUkupnoCard(double iznos) {
    return V3ContainerUtils.gradientContainer(
      gradient: LinearGradient(
        colors: [Colors.red.shade800, Colors.red.shade600],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(18),
      boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 5))],
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          V3ContainerUtils.iconContainer(
            width: 52,
            height: 52,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            borderRadiusGeometry: BorderRadius.circular(14),
            child: const Center(child: Text('🏦', style: TextStyle(fontSize: 26))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Preostala dugovanja',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 2),
                Text('Ukupno preostalo za otplatu',
                    style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
              ],
            ),
          ),
          Text(_fmtIznos(iznos),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }

  Future<void> _showKreditDialog(V3Kredit? kredit) async {
    final result = await showDialog<_KreditFormResult>(
      context: context,
      builder: (context) => _KreditDialog(kredit: kredit),
    );
    if (result == null) return;

    try {
      if (kredit == null) {
        await V3KreditService.dodaj(
          naziv: result.naziv,
          ukupanIznos: result.ukupanIznos,
          napomena: result.napomena,
          krajKredita: result.krajKredita,
        );
        if (mounted) V3AppSnackBar.success(context, '✅ Kredit dodat');
      } else {
        await V3KreditService.izmeni(
          id: kredit.id,
          naziv: result.naziv,
          ukupanIznos: result.ukupanIznos,
          napomena: result.napomena,
          krajKredita: result.krajKredita,
        );
        if (mounted) V3AppSnackBar.success(context, '✅ Kredit izmenjen');
      }
    } catch (e) {
      if (mounted) V3ErrorUtils.asyncError(this, context, e);
    }
  }

  Future<void> _showUplataDialog(V3Kredit kredit) async {
    final result = await showDialog<_UplataResult>(
      context: context,
      builder: (context) => _UplataDialog(kredit: kredit),
    );
    if (result == null || result.iznos <= 0) return;

    try {
      await V3KreditService.uplati(
        id: kredit.id,
        iznos: result.iznos,
        napomena: result.napomena,
      );
      if (mounted) V3AppSnackBar.success(context, '✅ Uplata evidentirana');
    } catch (e) {
      if (mounted) V3ErrorUtils.asyncError(this, context, e);
    }
  }

  Future<void> _obrisiKredit(V3Kredit kredit) async {
    final confirmed = await V3DialogHelper.showConfirmDialog(
      context,
      title: 'Obriši kredit',
      message: 'Da li si siguran da želiš da obrišeš „${kredit.naziv}"?',
      confirmText: 'Obriši',
      isDangerous: true,
    );
    if (confirmed != true) return;

    try {
      await V3KreditService.obrisi(kredit.id);
      if (mounted) V3AppSnackBar.success(context, '✅ Kredit obrisan');
    } catch (e) {
      if (mounted) V3ErrorUtils.asyncError(this, context, e);
    }
  }

  Future<void> _showIstorijaDialog(V3Kredit kredit) async {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9, maxHeight: MediaQuery.of(context).size.height * 0.7),
          decoration: BoxDecoration(
            gradient: Theme.of(context).backgroundGradient,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Theme.of(context).glassBorder, width: 0.8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Istorija uplata: ${kredit.naziv}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: kredit.uplate.isEmpty
                      ? const Center(
                          child: Text(
                            'Nema evidentiranih uplata',
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                        )
                      : ListView.builder(
                          itemCount: kredit.uplate.length,
                          itemBuilder: (context, index) {
                            final uplata = kredit.uplate[index];
                            final datumStr =
                                '${uplata.datum.day.toString().padLeft(2, '0')}.${uplata.datum.month.toString().padLeft(2, '0')}.${uplata.datum.year}';
                            final vremeStr =
                                '${uplata.datum.hour.toString().padLeft(2, '0')}:${uplata.datum.minute.toString().padLeft(2, '0')}';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E2235),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red.withValues(alpha: 0.3), width: 1.5),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${V3FormatUtils.formatBroj(uplata.iznos.round())} din',
                                          style: const TextStyle(
                                              fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '$datumStr $vremeStr',
                                          style: const TextStyle(fontSize: 12, color: Colors.white54),
                                        ),
                                        if (uplata.napomena != null && uplata.napomena!.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            uplata.napomena!,
                                            style: const TextStyle(fontSize: 11, color: Colors.white38),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () async {
                                      final confirmed = await V3DialogHelper.showConfirmDialog(
                                        context,
                                        title: 'Obriši uplatu',
                                        message: 'Da li si siguran da želiš da obrišeš ovu uplatu?',
                                        confirmText: 'Obriši',
                                        isDangerous: true,
                                      );
                                      if (confirmed == true) {
                                        try {
                                          await V3KreditService.obrisiUplatu(
                                            kreditId: kredit.id,
                                            uplataId: uplata.uplataId,
                                          );
                                          if (mounted) V3AppSnackBar.success(context, '✅ Uplata obrisana');
                                          Navigator.pop(context);
                                        } catch (e) {
                                          if (mounted) V3ErrorUtils.asyncError(this, context, e);
                                        }
                                      }
                                    },
                                    icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
                V3ButtonUtils.outlinedButton(
                  onPressed: () => Navigator.pop(context),
                  text: 'Zatvori',
                  borderColor: Colors.white24,
                  foregroundColor: Colors.white70,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fmtIznos(double iznos) => '${V3FormatUtils.formatBroj(iznos.round())} din';
}

// ─── Kartica kredita ─────────────────────────────────────────────────────────

class _KreditCard extends StatelessWidget {
  const _KreditCard({
    required this.kredit,
    required this.onUplati,
    required this.onIzmeni,
    required this.onObrisi,
    required this.onIstorija,
  });

  final V3Kredit kredit;
  final VoidCallback onUplati;
  final VoidCallback onIzmeni;
  final VoidCallback onObrisi;
  final VoidCallback onIstorija;

  @override
  Widget build(BuildContext context) {
    final preostalo = kredit.preostalo > 0 ? kredit.preostalo : 0.0;
    final progress = kredit.procenatOtplacenosti;
    final procenatText = '${(progress * 100).toStringAsFixed(0)}%';

    return GestureDetector(
      onTap: onIstorija,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2235),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      kredit.naziv,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  if (kredit.jeOtplacen)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
                      ),
                      child: const Text('OTPLAĆENO',
                          style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              if (kredit.napomena != null && kredit.napomena!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(kredit.napomena!, style: const TextStyle(fontSize: 12, color: Colors.white54)),
              ],
              if (kredit.krajKredita != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 12, color: Colors.white38),
                    const SizedBox(width: 6),
                    Text(
                      'Kraj: ${kredit.krajKredita!.day.toString().padLeft(2, '0')}.${kredit.krajKredita!.month.toString().padLeft(2, '0')}.${kredit.krajKredita!.year}',
                      style: const TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              _buildRow('Ukupan iznos', kredit.ukupanIznos, Colors.white70),
              _buildRow('Uplaćeno', kredit.uplaceno, const Color(0xFF4ADE80)),
              _buildRow('Preostalo', preostalo, const Color(0xFFF87171)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          kredit.jeOtplacen ? Colors.green : Colors.redAccent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(procenatText,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: kredit.jeOtplacen ? Colors.green : Colors.redAccent,
                      )),
                ],
              ),
              const SizedBox(height: 12),
              _buildStatsRow(),
              if (kredit.uplate.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(height: 100, child: _KreditChart(kredit: kredit)),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: V3ButtonUtils.successButton(
                      onPressed: onUplati,
                      text: 'UPLATI',
                      icon: Icons.payments,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _IconButton(icon: Icons.history, onTap: onIstorija, color: Colors.amber),
                  const SizedBox(width: 8),
                  _IconButton(icon: Icons.edit, onTap: onIzmeni, color: Colors.blueAccent),
                  const SizedBox(width: 8),
                  _IconButton(icon: Icons.delete, onTap: onObrisi, color: Colors.redAccent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(label: 'Uplate', value: '${kredit.brojUplata}'),
          _StatItem(label: 'Prosek', value: V3FormatUtils.formatBroj(kredit.prosecnaUplata.round())),
          _StatItem(label: 'Najveća', value: V3FormatUtils.formatBroj(kredit.najvecaUplata.round())),
        ],
      ),
    );
  }

  Widget _buildRow(String label, double iznos, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.white60)),
          Text('${V3FormatUtils.formatBroj(iznos.round())} din',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
      ],
    );
  }
}

class _KreditChart extends StatelessWidget {
  const _KreditChart({required this.kredit});
  final V3Kredit kredit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2235),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Grafik uplata po mesecima',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70)),
          const SizedBox(height: 8),
          Expanded(
            child: BarChart(
              _buildChartData(),
              swapAnimationDuration: const Duration(milliseconds: 300),
              swapAnimationCurve: Curves.easeInOut,
            ),
          ),
        ],
      ),
    );
  }

  BarChartData _buildChartData() {
    final mesecniIznosi = <String, double>{};
    for (final uplata in kredit.uplate) {
      final key = '${uplata.datum.month.toString().padLeft(2, '0')}.${uplata.datum.year}';
      mesecniIznosi[key] = (mesecniIznosi[key] ?? 0) + uplata.iznos;
    }

    final sortedKeys = mesecniIznosi.keys.toList()..sort();
    final maxY = mesecniIznosi.values.isEmpty ? 1.0 : mesecniIznosi.values.reduce((a, b) => a > b ? a : b) * 1.2;

    return BarChartData(
      alignment: BarChartAlignment.spaceAround,
      maxY: maxY,
      barTouchData: BarTouchData(enabled: false),
      titlesData: FlTitlesData(
        show: true,
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index < 0 || index >= sortedKeys.length) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  sortedKeys[index],
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              );
            },
            reservedSize: 28,
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (value, meta) {
              if (value == 0) return const SizedBox.shrink();
              return Text(
                value >= 1000 ? '${(value / 1000).toStringAsFixed(0)}k' : value.toStringAsFixed(0),
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              );
            },
          ),
        ),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      gridData: FlGridData(show: true, horizontalInterval: maxY / 4),
      borderData: FlBorderData(show: false),
      barGroups: sortedKeys.asMap().entries.map((entry) {
        final index = entry.key;
        final key = entry.value;
        return BarChartGroupData(
          x: index,
          barRods: [
            BarChartRodData(
              toY: mesecniIznosi[key] ?? 0,
              color: Colors.greenAccent,
              width: 16,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ],
        );
      }).toList(),
    );
  }
}

// ─── Dijalozi ────────────────────────────────────────────────────────────────

class _KreditFormResult {
  final String naziv;
  final double ukupanIznos;
  final String? napomena;
  final DateTime? krajKredita;
  const _KreditFormResult({
    required this.naziv,
    required this.ukupanIznos,
    this.napomena,
    this.krajKredita,
  });
}

class _KreditDialog extends StatefulWidget {
  const _KreditDialog({this.kredit});
  final V3Kredit? kredit;

  @override
  State<_KreditDialog> createState() => _KreditDialogState();
}

class _KreditDialogState extends State<_KreditDialog> {
  late final TextEditingController _nazivCtrl;
  late final TextEditingController _iznosCtrl;
  late final TextEditingController _napomenaCtrl;
  DateTime? _krajKredita;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nazivCtrl = TextEditingController(text: widget.kredit?.naziv ?? '');
    _iznosCtrl = TextEditingController(
      text: widget.kredit != null ? widget.kredit!.ukupanIznos.toStringAsFixed(0) : '',
    );
    _napomenaCtrl = TextEditingController(text: widget.kredit?.napomena ?? '');
    _krajKredita = widget.kredit?.krajKredita;
  }

  @override
  void dispose() {
    _nazivCtrl.dispose();
    _iznosCtrl.dispose();
    _napomenaCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _krajKredita ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Kraj kredita / zadnja rata',
    );
    if (picked != null) {
      V3StateUtils.safeSetState(this, () => _krajKredita = picked);
    }
  }

  Future<void> _save() async {
    final naziv = _nazivCtrl.text.trim();
    final iznos = double.tryParse(_iznosCtrl.text.replaceAll(',', '.')) ?? 0.0;

    if (naziv.isEmpty) {
      V3AppSnackBar.error(context, 'Naziv je obavezan');
      return;
    }
    if (iznos < 0) {
      V3AppSnackBar.error(context, 'Iznos ne može biti negativan');
      return;
    }

    V3StateUtils.safeSetState(this, () => _saving = true);
    await Future<void>.delayed(Duration.zero);
    if (mounted) {
      Navigator.pop(
        context,
        _KreditFormResult(
          naziv: naziv,
          ukupanIznos: iznos,
          napomena: _napomenaCtrl.text.trim().isEmpty ? null : _napomenaCtrl.text.trim(),
          krajKredita: _krajKredita,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.9),
        decoration: BoxDecoration(
          gradient: Theme.of(context).backgroundGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).glassBorder, width: 0.8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.kredit == null ? 'Dodaj kredit' : 'Izmeni kredit',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 16),
              V3InputUtils.textField(
                controller: _nazivCtrl,
                label: 'Naziv (npr. BMW, Mama)',
              ),
              const SizedBox(height: 12),
              V3InputUtils.numberField(
                controller: _iznosCtrl,
                label: 'Ukupan iznos (RSD)',
                suffixText: 'din',
              ),
              const SizedBox(height: 12),
              V3InputUtils.textField(
                controller: _napomenaCtrl,
                label: 'Napomena (opciono)',
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Kraj kredita (opciono)',
                    labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.78)),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white30),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                    ),
                    suffixIcon: _krajKredita != null
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white54, size: 20),
                            onPressed: () => V3StateUtils.safeSetState(this, () => _krajKredita = null),
                          )
                        : const Icon(Icons.calendar_today, color: Colors.amber, size: 20),
                  ),
                  child: Text(
                    _krajKredita != null
                        ? '${_krajKredita!.day.toString().padLeft(2, '0')}.${_krajKredita!.month.toString().padLeft(2, '0')}.${_krajKredita!.year}'
                        : 'Izaberi datum',
                    style: TextStyle(
                      color: _krajKredita != null ? Colors.white : Colors.white54,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: V3ButtonUtils.outlinedButton(
                      onPressed: () => Navigator.pop(context),
                      text: 'Otkaži',
                      borderColor: Colors.white24,
                      foregroundColor: Colors.white70,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: V3ButtonUtils.successButton(
                      onPressed: _saving ? null : _save,
                      text: 'Sačuvaj',
                      icon: Icons.save,
                      isLoading: _saving,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UplataResult {
  final double iznos;
  final String? napomena;
  const _UplataResult({required this.iznos, this.napomena});
}

class _UplataDialog extends StatefulWidget {
  const _UplataDialog({required this.kredit});
  final V3Kredit kredit;

  @override
  State<_UplataDialog> createState() => _UplataDialogState();
}

class _UplataDialogState extends State<_UplataDialog> {
  late final TextEditingController _iznosCtrl;
  late final TextEditingController _napomenaCtrl;

  @override
  void initState() {
    super.initState();
    _iznosCtrl = TextEditingController(
      text: widget.kredit.preostalo > 0 ? widget.kredit.preostalo.toStringAsFixed(0) : '',
    );
    _napomenaCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _iznosCtrl.dispose();
    _napomenaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.9),
        decoration: BoxDecoration(
          gradient: Theme.of(context).backgroundGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).glassBorder, width: 0.8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Uplata: ${widget.kredit.naziv}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                'Preostalo: ${V3FormatUtils.formatBroj(widget.kredit.preostalo.round())} din',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              V3InputUtils.numberField(
                controller: _iznosCtrl,
                label: 'Iznos uplate',
                suffixText: 'din',
              ),
              const SizedBox(height: 12),
              V3InputUtils.textField(
                controller: _napomenaCtrl,
                label: 'Napomena (opciono)',
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: V3ButtonUtils.outlinedButton(
                      onPressed: () => Navigator.pop(context),
                      text: 'Otkaži',
                      borderColor: Colors.white24,
                      foregroundColor: Colors.white70,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: V3ButtonUtils.successButton(
                      onPressed: () {
                        final iznos = double.tryParse(_iznosCtrl.text.replaceAll(',', '.')) ?? 0.0;
                        if (iznos <= 0) {
                          V3AppSnackBar.error(context, 'Iznos mora biti veći od nule');
                          return;
                        }
                        Navigator.pop(
                          context,
                          _UplataResult(
                            iznos: iznos,
                            napomena: _napomenaCtrl.text.trim().isEmpty ? null : _napomenaCtrl.text.trim(),
                          ),
                        );
                      },
                      text: 'Uplati',
                      icon: Icons.payments,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap, required this.color});
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}
