import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../utils/v3_app_snack_bar.dart';
import 'repositories/v3_racun_repository.dart';

/// V3 servis za generisanje PDF računa.
class V3RacunService {
  V3RacunService._();

  static final V3RacunRepository _repository = V3RacunRepository();

  // ─── Podaci o firmi ───────────────────────────────────────────────
  static const String _firmaIme = 'PR Limo Servis Gavra 013';
  static const String _firmaAdresa = 'Mihajla Pupina 74, 26340 Bela Crkva';
  static const String _firmaPIB = '102853497';
  static const String _firmaMB = '55572178';
  static const String _firmaTekuciRacun = '340-11436537-92';
  static const String _firmaVlasnik = 'Bojan Gavrilović';
  static const String _firmaTel = '064/116-2560';

  static const String _napomenaPDV = 'Poreski obveznik nije u sistemu PDV-a';
  static const String _napomenaValidnost =
      'Račun je punovažan bez pečata i potpisa u skladu sa Zakonom o privrednim društvima';

  static final PdfColor _navyBlue = PdfColors.black;

  static pw.Font? _regularFont;
  static pw.Font? _boldFont;

  static Future<void> _ensureFonts() async {
    if (_regularFont != null) return;
    final regData = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    _regularFont = pw.Font.ttf(regData);
    _boldFont = pw.Font.ttf(boldData);
  }

  static pw.Font get _regular => _regularFont ?? pw.Font.helvetica();
  static pw.Font get _bold => _boldFont ?? pw.Font.helveticaBold();

  static pw.MemoryImage? _logoImage;

  static Future<void> _ensureAssets() async {
    await _ensureFonts();
    if (_logoImage == null) {
      try {
        final imgData = await rootBundle.load('assets/logo_transparent.png');
        _logoImage = pw.MemoryImage(imgData.buffer.asUint8List());
      } catch (_) {}
    }
  }

  // ─── Sekvenca broja računa ────────────────────────────────────────
  /// Vraća sledeći broj računa u formatu `X/YYYY`.
  /// Koristi max(redni_broj) iz v3_racuni za tekuću godinu.
  static Future<String> getNextBrojRacuna() async {
    final godina = DateTime.now().year;
    try {
      final rows = await _repository.listRedniBrojByGodinaDescLimit1(godina);

      final maxBroj = (rows).isNotEmpty ? ((rows.first['redni_broj'] as int?) ?? 0) : 0;
      return '${maxBroj + 1}/$godina';
    } catch (e) {
      final ts = DateTime.now().millisecondsSinceEpoch;
      return 'T$ts/$godina';
    }
  }

  // ─── Račun za fizičko lice ────────────────────────────────────────
  static Future<void> stampajRacun({
    required String brojRacuna,
    required String imePrezimeKupca,
    required String adresaKupca,
    required String opisUsluge,
    required double cena,
    required double kolicina,
    required String jedinicaMere,
    required DateTime datumPrometa,
    required BuildContext context,
  }) async {
    try {
      await _ensureAssets();
      final pdfBytes = await _kreirajUnifiedRacun(
        brojRacuna: brojRacuna,
        kupacNaziv: imePrezimeKupca,
        kupacAdresa: adresaKupca,
        kupacPib: '', // Fizičko lice nema PIB
        opisUsluge: opisUsluge,
        cena: cena,
        kolicina: kolicina,
        jedinicaMere: jedinicaMere,
        datumPrometa: datumPrometa,
        datumIzdavanja: DateTime.now(),
      );
      await _openPDF(pdfBytes, 'Racun_$brojRacuna'.replaceAll('/', '_'));
    } catch (e) {
      if (context.mounted) {
        V3AppSnackBar.error(context, '❌ Greška pri štampanju računa: $e');
      }
    }
  }

  // ─── Računi za firme (B2B) ────────────────────────────────────────
  static Future<void> stampajRacuneZaFirme({
    required List<Map<String, dynamic>> racuniPodaci,
    required BuildContext context,
    required DateTime datumPrometa,
  }) async {
    if (racuniPodaci.isEmpty) {
      if (context.mounted) {
        V3AppSnackBar.warning(context, '⚠️ Nema odabranih putnika za fakturu');
      }
      return;
    }
    try {
      await _ensureAssets();
      final pdf = pw.Document();
      final theme = pw.ThemeData.withFont(
        base: _regular,
        bold: _bold,
        italic: _regular,
        boldItalic: _bold,
      );

      for (final r in racuniPodaci) {
        final imePutnika = r['ime_prezime']?.toString() ?? '---';
        final brojVoznji = (r['broj_voznji'] as num?)?.toDouble() ?? 1.0;
        final cenaPoVoznji = (r['cena_po_voznji'] as num?)?.toDouble() ?? 0.0;
        final brojRacuna = r['broj_racuna']?.toString() ?? await getNextBrojRacuna();

        final firmaNaziv = r['firma_naziv']?.toString() ?? imePutnika;
        final firmaAdresa = r['firma_adresa']?.toString() ?? '---';
        final firmaPib = r['firma_pib']?.toString() ?? '';

        final opis = 'Prevoz putnika na relaciji $imePutnika';

        pdf.addPage(
          _buildEFakturaStranica(
            theme: theme,
            brojRacuna: brojRacuna,
            datumIzdavanja: DateTime.now(),
            datumPrometa: datumPrometa,
            kupacNaziv: firmaNaziv,
            kupacAdresa: firmaAdresa,
            kupacPib: firmaPib,
            opisUsluge: opis,
            kolicina: brojVoznji,
            jedMere: 'dan',
            cena: cenaPoVoznji,
          ),
        );
      }

      final pdfBytes = await pdf.save();
      final mesec = DateFormat('MM_yyyy').format(datumPrometa);
      await _openPDF(pdfBytes, 'Racuni_firme_$mesec');
    } catch (e) {
      if (context.mounted) {
        V3AppSnackBar.error(context, '❌ Greška pri štampanju: $e');
      }
    }
  }

  // ─── UNIFIED EFaktura PDF ─────────────────────────────────────────

  static Future<List<int>> _kreirajUnifiedRacun({
    required String brojRacuna,
    required String kupacNaziv,
    required String kupacAdresa,
    required String kupacPib,
    required String opisUsluge,
    required double cena,
    required double kolicina,
    required String jedinicaMere,
    required DateTime datumPrometa,
    required DateTime datumIzdavanja,
  }) async {
    final pdf = pw.Document();
    final theme = pw.ThemeData.withFont(
      base: _regular,
      bold: _bold,
      italic: _regular,
      boldItalic: _bold,
    );
    pdf.addPage(
      _buildEFakturaStranica(
        theme: theme,
        brojRacuna: brojRacuna,
        datumIzdavanja: datumIzdavanja,
        datumPrometa: datumPrometa,
        kupacNaziv: kupacNaziv,
        kupacAdresa: kupacAdresa,
        kupacPib: kupacPib,
        opisUsluge: opisUsluge,
        kolicina: kolicina,
        jedMere: jedinicaMere,
        cena: cena,
      ),
    );
    return pdf.save();
  }

  static pw.Page _buildEFakturaStranica({
    required pw.ThemeData theme,
    required String brojRacuna,
    required DateTime datumIzdavanja,
    required DateTime datumPrometa,
    required String kupacNaziv,
    required String kupacAdresa,
    required String kupacPib,
    required String opisUsluge,
    required double kolicina,
    required String jedMere,
    required double cena,
  }) {
    final ukupno = cena * kolicina;
    final formatter = NumberFormat("#,##0.00", "sr_RS");
    final ukStr = formatter.format(ukupno);
    final datumIzdavanjaStr = DateFormat('dd.MM.yyyy.').format(datumIzdavanja);
    final datumPrometaStr = DateFormat('dd.MM.yyyy.').format(datumPrometa);

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: theme,
      build: (pw.Context ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // HEADING: LOGO + DESNI INFO
            pw.Container(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(width: 2)),
                ),
                padding: const pw.EdgeInsets.only(bottom: 10),
                child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      if (_logoImage != null)
                        pw.Image(_logoImage!, width: 120)
                      else
                        pw.Container(
                            width: 120,
                            height: 50,
                            decoration: pw.BoxDecoration(border: pw.Border.all()),
                            child: pw.Center(
                                child: pw.Text('LOGO',
                                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, letterSpacing: 2)))),
                      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                        pw.Row(children: [
                          pw.Text('Br. računa: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          pw.Text(brojRacuna)
                        ]),
                        pw.Row(children: [
                          pw.Text('Datum izdavanja: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          pw.Text(datumIzdavanjaStr)
                        ]),
                        pw.Row(children: [
                          pw.Text('Datum prometa: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          pw.Text(datumPrometaStr)
                        ]),
                        pw.Row(children: [
                          pw.Text('Mesto: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          pw.Text('Bela Crkva')
                        ]),
                      ])
                    ])),
            pw.SizedBox(height: 15),

            // INFO FIRMA + INFO KUPAC
            pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text(_firmaIme, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                    pw.Text(_firmaAdresa),
                    pw.Text('Vlasnik: $_firmaVlasnik'),
                    pw.Text('PIB: $_firmaPIB | MB: $_firmaMB'),
                    pw.Text('Tekući račun: $_firmaTekuciRacun'),
                    pw.Text('Tel: $_firmaTel'),
                  ]),
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text('Kupac:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text(kupacNaziv),
                    pw.Text(kupacAdresa),
                    if (kupacPib.isNotEmpty) pw.Text('PIB: $kupacPib'),
                  ])
                ]),
            pw.SizedBox(height: 30),

            // EFAKTURA TABLE (9 kolona)
            pw.Table(border: pw.TableBorder.all(width: 0.5), columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(1.2),
              4: const pw.FlexColumnWidth(1),
              5: const pw.FlexColumnWidth(1.4),
              6: const pw.FlexColumnWidth(0.8),
              7: const pw.FlexColumnWidth(1),
              8: const pw.FlexColumnWidth(1.2),
            }, children: [
              pw.TableRow(children: [
                _thCell('Naziv', align: pw.TextAlign.left),
                _thCell('Količina'),
                _thCell('Jedinica\nmere'),
                _thCell('Cena'),
                _thCell('Iznos\numanjenja'),
                _thCell('Iznos bez PDV'),
                _thCell('PDV %'),
                _thCell('PDV\nkategorija'),
                _thCell('Identifikator\nklasifikacije\nstavke'),
              ]),
              pw.TableRow(children: [
                _tdCell(opisUsluge, align: pw.TextAlign.left),
                _tdCell(kolicina.toStringAsFixed(0)), // ili formatDecimal
                _tdCell(jedMere),
                _tdCell(formatter.format(cena)),
                _tdCell('0,00'),
                _tdCell(ukStr),
                _tdCell('0'),
                _tdCell('SS'),
                _tdCell(''),
              ]),
            ]),
            pw.SizedBox(height: 30),

            // SUMMARY BLOCK RIGHT
            pw.Row(children: [
              pw.Spacer(flex: 2),
              pw.Expanded(
                  flex: 3,
                  child: pw.Table(children: [
                    _summaryRow('Zbir stavki - posebni postupci oporezivanja', ukStr),
                    _summaryRow('Ukupna naknada - posebni postupci oporezivanja', ukStr),
                    _summaryRow(
                        'Umanjen iznos naknade za iznos naknade po avansu - posebni postupci oporezivanja', ukStr),
                    _summaryRow('Iznos za zaokruživanje', '0,00'),
                    _summaryRow('Iznos za plaćanje', ukStr, bold: true, size: 12, paddingT: 10),
                  ]))
            ]),
            pw.Spacer(),

            // FOOTER NAPOMENA
            pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.only(top: 10),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(top: pw.BorderSide(width: 1)),
                ),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                  pw.Text('Poreski obveznik nije u sistemu PDV-a.', style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 10),
                  pw.Text('Shodno čl. 9. Zakona o računovodstvu i čl. 71. Zakona o privrednim društvima:',
                      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Račun je punovažan bez pečata i potpisa.',
                      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                ]))
          ],
        );
      },
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────
  static pw.Widget _thCell(String text, {pw.TextAlign align = pw.TextAlign.center}) {
    return pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(text, textAlign: align, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)));
  }

  static pw.Widget _tdCell(String text, {pw.TextAlign align = pw.TextAlign.center}) {
    return pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(text, textAlign: align, style: const pw.TextStyle(fontSize: 8)));
  }

  static pw.TableRow _summaryRow(String label, String value,
      {bool bold = false, double size = 9, double paddingT = 8}) {
    return pw.TableRow(
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
        children: [
          pw.Padding(
              padding: pw.EdgeInsets.only(top: paddingT, bottom: 8, right: 6),
              child: pw.Text(label,
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal))),
          pw.Padding(
              padding: pw.EdgeInsets.only(top: paddingT, bottom: 8, left: 6),
              child: pw.Text(value,
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal))),
        ]);
  }

  static Future<void> _openPDF(List<int> bytes, String name) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/${name}_${DateFormat('ddMMyyyy').format(DateTime.now())}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    await OpenFilex.open(file.path);
  }
}
