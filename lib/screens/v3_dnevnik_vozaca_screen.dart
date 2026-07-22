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
import '../services/v3/v3_finansije_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../services/v3_locale_manager.dart';
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

class _DnevTr {
  static const Map<String, Map<String, String>> _t = {
    'dnevnikVozaca': {'sr': 'Dnevnik vozača', 'en': 'Driver log', 'ru': 'Журнал водителя', 'de': 'Fahrertagebuch'},
    'sacuvajPdf': {'sr': 'Sačuvaj PDF', 'en': 'Save PDF', 'ru': 'Сохранить PDF', 'de': 'PDF speichern'},
    'kopirajIzvestaj': {
      'sr': 'Kopiraj izveštaj',
      'en': 'Copy report',
      'ru': 'Копировать отчёт',
      'de': 'Bericht kopieren'
    },
    'vozacHint': {'sr': 'Vozač', 'en': 'Driver', 'ru': 'Водитель', 'de': 'Fahrer'},
    'izaberiVozacaIDatum': {
      'sr': 'Izaberi vozača i datum',
      'en': 'Select driver and date',
      'ru': 'Выберите водителя и дату',
      'de': 'Fahrer und Datum auswählen',
    },
    'nemaAkcijaZa': {
      'sr': 'Nema akcija za',
      'en': 'No actions for',
      'ru': 'Нет действий для',
      'de': 'Keine Aktionen für',
    },
    'nepoznato': {'sr': 'Nepoznato', 'en': 'Unknown', 'ru': 'Неизвестно', 'de': 'Unbekannt'},
    'pokupio': {'sr': 'POKUPIO', 'en': 'PICKED UP', 'ru': 'ЗАБРАЛ', 'de': 'ABGEHOLT'},
    'dodao': {'sr': 'DODAO', 'en': 'ADDED', 'ru': 'ДОБАВИЛ', 'de': 'HINZUGEFÜGT'},
    'otkazao': {'sr': 'OTKAZAO', 'en': 'CANCELED', 'ru': 'ОТМЕНИЛ', 'de': 'STORNIERT'},
    'ukupnoNaplaceno': {
      'sr': 'Ukupno naplaćeno:',
      'en': 'Total collected:',
      'ru': 'Всего взыскано:',
      'de': 'Insgesamt eingezogen:',
    },
    'predao': {'sr': 'Predao:', 'en': 'Handed over:', 'ru': 'Сдал:', 'de': 'Übergeben:'},
    'sacuvaj': {'sr': 'Sačuvaj', 'en': 'Save', 'ru': 'Сохранить', 'de': 'Speichern'},
    'visak': {'sr': 'Višak:', 'en': 'Surplus:', 'ru': 'Излишек:', 'de': 'Überschuss:'},
    'manjak': {'sr': 'Manjak:', 'en': 'Shortage:', 'ru': 'Недостача:', 'de': 'Fehlbetrag:'},
    'unesiteIznosPredajeVeciOd0': {
      'sr': 'Unesite iznos predaje veći od 0 din.',
      'en': 'Enter a handover amount greater than 0.',
      'ru': 'Введите сумму передачи больше 0.',
      'de': 'Geben Sie einen Übergabebetrag größer als 0 ein.',
    },
    'predajaSacuvana': {
      'sr': '✅ Predaja sačuvana',
      'en': '✅ Handover saved',
      'ru': '✅ Передача сохранена',
      'de': '✅ Übergabe gespeichert',
    },
    'greskaPriCuvanju': {
      'sr': '❌ Greška pri čuvanju',
      'en': '❌ Error saving',
      'ru': '❌ Ошибка при сохранении',
      'de': '❌ Fehler beim Speichern',
    },
    'kopiranoUClipboard': {
      'sr': '📋 Kopirano u clipboard',
      'en': '📋 Copied to clipboard',
      'ru': '📋 Скопировано в буфер обмена',
      'de': '📋 In die Zwischenablage kopiert',
    },
    'greskaPriIzvozuPdf': {
      'sr': '❌ Greška pri izvozu PDF',
      'en': '❌ Error exporting PDF',
      'ru': '❌ Ошибка экспорта PDF',
      'de': '❌ Fehler beim PDF-Export',
    },
    'pokupljeni': {'sr': 'Pokupljeni', 'en': 'Picked up', 'ru': 'Забрано', 'de': 'Abgeholt'},
    'otkazani': {'sr': 'Otkazani', 'en': 'Canceled', 'ru': 'Отменено', 'de': 'Storniert'},
    'naplaceno': {'sr': 'Naplaćeno', 'en': 'Collected', 'ru': 'Взыскано', 'de': 'Eingezogen'},
    'dodati': {'sr': 'Dodati', 'en': 'Added', 'ru': 'Добавлено', 'de': 'Hinzugefügt'},
  };

  static String tr(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    return _t[key]?[code] ?? _t[key]?['sr'] ?? key;
  }
}

/// DNEVNIK VOZAČA — V3
/// Admin bira vozača i datum → vidi sve aktivnosti tog vozača za taj dan
/// Podaci iz v3_finansije cache (prihod operativna_naplata)
class V3DnevnikVozacaScreen extends StatefulWidget {
  const V3DnevnikVozacaScreen({super.key});

  @override
  State<V3DnevnikVozacaScreen> createState() => _V3DnevnikVozacaScreenState();
}

class _V3DnevnikVozacaScreenState extends State<V3DnevnikVozacaScreen> {
  String? _selectedVozacId;
  String? _selectedVozacIme;
  DateTime _selectedDate = DateTime.now();

  List<Map<String, dynamic>> _naplate = [];
  List<Map<String, dynamic>> _pokupio = [];
  List<Map<String, dynamic>> _dodao = [];
  List<Map<String, dynamic>> _otkazao = [];
  double _ukupnoIznos = 0;
  double? _predaoIznos; // za PDF/clipboard — ažurira ga footer

  List<_VozacItem> _vozaci = [];

  @override
  void initState() {
    super.initState();
    _vozaci = _buildVozaciList();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      V3StreamUtils.subscribe<int>(
        key: 'dnevnik_vozaca_cache',
        stream: V3MasterRealtimeManager.instance.tablesRevisionStream(const ['v3_auth']),
        onData: (_) {
          if (!mounted) return;
          _ucitajVozace();

          if (_selectedVozacId == null) return;

          V3StreamUtils.cancelTimer('dnevnik_vozaca_refresh_debounce');
          V3StreamUtils.createTimer(
            key: 'dnevnik_vozaca_refresh_debounce',
            duration: const Duration(milliseconds: 300),
            callback: () {
              if (mounted) _prikaziNaplate();
            },
          );
        },
      );
    });
  }

  List<_VozacItem> _buildVozaciList() {
    return V3VozacService.getAllVozaci().map((v) => _VozacItem(id: v.id, ime: v.imePrezime)).toList()
      ..sort((a, b) => a.ime.compareTo(b.ime));
  }

  void _ucitajVozace() {
    final list = _buildVozaciList();
    V3StateUtils.safeSetState(this, () => _vozaci = list);
  }

  void _prikaziNaplate() {
    if (_selectedVozacId == null) return;

    final vozacId = _selectedVozacId!;
    final datumIso = V3DateUtils.parseIsoDatePart(_selectedDate.toIso8601String());

    final naplateRows = V3FinansijeService.getNaplataRowsZaVozacaDan(
      vozacId: vozacId,
      dan: _selectedDate,
    );

    // Pokupljeni putnici — vozac ih je pokupio tog dana (iz arhive v3_finansije)
    final pokupljeniRows = V3FinansijeService.getPokupljeniPutniciZaVozacaDan(
      vozacId: vozacId,
      dan: _selectedDate,
    );

    // Dodati/ažurirani putnici — vozac ih je uneo ili azurirao (iz arhive v3_finansije)
    final dodatiRows = V3FinansijeService.getDodatiPutniciZaVozacaDan(
      vozacId: vozacId,
      dan: _selectedDate,
    );

    // Otkazane vožnje — vozac ih je otkazao tog dana (iz arhive v3_finansije)
    final otkazaoRows = V3FinansijeService.getOtkazaneVoznjeZaVozacaDan(
      vozacId: vozacId,
      dan: _selectedDate,
    );

    setState(() {
      _naplate = naplateRows;
      _pokupio = pokupljeniRows;
      _dodao = dodatiRows;
      _otkazao = otkazaoRows;
      _ukupnoIznos = naplateRows.fold<double>(
        0,
        (sum, row) => sum + ((row['iznos'] as num?)?.toDouble() ?? 0),
      );
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
        _pokupio = [];
        _dodao = [];
        _otkazao = [];
        _ukupnoIznos = 0;
        _predaoIznos = null;
      });
      _prikaziNaplate();
    }
  }

  void _share() {
    if (_naplate.isEmpty) return;

    final buf = StringBuffer();
    buf.writeln('DNEVNIK VOZAČA — $_selectedVozacIme');
    buf.writeln('Datum: ${_formatDatum(_selectedDate)}');
    buf.writeln('─────────────────────────');

    final rm = V3MasterRealtimeManager.instance;

    // Prikaz pokupljenih putnika
    if (_pokupio.isNotEmpty) {
      buf.writeln('POKUPLJENI PUTNICI (${_pokupio.length}):');
      for (int i = 0; i < _pokupio.length; i++) {
        final p = _pokupio[i];
        final datum = V3DateUtils.parseTs(p['pokupljen_at']?.toString()) ?? DateTime.now();
        final vreme = V3DanHelper.formatVreme(datum.hour, datum.minute);
        final putnikId = p['created_by']?.toString() ?? '';
        final putnik = rm.putniciCache[putnikId];
        final putnikIme = putnik?['ime_prezime']?.toString() ?? 'Nepoznato';
        buf.writeln('  ${i + 1}. $putnikIme — $vreme');
      }
      buf.writeln('─────────────────────────');
    }

    // Prikaz dodatih putnika
    if (_dodao.isNotEmpty) {
      buf.writeln('DODATI PUTNICI (${_dodao.length}):');
      for (int i = 0; i < _dodao.length; i++) {
        final p = _dodao[i];
        final putnikId = p['created_by']?.toString() ?? '';
        final putnik = rm.putniciCache[putnikId];
        final putnikIme = putnik?['ime_prezime']?.toString() ?? 'Nepoznato';
        final grad = (p['grad']?.toString() ?? '').trim().toUpperCase();
        final polazakAt = p['polazak_at']?.toString() ?? '';
        buf.writeln('  ${i + 1}. $putnikIme — $grad $polazakAt');
      }
      buf.writeln('─────────────────────────');
    }

    // Prikaz otkazanih vožnji
    if (_otkazao.isNotEmpty) {
      buf.writeln('OTKAZANE VOŽNJE (${_otkazao.length}):');
      for (int i = 0; i < _otkazao.length; i++) {
        final p = _otkazao[i];
        final datum = V3DateUtils.parseTs(p['otkazano_at']?.toString()) ?? DateTime.now();
        final vreme = V3DanHelper.formatVreme(datum.hour, datum.minute);
        final putnikId = p['putnik_v3_auth_id']?.toString() ?? '';
        final putnik = rm.putniciCache[putnikId];
        final putnikIme = putnik?['ime_prezime']?.toString() ?? 'Nepoznato';
        final grad = (p['grad']?.toString() ?? '').trim().toUpperCase();
        final polazakAt = p['vreme']?.toString() ?? '';
        buf.writeln('  ${i + 1}. $putnikIme — $grad $polazakAt — $vreme');
      }
      buf.writeln('─────────────────────────');
    }

    // Prikaz naplata
    buf.writeln('NAPLATE (${_naplate.length}):');
    for (int i = 0; i < _naplate.length; i++) {
      final n = _naplate[i];
      final datum = V3DateUtils.parseTs(n['updated_at']?.toString()) ?? DateTime.now();
      final vreme = V3DanHelper.formatVreme(datum.hour, datum.minute);
      final putnikId = n['putnik_v3_auth_id']?.toString() ?? '';
      final putnik = rm.putniciCache[putnikId];
      final putnikIme = putnik?['ime_prezime']?.toString() ?? n['naziv']?.toString() ?? 'Nepoznato';
      final iznos = (n['iznos'] as num?)?.toDouble() ?? 0;
      buf.writeln('  ${i + 1}. $putnikIme — ${iznos.toStringAsFixed(0)} din — $vreme');
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
    V3AppSnackBar.success(context, _DnevTr.tr('kopiranoUClipboard'));
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
    final rm = V3MasterRealtimeManager.instance;

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => [
          pw.Text('DNEVNIK VOZAČA', style: titleStyle),
          pw.SizedBox(height: 4),
          pw.Text('Vozač: $_selectedVozacIme', style: headerStyle),
          pw.Text('Datum: ${_formatDatum(_selectedDate)}', style: normalStyle),
          pw.SizedBox(height: 14),
          pw.Divider(),
          pw.SizedBox(height: 8),

          // Pokupljeni putnici
          if (_pokupio.isNotEmpty) ...[
            pw.Text('POKUPLJENI PUTNICI (${_pokupio.length})', style: headerStyle),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: const {
                0: pw.FixedColumnWidth(24),
                1: pw.FlexColumnWidth(4),
                2: pw.FixedColumnWidth(40),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _pdfCell('#', style: boldStyle),
                    _pdfCell('Ime', style: boldStyle),
                    _pdfCell('Vreme', style: boldStyle),
                  ],
                ),
                for (int i = 0; i < _pokupio.length; i++)
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: i.isEven ? PdfColors.white : PdfColors.grey50,
                    ),
                    children: [
                      _pdfCell('${i + 1}.', style: baseStyle),
                      _pdfCell(
                          (rm.putniciCache[_pokupio[i]['created_by']?.toString() ?? '']?['ime_prezime']?.toString() ??
                              'Nepoznato'),
                          style: baseStyle),
                      _pdfCell(
                          V3DanHelper.formatVreme(
                              (V3DateUtils.parseTs(_pokupio[i]['pokupljen_at']?.toString()) ?? DateTime.now()).hour,
                              (V3DateUtils.parseTs(_pokupio[i]['pokupljen_at']?.toString()) ?? DateTime.now()).minute),
                          style: baseStyle),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Divider(),
            pw.SizedBox(height: 8),
          ],

          // Dodati putnici
          if (_dodao.isNotEmpty) ...[
            pw.Text('DODATI PUTNICI (${_dodao.length})', style: headerStyle),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: const {
                0: pw.FixedColumnWidth(24),
                1: pw.FlexColumnWidth(4),
                2: pw.FixedColumnWidth(60),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _pdfCell('#', style: boldStyle),
                    _pdfCell('Ime', style: boldStyle),
                    _pdfCell('Termin', style: boldStyle),
                  ],
                ),
                for (int i = 0; i < _dodao.length; i++)
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: i.isEven ? PdfColors.white : PdfColors.grey50,
                    ),
                    children: [
                      _pdfCell('${i + 1}.', style: baseStyle),
                      _pdfCell(
                          (rm.putniciCache[_dodao[i]['created_by']?.toString() ?? '']?['ime_prezime']?.toString() ??
                              'Nepoznato'),
                          style: baseStyle),
                      _pdfCell(
                          '${(_dodao[i]['grad']?.toString() ?? '').trim().toUpperCase()} ${_dodao[i]['polazak_at']?.toString() ?? ''}',
                          style: baseStyle),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Divider(),
            pw.SizedBox(height: 8),
          ],

          // Otkazane vožnje
          if (_otkazao.isNotEmpty) ...[
            pw.Text('OTKAZANE VOŽNJE (${_otkazao.length})', style: headerStyle),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: const {
                0: pw.FixedColumnWidth(24),
                1: pw.FlexColumnWidth(4),
                2: pw.FixedColumnWidth(60),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _pdfCell('#', style: boldStyle),
                    _pdfCell('Ime', style: boldStyle),
                    _pdfCell('Termin', style: boldStyle),
                  ],
                ),
                for (int i = 0; i < _otkazao.length; i++)
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: i.isEven ? PdfColors.white : PdfColors.grey50,
                    ),
                    children: [
                      _pdfCell('${i + 1}.', style: baseStyle),
                      _pdfCell(
                          (rm.putniciCache[_otkazao[i]['putnik_v3_auth_id']?.toString() ?? '']?['ime_prezime']
                                  ?.toString() ??
                              'Nepoznato'),
                          style: baseStyle),
                      _pdfCell(
                          '${(_otkazao[i]['grad']?.toString() ?? '').trim().toUpperCase()} ${_otkazao[i]['vreme']?.toString() ?? ''}',
                          style: baseStyle),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Divider(),
            pw.SizedBox(height: 8),
          ],

          // Naplate
          pw.Text('NAPLATE (${_naplate.length})', style: headerStyle),
          pw.SizedBox(height: 6),
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
                    _pdfCell(
                        (rm.putniciCache[_naplate[i]['putnik_v3_auth_id']?.toString() ?? '']?['ime_prezime']
                                ?.toString() ??
                            _naplate[i]['naziv']?.toString() ??
                            'Nepoznato'),
                        style: baseStyle),
                    _pdfCell('${((_naplate[i]['iznos'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} din',
                        style: baseStyle),
                    _pdfCell(
                        V3DanHelper.formatVreme(
                            (V3DateUtils.parseTs(_naplate[i]['updated_at']?.toString()) ?? DateTime.now()).hour,
                            (V3DateUtils.parseTs(_naplate[i]['updated_at']?.toString()) ?? DateTime.now()).minute),
                        style: baseStyle),
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
      final file = File('${dir.path}/dnevnik_vozaca_${vozacStr}_$datumStr.pdf');
      await file.writeAsBytes(await doc.save());
      if (!mounted) return;
      await OpenFilex.open(file.path);
    } catch (e) {
      V3ErrorUtils.safeError(this, context, '${_DnevTr.tr('greskaPriIzvozuPdf')}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title:
            Text(_DnevTr.tr('dnevnikVozaca'), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        actions: [
          if (_naplate.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
              tooltip: _DnevTr.tr('sacuvajPdf'),
              onPressed: _exportPdf,
            ),
            IconButton(
              icon: const Icon(Icons.copy, color: Colors.white),
              tooltip: _DnevTr.tr('kopirajIzvestaj'),
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
                            hint: Text(_DnevTr.tr('vozacHint'), style: const TextStyle(color: Colors.white54)),
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
                                _pokupio = [];
                                _dodao = [];
                                _otkazao = [];
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
              if (_selectedVozacId != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: _StatsRow(
                    pokupljeno: _pokupio.length,
                    otkazano: _otkazao.length,
                    naplaceno: _naplate.length,
                    dodato: _dodao.length,
                  ),
                ),
              Expanded(
                child: _selectedVozacId == null
                    ? Center(
                        child: Text(
                          _DnevTr.tr('izaberiVozacaIDatum'),
                          style: const TextStyle(color: Colors.white54, fontSize: 16),
                        ),
                      )
                    : Column(
                        children: [
                          Expanded(
                            child: (_naplate.isEmpty && _pokupio.isEmpty && _dodao.isEmpty && _otkazao.isEmpty)
                                ? Center(
                                    child: Text(
                                      '${_DnevTr.tr('nemaAkcijaZa')} ${_formatDatum(_selectedDate)}',
                                      style: const TextStyle(color: Colors.white54, fontSize: 16),
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    itemCount: _dodao.length + _pokupio.length + _otkazao.length + _naplate.length,
                                    itemBuilder: (_, i) {
                                      if (i < _dodao.length) {
                                        return _DodaoCard(p: _dodao[i], index: i);
                                      }
                                      if (i < _dodao.length + _pokupio.length) {
                                        final pokupioIndex = i - _dodao.length;
                                        return _PokupioCard(p: _pokupio[pokupioIndex], index: pokupioIndex);
                                      }
                                      if (i < _dodao.length + _pokupio.length + _otkazao.length) {
                                        final otkazaoIndex = i - _dodao.length - _pokupio.length;
                                        return _OtkazaoCard(p: _otkazao[otkazaoIndex], index: otkazaoIndex);
                                      }
                                      final naplataIndex = i - _dodao.length - _pokupio.length - _otkazao.length;
                                      return _NaplataCard(n: _naplate[naplataIndex], index: naplataIndex);
                                    },
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

// ─── Widgets ──────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.pokupljeno,
    required this.otkazano,
    required this.naplaceno,
    required this.dodato,
  });

  final int pokupljeno;
  final int otkazano;
  final int naplaceno;
  final int dodato;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatChip(
            icon: '🚐',
            label: _DnevTr.tr('pokupljeni'),
            value: pokupljeno,
            color: Colors.blueAccent,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _StatChip(
            icon: '❌',
            label: _DnevTr.tr('otkazani'),
            value: otkazano,
            color: Colors.redAccent,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _StatChip(
            icon: '💰',
            label: _DnevTr.tr('naplaceno'),
            value: naplaceno,
            color: Colors.greenAccent,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _StatChip(
            icon: '➕',
            label: _DnevTr.tr('dodati'),
            value: dodato,
            color: Colors.orangeAccent,
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final String icon;
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Text('$icon $value', style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 10),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _PokupioCard extends StatelessWidget {
  const _PokupioCard({required this.p, required this.index});
  final Map<String, dynamic> p;
  final int index;

  @override
  Widget build(BuildContext context) {
    final pokupljenAt = V3DateUtils.parseTs(p['pokupljen_at']?.toString());
    final datum = pokupljenAt ?? V3DateUtils.parseTs(p['datum']?.toString()) ?? DateTime.now();
    final vreme = V3DanHelper.formatVreme(datum.hour, datum.minute);
    final putnikId = p['putnik_v3_auth_id']?.toString() ?? '';
    final rm = V3MasterRealtimeManager.instance;
    final putnik = rm.putniciCache[putnikId];
    final putnikIme = putnik?['ime_prezime']?.toString() ?? _DnevTr.tr('nepoznato');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('🚐', style: const TextStyle(color: Colors.white70, fontSize: 16)),
          ),
          Expanded(
            child:
                Text(putnikIme, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          Text(_DnevTr.tr('pokupio'),
              style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(width: 10),
          Text(vreme, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }
}

class _DodaoCard extends StatelessWidget {
  const _DodaoCard({required this.p, required this.index});
  final Map<String, dynamic> p;
  final int index;

  @override
  Widget build(BuildContext context) {
    final grad = (p['grad']?.toString() ?? '').trim().toUpperCase();
    final polazakAt = p['vreme']?.toString() ?? '';
    final putnikId = p['putnik_v3_auth_id']?.toString() ?? '';
    final rm = V3MasterRealtimeManager.instance;
    final putnik = rm.putniciCache[putnikId];
    final putnikIme = putnik?['ime_prezime']?.toString() ?? _DnevTr.tr('nepoznato');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('➕', style: const TextStyle(color: Colors.white70, fontSize: 16)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(putnikIme, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                if (grad.isNotEmpty)
                  Text('$grad $polazakAt', style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          Text(_DnevTr.tr('dodao'),
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _OtkazaoCard extends StatelessWidget {
  const _OtkazaoCard({required this.p, required this.index});
  final Map<String, dynamic> p;
  final int index;

  @override
  Widget build(BuildContext context) {
    final otkazanoAt = V3DateUtils.parseTs(p['otkazano_at']?.toString());
    final datum = otkazanoAt ?? V3DateUtils.parseTs(p['datum']?.toString()) ?? DateTime.now();
    final vreme = V3DanHelper.formatVreme(datum.hour, datum.minute);
    final grad = (p['grad']?.toString() ?? '').trim().toUpperCase();
    final polazakAt = p['vreme']?.toString() ?? '';
    final putnikId = p['putnik_v3_auth_id']?.toString() ?? '';
    final rm = V3MasterRealtimeManager.instance;
    final putnik = rm.putniciCache[putnikId];
    final putnikIme = putnik?['ime_prezime']?.toString() ?? _DnevTr.tr('nepoznato');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('❌', style: const TextStyle(color: Colors.white70, fontSize: 16)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(putnikIme, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                if (grad.isNotEmpty)
                  Text('$grad $polazakAt', style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          Text(_DnevTr.tr('otkazao'),
              style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(width: 10),
          Text(vreme, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }
}

class _NaplataCard extends StatelessWidget {
  const _NaplataCard({required this.n, required this.index});
  final Map<String, dynamic> n;
  final int index;

  @override
  Widget build(BuildContext context) {
    final datum = V3DateUtils.parseTs(n['updated_at']?.toString()) ?? DateTime.now();
    final vreme = V3DanHelper.formatVreme(datum.hour, datum.minute);
    final putnikId = n['putnik_v3_auth_id']?.toString() ?? '';
    final rm = V3MasterRealtimeManager.instance;
    final putnik = rm.putniciCache[putnikId];
    final putnikIme = putnik?['ime_prezime']?.toString() ?? n['naziv']?.toString() ?? _DnevTr.tr('nepoznato');
    final iznos = (n['iznos'] as num?)?.toDouble() ?? 0;
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
            child:
                Text(putnikIme, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          Text('${iznos.toStringAsFixed(0)} din',
              style: const TextStyle(color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(width: 10),
          Text(vreme, style: const TextStyle(color: Colors.white38, fontSize: 12)),
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
        V3AppSnackBar.warning(context, _DnevTr.tr('unesiteIznosPredajeVeciOd0'));
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
        V3AppSnackBar.success(context, _DnevTr.tr('predajaSacuvana'));
      }
    } catch (e) {
      V3ErrorUtils.safeError(this, context, '${_DnevTr.tr('greskaPriCuvanju')}: $e');
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
              Text(_DnevTr.tr('ukupnoNaplaceno'), style: const TextStyle(color: Colors.white70, fontSize: 14)),
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
              Text(_DnevTr.tr('predao'), style: const TextStyle(color: Colors.white70, fontSize: 14)),
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
                text: _sacuvan ? '✅' : _DnevTr.tr('sacuvaj'),
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
                  razlika >= 0 ? _DnevTr.tr('visak') : _DnevTr.tr('manjak'),
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
