import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../services/v3/v3_putnik_service.dart';
import '../../utils/v3_app_snack_bar.dart';

/// V3 servis za generisanje PDF spiska putnika za dati polazak.
class V3PrintingService {
  V3PrintingService._();

  static pw.Font get _regular => pw.Font.helvetica();
  static pw.Font get _bold => pw.Font.helveticaBold();

  // ─── Podaci o firmi ───────────────────────────────────────────────
  static const String _firmaIme = 'PR Limo Servis Gavra 013';
  static const String _firmaAdresa = 'Mihajla Pupina 74, 26340 Bela Crkva';
  static const String _firmaPIB = '102853497';
  static const String _firmaMB = '55572178';

  /// Generiše i otvara PDF spisak putnika za [datumIso]/[vreme]/[grad].
  static Future<void> printPutniksList({
    required String datumIso,
    required String dan,
    required String vreme,
    required String grad,
    required BuildContext context,
  }) async {
    try {
      // Putnici iz v3 cache-a za dati polazak
      final putnici = V3PutnikService.getKombinovaniPutniciByDatumGradVreme(
        datumIso: datumIso,
        grad: grad,
        vreme: vreme,
      );

      if (putnici.isEmpty) {
        if (context.mounted) {
          V3AppSnackBar.warning(
            context,
            '⚠️ Nema putnika za $dan - $vreme - $grad',
          );
        }
        return;
      }

      final pdfBytes = await _createSpisakPDF(
        putnici: putnici,
        dan: dan,
        vreme: vreme,
        grad: grad,
      );

      final tempDir = await getTemporaryDirectory();
      final fileName = 'Spisak_${dan}_${vreme}_${grad}_${DateFormat('dd_MM_yyyy').format(DateTime.now())}.pdf'
          .replaceAll(' ', '_')
          .replaceAll(':', '_');
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pdfBytes, flush: true);
      await OpenFilex.open(file.path);
    } catch (e) {
      if (context.mounted) {
        V3AppSnackBar.error(context, '❌ Greška pri štampanju: $e');
      }
    }
  }

  // ─── PDF - Spisak putnika ─────────────────────────────────────────
  static Future<List<int>> _createSpisakPDF({
    required List<Map<String, dynamic>> putnici,
    required String dan,
    required String vreme,
    required String grad,
  }) async {
    final pdf = pw.Document();

    final imeList = putnici.map((p) => p['ime_prezime']?.toString() ?? p['imePrezime']?.toString() ?? '---').toList()
      ..sort();

    final relacija = _relacija(grad, vreme);
    final danas = DateFormat('dd.MM.yyyy').format(DateTime.now());

    final theme = pw.ThemeData.withFont(
      base: _regular,
      bold: _bold,
      italic: _regular,
      boldItalic: _bold,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        theme: theme,
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Zaglavlje
              pw.Center(
                child: pw.Text(
                  'Limo servis "Gavra 013"',
                  style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(
                  'PIB: $_firmaPIB; MB: $_firmaMB',
                  style: const pw.TextStyle(fontSize: 12),
                ),
              ),
              pw.SizedBox(height: 40),

              // Podaci o vožnji
              _infoRow('Datum:', danas),
              pw.SizedBox(height: 8),
              _infoRow('Naručilac:', '______________________'),
              pw.SizedBox(height: 8),
              _infoRow('Relacija:', relacija),
              pw.SizedBox(height: 8),
              _infoRow('Vreme polaska:', vreme),
              pw.SizedBox(height: 8),
              _infoRow('Cena:', '______________________'),
              pw.SizedBox(height: 40),

              // Naslov spiska
              pw.Center(
                child: pw.Text(
                  'SPISAK PUTNIKA',
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 20),

              // Lista putnika (min 8 redova)
              ...List.generate(
                imeList.length > 8 ? imeList.length : 8,
                (index) {
                  final ime = index < imeList.length ? imeList[index] : '_____________________________________';
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 6),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.SizedBox(
                          width: 30,
                          child: pw.Text('${index + 1}.', style: const pw.TextStyle(fontSize: 12)),
                        ),
                        pw.Expanded(
                          child: pw.Container(
                            decoration: const pw.BoxDecoration(
                              border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
                            ),
                            child: pw.Text(ime, style: const pw.TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              pw.Spacer(),

              // Potpisi
              pw.Row(
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
                  // Pečat
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
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static String _relacija(String grad, String vreme) {
    final g = grad.toUpperCase();
    if (g == 'BC') return 'Bela Crkva - Vrsac';
    if (g == 'VS') return 'Vrsac - Bela Crkva';
    return '$grad - ______';
  }

  static pw.Widget _infoRow(String label, String value) {
    return pw.Row(
      children: [
        pw.SizedBox(
          width: 120,
          child: pw.Text(label, style: const pw.TextStyle(fontSize: 12)),
        ),
        pw.Text(value, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }
}
