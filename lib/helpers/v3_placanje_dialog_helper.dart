import 'package:flutter/material.dart';

import '../../models/v3_finansije.dart';
import '../../services/v3/v3_finansije_service.dart';
import '../../services/v3/v3_putnik_service.dart';
import '../../services/v3/v3_vozac_service.dart';
import '../../utils/v3_app_snack_bar.dart';

class V3PlacanjeRezultat {
  final double iznos;
  final int mesec;
  final int godina;
  const V3PlacanjeRezultat({
    required this.iznos,
    required this.mesec,
    required this.godina,
  });
}

class V3PlacanjeDialogHelper {
  V3PlacanjeDialogHelper._();

  static Future<V3PlacanjeRezultat?> prikaziDialog({
    required BuildContext context,
    required String imePrezime,
    required double defaultCena,
  }) async {
    final TextEditingController _iznosController = TextEditingController(text: defaultCena.toStringAsFixed(0));

    int _selectedMonth = DateTime.now().month;
    int _selectedYear = DateTime.now().year;

    return showDialog<V3PlacanjeRezultat>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Naplata: $imePrezime'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _iznosController,
                decoration: const InputDecoration(
                  labelText: 'Iznos (RSD)',
                  suffixText: 'RSD',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<int>(
                      value: _selectedMonth,
                      isExpanded: true,
                      items: List.generate(12, (i) => i + 1).map((m) {
                        return DropdownMenuItem(
                          value: m,
                          child: Text(_getMonthName(m)),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _selectedMonth = v!),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButton<int>(
                      value: _selectedYear,
                      isExpanded: true,
                      items: [2024, 2025, 2026].map((y) {
                        return DropdownMenuItem(value: y, child: Text('$y.'));
                      }).toList(),
                      onChanged: (v) => setState(() => _selectedYear = v!),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ODUSTANI'),
            ),
            ElevatedButton(
              onPressed: () {
                final iznos = double.tryParse(_iznosController.text) ?? 0;
                Navigator.pop(
                  context,
                  V3PlacanjeRezultat(
                    iznos: iznos,
                    mesec: _selectedMonth,
                    godina: _selectedYear,
                  ),
                );
              },
              child: const Text('POTVRDI'),
            ),
          ],
        ),
      ),
    );
  }

  static String _getMonthName(int m) {
    const names = [
      'Januar',
      'Februar',
      'Mart',
      'April',
      'Maj',
      'Jun',
      'Jul',
      'Avgust',
      'Septembar',
      'Oktobar',
      'Novembar',
      'Decembar'
    ];
    return names[m - 1];
  }

  static Future<bool> sacuvajPlacanje({
    required BuildContext context,
    required String putnikId,
    required String imePrezime,
    required V3PlacanjeRezultat rezultat,
    String? zahtevId,
  }) async {
    try {
      final vozac = V3VozacService.currentVozac;
      if (vozac == null) throw 'Vozač nije ulogovan u V3';

      final unos = V3FinansijskiUnos(
        id: '', // Baza će generisati UUID
        tip: 'prihod',
        kategorija: 'voznja',
        opis: 'Uplata: $imePrezime (${rezultat.mesec}/${rezultat.godina})',
        iznos: rezultat.iznos,
        datum: DateTime.now(),
        vozacId: vozac.id,
        putnikId: putnikId,
        createdAt: DateTime.now(),
      );

      await V3FinansijeService.addUnos(unos);

      // Za radnika i učenika ažuriramo arhivski zapis plaćenog meseca/godine
      final putnik = V3PutnikService.getPutnikById(putnikId);
      if (putnik != null && (putnik.tipPutnika == 'radnik' || putnik.tipPutnika == 'ucenik')) {
        final azuriran = putnik.copyWith(
          placeniMesec: rezultat.mesec,
          placenaGodina: rezultat.godina,
        );
        await V3PutnikService.addUpdatePutnik(azuriran, updatedBy: 'vozac:${vozac.id}');
      }

      if (context.mounted) {
        V3AppSnackBar.payment(context, '✅ Naplaćeno ${rezultat.iznos} RSD za $imePrezime');
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        V3AppSnackBar.error(context, 'Greška pri naplati: $e');
      }
      return false;
    }
  }
}
