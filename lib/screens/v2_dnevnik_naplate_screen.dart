import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../services/realtime/v2_master_realtime_manager.dart';
import '../services/v2_dnevna_predaja_service.dart';
import '../services/v2_polasci_service.dart';
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
  bool _predaoSacuvan = false;

  // Lista vozača — osvježava se kada RM emituje promjenu vozaciCache
  List<String> _vozaciImena = [];

  StreamSubscription<String>? _polasciSub;
  StreamSubscription<String>? _vozaciSub;
  Timer? _refreshDebounce;

  @override
  void initState() {
    super.initState();
    _vozaciImena = V2VozacService.getAllVozaci().map((v) => v.ime).toList();
    _vozaciSub = V2MasterRealtimeManager.instance.onCacheChanged.where((t) => t == 'v2_vozaci').listen((_) {
      if (!mounted) return;
      setState(() {
        _vozaciImena = V2VozacService.getAllVozaci().map((v) => v.ime).toList();
      });
    });
    _polasciSub = V2MasterRealtimeManager.instance.onCacheChanged.where((t) => t == 'v2_polasci').listen((_) {
      if (_selectedVozacIme == null) return;
      final today = DateTime.now();
      final isToday =
          _selectedDate.year == today.year && _selectedDate.month == today.month && _selectedDate.day == today.day;
      if (!isToday) return;
      _refreshDebounce?.cancel();
      _refreshDebounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) _ucitajNaplate();
      });
    });
  }

  @override
  void dispose() {
    _polasciSub?.cancel();
    _vozaciSub?.cancel();
    _refreshDebounce?.cancel();
    _predaoController.dispose();
    super.dispose();
  }

  Future<void> _ucitajNaplate() async {
    if (_selectedVozacIme == null) return;

    setState(() => _isLoading = true);

    try {
      final dateStr =
          '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

      final result = await _fetchNaplate(dateStr);

      setState(() {
        _naplate = result;
        _ukupnoIznos = result.fold(0.0, (sum, r) => sum + ((r['iznos'] as num?)?.toDouble() ?? 0));
        _isLoading = false;
        _predaoController.clear();
        _predaoSacuvan = false;
      });
      await _ucitajPredaju(dateStr);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        V2AppSnackBar.error(context, 'Greška: $e');
      }
    }
  }

  Future<void> _ucitajPredaju(String dateStr) async {
    final predaja = await V2DnevnaPredajaService.get(
      vozacIme: _selectedVozacIme!,
      datum: _selectedDate,
    );
    if (!mounted) return;
    if (predaja != null) {
      setState(() {
        _predaoController.text = predaja.predaoIznos > 0 ? predaja.predaoIznos.toStringAsFixed(0) : '';
        _predaoSacuvan = predaja.predaoIznos > 0;
      });
    } else {
      setState(() {
        _predaoController.clear();
        _predaoSacuvan = false;
      });
    }
  }

  Future<void> _sacuvajPredaju() async {
    final predaoVal = double.tryParse(_predaoController.text.replaceAll(',', '.'));
    if (predaoVal == null || _selectedVozacIme == null) return;
    final ok = await V2DnevnaPredajaService.upsert(
      vozacIme: _selectedVozacIme!,
      datum: _selectedDate,
      predaoIznos: predaoVal,
      ukupnoNaplaceno: _ukupnoIznos,
    );
    if (mounted) {
      if (ok) {
        setState(() => _predaoSacuvan = true);
        V2AppSnackBar.success(context, '✅ Predaja sačuvana');
      } else {
        V2AppSnackBar.error(context, 'Greška pri čuvanju');
      }
    }
  }

  /// Dohvata naplate za vozača i datum.
  /// Query za v2_polasci ide kroz V2PolasciService (jedino dozvoljeno mjesto za direktan DB).
  /// Imenovanja putnika se rješavaju iz RM cache-a — 0 dodatnih DB upita.
  Future<List<Map<String, dynamic>>> _fetchNaplate(String dateStr) async {
    final rows = await V2PolasciService.getNaplateZaVozacaDan(
      vozacIme: _selectedVozacIme!,
      dateStr: dateStr,
    );

    if (rows.isEmpty) return [];

    final rm = V2MasterRealtimeManager.instance;
    final sve = <Map<String, dynamic>>[];

    for (final r in rows) {
      final putnikId = r['putnik_id']?.toString() ?? '';
      final putnikTabela = r['putnik_tabela']?.toString() ?? '';
      // Ime iz RM cache-a — bez ijednog DB upita
      final ime = (putnikId.isNotEmpty && putnikTabela.isNotEmpty) ? (rm.getIme(putnikTabela, putnikId) ?? '?') : '?';
      sve.add(_dnevnikBuildRow(r, ime));
    }

    sve.sort((a, b) => (a['sort_ts'] as String).compareTo(b['sort_ts'] as String));

    return sve;
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
        _predaoController.clear();
        _predaoSacuvan = false;
      });
    }
  }

  void _share() {
    if (_naplate.isEmpty) return;

    final buffer = StringBuffer();
    buffer.writeln('DNEVNIK NAPLATE — $_selectedVozacIme');
    buffer.writeln('Datum: ${_dnevnikFormatDatum(_selectedDate)}');
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
    V2AppSnackBar.success(context, '📋 Kopirano u clipboard');
  }

  Future<void> _exportPdf() async {
    if (_naplate.isEmpty) return;

    // Lato font — podržava šđžćč i latin-extended
    final fontRegularData = await rootBundle.load('assets/fonts/Lato-Regular.ttf');
    final fontBoldData = await rootBundle.load('assets/fonts/Lato-Bold.ttf');
    final fontRegular = pw.Font.ttf(fontRegularData);
    final fontBold = pw.Font.ttf(fontBoldData);

    final baseStyle = pw.TextStyle(font: fontRegular, fontSize: 10);
    final boldStyle = pw.TextStyle(font: fontBold, fontSize: 10);
    final titleStyle = pw.TextStyle(font: fontBold, fontSize: 18);
    final headerStyle = pw.TextStyle(font: fontBold, fontSize: 11);
    final summaryStyle = pw.TextStyle(font: fontBold, fontSize: 12);
    final normalStyle = pw.TextStyle(font: fontRegular, fontSize: 12);

    final doc = pw.Document();
    final predaoVal = double.tryParse(_predaoController.text.replaceAll(',', '.'));
    final razlika = predaoVal != null ? predaoVal - _ukupnoIznos : null;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context ctx) {
          return [
            pw.Text('DNEVNIK NAPLATE', style: titleStyle),
            pw.SizedBox(height: 4),
            pw.Text('Vozač: $_selectedVozacIme', style: headerStyle),
            pw.Text('Datum: ${_dnevnikFormatDatum(_selectedDate)}', style: normalStyle),
            pw.SizedBox(height: 14),
            pw.Divider(),
            pw.SizedBox(height: 8),

            // Tabela naplata
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: const {
                0: pw.FixedColumnWidth(24),
                1: pw.FlexColumnWidth(3),
                2: pw.FlexColumnWidth(2.5),
                3: pw.FixedColumnWidth(60),
                4: pw.FixedColumnWidth(40),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _dnevnikPdfCell('#', style: boldStyle),
                    _dnevnikPdfCell('Ime', style: boldStyle),
                    _dnevnikPdfCell('Grad / Polazak', style: boldStyle),
                    _dnevnikPdfCell('Iznos', style: boldStyle),
                    _dnevnikPdfCell('Vreme', style: boldStyle),
                  ],
                ),
                for (int i = 0; i < _naplate.length; i++)
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: i.isEven ? PdfColors.white : PdfColors.grey50,
                    ),
                    children: [
                      _dnevnikPdfCell('${i + 1}.', style: baseStyle),
                      _dnevnikPdfCell(_naplate[i]['ime']?.toString() ?? '?', style: baseStyle),
                      _dnevnikPdfCell('${_naplate[i]['grad']} ${_naplate[i]['polazak']}', style: baseStyle),
                      _dnevnikPdfCell('${(_naplate[i]['iznos'] as double).toStringAsFixed(0)} din', style: baseStyle),
                      _dnevnikPdfCell(_naplate[i]['vreme_naplate'] as String, style: baseStyle),
                    ],
                  ),
              ],
            ),

            pw.SizedBox(height: 14),
            pw.Divider(),
            pw.SizedBox(height: 8),

            // Ukupno
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('UKUPNO (${_naplate.length} uplata):', style: summaryStyle),
                pw.Text('${_ukupnoIznos.toStringAsFixed(0)} din', style: summaryStyle),
              ],
            ),

            if (predaoVal != null) ...[
              pw.SizedBox(height: 6),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Predao:', style: normalStyle),
                  pw.Text('${predaoVal.toStringAsFixed(0)} din', style: normalStyle),
                ],
              ),
              if (razlika != null) ...[
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(razlika >= 0 ? 'Višak:' : 'Manjak:', style: summaryStyle),
                    pw.Text('${razlika.abs().toStringAsFixed(0)} din', style: summaryStyle),
                  ],
                ),
              ],
            ],
          ];
        },
      ),
    );

    try {
      final dir = await getApplicationDocumentsDirectory();
      final vozacStr = _selectedVozacIme?.replaceAll(' ', '_') ?? 'vozac';
      final datumStr = _dnevnikFormatDatum(_selectedDate).replaceAll('.', '-');
      final file = File('${dir.path}/dnevnik_${vozacStr}_$datumStr.pdf');
      await file.writeAsBytes(await doc.save());
      if (!mounted) return;
      await OpenFilex.open(file.path);
    } catch (e) {
      if (mounted) V2AppSnackBar.error(context, 'Greška pri izvozu PDF: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Dnevnik naplate', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_naplate.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
              tooltip: 'Sačuvaj PDF',
              onPressed: _exportPdf,
            ),
            IconButton(
              icon: const Icon(Icons.copy, color: Colors.white),
              tooltip: 'Kopiraj izveštaj',
              onPressed: _share,
            ),
          ],
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
                            items: _vozaciImena.map((ime) => DropdownMenuItem(value: ime, child: Text(ime))).toList(),
                            onChanged: (v) {
                              setState(() {
                                _selectedVozacIme = v;
                                _naplate = [];
                                _ukupnoIznos = 0;
                                _predaoController.clear();
                                _predaoSacuvan = false;
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
                              _dnevnikFormatDatum(_selectedDate),
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
                                  : 'Nema naplata za ${_dnevnikFormatDatum(_selectedDate)}',
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
                                          SizedBox(
                                            width: 28,
                                            child: Text(
                                              '${index + 1}.',
                                              style: const TextStyle(color: Colors.white38, fontSize: 13),
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              n['ime'] as String,
                                              style: const TextStyle(
                                                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                          Text(
                                            '${n['grad']} ${n['polazak']}',
                                            style: const TextStyle(color: Colors.white54, fontSize: 13),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            '$iznos din',
                                            style: const TextStyle(
                                              color: Colors.greenAccent,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
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

                              // Footer: Ukupno + Predao
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
                                        // Ukupno
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
                                        // Predao input
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
                                                onChanged: (_) {
                                                  setState(() => _predaoSacuvan = false);
                                                },
                                                onSubmitted: (_) => _sacuvajPredaju(),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            GestureDetector(
                                              onTap: _sacuvajPredaju,
                                              child: Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: _predaoSacuvan
                                                      ? Colors.green.withValues(alpha: 0.3)
                                                      : Colors.white.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: _predaoSacuvan ? Colors.greenAccent : Colors.white24,
                                                  ),
                                                ),
                                                child: Icon(
                                                  _predaoSacuvan ? Icons.check : Icons.save_outlined,
                                                  color: _predaoSacuvan ? Colors.greenAccent : Colors.white54,
                                                  size: 20,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        // Razlika
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

// ─── top-level helperi (bez state pristupa) ───────────────────────────────────

Map<String, dynamic> _dnevnikBuildRow(Map<String, dynamic> r, String ime) {
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
    // Prazni sort_ts idu na kraj (sentinel '9999' > svaka ISO vrijednost)
    'sort_ts': tsStr.isNotEmpty ? tsStr : '9999',
  };
}

String _dnevnikFormatDatum(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}

pw.Widget _dnevnikPdfCell(String text, {required pw.TextStyle style}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    child: pw.Text(text, style: style),
  );
}
