import 'dart:async';

import 'package:flutter/material.dart';

import '../models/v3_finansije.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_dug_service.dart';
import '../services/v3/v3_finansije_service.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dan_helper.dart';
import '../utils/v3_dialog_utils.dart';
import '../utils/v3_error_utils.dart';
import '../utils/v3_format_utils.dart';
import '../utils/v3_input_utils.dart';
import '../utils/v3_navigation_utils.dart';
import '../utils/v3_state_utils.dart';

/// FINANSIJE — V3
/// Prihodi: dnevneOperacijeCache (naplata_status='placeno', iznos_naplacen)
/// Troškovi: v3_troskovi cache (mesec/godina)
/// Potraživanja: V3DugService.getDugovi()
class V3FinansijeScreen extends StatefulWidget {
  const V3FinansijeScreen({super.key});

  @override
  State<V3FinansijeScreen> createState() => _V3FinansijeScreenState();
}

// ─── Podaci ───────────────────────────────────────────────────────────────────

class _V3IzvestajData {
  final double potrazivanjaIznos;
  final double prihodNedelja;
  final double trosakNedelja;
  final int voznjiNedelja;
  final double prihodMesec;
  final double trosakMesec;
  final int voznjiMesec;
  final double prihodGodina;
  final double trosakGodina;
  final int voznjiGodina;
  final Map<String, double> troskoviPoKategoriji;
  final String nedeljaPeriod;
  final int godinaBroj;

  const _V3IzvestajData({
    required this.potrazivanjaIznos,
    required this.prihodNedelja,
    required this.trosakNedelja,
    required this.voznjiNedelja,
    required this.prihodMesec,
    required this.trosakMesec,
    required this.voznjiMesec,
    required this.prihodGodina,
    required this.trosakGodina,
    required this.voznjiGodina,
    required this.troskoviPoKategoriji,
    required this.nedeljaPeriod,
    required this.godinaBroj,
  });
}

_V3IzvestajData _buildIzvestaj() {
  final now = DateTime.now();
  final rm = V3MasterRealtimeManager.instance;
  final ops = rm.operativnaNedeljaCache.values;

  // Nedelja: od ponedjeljka do nedjelje
  final dayOfWeek = now.weekday; // 1=Mon
  final nedStart = V3DanHelper.dateOnlyFrom(now.year, now.month, now.day - (dayOfWeek - 1));
  final nedEnd = nedStart.add(const Duration(days: 7));

  // Mesec
  final mesStart = V3DanHelper.dateOnlyFrom(now.year, now.month, 1);
  final mesEnd = V3DanHelper.dateOnlyFrom(now.year, now.month + 1, 1);

  // Prošla godina
  final proslaGod = now.year - 1;

  double prihodNed = 0, prihodMes = 0, prihodGod = 0;
  int voznjiNed = 0, voznjiMes = 0, voznjiGod = 0;

  for (final row in ops) {
    if ((row['naplata_status'] as String?) != 'placeno') continue;
    final updStr = row['updated_at'] as String?;
    if (updStr == null) continue;
    final dt = DateTime.tryParse(updStr)?.toLocal();
    if (dt == null) continue;
    final iznos = (row['iznos_naplacen'] as num?)?.toDouble() ?? 0.0;

    if (!dt.isBefore(nedStart) && dt.isBefore(nedEnd)) {
      prihodNed += iznos;
      voznjiNed++;
    }
    if (!dt.isBefore(mesStart) && dt.isBefore(mesEnd)) {
      prihodMes += iznos;
      voznjiMes++;
    }
    if (dt.year == proslaGod) {
      prihodGod += iznos;
      voznjiGod++;
    }
  }

  // Troškovi iz cache
  double trosakNed = 0, trosakMes = 0, trosakGod = 0;
  final troskoviMes = V3FinansijeService.getTroskoviMesec(mesec: now.month, godina: now.year);
  final troskoviGod = V3FinansijeService.getTroskoviMesec(mesec: null, godina: proslaGod);

  final Map<String, double> poKat = {};
  for (final t in troskoviMes) {
    trosakMes += t.iznos;
    final kat = _katLabel(t.kategorija);
    poKat[kat] = (poKat[kat] ?? 0) + t.iznos;
    // Nedelja: troškovi nemaju tačan datum, zanemarujemo za nedelju
  }
  for (final t in troskoviGod) {
    trosakGod += t.iznos;
  }
  trosakNed = 0; // troškovi su mesečni, nemamo nedeljna

  // Potraživanja
  final dugovi = V3DugService.getDugovi();
  final potr = dugovi.fold(0.0, (s, d) => s + d.iznos);

  // Period string za nedelju
  final nedeljaPeriod = '${V3DanHelper.formatDanMesec(nedStart)} — '
      '${V3DanHelper.formatDanMesec(nedEnd.subtract(const Duration(days: 1)))}';

  return _V3IzvestajData(
    potrazivanjaIznos: potr,
    prihodNedelja: prihodNed,
    trosakNedelja: trosakNed,
    voznjiNedelja: voznjiNed,
    prihodMesec: prihodMes,
    trosakMesec: trosakMes,
    voznjiMesec: voznjiMes,
    prihodGodina: prihodGod,
    trosakGodina: trosakGod,
    voznjiGodina: voznjiGod,
    troskoviPoKategoriji: poKat,
    nedeljaPeriod: nedeljaPeriod,
    godinaBroj: proslaGod,
  );
}

String _katLabel(String? kat) {
  const map = {
    'gorivo': 'Gorivo',
    'odrzavanje': 'Održavanje',
    'plata': 'Plate',
    'kredit': 'Kredit',
    'amortizacija': 'Amortizacija',
    'registracija': 'Registracija',
    'yu_auto': 'YU auto',
    'majstori': 'Majstori',
    'porez': 'Porez',
    'alimentacija': 'Alimentacija',
    'racuni': 'Računi',
    'ostalo': 'Ostalo',
  };
  return map[kat] ?? (kat ?? 'Ostalo');
}

// ─── State ────────────────────────────────────────────────────────────────────

class _V3FinansijeScreenState extends State<V3FinansijeScreen> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: V3MasterRealtimeManager.instance.onChange,
      builder: (context, _) {
        final iz = _buildIzvestaj();
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('💰 Finansije', style: TextStyle(fontWeight: FontWeight.bold)),
            actions: [
              IconButton(
                icon: const Icon(Icons.calendar_month, color: Colors.white),
                tooltip: 'Izveštaj za period',
                onPressed: _selectCustomRange,
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: Colors.white),
                tooltip: 'Dodaj troškove',
                onPressed: () => _showTroskoviDialog(iz.troskoviPoKategoriji),
              ),
            ],
          ),
          body: V3ContainerUtils.backgroundContainer(
            gradient: Theme.of(context).backgroundGradient,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPotrazivanjaCard(iz.potrazivanjaIznos),
                    const SizedBox(height: 16),
                    _buildPeriodCard(
                      icon: '📅',
                      naslov: 'Ova nedelja',
                      podnaslov: iz.nedeljaPeriod,
                      prihod: iz.prihodNedelja,
                      troskovi: iz.trosakNedelja,
                      voznjiLabel: '${iz.voznjiNedelja} vožnji',
                      color: Colors.blue,
                    ),
                    const SizedBox(height: 16),
                    _buildPeriodCard(
                      icon: '🗓️',
                      naslov: 'Ovaj mesec',
                      podnaslov: _mesecNaziv(DateTime.now().month),
                      prihod: iz.prihodMesec,
                      troskovi: iz.trosakMesec,
                      voznjiLabel: '${iz.voznjiMesec} vožnji',
                      color: Colors.green,
                    ),
                    const SizedBox(height: 16),
                    _buildPeriodCard(
                      icon: '📊',
                      naslov: 'Prošla godina (${iz.godinaBroj})',
                      podnaslov: 'Ceo godišnji bilans',
                      prihod: iz.prihodGodina,
                      troskovi: iz.trosakGodina,
                      voznjiLabel: '${iz.voznjiGodina} vožnji',
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    _buildTroskoviDetailsList(iz.troskoviPoKategoriji),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: V3ButtonUtils.outlinedButton(
                        onPressed: () => _showTroskoviDialog(iz.troskoviPoKategoriji),
                        text: 'Dodaj troškove',
                        icon: Icons.edit,
                        borderColor: Colors.white24,
                        foregroundColor: Colors.white70,
                        borderRadius: BorderRadius.circular(12),
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

  Widget _buildPotrazivanjaCard(double iznos) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade800, Colors.orange.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.orange.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 5))
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(child: Text('💰', style: TextStyle(fontSize: 26))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Potraživanja (Dugovi)',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 2),
                Text('Neplaćene vožnje svih putnika',
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

  Widget _buildPeriodCard({
    required String icon,
    required String naslov,
    required String podnaslov,
    required double prihod,
    required double troskovi,
    required String voznjiLabel,
    required Color color,
  }) {
    final neto = prihod - troskovi;
    final isPositive = neto >= 0;
    final netoColor = isPositive ? const Color(0xFF4ADE80) : const Color(0xFFF87171);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E2235),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0.1)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(naslov,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text(podnaslov, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6))),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.5)),
                  ),
                  child: Text(voznjiLabel,
                      style: TextStyle(
                          color: color == Colors.grey ? Colors.white70 : color,
                          fontWeight: FontWeight.bold,
                          fontSize: 11)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              children: [
                _FinRow('Prihod', prihod, const Color(0xFF4ADE80), prefix: '+'),
                const SizedBox(height: 8),
                _FinRow('Troškovi', troskovi, const Color(0xFFF87171), prefix: '-'),
                const SizedBox(height: 10),
                Divider(color: Colors.white.withValues(alpha: 0.1)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('NETO',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white.withValues(alpha: 0.9))),
                    Row(
                      children: [
                        Icon(isPositive ? Icons.trending_up : Icons.trending_down, color: netoColor, size: 20),
                        const SizedBox(width: 6),
                        Text(_fmtIznos(neto.abs()),
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: netoColor)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTroskoviDetailsList(Map<String, double> poKat) {
    final ukupno = poKat.values.fold(0.0, (s, v) => s + v);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E2235),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.red.withValues(alpha: 0.3), Colors.red.withValues(alpha: 0.1)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('📋 Mesečni troškovi',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                Text(_fmtIznos(ukupno),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFFF87171))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: poKat.isEmpty
                ? const Text('Nema troškova za ovaj mesec', style: TextStyle(color: Colors.white38, fontSize: 13))
                : Column(
                    children: poKat.entries
                        .map((e) => _FinRow(e.key, e.value, e.value > 0 ? const Color(0xFFF87171) : Colors.white38,
                            fontSize: 14, labelColor: Colors.white70))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  void _showTroskoviDialog(Map<String, double> poKat) {
    V3NavigationUtils.showBottomSheet(
      context,
      child: _TroskoviBottomSheet(poKat: poKat),
    );
  }

  Future<void> _selectCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      saveText: 'PRIKAŽI',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(
            primary: Colors.blue.shade700,
            onPrimary: Colors.white,
            onSurface: Colors.black87,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      _showCustomReportDialog(picked.start, picked.end);
    }
  }

  void _showCustomReportDialog(DateTime from, DateTime to) {
    final ops = V3MasterRealtimeManager.instance.operativnaNedeljaCache.values;
    double prihod = 0;
    int voznje = 0;
    for (final row in ops) {
      if ((row['naplata_status'] as String?) != 'placeno') continue;
      final dt = DateTime.tryParse(row['updated_at'] as String? ?? '')?.toLocal();
      if (dt == null) continue;
      if (dt.isBefore(from) || dt.isAfter(to.add(const Duration(days: 1)))) continue;
      prihod += (row['iznos_naplacen'] as num?)?.toDouble() ?? 0.0;
      voznje++;
    }
    double troskovi = 0;
    final cache = V3MasterRealtimeManager.instance.troskoviCache;
    for (final row in cache.values) {
      if (row['aktivno'] == false) continue;
      final mesec = row['mesec'] as int? ?? 0;
      final godina = row['godina'] as int? ?? 0;
      final tDt = DateTime(godina, mesec);
      if (!tDt.isBefore(V3DanHelper.dateOnlyFrom(from.year, from.month, 1)) &&
          !tDt.isAfter(V3DanHelper.dateOnlyFrom(to.year, to.month, 1))) {
        troskovi += (row['iznos'] as num?)?.toDouble() ?? 0.0;
      }
    }
    final neto = prihod - troskovi;
    // Koristimo V3DanHelper umesto DateFormat

    V3DialogUtils.showCustomDialog<void>(
      context: context,
      borderRadius: 20,
      title: '📊 Izveštaj za period',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${V3DanHelper.formatDatumPuni(from)} — ${V3DanHelper.formatDatumPuni(to)}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal, color: Colors.grey)),
          const SizedBox(height: 16),
          _FinRow('Prihod', prihod, Colors.green),
          const SizedBox(height: 8),
          _FinRow('Troškovi', troskovi, Colors.red),
          const Divider(),
          _FinRow('NETO', neto, neto >= 0 ? Colors.green : Colors.red, isBold: true),
          const SizedBox(height: 16),
          Text('$voznje vožnji u ovom periodu',
              style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.black54)),
        ],
      ),
      actions: [
        V3ButtonUtils.textButton(onPressed: () => Navigator.pop(context), text: 'ZATVORI'),
      ],
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _fmtIznos(double iznos) => '${V3FormatUtils.formatBroj(iznos.round())} din';

String _mesecNaziv(int m) {
  const names = [
    '',
    'Januar',
    'Februar',
    'Mart',
    'April',
    'Maj',
    'Jun',
    'Jul',
    'Avgust',
    'Septembar',
    'Oktobar',
    'Novembar',
    'Decembar'
  ];
  return m >= 1 && m <= 12 ? names[m] : '';
}

// ─── _FinRow Widget ───────────────────────────────────────────────────────────

class _FinRow extends StatelessWidget {
  const _FinRow(
    this.label,
    this.iznos,
    this.color, {
    this.prefix,
    this.isBold = false,
    this.fontSize = 15,
    this.labelColor = Colors.white60,
  });

  final String label;
  final double iznos;
  final Color color;
  final String? prefix;
  final bool isBold;
  final double fontSize;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: fontSize, color: labelColor, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(
            '${prefix ?? ''}${_fmtIznos(iznos.abs())}',
            style: TextStyle(fontSize: isBold ? fontSize + 3 : fontSize, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

// ─── Troškovi Bottom Sheet ────────────────────────────────────────────────────

class _TroskoviBottomSheet extends StatefulWidget {
  const _TroskoviBottomSheet({required this.poKat});
  final Map<String, double> poKat;

  @override
  State<_TroskoviBottomSheet> createState() => _TroskoviBottomSheetState();
}

class _TroskoviBottomSheetState extends State<_TroskoviBottomSheet> {
  static const _stavke = [
    ('plata', '💰', 'Plate'),
    ('kredit', '🏦', 'Kredit'),
    ('gorivo', '⛽', 'Gorivo'),
    ('amortizacija', '🔧', 'Amortizacija'),
    ('registracija', '📋', 'Registracija'),
    ('yu_auto', '🚗', 'YU auto'),
    ('majstori', '🛠️', 'Majstori'),
    ('porez', '🏗️', 'Porez'),
    ('alimentacija', '👶', 'Alimentacija'),
    ('racuni', '🧾', 'Računi'),
    ('ostalo', '📦', 'Ostalo'),
  ];

  late final Map<String, TextEditingController> _ctrls = {
    for (final s in _stavke) s.$1: TextEditingController(),
  };
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _ctrls.values) c.dispose();
    super.dispose();
  }

  Future<void> _sacuvaj() async {
    V3StateUtils.safeSetState(this, () => _saving = true);
    final now = DateTime.now();
    try {
      final futures = <Future<void>>[];
      for (final s in _stavke) {
        final val = double.tryParse(_ctrls[s.$1]!.text.replaceAll(',', '.')) ?? 0;
        if (val > 0) {
          futures.add(V3FinansijeService.addTrosak(V3Trosak(
            id: '',
            naziv: s.$3,
            kategorija: s.$1,
            iznos: val,
            isplataIz: 'pazar',
            ponavljajMesecno: false,
            mesec: now.month,
            godina: now.year,
          )));
        }
      }
      await Future.wait(futures);
      if (mounted) {
        V3AppSnackBar.success(context, '✅ Troškovi dodati');
        Navigator.pop(context);
      }
    } catch (e) {
      V3ErrorUtils.asyncError(this, context, e);
    } finally {
      V3StateUtils.safeSetState(this, () => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 16),
                const Text('⚙️ Dodaj troškove', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('Unesi iznos koji želiš da DODAŠ na trenutni trošak.', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 20),
                for (final s in _stavke) ...[
                  Row(
                    children: [
                      Text(s.$2, style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.$3, style: const TextStyle(fontSize: 16)),
                            if ((widget.poKat[_katLabel(s.$1)] ?? 0) > 0)
                              Text(
                                'Trenutno: ${V3FormatUtils.formatBroj((widget.poKat[_katLabel(s.$1)] ?? 0).round())}',
                                style:
                                    TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: V3InputUtils.numberField(
                          controller: _ctrls[s.$1]!,
                          label: 'Dodaj...',
                          suffixText: 'din',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: V3ButtonUtils.successButton(
                    onPressed: _saving ? null : _sacuvaj,
                    text: 'Dodaj troškove',
                    icon: Icons.add_circle,
                    isLoading: _saving,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
