import 'package:flutter/material.dart';

import '../../services/v3/v3_uplata_pazara_service.dart';
import '../../services/v3/v3_vozac_service.dart';
import '../../services/v3_locale_manager.dart';
import '../../utils/v3_app_snack_bar.dart';
import '../../utils/v3_button_utils.dart';
import '../../utils/v3_input_utils.dart';

class _PopupTr {
  static const Map<String, Map<String, String>> _t = {
    'unesiteIspravanIznos': {
      'sr': 'Unesite ispravan iznos stotino nula',
      'en': 'Enter a valid amount',
      'ru': 'Введите правильную сумму',
      'de': 'Geben Sie einen gültigen Betrag ein'
    },
    'pazarEvidentiran': {
      'sr': 'Pazar je uspesno evidentiran. Hvala.',
      'en': 'Earnings successfully recorded. Thank you.',
      'ru': 'Выручка успешно зарегистрирована. Спасибо.',
      'de': 'Einnahmen erfolgreich erfasst. Danke.'
    },
    'greska': {'sr': 'Greška', 'en': 'Error', 'ru': 'Ошибка', 'de': 'Fehler'},
    'smenaZavrsenaUnesiteIznos': {
      'sr': 'Vaša smena za danas je završena. Molimo unesite iznos današnjeg pazara.',
      'en': 'Your shift for today has ended. Please enter today\'s earnings amount.',
      'ru': 'Ваша смена на сегодня завершена. Пожалуйста, введите сумму сегодняшней выручки.',
      'de': 'Ihre Schicht für heute ist beendet. Bitte geben Sie den heutigen Einnahmenbetrag ein.'
    },
    'unesitePredatIznos': {
      'sr': 'Unesite predat iznos',
      'en': 'Enter handed over amount',
      'ru': 'Введите переданную сумму',
      'de': 'Geben Sie den übergebenen Betrag ein'
    },
    'belezenje': {'sr': 'Beleženje...', 'en': 'Recording...', 'ru': 'Запись...', 'de': 'Aufzeichnen...'},
    'sacuvajPazarIZatvori': {
      'sr': 'Sacuvaj pazar i zatvori',
      'en': 'Save earnings and close',
      'ru': 'Сохранить выручку и закрыть',
      'de': 'Einnahmen speichern und schließen'
    },
  };

  static String tr(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    return _t[key]?[code] ?? _t[key]?['sr'] ?? key;
  }
}

class V3VozacPazarPopup extends StatefulWidget {
  final DateTime datum;
  final double ukupno;
  final VoidCallback onSaved;

  const V3VozacPazarPopup({
    super.key,
    required this.datum,
    required this.ukupno,
    required this.onSaved,
  });

  @override
  State<V3VozacPazarPopup> createState() => _V3VozacPazarPopupState();
}

class _V3VozacPazarPopupState extends State<V3VozacPazarPopup> {
  final _iznosController = TextEditingController();
  bool _isSaving = false;

  Future<void> _save() async {
    final vozacId = V3VozacService.currentVozac?.id;
    if (vozacId == null) return;

    final predaoVal = double.tryParse(_iznosController.text.replaceAll(',', '.'));
    if (predaoVal == null || predaoVal < 0) {
      V3AppSnackBar.warning(context, _PopupTr.tr('unesiteIspravanIznos'));
      return;
    }

    setState(() => _isSaving = true);
    try {
      await V3UplataPazaraService.sacuvajDnevnuUplatu(
        vozacId: vozacId,
        datum: widget.datum,
        predao: predaoVal,
        ukupno: widget.ukupno,
        zahtevanUnos: false, // gasimo popup jer je ukucao!
      );
      if (!mounted) return;
      V3AppSnackBar.success(context, _PopupTr.tr('pazarEvidentiran'));
      widget.onSaved();
    } catch (e) {
      V3AppSnackBar.error(context, '${_PopupTr.tr('greska')}: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF2A2A2A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.attach_money, size: 64, color: Colors.greenAccent),
            const SizedBox(height: 16),
            Text(
              _PopupTr.tr('smenaZavrsenaUnesiteIznos'),
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            V3InputUtils.numberField(
              controller: _iznosController,
              label: _PopupTr.tr('unesitePredatIznos'),
              suffixText: 'din',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: V3ButtonUtils.elevatedButton(
                onPressed: _isSaving ? null : _save,
                text: _isSaving ? _PopupTr.tr('belezenje') : _PopupTr.tr('sacuvajPazarIZatvori'),
                isLoading: _isSaving,
                backgroundColor: Colors.greenAccent.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
