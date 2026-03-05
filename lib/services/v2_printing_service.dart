import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/v2_putnik.dart';
import '../services/v2_polasci_service.dart';
import '../utils/v2_app_snack_bar.dart';
import '../utils/v2_dan_utils.dart';
import '../utils/v2_grad_adresa_validator.dart';
import '../utils/v2_text_utils.dart';

class V2PrintingService {
  V2PrintingService._();

  // ========== FONTOVI SA PODRS KOM ZA SRPSKA SLOVA ==========
  static pw.Font get regularFont => pw.Font.helvetica();
  static pw.Font get boldFont => pw.Font.helveticaBold();

  static Future<void> printPutniksList(
    String selectedDay,
    String selectedVreme,
    String selectedGrad,
    BuildContext context,
  ) async {
    try {
      List<V2Putnik> sviPutnici = await V2PutnikStreamService()
          .streamKombinovaniPutniciFiltered(
            dan: V2DanUtils.odPunogNaziva(selectedDay),
            grad: selectedGrad,
            vreme: selectedVreme,
          )
          .first;

      final danBaza = V2DanUtils.odPunogNaziva(selectedDay);

      List<V2Putnik> putnici = sviPutnici.where((v2Putnik) {
        final normalizedStatus = V2TextUtils.normalizeText(v2Putnik.status ?? '');

        if (v2Putnik.isRadnik || v2Putnik.isUcenik) {
          final normalizedPutnikGrad = V2TextUtils.normalizeText(v2Putnik.grad);
          final normalizedGrad = V2TextUtils.normalizeText(selectedGrad);
          final odgovarajuciGrad =
              normalizedPutnikGrad.contains(normalizedGrad) || normalizedGrad.contains(normalizedPutnikGrad);

          final putnikPolazak = v2Putnik.polazak.toString().trim();
          final selectedVremeStr = selectedVreme.trim();
          final odgovarajuciPolazak = V2GradAdresaValidator.normalizeTime(putnikPolazak) ==
                  V2GradAdresaValidator.normalizeTime(selectedVremeStr) ||
              V2GradAdresaValidator.normalizeTime(putnikPolazak)
                  .startsWith(V2GradAdresaValidator.normalizeTime(selectedVremeStr));

          final odgovarajuciDan = v2Putnik.dan.toLowerCase().contains(danBaza.toLowerCase());

          final result = odgovarajuciGrad && odgovarajuciPolazak && odgovarajuciDan && normalizedStatus != 'obrisan';

          return result;
        } else {
          final normalizedPutnikGrad = V2TextUtils.normalizeText(v2Putnik.grad);
          final normalizedGrad = V2TextUtils.normalizeText(selectedGrad);
          final gradMatch =
              normalizedPutnikGrad.contains(normalizedGrad) || normalizedGrad.contains(normalizedPutnikGrad);

          final odgovara = gradMatch &&
              V2GradAdresaValidator.normalizeTime(v2Putnik.polazak) ==
                  V2GradAdresaValidator.normalizeTime(selectedVreme) &&
              v2Putnik.dan.toLowerCase().contains(danBaza.toLowerCase()) &&
              normalizedStatus != 'obrisan';

          return odgovara;
        }
      }).toList();

      if (putnici.isEmpty) {
        if (context.mounted) {
          V2AppSnackBar.warning(
            context,
            '⚠️ Nema putnika za $selectedDay - $selectedVreme - $selectedGrad',
          );
        }
        return;
      }

      // Fonts loaded automatically via getters

      final pdf = await _createPutniksPDF(
        putnici,
        selectedDay,
        selectedVreme,
        selectedGrad,
      );

      final bytes = pdf;
      final tempDir = await getTemporaryDirectory();
      final fileName =
          'Spisak_putnika_${selectedDay}_${selectedVreme}_${selectedGrad}_${DateFormat('dd_MM_yyyy').format(DateTime.now())}.pdf'
              .replaceAll(' ', '_');
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);

      await OpenFilex.open(file.path);
    } catch (e) {
      if (context.mounted) {
        V2AppSnackBar.error(context, '❌ Greška pri štampanju: $e');
      }
    }
  }

  static Future<Uint8List> _createPutniksPDF(
    List<V2Putnik> putnici,
    String selectedDay,
    String selectedVreme,
    String selectedGrad,
  ) async {
    final pdf = pw.Document();

    putnici.sort((a, b) => a.ime.compareTo(b.ime));

    String relacija = _odredjiRelaciju(selectedGrad, selectedVreme);

    final danas = DateFormat('dd.MM.yyyy').format(DateTime.now());

    final theme = pw.ThemeData.withFont(
      base: regularFont,
      bold: boldFont,
      italic: regularFont,
      boldItalic: boldFont,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        theme: theme,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ========== ZAGLAVLJE ==========
              pw.Center(
                child: pw.Text(
                  'Limo servis "Gavra 013"',
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(
                  'PIB: 102853497; MB: 55572178',
                  style: const pw.TextStyle(fontSize: 12),
                ),
              ),

              pw.SizedBox(height: 40),

              // ========== PODACI O VOZNJI ==========
              _buildInfoRow('Datum:', danas),
              pw.SizedBox(height: 8),
              _buildInfoRow('Narucilac:', '______________________'),
              pw.SizedBox(height: 8),
              _buildInfoRow('Relacija:', relacija),
              pw.SizedBox(height: 8),
              _buildInfoRow('Vreme polaska:', selectedVreme),
              pw.SizedBox(height: 8),
              _buildInfoRow('Cena:', '______________________'),

              pw.SizedBox(height: 40),

              // ========== SPISAK PUTNIKA NASLOV ==========
              pw.Center(
                child: pw.Text(
                  'SPISAK PUTNIKA',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),

              pw.SizedBox(height: 20),

              // ========== LISTA PUTNIKA (1-8 + dodatni ako ima više) ==========
              ...List.generate(
                putnici.length > 8 ? putnici.length : 8,
                (index) {
                  final broj = index + 1;
                  final imePutnika =
                      index < putnici.length ? putnici[index].ime : '______________________________________';
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 6),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.SizedBox(
                          width: 30,
                          child: pw.Text(
                            '$broj.',
                            style: const pw.TextStyle(fontSize: 12),
                          ),
                        ),
                        pw.Expanded(
                          child: pw.Container(
                            decoration: const pw.BoxDecoration(
                              border: pw.Border(
                                bottom: pw.BorderSide(width: 0.5),
                              ),
                            ),
                            child: pw.Text(
                              imePutnika,
                              style: const pw.TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              pw.Spacer(),

              // ========== POTPISI NA DNU ==========
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  // Potpis narucioca
                  pw.Column(
                    children: [
                      pw.Container(
                        width: 120,
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(
                            bottom: pw.BorderSide(width: 0.5),
                          ),
                        ),
                        child: pw.SizedBox(height: 40),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Potpis narucioca',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ],
                  ),

                  // Pecat (sredina)
                  pw.Container(
                    width: 80,
                    height: 80,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: PdfColors.blue,
                        width: 2,
                      ),
                      borderRadius: pw.BorderRadius.circular(40),
                    ),
                    child: pw.Center(
                      child: pw.Column(
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: [
                          pw.Text(
                            'Bojan Gavrilovic',
                            style: pw.TextStyle(
                              fontSize: 6,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blue,
                            ),
                            textAlign: pw.TextAlign.center,
                          ),
                          pw.Text(
                            'LIMO',
                            style: pw.TextStyle(
                              fontSize: 5,
                              color: PdfColors.blue,
                            ),
                          ),
                          pw.Text(
                            'GAVRA 013',
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blue,
                            ),
                          ),
                          pw.Text(
                            'Bela Crkva',
                            style: pw.TextStyle(
                              fontSize: 6,
                              color: PdfColors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Potpis prevoznika
                  pw.Column(
                    children: [
                      pw.Container(
                        width: 120,
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(
                            bottom: pw.BorderSide(width: 0.5),
                          ),
                        ),
                        child: pw.SizedBox(height: 40),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Potpis prevoznika',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static String _odredjiRelaciju(String grad, String vreme) {
    if (V2GradAdresaValidator.isBelaCrkva(grad)) {
      return 'Bela Crkva - Vrsac';
    } else if (V2GradAdresaValidator.isVrsac(grad)) {
      return 'Vrsac - Bela Crkva';
    }
    return '$grad - ______';
  }

  static pw.Widget _buildInfoRow(String label, String value) {
    return pw.Row(
      children: [
        pw.SizedBox(
          width: 120,
          child: pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 12),
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
