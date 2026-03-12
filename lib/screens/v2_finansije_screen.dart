import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/v2_finansije_service.dart';
import '../utils/v2_dan_utils.dart';

/// FINANSIJE SCREEN
/// Prikazuje prihode, troškove i neto zaradu
class V2FinansijeScreen extends StatefulWidget {
  const V2FinansijeScreen({super.key});

  @override
  State<V2FinansijeScreen> createState() => _FinansijeScreenState();
}

class _FinansijeScreenState extends State<V2FinansijeScreen> {
  static final _formatBroja = NumberFormat('#,###', 'sr');
  final Stream<V2FinansijskiIzvestaj> _stream = V2FinansijeService.streamIzvestaj();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<V2FinansijskiIzvestaj>(
      stream: _stream,
      builder: (context, snapshot) {
        final izvestaj = snapshot.data;
        final isLoading = snapshot.connectionState == ConnectionState.waiting && izvestaj == null;

        return Scaffold(
          appBar: AppBar(
            title: const Text('💰 Finansije'),
            centerTitle: true,
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.calendar_month),
                onPressed: _selectCustomRange,
                tooltip: 'Izveštaj za period',
              ),
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => _showTroskoviDialog(izvestaj?.troskoviPoTipu ?? {}),
                tooltip: 'Podesi troškove',
              ),
            ],
          ),
          body: Container(
            color: const Color(0xFF0F1221),
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : izvestaj == null
                    ? const Center(child: Text('Greška pri učitavanju', style: TextStyle(color: Colors.white70)))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildPotrazivanjaCard(izvestaj.potrazivanja),
                            const SizedBox(height: 16),
                            _buildPeriodCard(
                              icon: '📅',
                              naslov: 'Ova nedelja',
                              podnaslov: izvestaj.nedeljaPeriod,
                              prihod: izvestaj.prihodNedelja,
                              troskovi: izvestaj.troskoviNedelja,
                              neto: izvestaj.netoNedelja,
                              voznjiLabel: '${izvestaj.voznjiNedelja} vožnji',
                              color: Colors.blue,
                            ),
                            const SizedBox(height: 16),
                            _buildPeriodCard(
                              icon: '🗓️',
                              naslov: 'Ovaj mesec',
                              podnaslov: V2DanUtils.mesecNaziv(izvestaj.startNedelja.month),
                              prihod: izvestaj.prihodMesec,
                              troskovi: izvestaj.troskoviMesec,
                              neto: izvestaj.netoMesec,
                              voznjiLabel: '${izvestaj.voznjiMesec} vožnji',
                              color: Colors.green,
                            ),
                            const SizedBox(height: 16),
                            _buildPeriodCard(
                              icon: '📊',
                              naslov: 'Prošla godina (${izvestaj.proslaGodina})',
                              podnaslov: 'Ceo godišnji bilans',
                              prihod: izvestaj.prihodProslaGodina,
                              troskovi: izvestaj.troskoviProslaGodina,
                              neto: izvestaj.netoProslaGodina,
                              voznjiLabel: '${izvestaj.voznjiProslaGodina} vožnji',
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            _buildTroskoviDetailsList(izvestaj.troskoviPoTipu),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _showTroskoviDialog(izvestaj.troskoviPoTipu),
                                icon: const Icon(Icons.edit, color: Colors.white70),
                                label: const Text('Podesi troškove', style: TextStyle(color: Colors.white70)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.white24),
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
          ),
        );
      },
    );
  }

  Widget _buildPeriodCard({
    required String icon,
    required String naslov,
    required String podnaslov,
    required double prihod,
    required double troskovi,
    required double neto,
    required String voznjiLabel,
    required Color color,
  }) {
    final isPositive = neto >= 0;
    final netoColor = isPositive ? const Color(0xFF4ADE80) : const Color(0xFFF87171);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E2235),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header sa gradijentom
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
                      Text(
                        naslov,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        podnaslov,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
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
                  child: Text(
                    voznjiLabel,
                    style: TextStyle(
                      color: color == Colors.grey ? Colors.white70 : color,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Body
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
                    Text(
                      'NETO',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    Row(
                      children: [
                        Icon(
                          isPositive ? Icons.trending_up : Icons.trending_down,
                          color: netoColor,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatIznos(neto.abs()),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: netoColor,
                          ),
                        ),
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

  Widget _buildTroskoviDetailsList(Map<String, double> troskoviPoTipu) {
    final ukupnoMesecniTroskovi = troskoviPoTipu.values.fold(0.0, (sum, item) => sum + item);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E2235),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
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
                const Text(
                  '📋 Mesečni troškovi',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  _formatIznos(ukupnoMesecniTroskovi),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFF87171),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Column(
              children: [
                ...troskoviPoTipu.entries.map(
                  (e) => _FinRow(e.key, e.value, e.value > 0 ? const Color(0xFFF87171) : Colors.white38,
                      fontSize: 14, labelColor: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showTroskoviDialog(Map<String, double> poTipu) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _TroskoviBottomSheet(
        poTipu: poTipu,
        formatBroja: _formatBroja,
        onSave: _saveTroskovi,
      ),
    );
  }

  Future<void> _saveTroskovi(Map<String, double> unosi) async {
    await Future.wait([
      _finansijeAddTrosakIfPositive('Plate', 'plata', unosi['plata'] ?? 0),
      _finansijeAddTrosakIfPositive('Kredit', 'kredit', unosi['kredit'] ?? 0),
      _finansijeAddTrosakIfPositive('Gorivo', 'gorivo', unosi['gorivo'] ?? 0),
      _finansijeAddTrosakIfPositive('Amortizacija', 'amortizacija', unosi['amortizacija'] ?? 0),
      _finansijeAddTrosakIfPositive('Registracija', 'registracija', unosi['registracija'] ?? 0),
      _finansijeAddTrosakIfPositive('YU auto', 'yu_auto', unosi['yu_auto'] ?? 0),
      _finansijeAddTrosakIfPositive('Majstori', 'majstori', unosi['majstori'] ?? 0),
      _finansijeAddTrosakIfPositive('Porez', 'porez', unosi['porez'] ?? 0),
      _finansijeAddTrosakIfPositive('Alimentacija', 'alimentacija', unosi['alimentacija'] ?? 0),
      _finansijeAddTrosakIfPositive('Računi', 'racuni', unosi['racuni'] ?? 0),
      _finansijeAddTrosakIfPositive('Ostalo', 'ostalo', unosi['ostalo'] ?? 0),
    ]);
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
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
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
            child: const Center(
              child: Text('💰', style: TextStyle(fontSize: 26)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Potraživanja (Dugovi)',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Neplaćene vožnje svih putnika',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          Text(
            _formatIznos(iznos),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      saveText: 'PRIKAŽI',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.blue.shade700,
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      _showCustomReportDialog(picked.start, picked.end);
    }
  }

  void _showCustomReportDialog(DateTime from, DateTime to) {
    final dateFormat = DateFormat('dd.MM.yyyy');
    final future = V2FinansijeService.getIzvestajZaPeriod(from, to);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            const Text('📊 Izveštaj za period'),
            Text(
              '${dateFormat.format(from)} - ${dateFormat.format(to)}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal, color: Colors.grey),
            ),
          ],
        ),
        content: FutureBuilder<Map<String, dynamic>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.hasError || snapshot.data == null) {
              return const Text('Greška pri učitavanju podataka');
            }

            final data = snapshot.data!;
            final double prihod = (data['prihod'] as num).toDouble();
            final double troskovi = (data['troskovi'] as num).toDouble();
            final double neto = (data['neto'] as num).toDouble();
            final int voznje = data['voznje'] ?? 0;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FinRow('Prihod', prihod, Colors.green),
                const SizedBox(height: 8),
                _FinRow('Troškovi', troskovi, Colors.red),
                const Divider(),
                _FinRow('NETO', neto, neto >= 0 ? Colors.green : Colors.red, isBold: true),
                const SizedBox(height: 16),
                Text('$voznje vožnji u ovom periodu', style: const TextStyle(fontStyle: FontStyle.italic)),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ZATVORI'),
          ),
        ],
      ),
    );
  }
}

class _TroskoviBottomSheet extends StatefulWidget {
  final Map<String, double> poTipu;
  final NumberFormat formatBroja;
  final Future<void> Function(Map<String, double>) onSave;

  const _TroskoviBottomSheet({
    required this.poTipu,
    required this.formatBroja,
    required this.onSave,
  });

  @override
  State<_TroskoviBottomSheet> createState() => _TroskoviBottomSheetState();
}

class _TroskoviBottomSheetState extends State<_TroskoviBottomSheet> {
  // Ključevi moraju biti isti kao u V2FinansijeService (tip kolona)
  static const _kljucevi = [
    'plata',
    'kredit',
    'gorivo',
    'amortizacija',
    'registracija',
    'yu_auto',
    'majstori',
    'porez',
    'alimentacija',
    'racuni',
    'ostalo',
  ];

  late final Map<String, TextEditingController> _ctrls = {
    for (final k in _kljucevi) k: TextEditingController(),
  };

  @override
  void dispose() {
    for (final c in _ctrls.values) c.dispose();
    super.dispose();
  }

  Widget _buildTrosakInputRow(String emoji, String label, TextEditingController controller, {double? currentTotal}) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 16)),
              if (currentTotal != null && currentTotal > 0)
                Text('Trenutno: ${widget.formatBroja.format(currentTotal)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Expanded(
          flex: 3,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              hintText: 'Dodaj...',
              suffixText: 'din',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pt = widget.poTipu;
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
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '⚙️ Dodaj troškove',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Unesi iznos koji želiš da DODAŠ na trenutni trošak.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                // Redovi za unos — emoji i labele po kljucu
                ...(() {
                  const meta = {
                    'plata': ('💰', 'Plate'),
                    'kredit': ('🏦', 'Kredit'),
                    'gorivo': ('⛽', 'Gorivo'),
                    'amortizacija': ('🔧', 'Amortizacija'),
                    'registracija': ('📋', 'Registracija'),
                    'yu_auto': ('🚗', 'YU auto'),
                    'majstori': ('🛠️', 'Majstori'),
                    'porez': ('🏗️', 'Porez'),
                    'alimentacija': ('👶', 'Alimentacija'),
                    'racuni': ('🧾', 'Računi'),
                    'ostalo': ('📋', 'Ostalo'),
                  };
                  final rows = <Widget>[];
                  for (final k in _TroskoviBottomSheetState._kljucevi) {
                    final (emoji, label) = meta[k]!;
                    rows.add(_buildTrosakInputRow(emoji, label, _ctrls[k]!, currentTotal: pt[k]));
                    rows.add(const SizedBox(height: 12));
                  }
                  return rows;
                })(),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final unosi = <String, double>{
                        for (final k in _TroskoviBottomSheetState._kljucevi)
                          k: double.tryParse(_ctrls[k]!.text.replaceAll(',', '.')) ?? 0,
                      };
                      await widget.onSave(unosi);
                      if (!context.mounted) return;
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.add_circle),
                    label: const Text('Dodaj troškove'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
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

// ─── top-level helperi (bez state pristupa) ───────────────────────────────────

Future<void> _finansijeAddTrosakIfPositive(String naziv, String tip, double iznos) async {
  if (iznos != 0) {
    await V2FinansijeService.addTrosak(naziv, tip, iznos);
  }
}

String _formatIznos(double iznos) {
  return '${_FinansijeScreenState._formatBroja.format(iznos.round())} din';
}

// Unifikovani row widget — zamjenjuje _buildRow, _buildPopupRow, _buildTrosakRow
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
            '${prefix ?? ''}${_formatIznos(iznos.abs())}',
            style: TextStyle(
                fontSize: isBold ? fontSize + 3 : fontSize,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w700,
                color: color),
          ),
        ],
      ),
    );
  }
}
