import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../utils/app_snack_bar.dart';

/// Servis za generisanje i štampanje računa za fizička lica
class V2RacunService {
  // ========== FONTOVI SA PODRŠKOM ZA SRPSKA SLOVA ==========
  static pw.Font get regularFont => pw.Font.helvetica();
  static pw.Font get boldFont => pw.Font.helveticaBold();

  // ========== PODACI O IZDAVAOCU ==========
  static const String firmaIme = 'PR Limo Servis Gavra 013';
  static const String firmaAdresa = 'Mihajla Pupina 74, 26340 Bela Crkva';
  static const String firmaPIB = '102853497';
  static const String firmaMB = '55572178';
  static const String firmaTekuciRacun = '340-11436537-92';

  // ========== NAPOMENA ZA RAČUN ==========
  static const String napomenaPDV = 'Poreski obveznik nije u sistemu PDV-a';
  static const String napomenaValidnost =
      'Račun je punovažan bez pečata i potpisa u skladu sa Zakonom o privrednim društvima';

  // ========== AUTO-INCREMENT BROJ RAČUNA (BAZA) ==========
  static SupabaseClient get _supabase => supabase;

  /// Vraća sledeći broj računa u formatu "X/YYYY" i automatski uvećava brojač u BAZI
  /// Atomska operacija putem optimistic locking - sprečava duplikate između vozača
  static Future<String> _getNextBrojRacuna() async {
    final godina = DateTime.now().year;

    try {
      // Optimistic lock: čitaj → pokušaj atomski UPDATE sa WHERE stari_broj = pročitani
      // Ponovi max 5 puta ako je race condition
      for (int attempt = 0; attempt < 5; attempt++) {
        // Čitaj trenutni broj
        final selectResp =
            await _supabase.from('v2_racun_sequence').select('poslednji_broj').eq('godina', godina).maybeSingle();

        if (selectResp == null) {
          // Red ne postoji — kreiraj ga s brojem 1
          await _supabase.from('v2_racun_sequence').insert({'godina': godina, 'poslednji_broj': 1});
          return '1/$godina';
        }

        final stari = selectResp['poslednji_broj'] as int;
        final novi = stari + 1;

        // Pokušaj UPDATE samo ako stari_broj == onaj koji smo pročitali
        final updateResp = await _supabase
            .from('v2_racun_sequence')
            .update({'poslednji_broj': novi})
            .eq('godina', godina)
            .eq('poslednji_broj', stari)
            .select('poslednji_broj');

        if ((updateResp as List).isNotEmpty) {
          // UPDATE uspio — novi broj je naš
          return '$novi/$godina';
        }
        // Drugi je stigao prvi — kratka pauza pa retry
        await Future.delayed(Duration(milliseconds: 50 * (attempt + 1)));
      }

      // Fallback na timestamp ako svi retry-ovi ne uspiju
      final timestamp = DateTime.now().millisecondsSinceEpoch % 100000;
      return 'T$timestamp/$godina';
    } catch (e) {
      // Fallback na timestamp ako baza nije dostupna
      final timestamp = DateTime.now().millisecondsSinceEpoch % 100000;
      return 'T$timestamp/$godina';
    }
  }

  /// Vraća trenutni broj računa BEZ uvećavanja (za prikaz)
  static Future<String> getTrenutniBrojRacuna() async {
    final godina = DateTime.now().year;

    try {
      final response =
          await _supabase.from('v2_racun_sequence').select('poslednji_broj').eq('godina', godina).maybeSingle();

      final trenutniBroj = response?['poslednji_broj'] as int? ?? 0;
      return '${trenutniBroj + 1}/$godina';
    } catch (e) {
      return '?/$godina';
    }
  }

  /// Štampa račun za fizičko lice
  static Future<void> stampajRacun({
    required String brojRacuna,
    required String imePrezimeKupca,
    required String adresaKupca,
    required String opisUsluge,
    required double cena,
    required int kolicina,
    required String jedinicaMere,
    required DateTime datumPrometa,
    required BuildContext context,
  }) async {
    try {
      // Fonts loaded automatically via getters

      final pdf = await _kreirajRacunPDF(
        brojRacuna: brojRacuna,
        imePrezimeKupca: imePrezimeKupca,
        adresaKupca: adresaKupca,
        opisUsluge: opisUsluge,
        cena: cena,
        kolicina: kolicina,
        jedinicaMere: jedinicaMere,
        datumPrometa: datumPrometa,
      );

      // Sačuvaj PDF
      final tempDir = await getTemporaryDirectory();
      final fileName =
          'Racun_${brojRacuna.replaceAll('/', '_')}_${DateFormat('dd_MM_yyyy').format(DateTime.now())}.pdf';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pdf, flush: true);

      // Otvori PDF
      await OpenFilex.open(file.path);
    } catch (e) {
      if (context.mounted) {
        AppSnackBar.error(context, '❌ Greška pri štampanju računa: $e');
      }
    }
  }

  /// 🧾 Štampa račune za firme (B2B) - kraj meseca
  static Future<void> stampajRacuneZaFirme({
    required List<Map<String, dynamic>> racuniPodaci,
    required BuildContext context,
    DateTime? datumPrometa,
  }) async {
    if (racuniPodaci.isEmpty) {
      if (context.mounted) {
        AppSnackBar.warning(context, 'Nema računa za štampanje');
      }
      return;
    }

    try {
      // Fonts loaded automatically via getters

      final pdf = pw.Document();
      final obracunskiDatum = datumPrometa ?? DateTime.now();
      final mesecStr = DateFormat('MMMM yyyy', 'sr_Latn').format(obracunskiDatum);

      for (final podaci in racuniPodaci) {
        final putnik = podaci['putnik'];
        final brojDana = podaci['brojDana'] as int;
        final cenaPoDanu = podaci['cenaPoDanu'] as double;
        final ukupno = podaci['ukupno'] as double;
        final brojRacuna = await _getNextBrojRacuna();

        final stranica = await _kreirajRacunZaFirmuStranicu(
          brojRacuna: brojRacuna,
          firmaNaziv: putnik.firmaNaziv ?? putnik.putnikIme,
          firmaPib: putnik.firmaPib ?? '',
          firmaMb: putnik.firmaMb ?? '',
          firmaZiro: putnik.firmaZiro ?? '',
          firmaAdresa: putnik.firmaAdresa ?? '',
          putnikIme: putnik.putnikIme,
          opisUsluge: 'Prevoz putnika za $mesecStr',
          cenaPoDanu: cenaPoDanu,
          brojDana: brojDana,
          ukupno: ukupno,
          datumPrometa: obracunskiDatum,
        );

        pdf.addPage(stranica);
      }

      // Sačuvaj PDF
      final tempDir = await getTemporaryDirectory();
      final fileName = 'Racuni_Firme_${DateFormat('MM_yyyy').format(DateTime.now())}.pdf';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(await pdf.save(), flush: true);

      await OpenFilex.open(file.path);

      if (context.mounted) {
        AppSnackBar.success(context, '✅ Generisano ${racuniPodaci.length} računa za firme');
      }
    } catch (e) {
      if (context.mounted) {
        AppSnackBar.error(context, '❌ Greška: $e');
      }
    }
  }

  /// Kreira stranicu računa za firmu (B2B)
  static Future<pw.Page> _kreirajRacunZaFirmuStranicu({
    required String brojRacuna,
    required String firmaNaziv,
    required String firmaPib,
    required String firmaMb,
    required String firmaZiro,
    required String firmaAdresa,
    required String putnikIme,
    required String opisUsluge,
    required double cenaPoDanu,
    required int brojDana,
    required double ukupno,
    DateTime? datumPrometa,
  }) async {
    final referentniDatum = datumPrometa ?? DateTime.now();
    final danas = DateFormat('dd.MM.yyyy').format(DateTime.now());
    final datumPrometaStr = DateFormat('dd.MM.yyyy').format(referentniDatum);

    // Kreiraj temu sa fontovima koji podržavaju srpska slova
    final theme = pw.ThemeData.withFont(
      base: regularFont,
      bold: boldFont,
      italic: regularFont,
      boldItalic: boldFont,
    );

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      theme: theme,
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // ========== IZDAVALAC ==========
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('IZDAVALAC',
                      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
                  pw.SizedBox(height: 8),
                  pw.Text(firmaIme, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Adresa: $firmaAdresa', style: const pw.TextStyle(fontSize: 11)),
                  pw.Text('PIB: $firmaPIB | MB: $firmaMB', style: const pw.TextStyle(fontSize: 11)),
                  pw.Text('Žiro račun: $firmaTekuciRacun', style: const pw.TextStyle(fontSize: 11)),
                ],
              ),
            ),

            pw.SizedBox(height: 20),

            // ========== NASLOV ==========
            pw.Center(
              child:
                  pw.Text('RAČUN br. $brojRacuna', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text('za mesec: ${DateFormat('MMMM yyyy', 'sr_Latn').format(referentniDatum)}',
                  style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700)),
            ),

            pw.SizedBox(height: 10),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Datum izdavanja: $danas', style: const pw.TextStyle(fontSize: 11)),
                pw.Text('Datum prometa: $datumPrometaStr', style: const pw.TextStyle(fontSize: 11)),
              ],
            ),

            pw.SizedBox(height: 20),

            // ========== KUPAC (FIRMA) ==========
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('KUPAC',
                      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
                  pw.SizedBox(height: 8),
                  pw.Text(firmaNaziv, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  if (firmaAdresa.isNotEmpty) pw.Text('Adresa: $firmaAdresa', style: const pw.TextStyle(fontSize: 11)),
                  if (firmaPib.isNotEmpty) pw.Text('PIB: $firmaPib', style: const pw.TextStyle(fontSize: 11)),
                  if (firmaMb.isNotEmpty) pw.Text('MB: $firmaMb', style: const pw.TextStyle(fontSize: 11)),
                  if (firmaZiro.isNotEmpty) pw.Text('Žiro račun: $firmaZiro', style: const pw.TextStyle(fontSize: 11)),
                  pw.SizedBox(height: 8),
                  pw.Text('Putnik: $putnikIme', style: pw.TextStyle(fontSize: 11, fontStyle: pw.FontStyle.italic)),
                ],
              ),
            ),

            pw.SizedBox(height: 30),

            // ========== TABELA ==========
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              columnWidths: {
                0: const pw.FixedColumnWidth(30),
                1: const pw.FlexColumnWidth(3),
                2: const pw.FixedColumnWidth(50),
                3: const pw.FixedColumnWidth(80),
                4: const pw.FixedColumnWidth(80),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _tableCell('R.br.', isHeader: true),
                    _tableCell('Opis usluge', isHeader: true),
                    _tableCell('Dana', isHeader: true),
                    _tableCell('Cena/dan', isHeader: true),
                    _tableCell('Iznos', isHeader: true),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _tableCell('1'),
                    _tableCell(opisUsluge),
                    _tableCell(brojDana.toString()),
                    _tableCell('${cenaPoDanu.toStringAsFixed(0)} RSD'),
                    _tableCell('${ukupno.toStringAsFixed(0)} RSD'),
                  ],
                ),
              ],
            ),

            pw.SizedBox(height: 10),

            // ========== UKUPNO ==========
            pw.Container(
              alignment: pw.Alignment.centerRight,
              child: pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey600, width: 2)),
                child: pw.Text('UKUPNO: ${ukupno.toStringAsFixed(0)} RSD',
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              ),
            ),

            pw.SizedBox(height: 30),

            // ========== NAPOMENA ==========
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(color: PdfColors.grey100, border: pw.Border.all(color: PdfColors.grey300)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Napomena: $napomenaPDV', style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 4),
                  pw.Text(napomenaValidnost, style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),

            pw.Spacer(),

            // ========== POTPISI ==========
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  children: [
                    pw.Container(
                        width: 150,
                        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
                        child: pw.SizedBox(height: 40)),
                    pw.SizedBox(height: 4),
                    pw.Text('Potpis kupca', style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Container(
                        width: 150,
                        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
                        child: pw.SizedBox(height: 40)),
                    pw.SizedBox(height: 4),
                    pw.Text('M.P. Potpis izdavaoca', style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// Kreira PDF račun
  static Future<Uint8List> _kreirajRacunPDF({
    required String brojRacuna,
    required String imePrezimeKupca,
    required String adresaKupca,
    required String opisUsluge,
    required double cena,
    required int kolicina,
    required String jedinicaMere,
    required DateTime datumPrometa,
  }) async {
    final pdf = pw.Document();

    final danas = DateFormat('dd.MM.yyyy').format(DateTime.now());
    final datumPrometaStr = DateFormat('dd.MM.yyyy').format(datumPrometa);
    final ukupno = cena * kolicina;

    // Kreiraj temu sa fontovima koji podržavaju srpska slova
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
              // ========== ZAGLAVLJE - IZDAVALAC ==========
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'IZDAVALAC RAČUNA',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey600,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      firmaIme,
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text('Adresa: $firmaAdresa', style: const pw.TextStyle(fontSize: 11)),
                    pw.Text('PIB: $firmaPIB', style: const pw.TextStyle(fontSize: 11)),
                    pw.Text('Matični broj: $firmaMB', style: const pw.TextStyle(fontSize: 11)),
                    pw.Text('Tekući račun: $firmaTekuciRacun', style: const pw.TextStyle(fontSize: 11)),
                  ],
                ),
              ),

              pw.SizedBox(height: 20),

              // ========== NASLOV RAČUNA ==========
              pw.Center(
                child: pw.Text(
                  'RAČUN br. $brojRacuna',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),

              pw.SizedBox(height: 20),

              // ========== DATUMI ==========
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Datum izdavanja: $danas', style: const pw.TextStyle(fontSize: 11)),
                  pw.Text('Datum prometa: $datumPrometaStr', style: const pw.TextStyle(fontSize: 11)),
                ],
              ),

              pw.SizedBox(height: 20),

              // ========== KUPAC ==========
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'KUPAC',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey600,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      imePrezimeKupca,
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (adresaKupca.isNotEmpty)
                      pw.Text('Adresa: $adresaKupca', style: const pw.TextStyle(fontSize: 11)),
                  ],
                ),
              ),

              pw.SizedBox(height: 30),

              // ========== TABELA STAVKI ==========
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                columnWidths: {
                  0: const pw.FixedColumnWidth(30), // R.br.
                  1: const pw.FlexColumnWidth(3), // Naziv
                  2: const pw.FixedColumnWidth(50), // Jed.
                  3: const pw.FixedColumnWidth(50), // Kol.
                  4: const pw.FixedColumnWidth(80), // Cena
                  5: const pw.FixedColumnWidth(80), // Iznos
                },
                children: [
                  // Zaglavlje tabele
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _tableCell('R.br.', isHeader: true),
                      _tableCell('Naziv dobra / usluge', isHeader: true),
                      _tableCell('Jed.', isHeader: true),
                      _tableCell('Kol.', isHeader: true),
                      _tableCell('Cena', isHeader: true),
                      _tableCell('Iznos', isHeader: true),
                    ],
                  ),
                  // Stavka
                  pw.TableRow(
                    children: [
                      _tableCell('1'),
                      _tableCell(opisUsluge),
                      _tableCell(jedinicaMere),
                      _tableCell(kolicina.toString()),
                      _tableCell('${cena.toStringAsFixed(2)} RSD'),
                      _tableCell('${ukupno.toStringAsFixed(2)} RSD'),
                    ],
                  ),
                ],
              ),

              pw.SizedBox(height: 10),

              // ========== UKUPNO ==========
              pw.Container(
                alignment: pw.Alignment.centerRight,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey600, width: 2),
                  ),
                  child: pw.Text(
                    'UKUPNO: ${ukupno.toStringAsFixed(2)} RSD',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ),

              pw.SizedBox(height: 30),

              // ========== NAPOMENA ==========
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Napomena: $napomenaPDV',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      napomenaValidnost,
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ),

              pw.Spacer(),

              // ========== POTPISI ==========
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  // Potpis kupca
                  pw.Column(
                    children: [
                      pw.Container(
                        width: 150,
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
                        ),
                        child: pw.SizedBox(height: 40),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text('Potpis kupca', style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                  // Pečat i potpis izdavaoca
                  pw.Column(
                    children: [
                      pw.Container(
                        width: 150,
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
                        ),
                        child: pw.SizedBox(height: 40),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text('M.P. Potpis izdavaoca', style: const pw.TextStyle(fontSize: 10)),
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

  /// Helper za ćeliju tabele
  static pw.Widget _tableCell(String text, {bool isHeader = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 10 : 11,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: isHeader ? pw.TextAlign.center : pw.TextAlign.left,
      ),
    );
  }
}
