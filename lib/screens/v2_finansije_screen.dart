import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/v2_finansije_service.dart';

/// FINANSIJE SCREEN
/// Prikazuje prihode, troškove i neto zaradu
class V2FinansijeScreen extends StatefulWidget {
  const V2FinansijeScreen({super.key});

  @override
  State<V2FinansijeScreen> createState() => _FinansijeScreenState();
}

class _FinansijeScreenState extends State<V2FinansijeScreen> {
  final _formatBroja = NumberFormat('#,###', 'sr');
  final _refreshKey = GlobalKey<RefreshIndicatorState>();

  late Stream<V2FinansijskiIzvestaj> _streamIzvestaj;

  @override
  void initState() {
    super.initState();
    _prijaviStream();
  }

  void _prijaviStream() {
    _streamIzvestaj = V2FinansijeService.streamIzvestaj();
  }

  String _formatIznos(double iznos) {
    return '${_formatBroja.format(iznos.round())} din';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<V2FinansijskiIzvestaj>(
      stream: _streamIzvestaj,
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
                    : RefreshIndicator(
                        key: _refreshKey,
                        onRefresh: () async {
                          setState(_prijaviStream);
                        },
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
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
                                podnaslov: _getMesecNaziv(izvestaj.startNedelja.month),
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
                _buildRow('Prihod', prihod, const Color(0xFF4ADE80), isPlus: true),
                const SizedBox(height: 8),
                _buildRow('Troškovi', troskovi, const Color(0xFFF87171), isMinus: true),
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

  Widget _buildRow(String label, double iznos, Color color, {bool isMinus = false, bool isPlus = false}) {
    String prefix = '';
    if (isPlus) prefix = '+';
    if (isMinus) prefix = '-';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.white60,
          ),
        ),
        Text(
          '$prefix${_formatIznos(iznos)}',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
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
                  (entry) => _buildTrosakRow(entry.key, entry.value),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrosakRow(String label, double iznos) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, color: Colors.white70),
          ),
          Text(
            _formatIznos(iznos),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: iznos > 0 ? const Color(0xFFF87171) : Colors.white38,
            ),
          ),
        ],
      ),
    );
  }

  static String _getMesecNaziv(int mesec) {
    assert(mesec >= 1 && mesec <= 12, 'Mesec mora biti izmedju 1 i 12, dobijeno: $mesec');
    const meseci = [
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
    return meseci[mesec];
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

  Future<void> _saveTroskovi({
    required double plate,
    required double kredit,
    required double gorivo,
    required double amortizacija,
    required double registracija,
    required double yuAuto,
    required double majstori,
    required double ostalo,
    required double porez,
    required double alimentacija,
    required double racuni,
  }) async {
    // Paralelni INSERT-i za sve kategorije sa iznosom != 0
    await Future.wait([
      _addTrosakIfPositive('Plate', 'plata', plate),
      _addTrosakIfPositive('Kredit', 'kredit', kredit),
      _addTrosakIfPositive('Gorivo', 'gorivo', gorivo),
      _addTrosakIfPositive('Amortizacija', 'amortizacija', amortizacija),
      _addTrosakIfPositive('Registracija', 'registracija', registracija),
      _addTrosakIfPositive('YU auto', 'yu_auto', yuAuto),
      _addTrosakIfPositive('Majstori', 'majstori', majstori),
      _addTrosakIfPositive('Porez', 'porez', porez),
      _addTrosakIfPositive('Alimentacija', 'alimentacija', alimentacija),
      _addTrosakIfPositive('Računi', 'racuni', racuni),
      _addTrosakIfPositive('Ostalo', 'ostalo', ostalo),
    ]);
  }

  static Future<void> _addTrosakIfPositive(String naziv, String tip, double iznos) async {
    if (iznos != 0) {
      await V2FinansijeService.addTrosak(naziv, tip, iznos);
    }
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
                _buildPopupRow('Prihod', prihod, Colors.green),
                const SizedBox(height: 8),
                _buildPopupRow('Troškovi', troskovi, Colors.red),
                const Divider(),
                _buildPopupRow('NETO', neto, neto >= 0 ? Colors.green : Colors.red, isBold: true),
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

  Widget _buildPopupRow(String label, double iznos, Color color, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        Text(
          _formatIznos(iznos),
          style: TextStyle(
            color: color,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            fontSize: isBold ? 18 : 16,
          ),
        ),
      ],
    );
  }
}

class _TroskoviBottomSheet extends StatefulWidget {
  final Map<String, double> poTipu;
  final NumberFormat formatBroja;
  final Future<void> Function({
    required double plate,
    required double kredit,
    required double gorivo,
    required double amortizacija,
    required double registracija,
    required double yuAuto,
    required double majstori,
    required double ostalo,
    required double porez,
    required double alimentacija,
    required double racuni,
  }) onSave;

  const _TroskoviBottomSheet({
    required this.poTipu,
    required this.formatBroja,
    required this.onSave,
  });

  @override
  State<_TroskoviBottomSheet> createState() => _TroskoviBottomSheetState();
}

class _TroskoviBottomSheetState extends State<_TroskoviBottomSheet> {
  final _plateController = TextEditingController();
  final _kreditController = TextEditingController();
  final _gorivoController = TextEditingController();
  final _amortizacijaController = TextEditingController();
  final _registracijaController = TextEditingController();
  final _yuAutoController = TextEditingController();
  final _majstoriController = TextEditingController();
  final _ostaloController = TextEditingController();
  final _porezController = TextEditingController();
  final _alimentacijaController = TextEditingController();
  final _racuniController = TextEditingController();

  @override
  void dispose() {
    _plateController.dispose();
    _kreditController.dispose();
    _gorivoController.dispose();
    _amortizacijaController.dispose();
    _registracijaController.dispose();
    _yuAutoController.dispose();
    _majstoriController.dispose();
    _ostaloController.dispose();
    _porezController.dispose();
    _alimentacijaController.dispose();
    _racuniController.dispose();
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
                _buildTrosakInputRow('💰', 'Plate', _plateController, currentTotal: pt['plata']),
                const SizedBox(height: 12),
                _buildTrosakInputRow('🏦', 'Kredit', _kreditController, currentTotal: pt['kredit']),
                const SizedBox(height: 12),
                _buildTrosakInputRow('⛽', 'Gorivo', _gorivoController, currentTotal: pt['gorivo']),
                const SizedBox(height: 12),
                _buildTrosakInputRow('🔧', 'Amortizacija', _amortizacijaController, currentTotal: pt['amortizacija']),
                const SizedBox(height: 12),
                _buildTrosakInputRow('📋', 'Registracija', _registracijaController, currentTotal: pt['registracija']),
                const SizedBox(height: 12),
                _buildTrosakInputRow('🚗', 'YU auto', _yuAutoController, currentTotal: pt['yu_auto']),
                const SizedBox(height: 12),
                _buildTrosakInputRow('🛠️', 'Majstori', _majstoriController, currentTotal: pt['majstori']),
                const SizedBox(height: 12),
                _buildTrosakInputRow('🏛️', 'Porez', _porezController, currentTotal: pt['porez']),
                const SizedBox(height: 12),
                _buildTrosakInputRow('👶', 'Alimentacija', _alimentacijaController, currentTotal: pt['alimentacija']),
                const SizedBox(height: 12),
                _buildTrosakInputRow('🧾', 'Računi', _racuniController, currentTotal: pt['racuni']),
                const SizedBox(height: 12),
                _buildTrosakInputRow('📋', 'Ostalo', _ostaloController, currentTotal: pt['ostalo']),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await widget.onSave(
                        plate: double.tryParse(_plateController.text.replaceAll(',', '.')) ?? 0,
                        kredit: double.tryParse(_kreditController.text.replaceAll(',', '.')) ?? 0,
                        gorivo: double.tryParse(_gorivoController.text.replaceAll(',', '.')) ?? 0,
                        amortizacija: double.tryParse(_amortizacijaController.text.replaceAll(',', '.')) ?? 0,
                        registracija: double.tryParse(_registracijaController.text.replaceAll(',', '.')) ?? 0,
                        yuAuto: double.tryParse(_yuAutoController.text.replaceAll(',', '.')) ?? 0,
                        majstori: double.tryParse(_majstoriController.text.replaceAll(',', '.')) ?? 0,
                        ostalo: double.tryParse(_ostaloController.text.replaceAll(',', '.')) ?? 0,
                        porez: double.tryParse(_porezController.text.replaceAll(',', '.')) ?? 0,
                        alimentacija: double.tryParse(_alimentacijaController.text.replaceAll(',', '.')) ?? 0,
                        racuni: double.tryParse(_racuniController.text.replaceAll(',', '.')) ?? 0,
                      );
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
