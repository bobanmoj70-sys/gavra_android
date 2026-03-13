import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/v3_dnevna_predaja.dart';
import '../models/v3_vozac.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v2_polasci_service.dart';
import '../services/v3/v3_dnevna_predaja_service.dart';
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
  String? _selectedVozacId;
  String? _selectedVozacIme;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  List<Map<String, dynamic>> _naplate = [];
  double _ukupnoIznos = 0;
  double? _predaoIznos;

  @override
  void initState() {
    super.initState();
  }

  void _resetNaplate() {
    _naplate = [];
    _ukupnoIznos = 0;
    _predaoIznos = null;
  }

  Future<void> _ucitajNaplate() async {
    if (_selectedVozacIme == null) return;

    setState(() => _isLoading = true);

    try {
      final dateStr =
          '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, "0")}-${_selectedDate.day.toString().padLeft(2, "0")}';

      final result = await _fetchNaplate(dateStr);

      setState(() {
        _naplate = result;
        _ukupnoIznos = result.fold(0.0, (sum, r) => sum + ((r['iznos'] as num?)?.toDouble() ?? 0));
        _isLoading = false;
        _predaoIznos = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        V2AppSnackBar.error(context, '❌ Greška: $e');
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchNaplate(String dateStr) async {
    final rows = await V2PolasciService.getNaplateZaVozacaDan(
      vozacIme: _selectedVozacIme!,
      dateStr: dateStr,
    );

    if (rows.isEmpty) return [];

    final rm = V3MasterRealtimeManager.instance;
    final sve = <Map<String, dynamic>>[];

    for (final r in rows) {
      final putnikId = r['putnik_id']?.toString() ?? '';
      final putnikTabela = r['putnik_tabela']?.toString() ?? '';

      String ime = '?';
      if (putnikId.isNotEmpty && putnikTabela.isNotEmpty) {
        if (putnikTabela == 'v3_putnici') {
          final p = rm.getPutnik(putnikId);
          ime = p != null ? p['ime_prezime']?.toString() ?? '?' : '?';
        } else {
          ime = '? (v2)';
        }
      }

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
        _resetNaplate();
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
      buffer.writeln('${i + 1}. ${n["ime"]} (${n["grad"]} ${n["polazak"]}) — $iznos din — ${n["vreme_naplate"]}');
    }
    buffer.writeln('─────────────────────────');
    buffer.writeln('UKUPNO: ${_naplate.length} uplata — ${_ukupnoIznos.toStringAsFixed(0)} din');
    final predaoVal = _predaoIznos;
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
    final predaoVal = _predaoIznos;
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
                      _dnevnikPdfCell('${_naplate[i]["grad"]} ${_naplate[i]["polazak"]}', style: baseStyle),
                      _dnevnikPdfCell('${(_naplate[i]["iznos"] as double).toStringAsFixed(0)} din', style: baseStyle),
                      _dnevnikPdfCell(_naplate[i]['vreme_naplate'] as String, style: baseStyle),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Divider(),
            pw.SizedBox(height: 8),
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
      if (mounted) V2AppSnackBar.error(context, '❌ Greška pri izvozu PDF: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rm = V3MasterRealtimeManager.instance;
    final vozaciList = rm.vozaciCache.values.map((v) => V3Vozac.fromJson(v)).toList()
      ..sort((a, b) => a.imePrezime.compareTo(b.imePrezime));

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
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(25),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedVozacId,
                            hint: const Text('Vozač', style: TextStyle(color: Colors.white54)),
                            dropdownColor: const Color(0xFF1A1A2E),
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
                            isExpanded: true,
                            items: vozaciList
                                .map((v) => DropdownMenuItem(value: v.id, child: Text(v.imePrezime)))
                                .toList(),
                            onChanged: (id) {
                              if (id == null) return;
                              final v = rm.getVozac(id);
                              setState(() {
                                _selectedVozacId = id;
                                _selectedVozacIme = v?['ime_prezime']?.toString();
                                _resetNaplate();
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(25),
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
                    ElevatedButton(
                      onPressed: _selectedVozacId == null ? null : _ucitajNaplate,
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
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : _naplate.isEmpty
                        ? Center(
                            child: Text(
                              _selectedVozacId == null
                                  ? 'Izaberi vozača i datum'
                                  : 'Nema naplata za ${_dnevnikFormatDatum(_selectedDate)}',
                              style: const TextStyle(color: Colors.white54, fontSize: 16),
                            ),
                          )
                        : Column(
                            children: [
                              Expanded(
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  itemCount: _naplate.length,
                                  itemBuilder: (_, index) => _NaplataCard(n: _naplate[index], index: index),
                                ),
                              ),
                              _PredajaFooter(
                                key: ValueKey('$_selectedVozacId-${_selectedDate.toIso8601String()}'),
                                naplate: _naplate,
                                ukupnoIznos: _ukupnoIznos,
                                vozacId: _selectedVozacId!,
                                vozacIme: _selectedVozacIme!,
                                datum: _selectedDate,
                                onPredaoChanged: (v) => _predaoIznos = v,
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

Map<String, dynamic> _dnevnikBuildRow(Map<String, dynamic> r, String ime) {
  final placenAt = r['placen_at'] as String?;
  final updatedAt = r['updated_at'] as String?;
  final tsStr = placenAt ?? updatedAt ?? '';
  String vremeNaplate = '-';
  if (tsStr.isNotEmpty) {
    final dt = DateTime.tryParse(tsStr)?.toLocal();
    if (dt != null) {
      vremeNaplate = '${dt.hour.toString().padLeft(2, "0")}:${dt.minute.toString().padLeft(2, "0")}';
    }
  }
  return {
    'ime': ime,
    'grad': r['grad'] as String? ?? '-',
    'polazak': r['dodeljeno_vreme'] as String? ?? '-',
    'iznos': (r['placen_iznos'] as num?)?.toDouble() ?? 0.0,
    'vreme_naplate': vremeNaplate,
    'sort_ts': tsStr.isNotEmpty ? tsStr : '9999',
  };
}

String _dnevnikFormatDatum(DateTime date) {
  return '${date.day.toString().padLeft(2, "0")}.${date.month.toString().padLeft(2, "0")}.${date.year}';
}

pw.Widget _dnevnikPdfCell(String text, {required pw.TextStyle style}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    child: pw.Text(text, style: style),
  );
}

class _NaplataCard extends StatelessWidget {
  const _NaplataCard({required this.n, required this.index});

  final Map<String, dynamic> n;
  final int index;

  @override
  Widget build(BuildContext context) {
    final iznos = (n['iznos'] as double).toStringAsFixed(0);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('${index + 1}.', style: const TextStyle(color: Colors.white38, fontSize: 13)),
          ),
          Expanded(
            child: Text(n['ime'] as String,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          Text('${n["grad"]} ${n["polazak"]}', style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(width: 10),
          Text('$iznos din',
              style: const TextStyle(color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(width: 10),
          Text(n['vreme_naplate'] as String, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }
}

class _PredajaFooter extends StatefulWidget {
  const _PredajaFooter({
    super.key,
    required this.naplate,
    required this.ukupnoIznos,
    required this.vozacId,
    required this.vozacIme,
    required this.datum,
    this.onPredaoChanged,
  });

  final List<Map<String, dynamic>> naplate;
  final double ukupnoIznos;
  final String vozacId;
  final String vozacIme;
  final DateTime datum;
  final void Function(double?)? onPredaoChanged;

  @override
  State<_PredajaFooter> createState() => _PredajaFooterState();
}

class _PredajaFooterState extends State<_PredajaFooter> {
  final _ctrl = TextEditingController();
  bool _sacuvan = false;

  @override
  void initState() {
    super.initState();
    _loadPredaja();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadPredaja() async {
    final predaja = await V3DnevnaPredajaService.getPredaja(
      vozacId: widget.vozacId,
      datum: widget.datum,
    );
    if (!mounted) return;
    final iznos = (predaja != null && predaja.predaoIznos > 0) ? predaja.predaoIznos : null;
    widget.onPredaoChanged?.call(iznos);
    setState(() {
      _ctrl.text = iznos != null ? iznos.toStringAsFixed(0) : '';
      _sacuvan = iznos != null;
    });
  }

  Future<void> _sacuvaj() async {
    final predaoVal = double.tryParse(_ctrl.text.replaceAll(',', '.'));
    if (predaoVal == null) return;

    final newPredaja = V3DnevnaPredaja(
      id: '',
      vozacId: widget.vozacId,
      vozacImePrezime: widget.vozacIme,
      datum: widget.datum,
      predaoIznos: predaoVal,
      ukupnoNaplaceno: widget.ukupnoIznos,
      razlika: predaoVal - widget.ukupnoIznos,
    );

    try {
      await V3DnevnaPredajaService.upsertPredaja(newPredaja);
      if (mounted) {
        widget.onPredaoChanged?.call(predaoVal);
        setState(() => _sacuvan = true);
        V2AppSnackBar.success(context, '✅ Predaja sačuvana');
      }
    } catch (e) {
      if (mounted) V2AppSnackBar.error(context, '❌ Greška pri čuvanju');
    }
  }

  @override
  Widget build(BuildContext context) {
    final predaoVal = double.tryParse(_ctrl.text.replaceAll(',', '.'));
    final razlika = predaoVal != null ? predaoVal - widget.ukupnoIznos : null;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.green.withAlpha(38),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withAlpha(102)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${widget.naplate.length} uplata', style: const TextStyle(color: Colors.white70, fontSize: 15)),
              Text('${widget.ukupnoIznos.toStringAsFixed(0)} din',
                  style: const TextStyle(color: Colors.greenAccent, fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('Predao:', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: '0',
                    hintStyle: const TextStyle(color: Colors.white38),
                    suffixText: 'din',
                    suffixStyle: const TextStyle(color: Colors.white54),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    filled: true,
                    fillColor: Colors.white.withAlpha(20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                  onChanged: (v) {
                    widget.onPredaoChanged?.call(double.tryParse(v.replaceAll(',', '.')));
                    setState(() => _sacuvan = false);
                  },
                  onSubmitted: (_) => _sacuvaj(),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _sacuvaj,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _sacuvan ? Colors.green.withAlpha(77) : Colors.white.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _sacuvan ? Colors.greenAccent : Colors.white24),
                  ),
                  child: Icon(
                    _sacuvan ? Icons.check : Icons.save_outlined,
                    color: _sacuvan ? Colors.greenAccent : Colors.white54,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
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
                      fontWeight: FontWeight.w600),
                ),
                Text(
                  '${razlika.abs().toStringAsFixed(0)} din',
                  style: TextStyle(
                      color: razlika >= 0 ? Colors.greenAccent : Colors.redAccent,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
