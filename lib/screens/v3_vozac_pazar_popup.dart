import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../services/realtime/v3_master_realtime_manager.dart';
import '../../services/v3/v3_finansije_service.dart';
import '../../services/v3/v3_uplata_pazara_service.dart';
import '../../services/v3/v3_vozac_service.dart';
import '../../services/v3_locale_manager.dart';
import '../../utils/v3_app_snack_bar.dart';
import '../../utils/v3_button_utils.dart';
import '../../utils/v3_input_utils.dart';
import '../l10n/app_translations.dart';

class _PopupTr {
  static final Map<String, Map<String, String>> _t = AppTranslations.ns('vozacPazarPopup');

  static String tr(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    return _t[key]?[code] ?? _t[key]?['sr'] ?? key;
  }
}

class V3VozacPazarPopup extends StatefulWidget {
  final DateTime datum;
  final double ukupno;
  final double predao;
  final bool naknadnaNaplataDetektovana;
  final VoidCallback onSaved;

  const V3VozacPazarPopup({
    super.key,
    required this.datum,
    required this.ukupno,
    this.predao = 0,
    this.naknadnaNaplataDetektovana = false,
    required this.onSaved,
  });

  @override
  State<V3VozacPazarPopup> createState() => _V3VozacPazarPopupState();
}

class _V3VozacPazarPopupState extends State<V3VozacPazarPopup> {
  final _iznosController = TextEditingController();
  StreamSubscription<V3PazarPromptEvent>? _eventSub;
  bool _isSaving = false;
  late double _ukupno = widget.ukupno;
  late double _vecPredato = widget.predao;
  late bool _naknadna = widget.naknadnaNaplataDetektovana;

  @override
  void initState() {
    super.initState();
    // Dok je popup otvoren osvezava prikazane iznose kad stigne noviji event za
    // isti dan (npr. naplata pristigla dok vozac kuca iznos).
    _eventSub = V3MasterRealtimeManager.instance.pazarPromptStream.listen((event) {
      if (event.datum.year != widget.datum.year ||
          event.datum.month != widget.datum.month ||
          event.datum.day != widget.datum.day) {
        return;
      }
      if (!mounted) return;
      setState(() {
        if (event.ukupno > _ukupno) _ukupno = event.ukupno;
        _vecPredato = event.predao;
        _naknadna = _naknadna || event.naknadnaNaplataDetektovana;
      });
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _iznosController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final vozacId = V3VozacService.currentVozac?.id;
    if (vozacId == null) return;

    final predaoVal = double.tryParse(_iznosController.text.replaceAll(',', '.'));
    if (predaoVal == null || predaoVal < 0) {
      V3AppSnackBar.warning(context, _PopupTr.tr('unesiteIspravanIznos'));
      return;
    }

    setState(() => _isSaving = true);
    try {
      // Svezi ukupno u trenutku cuvanja — naplata moze stici dok je popup otvoren.
      final pazarMap = V3FinansijeService.getPazarPoVozacuZaDan(widget.datum);
      final svezeUkupno = max(_ukupno, pazarMap[vozacId] ?? 0.0);
      await V3UplataPazaraService.sacuvajDnevnuUplatu(
        vozacId: vozacId,
        datum: widget.datum,
        predao: _vecPredato + predaoVal,
        ukupno: svezeUkupno,
        zahtevanUnos: false, // gasimo popup jer je ukucao!
      );
      final noviPredao = await V3UplataPazaraService.getPredaoZaDan(
        vozacId: vozacId,
        datum: widget.datum,
      );
      if (!mounted) return;
      final ukupnoPredato = (noviPredao ?? (_vecPredato + predaoVal)).toStringAsFixed(0);
      V3AppSnackBar.success(
        context,
        _PopupTr.tr('pazarEvidentiranSaUkupnim').replaceAll('{iznos}', ukupnoPredato),
      );
      widget.onSaved();
    } catch (e) {
      V3AppSnackBar.error(context, '${_PopupTr.tr('greska')}: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Dialog(
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
              const SizedBox(height: 12),
              Text(
                _PopupTr.tr('ukupanPazar').replaceAll('{iznos}', _ukupno.toStringAsFixed(0)),
                style: const TextStyle(color: Colors.greenAccent, fontSize: 16, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              if (_vecPredato > 0) ...[
                const SizedBox(height: 6),
                Text(
                  _PopupTr.tr('vecPredato').replaceAll('{iznos}', _vecPredato.toStringAsFixed(0)),
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
              if (_naknadna) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    _PopupTr.tr('naknadnaNaplataDetektovanaPoruka'),
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              V3InputUtils.numberField(
                controller: _iznosController,
                label: _vecPredato > 0 ? _PopupTr.tr('unesiteDodatniIznos') : _PopupTr.tr('unesitePredatIznos'),
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
      ),
    );
  }
}
