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
                onPressed: () => _selectCustomRange(),
                tooltip: 'Izveštaj za period',
              ),
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => _showTroskoviDialog(izvestaj?.troskoviPoTipu ?? {}),
                tooltip: 'Podesi troškove',
              ),
            ],
          ),
          body: isLoading
              ? const Center(child: CircularProgressIndicator())
              : izvestaj == null
                  ? const Center(child: Text('Greška pri učitavanju'))
                  : RefreshIndicator(
                      key: _refreshKey,
                      onRefresh: () async {
                        setState(() {
                          _streamIzvestaj = V2FinansijeService.streamIzvestaj();
                        });
                      },
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // POTRAŽIVANJA (Dugovi putnika)
                            _buildPotrazivanjaCard(izvestaj.potrazivanja),

                            const SizedBox(height: 16),

                            // NEDELJA
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

                            // MESEC
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

                            // PROŠLA GODINA
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

                            // DETALJI TROŠKOVA
                            _buildTroskoviDetailsList(izvestaj.troskoviPoTipu),

                            const SizedBox(height: 16),

                            // Dugme za podešavanje
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _showTroskoviDialog(izvestaj.troskoviPoTipu),
                                icon: const Icon(Icons.edit),
                                label: const Text('Podesi troškove'),
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

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.3), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        naslov,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        podnaslov,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    voznjiLabel,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // Prihod
            _buildRow('Prihod', prihod, Colors.green.shade700, isPlus: true),
            const SizedBox(height: 8),

            // Troškovi
            _buildRow('Troškovi', troskovi, Colors.red.shade700, isMinus: true),

            const SizedBox(height: 8),
            Divider(color: Colors.grey.shade300),
            const SizedBox(height: 8),

            // NETO
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'NETO',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    Icon(
                      isPositive ? Icons.trending_up : Icons.trending_down,
                      color: isPositive ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatIznos(neto.abs()),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isPositive ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
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
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade700,
          ),
        ),
        Text(
          '$prefix${_formatIznos(iznos)}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildTroskoviDetailsList(Map<String, double> troskoviPoTipu) {
    final ukupnoMesecniTroskovi = troskoviPoTipu.values.fold(0.0, (sum, item) => sum + item);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '📋 Mesečni troškovi',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _formatIznos(ukupnoMesecniTroskovi),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Lista po tipu
            ...troskoviPoTipu.entries.map(
              (entry) => _buildTrosakRow(entry.key, entry.value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrosakRow(String label, double iznos) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            _formatIznos(iznos),
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: iznos > 0 ? Colors.red.shade600 : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  static String _getMesecNaziv(int mesec) {
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

  static Widget _buildTrosakInputRow(String emoji, String label, TextEditingController controller,
      {double? currentTotal, required NumberFormat formatBroja}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
                    Text('Trenutno: ${formatBroja.format(currentTotal)}',
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
        ),
      ],
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
      // Dozvoljava i negativne za ispravke
      await V2FinansijeService.addTrosak(naziv, tip, iznos);
    }
  }

  Widget _buildPotrazivanjaCard(double iznos) {
    return Card(
      elevation: 4,
      color: Colors.orange.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.orange.shade200, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Text('💰', style: TextStyle(fontSize: 32)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Potraživanja (Dugovi)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  Text(
                    'Neplaćene vožnje svih putnika',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            Text(
              _formatIznos(iznos),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.orange.shade900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 31)),
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
          future: V2FinansijeService.getIzvestajZaPeriod(from, to),
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

// ─────────────────────────────────────────────────────────────────────────────
// Zasebni StatefulWidget za bottom sheet unosa troškova → proper dispose()
// ─────────────────────────────────────────────────────────────────────────────

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
  late final TextEditingController _plateController;
  late final TextEditingController _kreditController;
  late final TextEditingController _gorivoController;
  late final TextEditingController _amortizacijaController;
  late final TextEditingController _registracijaController;
  late final TextEditingController _yuAutoController;
  late final TextEditingController _majstoriController;
  late final TextEditingController _ostaloController;
  late final TextEditingController _porezController;
  late final TextEditingController _alimentacijaController;
  late final TextEditingController _racuniController;

  @override
  void initState() {
    super.initState();
    _plateController = TextEditingController();
    _kreditController = TextEditingController();
    _gorivoController = TextEditingController();
    _amortizacijaController = TextEditingController();
    _registracijaController = TextEditingController();
    _yuAutoController = TextEditingController();
    _majstoriController = TextEditingController();
    _ostaloController = TextEditingController();
    _porezController = TextEditingController();
    _alimentacijaController = TextEditingController();
    _racuniController = TextEditingController();
  }

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
                // Handle
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

                _FinansijeScreenState._buildTrosakInputRow('💰', 'Plate', _plateController,
                    currentTotal: pt['plata'], formatBroja: widget.formatBroja),
                const SizedBox(height: 12),
                _FinansijeScreenState._buildTrosakInputRow('🏦', 'Kredit', _kreditController,
                    currentTotal: pt['kredit'], formatBroja: widget.formatBroja),
                const SizedBox(height: 12),
                _FinansijeScreenState._buildTrosakInputRow('⛽', 'Gorivo', _gorivoController,
                    currentTotal: pt['gorivo'], formatBroja: widget.formatBroja),
                const SizedBox(height: 12),
                _FinansijeScreenState._buildTrosakInputRow('🔧', 'Amortizacija', _amortizacijaController,
                    currentTotal: pt['amortizacija'], formatBroja: widget.formatBroja),
                const SizedBox(height: 12),
                _FinansijeScreenState._buildTrosakInputRow('📋', 'Registracija', _registracijaController,
                    currentTotal: pt['registracija'], formatBroja: widget.formatBroja),
                const SizedBox(height: 12),
                _FinansijeScreenState._buildTrosakInputRow('🚗', 'YU auto', _yuAutoController,
                    currentTotal: pt['yu_auto'], formatBroja: widget.formatBroja),
                const SizedBox(height: 12),
                _FinansijeScreenState._buildTrosakInputRow('🛠️', 'Majstori', _majstoriController,
                    currentTotal: pt['majstori'], formatBroja: widget.formatBroja),
                const SizedBox(height: 12),
                _FinansijeScreenState._buildTrosakInputRow('🏛️', 'Porez', _porezController,
                    currentTotal: pt['porez'], formatBroja: widget.formatBroja),
                const SizedBox(height: 12),
                _FinansijeScreenState._buildTrosakInputRow('👶', 'Alimentacija', _alimentacijaController,
                    currentTotal: pt['alimentacija'], formatBroja: widget.formatBroja),
                const SizedBox(height: 12),
                _FinansijeScreenState._buildTrosakInputRow('🧾', 'Računi', _racuniController,
                    currentTotal: pt['racuni'], formatBroja: widget.formatBroja),
                const SizedBox(height: 12),
                _FinansijeScreenState._buildTrosakInputRow('📋', 'Ostalo', _ostaloController,
                    currentTotal: pt['ostalo'], formatBroja: widget.formatBroja),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await widget.onSave(
                        plate: double.tryParse(_plateController.text) ?? 0,
                        kredit: double.tryParse(_kreditController.text) ?? 0,
                        gorivo: double.tryParse(_gorivoController.text) ?? 0,
                        amortizacija: double.tryParse(_amortizacijaController.text) ?? 0,
                        registracija: double.tryParse(_registracijaController.text) ?? 0,
                        yuAuto: double.tryParse(_yuAutoController.text) ?? 0,
                        majstori: double.tryParse(_majstoriController.text) ?? 0,
                        ostalo: double.tryParse(_ostaloController.text) ?? 0,
                        porez: double.tryParse(_porezController.text) ?? 0,
                        alimentacija: double.tryParse(_alimentacijaController.text) ?? 0,
                        racuni: double.tryParse(_racuniController.text) ?? 0,
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
