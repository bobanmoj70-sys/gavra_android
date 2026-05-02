import 'package:flutter/material.dart';

import '../services/v3/v3_finansije_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_date_utils.dart';
import '../utils/v3_dialog_helper.dart';

class V3PlacanjeRezultat {
  final double iznos;
  final int mesec;
  final int godina;
  final int brojVoznji;
  const V3PlacanjeRezultat({
    required this.iznos,
    required this.mesec,
    required this.godina,
    this.brojVoznji = 1,
  });
}

class V3PlacanjeDialogHelper {
  V3PlacanjeDialogHelper._();

  static String _formatDatumVreme(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  static Future<V3PlacanjeRezultat?> _prikaziDialog({
    required BuildContext context,
    required String putnikId,
    required String imePrezime,
    required double defaultCena,
  }) async {
    final TextEditingController _iznosController = TextEditingController(text: defaultCena.toStringAsFixed(0));

    int _selectedMonth = DateTime.now().month;
    int _selectedYear = DateTime.now().year;
    final currentYear = DateTime.now().year;
    final years = List.generate(6, (i) => currentYear - 1 + i);
    final zadnjaNaplata = V3FinansijeService.getLatestNaplataForPutnik(putnikId);
    final vremePlacen = zadnjaNaplata?.paidAt;
    final zadnjiIznos = zadnjaNaplata?.iznos ?? 0.0;
    final naplatioIme = (zadnjaNaplata?.paidBy == null)
        ? 'Nepoznato'
        : (V3VozacService.getVozacById(zadnjaNaplata!.paidBy!)?.imePrezime ?? 'Nepoznato');

    return V3DialogHelper.showDialogBuilder<V3PlacanjeRezultat>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final cs = Theme.of(context).colorScheme;
          return AlertDialog(
            backgroundColor: cs.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: cs.outline.withValues(alpha: 0.25), width: 1),
            ),
            titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
            contentPadding: const EdgeInsets.fromLTRB(22, 6, 22, 8),
            actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            title: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.payments_outlined, color: cs.primary, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Naplata: $imePrezime',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (zadnjaNaplata != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Zadnja naplata',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Datum: ${vremePlacen == null ? '-' : _formatDatumVreme(vremePlacen)}',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                        Text(
                          'Iznos: ${zadnjiIznos.toStringAsFixed(0)} RSD',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                        Text('Naplatio: $naplatioIme', style: TextStyle(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                TextField(
                  controller: _iznosController,
                  decoration: InputDecoration(
                    labelText: 'Iznos (RSD)',
                    suffixText: 'RSD',
                    prefixIcon: const Icon(Icons.payments_outlined),
                  ),
                  style: TextStyle(color: cs.onSurface),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: 'Mesec',
                          prefixIcon: Icon(Icons.calendar_month_outlined),
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        value: _selectedMonth,
                        isExpanded: true,
                        items: List.generate(12, (i) => i + 1).map((m) {
                          return DropdownMenuItem(
                            value: m,
                            child: Text(V3DateUtils.mesecNaziv(m)),
                          );
                        }).toList(),
                        onChanged: (v) => setState(() => _selectedMonth = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: 'Godina',
                          prefixIcon: Icon(Icons.event_outlined),
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        value: _selectedYear,
                        isExpanded: true,
                        items: years.map((y) {
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
                style: TextButton.styleFrom(foregroundColor: cs.error),
                child: const Text('ODUSTANI'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                onPressed: () {
                  final rawIznos = _iznosController.text.trim().replaceAll(',', '.');
                  final iznos = double.tryParse(rawIznos) ?? 0;
                  if (iznos <= 0) {
                    V3AppSnackBar.warning(context, 'Unesite ispravan iznos (> 0 RSD).');
                    return;
                  }
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
          );
        },
      ),
    );
  }

  static Future<V3PlacanjeRezultat?> naplati({
    required BuildContext context,
    required String putnikId,
    required String imePrezime,
    required double defaultCena,
    bool snimiMesecnuUplatu = false,
    int brojVoznji = 1,
  }) async {
    final dialogRezultat = await _prikaziDialog(
      context: context,
      putnikId: putnikId,
      imePrezime: imePrezime,
      defaultCena: defaultCena,
    );
    if (dialogRezultat == null) return null;

    // Ugradi brojVoznji u rezultat
    final rezultat = V3PlacanjeRezultat(
      iznos: dialogRezultat.iznos,
      mesec: dialogRezultat.mesec,
      godina: dialogRezultat.godina,
      brojVoznji: brojVoznji,
    );

    final ok = await _sacuvajPlacanje(
      context: context,
      putnikId: putnikId,
      rezultat: rezultat,
      snimiMesecnuUplatu: snimiMesecnuUplatu,
    );
    if (!ok) return null;

    return rezultat;
  }

  static Future<bool> _sacuvajPlacanje({
    required BuildContext context,
    required String putnikId,
    required V3PlacanjeRezultat rezultat,
    bool snimiMesecnuUplatu = false,
  }) async {
    try {
      final vozac = V3VozacService.currentVozac;
      if (vozac == null) throw 'Vozač nije ulogovan u V3';

      if (snimiMesecnuUplatu) {
        await V3FinansijeService.sacuvajMesecnuNaplatu(
          putnikId: putnikId,
          naplacenoBy: vozac.id,
          iznos: rezultat.iznos,
          mesec: rezultat.mesec,
          godina: rezultat.godina,
          brojVoznji: rezultat.brojVoznji,
        );
      } else {
        await V3FinansijeService.sacuvajNaplatuZaMesec(
          putnikId: putnikId,
          naplacenoBy: vozac.id,
          iznos: rezultat.iznos,
          datum: DateTime(rezultat.godina, rezultat.mesec, 1),
        );
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
