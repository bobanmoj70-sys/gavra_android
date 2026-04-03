import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../utils/v3_app_snack_bar.dart';
import '../../utils/v3_dan_helper.dart';
import '../../utils/v3_format_utils.dart';
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
  static const String _firmaEmail = 'gavriconi19@gmail.com';

  static const String _napomenaPDV = 'Poreski obveznik nije u sistemu PDV-a';
  static const String _napomenaValidnost =
      'Račun je punovažan bez pečata i potpisa u skladu sa Zakonom o privrednim društvima';

  static final PdfColor _navyBlue = PdfColors.black;

  static pw.Font get _regular => pw.Font.helvetica();
  static pw.Font get _bold => pw.Font.helveticaBold();

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
      final pdfBytes = await _kreirajRacunPDF(
        brojRacuna: brojRacuna,
        imePrezimeKupca: imePrezimeKupca,
        adresaKupca: adresaKupca,
        opisUsluge: opisUsluge,
        cena: cena,
        kolicina: kolicina,
        jedinicaMere: jedinicaMere,
        datumPrometa: datumPrometa,
      );
      await _openPDF(pdfBytes, 'Racun_$brojRacuna'.replaceAll('/', '_'));
    } catch (e) {
      if (context.mounted) {
        V3AppSnackBar.error(context, '❌ Greška pri štampanju računa: $e');
      }
    }
  }

  // ─── Računi za firme (B2B) ────────────────────────────────────────
  /// [racuniPodaci] = lista mapa s putnik_id, ime_prezime, broj_vožnji, cena_po_voznji
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
      // Dohvati firma podatke iz Supabase za sve putnik_id-ove
      final ids = racuniPodaci.map((r) => r['putnik_id']).toList();
      final firme = await _repository.listAktivneFirmeByPutnikIds(ids);
      final firmaMap = <String, Map<String, dynamic>>{};
      for (final f in firme) {
        firmaMap[f['putnik_id'].toString()] = f as Map<String, dynamic>;
      }

      final pdf = pw.Document();
      final theme = pw.ThemeData.withFont(
        base: _regular,
        bold: _bold,
        italic: _regular,
        boldItalic: _bold,
      );

      for (final r in racuniPodaci) {
        final putnikId = r['putnik_id'].toString();
        final firma = firmaMap[putnikId];
        final imePutnika = r['ime_prezime']?.toString() ?? '---';
        final brojVoznji = (r['broj_voznji'] as num?)?.toDouble() ?? 1.0;
        final cenaPoVoznji = (r['cena_po_voznji'] as num?)?.toDouble() ?? 0.0;
        final brojRacuna = r['broj_racuna']?.toString() ?? await getNextBrojRacuna();

        pdf.addPage(
          _kreirajRacunZaFirmuStranicu(
            theme: theme,
            brojRacuna: brojRacuna,
            imePutnika: imePutnika,
            firma: firma,
            brojVoznji: brojVoznji,
            cenaPoVoznji: cenaPoVoznji,
            datumPrometa: datumPrometa,
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

  // ─── PDF - Račun za fizičko lice ──────────────────────────────────
  static Future<List<int>> _kreirajRacunPDF({
    required String brojRacuna,
    required String imePrezimeKupca,
    required String adresaKupca,
    required String opisUsluge,
    required double cena,
    required double kolicina,
    required String jedinicaMere,
    required DateTime datumPrometa,
  }) async {
    final pdf = pw.Document();
    final theme = pw.ThemeData.withFont(
      base: _regular,
      bold: _bold,
      italic: _regular,
      boldItalic: _bold,
    );
    final ukupno = cena * kolicina;
    // Datum prometa fiksiran na 31.03.tekuće godine
    final datumPrometaFiksni = DateTime(DateTime.now().year, 3, 31);
    final datumStr = DateFormat('dd.MM.yyyy.').format(datumPrometaFiksni);
    final danasDatumStr = DateFormat('dd.MM.yyyy.').format(DateTime.now());
    const kolicinaMart = 22.0; // Fiksno za mart 2026.
    final ukupnoMart = cena * kolicinaMart;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: theme,
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // 1. TOP HEADER (Naziv firme i Racun br)
              // ... existing code ...
              // 3. TABLE
              pw.Table(
                columnWidths: const {
                  0: pw.FixedColumnWidth(25),
                  1: pw.FlexColumnWidth(),
                  2: pw.FixedColumnWidth(40),
                  3: pw.FixedColumnWidth(40),
                  4: pw.FixedColumnWidth(70),
                  5: pw.FixedColumnWidth(80),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide(width: 1.5)),
                    ),
                    children: [
                      _tCell('#', color: PdfColors.black, bold: true),
                      _tCell('Opis usluge', color: PdfColors.black, bold: true),
                      _tCell('Jed. mera', color: PdfColors.black, bold: true, align: pw.TextAlign.center),
                      _tCell('Kol.', color: PdfColors.black, bold: true, align: pw.TextAlign.center),
                      _tCell('Cena/jed.', color: PdfColors.black, bold: true, align: pw.TextAlign.right),
                      _tCell('Ukupno', color: PdfColors.black, bold: true, align: pw.TextAlign.right),
                    ],
                  ),
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide(width: 0.5, color: PdfColors.grey300)),
                    ),
                    children: [
                      _tCell('1.', align: pw.TextAlign.center),
                      _tCell('Prevoz putnika - mart 2026.'),
                      _tCell(jedinicaMere, align: pw.TextAlign.center),
                      _tCell(V3FormatUtils.formatDecimal2(kolicinaMart), align: pw.TextAlign.center),
                      _tCell(V3FormatUtils.formatNovacRsd(cena), align: pw.TextAlign.right),
                      _tCell(V3FormatUtils.formatNovacRsd(ukupnoMart), align: pw.TextAlign.right),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 10),

              // 4. TOTALS
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  _totalRow('Ukupno bez PDV-a:', V3FormatUtils.formatNovacRsd(ukupnoMart)),
                  _totalRow('PDV (nije u sistemu PDV-a):', '0,00 RSD'),
                ],
              ),
              pw.SizedBox(height: 15),

              // 5. ZA UPLATU BAR
              pw.Container(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    top: pw.BorderSide(width: 1.5),
                    bottom: pw.BorderSide(width: 1.5),
                  ),
                ),
                padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 10),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('ZA UPLATU:',
                        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(V3FormatUtils.formatNovac(ukupnoMart),
                            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                        pw.Text('RSD', style: pw.TextStyle(fontSize: 10, color: PdfColors.black)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 30),

              // 6. NAPOMENE BOX
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey200),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Napomene:',
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _navyBlue)),
                    pw.SizedBox(height: 4),
                    _napomenaItem(_napomenaPDV),
                    _napomenaItem(_napomenaValidnost),
                    _napomenaItem('Način plaćanja: Gotovina ili uplata na tekući račun'),
                    _napomenaItem('Uplata na žiro račun: $_firmaTekuciRacun, poziv na broj: $brojRacuna'),
                  ],
                ),
              ),
              pw.Spacer(),

              // 7. FOOTER SIGNATURE
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  children: [
                    pw.Container(
                      width: 180,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
                      ),
                      child: pw.SizedBox(height: 30),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text('$_firmaVlasnik, vlasnik', style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  // ─── PDF - Stranica za jednu firmu (B2B) ─────────────────────────
  static pw.Page _kreirajRacunZaFirmuStranicu({
    required pw.ThemeData theme,
    required String brojRacuna,
    required String imePutnika,
    required Map<String, dynamic>? firma,
    required double brojVoznji,
    required double cenaPoVoznji,
    required DateTime datumPrometa,
  }) {
    final ukupno = cenaPoVoznji * brojVoznji;
    final mesecGodina = DateFormat('MMMM yyyy', 'sr_Latn_RS').format(datumPrometa);
    final danasDatumStr = V3DanHelper.formatDatumPuni(DateTime.now());
    final datumStr = V3DanHelper.formatDatumPuni(datumPrometa);

    final firmaNaziv = firma?['firma_naziv']?.toString() ?? imePutnika;
    final firmaAdresa = firma?['firma_adresa']?.toString() ?? '---';
    final firmaPib = firma?['firma_pib']?.toString() ?? '';
    final firmaMb = firma?['firma_mb']?.toString() ?? '';
    final firmaZiro = firma?['firma_ziro']?.toString() ?? '';

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      theme: theme,
      build: (pw.Context ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // IZDAVALAC
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('IZDAVALAC:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Text(_firmaIme, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  pw.Text(_firmaAdresa, style: const pw.TextStyle(fontSize: 10)),
                  pw.Text('PIB: $_firmaPIB   MB: $_firmaMB', style: const pw.TextStyle(fontSize: 10)),
                  pw.Text('Tekući račun: $_firmaTekuciRacun', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Naslov
            pw.Center(
              child: pw.Text(
                'RAČUN br. $brojRacuna',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                'Datum: $danasDatumStr   za mesec: $mesecGodina',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
            pw.SizedBox(height: 16),

            // KUPAC (firma)
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('KUPAC:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Text(firmaNaziv, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  pw.Text(firmaAdresa, style: const pw.TextStyle(fontSize: 10)),
                  if (firmaPib.isNotEmpty)
                    pw.Text('PIB: $firmaPib   MB: $firmaMb', style: const pw.TextStyle(fontSize: 10)),
                  if (firmaZiro.isNotEmpty) pw.Text('Žiro: $firmaZiro', style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 4),
                  pw.Text('Putnik: $imePutnika', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            pw.SizedBox(height: 24),

            // Tabela
            pw.Table(
              border: pw.TableBorder.all(width: 0.5),
              columnWidths: const {
                0: pw.FixedColumnWidth(30),
                1: pw.FlexColumnWidth(),
                2: pw.FixedColumnWidth(50),
                3: pw.FixedColumnWidth(60),
                4: pw.FixedColumnWidth(80),
                5: pw.FixedColumnWidth(80),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _tCell('R.br', bold: true),
                    _tCell('Opis usluge', bold: true),
                    _tCell('Jed', bold: true),
                    _tCell('Dana', bold: true),
                    _tCell('Cena/dan', bold: true),
                    _tCell('Iznos', bold: true),
                  ],
                ),
                pw.TableRow(children: [
                  _tCell('1'),
                  _tCell('Prevoz putnika - $mesecGodina'),
                  _tCell('dan'),
                  _tCell(V3FormatUtils.formatDecimal2(brojVoznji)),
                  _tCell(V3FormatUtils.formatNovacRsd(cenaPoVoznji)),
                  _tCell(V3FormatUtils.formatNovacRsd(ukupno)),
                ]),
              ],
            ),
            pw.SizedBox(height: 8),

            // Ukupno
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
                child: pw.Text(
                  'UKUPNO: ${V3FormatUtils.formatNovacRsd(ukupno)}',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                ),
              ),
            ),
            pw.SizedBox(height: 24),

            pw.Text(_napomenaPDV, style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 4),
            pw.Text(_napomenaValidnost, style: const pw.TextStyle(fontSize: 9)),
            pw.Spacer(),

            _potpisRow(),
          ],
        );
      },
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────
  static pw.Widget _tCell(String text, {bool bold = false, PdfColor? color, pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  static pw.Widget _totalRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.SizedBox(width: 10),
          pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  static pw.Widget _napomenaItem(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('• ', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.Expanded(
            child: pw.Text(text, style: const pw.TextStyle(fontSize: 9)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _potpisRow() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(children: [
          pw.Container(
            width: 120,
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
            ),
            child: pw.SizedBox(height: 40),
          ),
          pw.SizedBox(height: 4),
          pw.Text('Potpis narucioca', style: const pw.TextStyle(fontSize: 10)),
        ]),
        pw.Container(
          width: 80,
          height: 80,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.blue, width: 2),
            borderRadius: pw.BorderRadius.circular(40),
          ),
          child: pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text('Bojan Gavrilovic',
                    style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold, color: PdfColors.blue),
                    textAlign: pw.TextAlign.center),
                pw.Text('LIMO', style: pw.TextStyle(fontSize: 5, color: PdfColors.blue)),
                pw.Text('GAVRA 013',
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.blue)),
                pw.Text('Bela Crkva', style: pw.TextStyle(fontSize: 6, color: PdfColors.blue)),
              ],
            ),
          ),
        ),
        pw.Column(children: [
          pw.Container(
            width: 120,
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
            ),
            child: pw.SizedBox(height: 40),
          ),
          pw.SizedBox(height: 4),
          pw.Text('Potpis prevoznika', style: const pw.TextStyle(fontSize: 10)),
        ]),
      ],
    );
  }

  static Future<void> _openPDF(List<int> bytes, String name) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/${name}_${DateFormat('ddMMyyyy').format(DateTime.now())}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    await OpenFilex.open(file.path);
  }
}
