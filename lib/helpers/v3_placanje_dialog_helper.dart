import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';

import '../l10n/app_translations.dart';
import '../services/v3/v3_finansije_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../services/v3_locale_manager.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_belgrade_time.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dialog_helper.dart';
import '../utils/v3_input_utils.dart';

Map<String, Map<String, String>> get _placanjeT => AppTranslations.ns('placanjeDialogHelper');

String _placanjeTr(String key) {
  final code = V3LocaleManager().currentLocale.languageCode;
  return _placanjeT[key]?[code] ?? _placanjeT[key]?['sr'] ?? key;
}

String _placanjeTrf(String key, Map<String, String> params) {
  var text = _placanjeTr(key);
  params.forEach((placeholder, value) {
    text = text.replaceAll('%$placeholder%', value);
  });
  return text;
}

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

  static Widget _oneLineDropdownLabel(String text, TextStyle style) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
          style: style,
        ),
      ),
    );
  }

  static InputDecoration _compactDropdownDecoration() {
    return V3InputUtils.dropdownDecoration().copyWith(
      isDense: true,
      contentPadding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
    );
  }

  static DropdownStyleData get _compactDropdownStyle => DropdownStyleData(
        decoration: BoxDecoration(
          color: V3InputStyle.dropdownMenu,
          borderRadius: BorderRadius.circular(V3InputStyle.radius),
          border: Border.all(color: V3InputStyle.border),
        ),
        padding: const EdgeInsets.symmetric(vertical: 4),
      );

  static const ButtonStyleData _compactButtonStyle = ButtonStyleData(
    padding: EdgeInsets.only(right: 4),
    height: 44,
  );

  static Future<V3PlacanjeRezultat?> _prikaziDialog({
    required BuildContext context,
    required String putnikId,
    required String imePrezime,
    required double defaultCena,
    double? cenaPoModelu,
    int? mesec,
    int? godina,
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
      final preostaloZaNaplatu = V3FinansijeService.getNenaplacenIznosForPutnik(
        putnikId: putnikId,
        mesec: mesec,
        godina: godina,
      );
      return preostaloZaNaplatu > 0 ? preostaloZaNaplatu : 0.0;
    }

    _iznosController.addListener(() {
      if (_suppressAutoIznosListener) return;
      _autoIznosEnabled = false;
    });

    final now = V3BelgradeTime.now();
    int _selectedMonth = mesec ?? now.month;
    int _selectedYear = godina ?? now.year;
    final currentYear = now.year;
    final years = List.generate(6, (i) => currentYear - 1 + i);
    final zadnjaNaplata = V3FinansijeService.getLatestNaplataForPutnik(putnikId);
    final vremePlacen = zadnjaNaplata?.paidAt;
    final zadnjiIznos = zadnjaNaplata?.poslednjaDopuna ?? 0.0;
    final naplatioIme = (zadnjaNaplata?.paidBy == null)
        ? _placanjeTr('nepoznato')
        : (V3VozacService.getVozacById(zadnjaNaplata!.paidBy!)?.imePrezime ?? _placanjeTr('nepoznato'));

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
            final nenaplacenIznos = V3FinansijeService.getNenaplacenIznosForPutnik(
              putnikId: putnikId,
              mesec: mesec,
              godina: _selectedYear,
            );
            final uplaceno = summary.ukupanIznos;
            if (nenaplacenIznos > 0.009) {
              return (color: const Color(0xFFFF6D00), weight: FontWeight.w700);
            }

            // Beli meni (V3InputStyle.dropdownMenu) — bela boja bi bila nečitljiva
            if (uplaceno <= 0) {
              return (color: V3InputStyle.text, weight: FontWeight.w500);
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
                            _placanjeTrf('naplataNaslov', {'NAME': imePrezime}),
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
                                  Text(
                                    _placanjeTr('zadnjaNaplata'),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _placanjeTrf('datumLabel',
                                        {'VALUE': vremePlacen == null ? '-' : _formatDatumVreme(vremePlacen)}),
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                  Text(
                                    _placanjeTrf('iznosLabel', {'VALUE': zadnjiIznos.toStringAsFixed(0)}),
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                  Text(
                                    _placanjeTrf('naplatioLabel', {'NAME': naplatioIme}),
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),
                          // Labele iznad polja (ne floating na ivici — inače pola teksta ide preko tamne pozadine).
                          Text(
                            _placanjeTr('iznosRsd'),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.78),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          V3InputUtils.numberField(
                            controller: _iznosController,
                            hint: '0',
                            suffixText: 'RSD',
                            keyboardType: TextInputType.number,
                            icon: Icons.payments_outlined,
                          ),
                          const SizedBox(height: 16),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final yearWidth = (constraints.maxWidth * 0.34).clamp(92.0, 124.0);
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          _placanjeTr('mesec'),
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.78),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        DropdownButtonFormField2<int>(
                                          isExpanded: true,
                                          dropdownStyleData: _compactDropdownStyle,
                                          buttonStyleData: _compactButtonStyle,
                                          style: V3InputUtils.fieldTextStyle,
                                          iconStyleData: const IconStyleData(
                                            iconEnabledColor: V3InputStyle.icon,
                                            iconSize: 20,
                                          ),
                                          decoration: _compactDropdownDecoration(),
                                          value: _selectedMonth,
                                          selectedItemBuilder: (context) {
                                            return List.generate(12, (i) {
                                              final m = i + 1;
                                              return _oneLineDropdownLabel(
                                                V3BelgradeTime.mesecNaziv(m),
                                                V3InputUtils.fieldTextStyle,
                                              );
                                            });
                                          },
                                          items: List.generate(12, (i) => i + 1).map((m) {
                                            final mesecStyle = _mesecStyle(m);
                                            return DropdownMenuItem(
                                              value: m,
                                              child: _oneLineDropdownLabel(
                                                V3BelgradeTime.mesecNaziv(m),
                                                TextStyle(
                                                  color: mesecStyle.color,
                                                  fontWeight: mesecStyle.weight,
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (v) => setState(() {
                                            _selectedMonth = v!;
                                            if (_autoIznosEnabled) {
                                              _setIznosController(
                                                  _predlozeniIznosZaMesecGodinu(_selectedMonth, _selectedYear));
                                            }
                                          }),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: yearWidth,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          _placanjeTr('godina'),
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.78),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        DropdownButtonFormField2<int>(
                                          isExpanded: true,
                                          dropdownStyleData: _compactDropdownStyle,
                                          buttonStyleData: _compactButtonStyle,
                                          style: V3InputUtils.fieldTextStyle,
                                          iconStyleData: const IconStyleData(
                                            iconEnabledColor: V3InputStyle.icon,
                                            iconSize: 20,
                                          ),
                                          decoration: _compactDropdownDecoration(),
                                          value: _selectedYear,
                                          selectedItemBuilder: (context) {
                                            return years
                                                .map((y) => _oneLineDropdownLabel('$y.', V3InputUtils.fieldTextStyle))
                                                .toList();
                                          },
                                          items: years.map((y) {
                                            return DropdownMenuItem(
                                              value: y,
                                              child: _oneLineDropdownLabel(
                                                '$y.',
                                                V3InputUtils.fieldTextStyle,
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (v) => setState(() {
                                            _selectedYear = v!;
                                            if (_autoIznosEnabled) {
                                              _setIznosController(
                                                  _predlozeniIznosZaMesecGodinu(_selectedMonth, _selectedYear));
                                            }
                                          }),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
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
                            text: _placanjeTr('otkazi'),
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
                                V3AppSnackBar.warning(context, _placanjeTr('unesiteIspravanIznos'));
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
                            text: _placanjeTr('potvrdi'),
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
    int? mesec,
    int? godina,
  }) async {
    final dialogRezultat = await _prikaziDialog(
      context: context,
      putnikId: putnikId,
      imePrezime: imePrezime,
      defaultCena: defaultCena,
      cenaPoModelu: cenaPoModelu,
      mesec: mesec,
      godina: godina,
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
      if (vozac == null) throw _placanjeTr('vozacNijeUlogovan');

      if (snimiMesecnuUplatu) {
        await V3FinansijeService.sacuvajMesecnuNaplatu(
          putnikId: putnikId,
          naplacenoBy: vozac.id,
          iznos: rezultat.iznos,
          mesec: rezultat.mesec,
          godina: rezultat.godina,
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
        V3AppSnackBar.error(context, '${_placanjeTr('greskaPriNaplati')}: $e');
      }
      return false;
    }
  }
}
