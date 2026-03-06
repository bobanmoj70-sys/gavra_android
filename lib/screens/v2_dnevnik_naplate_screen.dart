import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../globals.dart';
import '../services/v2_vozac_service.dart';
import '../theme.dart';
import '../utils/v2_app_snack_bar.dart';

/// DNEVNIK NAPLATE
/// Admin bira vozača i datum — vidi sve naplate tog vozača za taj dan
class V2DnevnikNaplateScreen extends StatefulWidget {
  const V2DnevnikNaplateScreen({super.key});

  @override
  State<V2DnevnikNaplateScreen> createState() => _V2DnevnikNaplateScreenState();
}

class _V2DnevnikNaplateScreenState extends State<V2DnevnikNaplateScreen> {
  String? _selectedVozacIme;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  List<Map<String, dynamic>> _naplate = [];
  double _ukupnoIznos = 0;
  final _predaoController = TextEditingController();

  @override
  void dispose() {
    _predaoController.dispose();
    super.dispose();
  }

  List<String> get _vozaciImena {
    final vozaci = V2VozacService.getAllVozaci();
    return vozaci.map((v) => v.ime).toList();
  }

  Future<void> _ucitajNaplate() async {
    if (_selectedVozacIme == null) return;

    setState(() => _isLoading = true);

    try {
      final dateStr =
          '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

      final result = await _fetchDirectQuery(dateStr);

      setState(() {
        _naplate = result;
        _ukupnoIznos = result.fold(0.0, (sum, r) => sum + ((r['iznos'] as num?)?.toDouble() ?? 0));
        _isLoading = false;
        _predaoController.clear();
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) V2AppSnackBar.error(context, 'Greška: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _fetchDirectQuery(String dateStr) async {
    // Jedan upit — bez JOIN (v2_polasci nema FK prema putnik tabelama)
    final rows = await supabase
        .from('v2_polasci')
        .select('putnik_id, putnik_tabela, grad, dodeljeno_vreme, placen_iznos, placen_at, updated_at')
        .eq('placen', true)
        .eq('placen_vozac_ime', _selectedVozacIme!)
        .gte('updated_at', '${dateStr}T00:00:00')
        .lte('updated_at', '${dateStr}T23:59:59') as List;

    if (rows.isEmpty) return [];

    // Grupiši putnik_id-ove po tabeli za batch lookup
    final dnevniIds = <String>[];
    final radniciIds = <String>[];
    final uceniciIds = <String>[];

    for (final r in rows) {
      final id = r['putnik_id']?.toString() ?? '';
      if (id.isEmpty) continue;
      switch (r['putnik_tabela'] as String?) {
        case 'v2_dnevni':
          dnevniIds.add(id);
        case 'v2_radnici':
          radniciIds.add(id);
        case 'v2_ucenici':
          uceniciIds.add(id);
      }
    }

    // Batch fetch imena iz svake tabele
    final Map<String, String> imeMap = {};

    Future<void> fetchIme(String tabela, List<String> ids) async {
      if (ids.isEmpty) return;
      final res = await supabase.from(tabela).select('id, ime').inFilter('id', ids) as List;
      for (final r in res) {
        imeMap[r['id'].toString()] = r['ime']?.toString() ?? '?';
      }
    }

    await Future.wait([
      fetchIme('v2_dnevni', dnevniIds),
      fetchIme('v2_radnici', radniciIds),
      fetchIme('v2_ucenici', uceniciIds),
    ]);

    final sve = <Map<String, dynamic>>[];
    for (final r in rows) {
      final id = r['putnik_id']?.toString() ?? '';
      final ime = imeMap[id] ?? '?';
      sve.add(_buildRow(r as Map<String, dynamic>, ime));
    }

    // Sortiraj po vremenu naplate
    sve.sort((a, b) => (a['sort_ts'] as String).compareTo(b['sort_ts'] as String));

    return sve;
  }

  Map<String, dynamic> _buildRow(Map<String, dynamic> r, String ime) {
    final placenAt = r['placen_at'] as String?;
    final updatedAt = r['updated_at'] as String?;
    final tsStr = placenAt ?? updatedAt ?? '';
    String vremeNaplate = '-';
    if (tsStr.isNotEmpty) {
      final dt = DateTime.tryParse(tsStr)?.toLocal();
      if (dt != null) {
        vremeNaplate = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    }
    return {
      'ime': ime,
      'grad': r['grad'] as String? ?? '-',
      'polazak': r['dodeljeno_vreme'] as String? ?? '-',
      'iznos': (r['placen_iznos'] as num?)?.toDouble() ?? 0.0,
      'vreme_naplate': vremeNaplate,
      'sort_ts': tsStr,
    };
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: ThemeData.dark(),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _naplate = [];
        _ukupnoIznos = 0;
      });
    }
  }

  String _formatDatum() {
    return '${_selectedDate.day.toString().padLeft(2, '0')}.${_selectedDate.month.toString().padLeft(2, '0')}.${_selectedDate.year}';
  }

  void _share() {
    if (_naplate.isEmpty) return;

    final buffer = StringBuffer();
    buffer.writeln('DNEVNIK NAPLATE — $_selectedVozacIme');
    buffer.writeln('Datum: ${_formatDatum()}');
    buffer.writeln('─────────────────────────');
    for (int i = 0; i < _naplate.length; i++) {
      final n = _naplate[i];
      final iznos = (n['iznos'] as double).toStringAsFixed(0);
      buffer.writeln('${i + 1}. ${n['ime']} (${n['grad']} ${n['polazak']}) — $iznos din — ${n['vreme_naplate']}');
    }
    buffer.writeln('─────────────────────────');
    buffer.writeln('UKUPNO: ${_naplate.length} uplata — ${_ukupnoIznos.toStringAsFixed(0)} din');
    final predaoVal = double.tryParse(_predaoController.text.replaceAll(',', '.'));
    if (predaoVal != null) {
      final razlika = predaoVal - _ukupnoIznos;
      buffer.writeln('Predao: ${predaoVal.toStringAsFixed(0)} din');
      buffer.writeln(razlika >= 0
          ? 'Višak: ${razlika.toStringAsFixed(0)} din'
          : 'Manjak: ${razlika.abs().toStringAsFixed(0)} din');
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    V2AppSnackBar.success(context, '📋 Kopirano u clipboard — možeš nalepiti u WhatsApp/SMS');
  }

  @override
  Widget build(BuildContext context) {
    final vozaci = _vozaciImena;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Dnevnik naplate', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_naplate.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy, color: Colors.white),
              tooltip: 'Kopiraj izveštaj',
              onPressed: _share,
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              // Filter bar
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // Vozač dropdown
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedVozacIme,
                            hint: const Text('Vozač', style: TextStyle(color: Colors.white54)),
                            dropdownColor: const Color(0xFF1A1A2E),
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
                            isExpanded: true,
                            items: vozaci.map((ime) => DropdownMenuItem(value: ime, child: Text(ime))).toList(),
                            onChanged: (v) {
                              setState(() {
                                _selectedVozacIme = v;
                                _naplate = [];
                                _ukupnoIznos = 0;
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Datum picker
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, color: Colors.white70, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              _formatDatum(),
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Učitaj dugme
                    ElevatedButton(
                      onPressed: _selectedVozacIme == null ? null : _ucitajNaplate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.search, size: 20),
                    ),
                  ],
                ),
              ),

              // Sadržaj
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : _naplate.isEmpty
                        ? Center(
                            child: Text(
                              _selectedVozacIme == null
                                  ? 'Izaberi vozača i datum'
                                  : 'Nema naplata za ${_formatDatum()}',
                              style: const TextStyle(color: Colors.white54, fontSize: 16),
                            ),
                          )
                        : Column(
                            children: [
                              // Lista naplata
                              Expanded(
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  itemCount: _naplate.length,
                                  itemBuilder: (context, index) {
                                    final n = _naplate[index];
                                    final iznos = (n['iznos'] as double).toStringAsFixed(0);
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.07),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.white12),
                                      ),
                                      child: Row(
                                        children: [
                                          // Redni broj
                                          SizedBox(
                                            width: 28,
                                            child: Text(
                                              '${index + 1}.',
                                              style: const TextStyle(color: Colors.white38, fontSize: 13),
                                            ),
                                          ),
                                          // Ime
                                          Expanded(
                                            child: Text(
                                              n['ime'] as String,
                                              style: const TextStyle(
                                                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                          // Grad + polazak
                                          Text(
                                            '${n['grad']} ${n['polazak']}',
                                            style: const TextStyle(color: Colors.white54, fontSize: 13),
                                          ),
                                          const SizedBox(width: 10),
                                          // Iznos
                                          Text(
                                            '$iznos din',
                                            style: const TextStyle(
                                              color: Colors.greenAccent,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          // Vreme
                                          Text(
                                            n['vreme_naplate'] as String,
                                            style: const TextStyle(color: Colors.white38, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),

                              // Ukupno + Predao footer
                              StatefulBuilder(
                                builder: (context, setFooter) {
                                  final predaoVal = double.tryParse(_predaoController.text.replaceAll(',', '.'));
                                  final razlika = predaoVal != null ? predaoVal - _ukupnoIznos : null;
                                  return Container(
                                    margin: const EdgeInsets.all(12),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                                    ),
                                    child: Column(
                                      children: [
                                        // Red 1 — ukupno
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              '${_naplate.length} uplata',
                                              style: const TextStyle(color: Colors.white70, fontSize: 15),
                                            ),
                                            Text(
                                              '${_ukupnoIznos.toStringAsFixed(0)} din',
                                              style: const TextStyle(
                                                color: Colors.greenAccent,
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        // Red 2 — Predao input
                                        Row(
                                          children: [
                                            const Text(
                                              'Predao:',
                                              style: TextStyle(color: Colors.white70, fontSize: 14),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: TextField(
                                                controller: _predaoController,
                                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                style: const TextStyle(color: Colors.white, fontSize: 15),
                                                decoration: InputDecoration(
                                                  hintText: '0',
                                                  hintStyle: const TextStyle(color: Colors.white38),
                                                  suffixText: 'din',
                                                  suffixStyle: const TextStyle(color: Colors.white54),
                                                  isDense: true,
                                                  contentPadding:
                                                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                  filled: true,
                                                  fillColor: Colors.white.withValues(alpha: 0.08),
                                                  border: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(8),
                                                    borderSide: BorderSide.none,
                                                  ),
                                                ),
                                                onChanged: (_) => setFooter(() {}),
                                              ),
                                            ),
                                          ],
                                        ),
                                        // Red 3 — Razlika (samo ako je uneseno)
                                        if (razlika != null) ...[
                                          const SizedBox(height: 8),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                razlika >= 0 ? 'Višak:' : 'Manjak:',
                                                style: TextStyle(
                                                  color: razlika >= 0 ? Colors.greenAccent : Colors.redAccent,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Text(
                                                '${razlika.abs().toStringAsFixed(0)} din',
                                                style: TextStyle(
                                                  color: razlika >= 0 ? Colors.greenAccent : Colors.redAccent,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
