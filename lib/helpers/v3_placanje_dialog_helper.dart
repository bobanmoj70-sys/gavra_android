import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';

import '../services/v3/v3_finansije_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
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
    this.brojVoznji = 0,
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
    double? cenaPoModelu,
  }) async {
    final TextEditingController _iznosController = TextEditingController(text: defaultCena.toStringAsFixed(0));
    var _autoIznosEnabled = true;
    var _suppressAutoIznosListener = false;

    void _setIznosController(double iznos) {
      final value = iznos.isFinite ? iznos : 0.0;
      _suppressAutoIznosListener = true;
      _iznosController.text = value.toStringAsFixed(0);
      _iznosController.selection = TextSelection.fromPosition(
        TextPosition(offset: _iznosController.text.length),
      );
      _suppressAutoIznosListener = false;
    }

    double _predlozeniIznosZaMesecGodinu(int mesec, int godina) {
      final cena = cenaPoModelu ?? 0.0;
      if (cena <= 0) return defaultCena;
      final summary = V3FinansijeService.getNaplataSummaryForPutnik(
        putnikId: putnikId,
        mesec: mesec,
        godina: godina,
      );
      final ukupnaObaveza = cena * summary.brojVoznji;
      final preostaloZaNaplatu = ukupnaObaveza - summary.ukupanIznos;
      return preostaloZaNaplatu > 0 ? preostaloZaNaplatu : 0.0;
    }

    _iznosController.addListener(() {
      if (_suppressAutoIznosListener) return;
      _autoIznosEnabled = false;
    });

    int _selectedMonth = DateTime.now().month;
    int _selectedYear = DateTime.now().year;
    final currentYear = DateTime.now().year;
    final years = List.generate(6, (i) => currentYear - 1 + i);
    final zadnjaNaplata = V3FinansijeService.getLatestNaplataForPutnik(putnikId);
    final vremePlacen = zadnjaNaplata?.paidAt;
    final zadnjiIznos = zadnjaNaplata?.poslednjaDopuna ?? 0.0;
    final naplatioIme = (zadnjaNaplata?.paidBy == null)
        ? 'Nepoznato'
        : (V3VozacService.getVozacById(zadnjaNaplata!.paidBy!)?.imePrezime ?? 'Nepoznato');

    return V3DialogHelper.showDialogBuilder<V3PlacanjeRezultat>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final cs = Theme.of(context).colorScheme;

          ({Color color, FontWeight weight}) _mesecStyle(int mesec) {
            final summary = V3FinansijeService.getNaplataSummaryForPutnik(
              putnikId: putnikId,
              mesec: mesec,
              godina: _selectedYear,
            );
            final uplaceno = summary.ukupanIznos;
            final cena = cenaPoModelu ?? 0.0;
            if (cena > 0) {
              final ukupnaObaveza = cena * summary.brojVoznji;
              if (ukupnaObaveza > 0 && uplaceno + 0.009 < ukupnaObaveza) {
                return (color: const Color(0xFFFF6D00), weight: FontWeight.w700);
              }
            }

            if (uplaceno <= 0) {
              return (color: Colors.white, weight: FontWeight.w500);
            }

            return (color: const Color(0xFF00C853), weight: FontWeight.w700);
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.9,
              ),
              decoration: BoxDecoration(
                gradient: Theme.of(context).backgroundGradient,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Theme.of(context).glassBorder, width: 0.8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  V3ContainerUtils.iconContainer(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Theme.of(context).glassContainer,
                    borderRadiusGeometry: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    border: Border(bottom: BorderSide(color: Theme.of(context).glassBorder)),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Naplata: $imePrezime',
                            style: const TextStyle(
                              fontSize: 18,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: V3ContainerUtils.iconContainer(
                            padding: const EdgeInsets.all(8),
                            backgroundColor: Colors.red.withValues(alpha: 0.2),
                            borderRadiusGeometry: BorderRadius.circular(15),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                            child: const Icon(Icons.close, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (zadnjaNaplata != null)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.surface.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Theme.of(context).glassBorder),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Zadnja naplata',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Datum: ${vremePlacen == null ? '-' : _formatDatumVreme(vremePlacen)}',
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                  Text(
                                    'Iznos: ${zadnjiIznos.toStringAsFixed(0)} RSD',
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                  Text(
                                    'Naplatio: $naplatioIme',
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),
                          TextField(
                            controller: _iznosController,
                            decoration: const InputDecoration(
                              labelText: 'Iznos (RSD)',
                              labelStyle: TextStyle(color: Colors.white70),
                              suffixText: 'RSD',
                              suffixStyle: TextStyle(color: Colors.white70),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white38),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                            ),
                            style: const TextStyle(color: Colors.white),
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField2<int>(
                                  isExpanded: true,
                                  dropdownStyleData: DropdownStyleData(
                                    decoration: BoxDecoration(
                                      gradient: Theme.of(context).backgroundGradient,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Theme.of(context).glassBorder, width: 0.8),
                                    ),
                                  ),
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                  iconStyleData: const IconStyleData(
                                    iconEnabledColor: Colors.white,
                                  ),
                                  decoration: const InputDecoration(
                                    contentPadding: EdgeInsets.zero,
                                    labelText: 'Mesec',
                                    labelStyle: TextStyle(color: Colors.white70),
                                    enabledBorder: UnderlineInputBorder(
                                      borderSide: BorderSide(color: Colors.white38),
                                    ),
                                    focusedBorder: UnderlineInputBorder(
                                      borderSide: BorderSide(color: Colors.white),
                                    ),
                                  ),
                                  value: _selectedMonth,
                                  items: List.generate(12, (i) => i + 1).map((m) {
                                    final mesecStyle = _mesecStyle(m);
                                    return DropdownMenuItem(
                                      value: m,
                                      child: Text(
                                        V3DateUtils.mesecNaziv(m),
                                        style: TextStyle(
                                          color: mesecStyle.color,
                                          fontWeight: mesecStyle.weight,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (v) => setState(() {
                                    _selectedMonth = v!;
                                    if (_autoIznosEnabled) {
                                      _setIznosController(_predlozeniIznosZaMesecGodinu(_selectedMonth, _selectedYear));
                                    }
                                  }),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField2<int>(
                                  isExpanded: true,
                                  dropdownStyleData: DropdownStyleData(
                                    decoration: BoxDecoration(
                                      gradient: Theme.of(context).backgroundGradient,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Theme.of(context).glassBorder, width: 0.8),
                                    ),
                                  ),
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                  iconStyleData: const IconStyleData(
                                    iconEnabledColor: Colors.white,
                                  ),
                                  decoration: const InputDecoration(
                                    contentPadding: EdgeInsets.zero,
                                    labelText: 'Godina',
                                    labelStyle: TextStyle(color: Colors.white70),
                                    enabledBorder: UnderlineInputBorder(
                                      borderSide: BorderSide(color: Colors.white38),
                                    ),
                                    focusedBorder: UnderlineInputBorder(
                                      borderSide: BorderSide(color: Colors.white),
                                    ),
                                  ),
                                  value: _selectedYear,
                                  items: years.map((y) {
                                    return DropdownMenuItem(
                                      value: y,
                                      child: Text(
                                        '$y.',
                                        style: const TextStyle(color: Colors.white),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (v) => setState(() {
                                    _selectedYear = v!;
                                    if (_autoIznosEnabled) {
                                      _setIznosController(_predlozeniIznosZaMesecGodinu(_selectedMonth, _selectedYear));
                                    }
                                  }),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Actions
                  V3ContainerUtils.iconContainer(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Theme.of(context).glassContainer,
                    borderRadiusGeometry: const BorderRadius.only(
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                    border: Border(top: BorderSide(color: Theme.of(context).glassBorder)),
                    child: Row(
                      children: [
                        Expanded(
                          child: V3ButtonUtils.outlinedButton(
                            onPressed: () => Navigator.pop(context),
                            text: 'Otkaži',
                            borderColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: V3ButtonUtils.elevatedButton(
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
                            text: 'Potvrdi',
                            icon: Icons.check,
                            backgroundColor: Colors.green.withValues(alpha: 0.7),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
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
    double? cenaPoModelu,
    bool snimiMesecnuUplatu = false,
    int brojVoznji = 0,
  }) async {
    final dialogRezultat = await _prikaziDialog(
      context: context,
      putnikId: putnikId,
      imePrezime: imePrezime,
      defaultCena: defaultCena,
      cenaPoModelu: cenaPoModelu,
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
