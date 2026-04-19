import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/v3_dnevna_predaja.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_dnevna_predaja_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_dan_helper.dart';
import '../utils/v3_date_utils.dart';
import '../utils/v3_error_utils.dart';
import '../utils/v3_input_utils.dart';
import '../utils/v3_state_utils.dart';
import '../utils/v3_stream_utils.dart';
import '../utils/v3_text_utils.dart';

/// DNEVNIK NAPLATE — V3
/// Admin bira vozača i datum → vidi sve naplate tog vozača za taj dan
/// Podaci iz v3_operativna_nedelja cache (placeno kada je naplacen_at postavljen)
class V3DnevnikNaplateScreen extends StatefulWidget {
  const V3DnevnikNaplateScreen({super.key});

  @override
  State<V3DnevnikNaplateScreen> createState() => _V3DnevnikNaplateScreenState();
}

class _V3DnevnikNaplateScreenState extends State<V3DnevnikNaplateScreen> {
  String? _selectedVozacId;
  String? _selectedVozacIme;
  DateTime _selectedDate = DateTime.now();

  List<_NaplataRow> _naplate = [];
  double _ukupnoIznos = 0;
  double? _predaoIznos; // za PDF/clipboard — ažurira ga footer

  List<_VozacItem> _vozaci = [];

  @override
  void initState() {
    super.initState();
    _ucitajVozace();

    V3StreamUtils.subscribe<int>(
      key: 'dnevnik_naplate_cache',
      stream: V3MasterRealtimeManager.instance.tablesRevisionStream(const ['v3_operativna_nedelja', 'v3_auth']),
      onData: (_) {
        if (!mounted) return;
        _ucitajVozace();

        if (_selectedVozacId == null) return;

        V3StreamUtils.cancelTimer('dnevnik_naplate_refresh_debounce');
        V3StreamUtils.createTimer(
          key: 'dnevnik_naplate_refresh_debounce',
          duration: const Duration(milliseconds: 300),
          callback: () {
            if (mounted) _prikaziNaplate();
          },
        );
      },
    );
  }

  @override
  void dispose() {
    V3StreamUtils.cancelSubscription('dnevnik_naplate_cache');
    V3StreamUtils.cancelTimer('dnevnik_naplate_refresh_debounce');
    super.dispose();
  }

  void _ucitajVozace() {
    final list = V3VozacService.getAllVozaci().map((v) => _VozacItem(id: v.id, ime: v.imePrezime)).toList()
      ..sort((a, b) => a.ime.compareTo(b.ime));
    V3StateUtils.safeSetState(this, () => _vozaci = list);
  }

  void _prikaziNaplate() {
    if (_selectedVozacId == null) return;

    final target = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final cache = V3MasterRealtimeManager.instance.operativnaNedeljaCache;
    final putniciCache = V3MasterRealtimeManager.instance.putniciCache;

    final rows = <_NaplataRow>[];
    for (final row in cache.values) {
      if (row['naplacen_at'] == null) continue;

      final vozacId = row['naplacen_by']?.toString() ?? '';
      if (vozacId != _selectedVozacId) continue;

      final vremePlaceno = row['naplacen_at'] as String? ?? '';
      final dt = V3DateUtils.parseTs(vremePlaceno);
      if (dt == null) continue;

      final payDay = DateTime(dt.year, dt.month, dt.day);
      if (payDay != target) continue;

      final putnikId = row['created_by']?.toString() ?? '';
      final putnikData = putniciCache[putnikId];
      final ime = (putnikData?['ime_prezime'] as String?) ??
          row['ime_prezime'] as String? ??
          row['putnik_ime'] as String? ??
          '?';
      final iznos = (row['naplacen_iznos'] as num?)?.toDouble() ?? 0.0;
      final vreme = V3DanHelper.formatVreme(dt.hour, dt.minute);
      rows.add(_NaplataRow(
        id: row['id']?.toString() ?? '',
        ime: ime,
        iznos: iznos,
        vremeNaplate: vreme,
        sortAt: dt,
      ));
    }

    rows.sort((a, b) => a.sortAt.compareTo(b.sortAt));

    setState(() {
      _naplate = rows;
      _ukupnoIznos = rows.fold(0.0, (sum, r) => sum + r.iznos);
      _predaoIznos = null;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(data: ThemeData.dark(), child: child!),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _naplate = [];
        _ukupnoIznos = 0;
        _predaoIznos = null;
      });
      _prikaziNaplate();
    }
  }

  void _share() {
    if (_naplate.isEmpty) return;

    final buf = StringBuffer();
    buf.writeln('DNEVNIK NAPLATE — $_selectedVozacIme');
    buf.writeln('Datum: ${_formatDatum(_selectedDate)}');
    buf.writeln('─────────────────────────');
    for (int i = 0; i < _naplate.length; i++) {
      final n = _naplate[i];
      buf.writeln('${i + 1}. ${n.ime} — ${n.iznos.toStringAsFixed(0)} din — ${n.vremeNaplate}');
    }
    buf.writeln('─────────────────────────');
    buf.writeln('UKUPNO: ${_naplate.length} uplata — ${_ukupnoIznos.toStringAsFixed(0)} din');
    final predaoVal = _predaoIznos;
    if (predaoVal != null) {
      final razlika = predaoVal - _ukupnoIznos;
      buf.writeln('Predao: ${predaoVal.toStringAsFixed(0)} din');
      buf.writeln(razlika >= 0
          ? 'Višak: ${razlika.toStringAsFixed(0)} din'
          : 'Manjak: ${razlika.abs().toStringAsFixed(0)} din');
    }

    Clipboard.setData(ClipboardData(text: buf.toString()));
    V3AppSnackBar.success(context, '📋 Kopirano u clipboard');
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

    final predaoVal = _predaoIznos;
    final razlika = predaoVal != null ? predaoVal - _ukupnoIznos : null;

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => [
          pw.Text('DNEVNIK NAPLATE', style: titleStyle),
          pw.SizedBox(height: 4),
          pw.Text('Vozač: $_selectedVozacIme', style: headerStyle),
          pw.Text('Datum: ${_formatDatum(_selectedDate)}', style: normalStyle),
          pw.SizedBox(height: 14),
          pw.Divider(),
          pw.SizedBox(height: 8),

          // Tabela
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: const {
              0: pw.FixedColumnWidth(24),
              1: pw.FlexColumnWidth(4),
              2: pw.FixedColumnWidth(70),
              3: pw.FixedColumnWidth(40),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _pdfCell('#', style: boldStyle),
                  _pdfCell('Ime', style: boldStyle),
                  _pdfCell('Iznos', style: boldStyle),
                  _pdfCell('Vreme', style: boldStyle),
                ],
              ),
              for (int i = 0; i < _naplate.length; i++)
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: i.isEven ? PdfColors.white : PdfColors.grey50,
                  ),
                  children: [
                    _pdfCell('${i + 1}.', style: baseStyle),
                    _pdfCell(_naplate[i].ime, style: baseStyle),
                    _pdfCell('${_naplate[i].iznos.toStringAsFixed(0)} din', style: baseStyle),
                    _pdfCell(_naplate[i].vremeNaplate, style: baseStyle),
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
        ],
      ),
    );

    try {
      final dir = await getApplicationDocumentsDirectory();
      final vozacStr = (_selectedVozacIme ?? 'vozac').replaceAll(' ', '_');
      final datumStr = _formatDatum(_selectedDate).replaceAll('.', '-');
      final file = File('${dir.path}/dnevnik_${vozacStr}_$datumStr.pdf');
      await file.writeAsBytes(await doc.save());
      if (!mounted) return;
      await OpenFilex.open(file.path);
    } catch (e) {
      V3ErrorUtils.safeError(this, context, '❌ Greška pri izvozu PDF: $e');
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
              // ─── Filter bar ───────────────────────────────────────
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
                            value: _selectedVozacId,
                            hint: const Text('Vozač', style: TextStyle(color: Colors.white54)),
                            dropdownColor: const Color(0xFF1A1A2E),
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
                            isExpanded: true,
                            items: _vozaci
                                .map((v) => DropdownMenuItem(
                                      value: v.id,
                                      child: Text(v.ime),
                                    ))
                                .toList(),
                            onChanged: (id) {
                              if (id == null) return;
                              final vozac = _vozaci.firstWhere((v) => v.id == id);
                              setState(() {
                                _selectedVozacId = id;
                                _selectedVozacIme = vozac.ime;
                                _naplate = [];
                                _ukupnoIznos = 0;
                                _predaoIznos = null;
                              });
                              _prikaziNaplate();
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
                              _formatDatum(_selectedDate),
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ─── Sadržaj ──────────────────────────────────────────
              Expanded(
                child: _selectedVozacId == null
                    ? const Center(
                        child: Text(
                          'Izaberi vozača i datum',
                          style: TextStyle(color: Colors.white54, fontSize: 16),
                        ),
                      )
                    : Column(
                        children: [
                          Expanded(
                            child: _naplate.isEmpty
                                ? Center(
                                    child: Text(
                                      'Nema naplata za ${_formatDatum(_selectedDate)}',
                                      style: const TextStyle(color: Colors.white54, fontSize: 16),
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    itemCount: _naplate.length,
                                    itemBuilder: (_, i) => _NaplataCard(n: _naplate[i], index: i),
                                  ),
                          ),
                          // Footer: Ukupno + Predao
                          _PredajaFooter(
                            key: ValueKey('$_selectedVozacId-${_selectedDate.toIso8601String()}'),
                            naplate: _naplate,
                            ukupnoIznos: _ukupnoIznos,
                            vozacId: _selectedVozacId!,
                            vozacIme: _selectedVozacIme ?? '',
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

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _formatDatum(DateTime d) => V3DanHelper.formatDatumPuni(d);

pw.Widget _pdfCell(String text, {required pw.TextStyle style}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(text, style: style),
    );

// ─── Model ────────────────────────────────────────────────────────────────────

class _VozacItem {
  final String id;
  final String ime;
  const _VozacItem({required this.id, required this.ime});
}

class _NaplataRow {
  final String id;
  final String ime;
  final double iznos;
  final String vremeNaplate;
  final DateTime sortAt;
  const _NaplataRow({
    required this.id,
    required this.ime,
    required this.iznos,
    required this.vremeNaplate,
    required this.sortAt,
  });
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

class _NaplataCard extends StatelessWidget {
  const _NaplataCard({required this.n, required this.index});
  final _NaplataRow n;
  final int index;

  @override
  Widget build(BuildContext context) {
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
            child: Text('${index + 1}.', style: const TextStyle(color: Colors.white38, fontSize: 13)),
          ),
          Expanded(
            child: Text(n.ime, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          Text('${n.iznos.toStringAsFixed(0)} din',
              style: const TextStyle(color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(width: 10),
          Text(n.vremeNaplate, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Footer — izolirani StatefulWidget, setState ne triguje roditelja.
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

  final List<_NaplataRow> naplate;
  final double ukupnoIznos;
  final String vozacId;
  final String vozacIme;
  final DateTime datum;
  final void Function(double?)? onPredaoChanged;

  @override
  State<_PredajaFooter> createState() => _PredajaFooterState();
}

class _PredajaFooterState extends State<_PredajaFooter> {
  bool _sacuvan = false;

  @override
  void initState() {
    super.initState();
    _loadPredaja();
  }

  @override
  void dispose() {
    V3TextUtils.disposeController('iznos');
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
      V3TextUtils.setControllerText('iznos', iznos != null ? iznos.toStringAsFixed(0) : '');
      _sacuvan = iznos != null;
    });
  }

  Future<void> _sacuvaj() async {
    final predaoVal = double.tryParse(V3TextUtils.getControllerText('iznos').replaceAll(',', '.'));
    if (predaoVal == null) return;
    if (predaoVal <= 0) {
      if (mounted) {
        V3AppSnackBar.warning(context, 'Unesite iznos predaje veći od 0 din.');
      }
      return;
    }

    try {
      await V3DnevnaPredajaService.upsertPredaja(V3DnevnaPredaja(
        id: '',
        vozacId: widget.vozacId,
        vozacImePrezime: widget.vozacIme,
        datum: widget.datum,
        predaoIznos: predaoVal,
        ukupnoNaplaceno: widget.ukupnoIznos,
        razlika: predaoVal - widget.ukupnoIznos,
      ));
      if (mounted) {
        widget.onPredaoChanged?.call(predaoVal);
        setState(() => _sacuvan = true);
        V3AppSnackBar.success(context, '✅ Predaja sačuvana');
      }
    } catch (e) {
      V3ErrorUtils.safeError(this, context, '❌ Greška pri čuvanju: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final predaoVal = double.tryParse(V3TextUtils.getControllerText('iznos').replaceAll(',', '.'));
    final razlika = predaoVal != null ? predaoVal - widget.ukupnoIznos : null;

    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ukupno naplaćeno
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Ukupno naplaćeno:', style: TextStyle(color: Colors.white70, fontSize: 14)),
              Text(
                '${widget.ukupnoIznos.toStringAsFixed(0)} din',
                style: const TextStyle(color: Colors.greenAccent, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Predao input + dugme
          Row(
            children: [
              const Text('Predao:', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(width: 10),
              Expanded(
                child: V3InputUtils.numberField(
                  controller: V3TextUtils.iznosController,
                  label: '0',
                  suffixText: 'din',
                ),
              ),
              const SizedBox(width: 8),
              V3ButtonUtils.elevatedButton(
                onPressed: _sacuvaj,
                text: _sacuvan ? '✅' : 'Sačuvaj',
                backgroundColor: _sacuvan ? Colors.green[700] : Colors.green,
                foregroundColor: Colors.white,
                borderRadius: BorderRadius.circular(10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ],
          ),

          // Višak / Manjak
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
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
