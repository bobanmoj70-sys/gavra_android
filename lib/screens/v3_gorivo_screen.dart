import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gavra_android/models/v3_gorivo.dart';
import 'package:gavra_android/services/realtime/v3_master_realtime_manager.dart';
import 'package:gavra_android/services/v3/v3_gorivo_service.dart';
import 'package:gavra_android/theme.dart';

import '../l10n/app_translations.dart';
import '../services/v3_locale_manager.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_format_utils.dart';
import '../utils/v3_input_utils.dart';

class _GorTr {
  static final Map<String, Map<String, String>> _t = AppTranslations.ns('gorivoScreen');

  static String tr(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    return _t[key]?[code] ?? _t[key]?['sr'] ?? key;
  }
}

class V3GorivoScreen extends StatefulWidget {
  const V3GorivoScreen({super.key});

  @override
  State<V3GorivoScreen> createState() => _V3GorivoScreenState();
}

class _V3GorivoScreenState extends State<V3GorivoScreen> {
  static const Color _accent = Color(0xFFFF9800);
  static const Color _cardBg = Color(0xFF1E2235);
  static const Color _sheetBg = Color(0xFF161A28);

  bool _isCreatingInitialData = false;
  bool _isSavingFuelData = false;
  bool _isDodavanjeGoriva = false;

  double? _toDoubleOrNull(String input) {
    final normalized = input.trim().replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  double _roundMoney(double v) => (v * 100).roundToDouble() / 100;

  Future<void> _openDopunaSheet({required V3PumpaRezervoar? rezervoar, required V3PumpaStanje? stanje}) async {
    final String? id =
        stanje?.id.isNotEmpty == true ? stanje!.id : (rezervoar?.id.isNotEmpty == true ? rezervoar!.id : null);
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_GorTr.tr('nemaRedaZaDopunu'))),
      );
      return;
    }

    final trenutno = stanje?.trenutnoStanje ?? rezervoar?.trenutnoLitara ?? 0;
    final kapacitet = stanje?.kapacitetLitri ?? rezervoar?.kapacitetMax ?? 0;
    final cenaPoLitruInit = stanje?.cenaPoLitru ?? 0;
    final trenutniDug = stanje?.dugIznos ?? 0;
    final dodatoCtrl = TextEditingController();
    final cenaCtrl = TextEditingController(
      text: cenaPoLitruInit > 0 ? cenaPoLitruInit.toStringAsFixed(2) : '',
    );
    final dugCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var dugRucno = false;

    void syncDugFromLitriCena(void Function(void Function()) setModal) {
      if (dugRucno) return;
      final litri = _toDoubleOrNull(dodatoCtrl.text);
      final cena = _toDoubleOrNull(cenaCtrl.text);
      if (litri != null && litri > 0 && cena != null && cena > 0) {
        final iznos = _roundMoney(litri * cena);
        setModal(() {
          dugCtrl.text = iznos.toStringAsFixed(2);
        });
      } else if (!dugRucno) {
        setModal(() {
          if (dugCtrl.text.isNotEmpty) dugCtrl.clear();
        });
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: V3ContainerUtils.styledContainer(
            backgroundColor: _sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
            padding: EdgeInsets.zero,
            child: SafeArea(
              top: false,
              child: StatefulBuilder(
                builder: (context, setModal) {
                  final litriPreview = _toDoubleOrNull(dodatoCtrl.text);
                  final cenaPreview = _toDoubleOrNull(cenaCtrl.text);
                  final racunPreview =
                      (litriPreview != null && litriPreview > 0 && cenaPreview != null && cenaPreview > 0)
                          ? _roundMoney(litriPreview * cenaPreview)
                          : null;
                  final dugUnos = _toDoubleOrNull(dugCtrl.text);
                  final dugPosle = trenutniDug + (dugUnos != null && dugUnos > 0 ? dugUnos : 0);

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                    child: Form(
                      key: formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _sheetHandle(),
                          _sheetHeader(
                            icon: Icons.local_gas_station_rounded,
                            iconColor: Colors.greenAccent,
                            title: _GorTr.tr('dodajGorivo'),
                            subtitle:
                                '${V3FormatUtils.formatGorivo(trenutno)} L / ${V3FormatUtils.formatGorivo(kapacitet)} L',
                          ),
                          const SizedBox(height: 14),
                          _infoChipRow([
                            _InfoChipData(
                              icon: Icons.water_drop_outlined,
                              label: _GorTr.tr('trenutnoKapacitet'),
                              value: '${V3FormatUtils.formatGorivo(trenutno)} L',
                              color: Colors.lightBlueAccent,
                            ),
                            _InfoChipData(
                              icon: Icons.account_balance_wallet_outlined,
                              label: _GorTr.tr('trenutniDug'),
                              value: '${trenutniDug.toStringAsFixed(0)} RSD',
                              color: trenutniDug > 0 ? Colors.orangeAccent : Colors.greenAccent,
                            ),
                          ]),
                          const SizedBox(height: 18),
                          _fuelField(
                            controller: dodatoCtrl,
                            label: _GorTr.tr('kolikoLitaraJeDopunjeno'),
                            prefixIcon: Icons.opacity_rounded,
                            onChanged: (_) => syncDugFromLitriCena(setModal),
                          ),
                          _fuelField(
                            controller: cenaCtrl,
                            label: _GorTr.tr('cenaPoLitruOvaIsporuka'),
                            prefixIcon: Icons.payments_outlined,
                            requiredField: false,
                            onChanged: (_) => syncDugFromLitriCena(setModal),
                          ),
                          _hintText(_GorTr.tr('cenaPoLitruDopunaHint')),
                          if (racunPreview != null) ...[
                            const SizedBox(height: 10),
                            _previewBanner(
                              color: Colors.green,
                              icon: Icons.calculate_outlined,
                              text: _GorTr.tr('racunLitriPutaCena')
                                  .replaceAll('%L%', V3FormatUtils.formatGorivo(litriPreview!))
                                  .replaceAll('%CENA%', cenaPreview!.toStringAsFixed(2))
                                  .replaceAll('%IZNOS%', racunPreview.toStringAsFixed(2)),
                            ),
                          ],
                          const SizedBox(height: 12),
                          _fuelField(
                            controller: dugCtrl,
                            label: _GorTr.tr('iznosDugaOvaIsporuka'),
                            prefixIcon: Icons.receipt_long_outlined,
                            requiredField: false,
                            onChanged: (_) {
                              dugRucno = dugCtrl.text.trim().isNotEmpty;
                              setModal(() {});
                            },
                          ),
                          _hintText(_GorTr.tr('iznosDugaHint')),
                          if (dugUnos != null && dugUnos > 0) ...[
                            const SizedBox(height: 10),
                            _previewBanner(
                              color: Colors.orange,
                              icon: Icons.trending_up_rounded,
                              text: _GorTr.tr('dugPosleDopune')
                                  .replaceAll('%STARI%', trenutniDug.toStringAsFixed(2))
                                  .replaceAll('%DODATO%', dugUnos.toStringAsFixed(2))
                                  .replaceAll('%NOVI%', dugPosle.toStringAsFixed(2)),
                            ),
                          ],
                          const SizedBox(height: 20),
                          _sheetActions(
                            cancelLabel: _GorTr.tr('otkazi'),
                            confirmLabel: _GorTr.tr('dodaj'),
                            confirmColor: Colors.green,
                            loading: _isDodavanjeGoriva,
                            onCancel: _isDodavanjeGoriva ? null : () => Navigator.of(context).pop(),
                            onConfirm: _isDodavanjeGoriva
                                ? null
                                : () async {
                                    if (formKey.currentState?.validate() != true) return;

                                    final dodato = _toDoubleOrNull(dodatoCtrl.text)!;
                                    if (dodato <= 0) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(_GorTr.tr('unesiPozitivanBrojLitara'))),
                                      );
                                      return;
                                    }

                                    final cenaText = cenaCtrl.text.trim();
                                    double? cenaUnos;
                                    if (cenaText.isNotEmpty) {
                                      cenaUnos = _toDoubleOrNull(cenaText);
                                      if (cenaUnos == null || cenaUnos < 0) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text(_GorTr.tr('unesiIspravnuCenu'))),
                                        );
                                        return;
                                      }
                                    }

                                    final dugText = dugCtrl.text.trim();
                                    double? dugDodato;
                                    if (dugText.isNotEmpty) {
                                      dugDodato = _toDoubleOrNull(dugText);
                                      if (dugDodato == null || dugDodato < 0) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text(_GorTr.tr('unesiIspravanIznosDuga'))),
                                        );
                                        return;
                                      }
                                    } else if (cenaUnos != null && cenaUnos > 0) {
                                      dugDodato = _roundMoney(dodato * cenaUnos);
                                    }

                                    final novoStanje = trenutno + dodato;

                                    setState(() => _isDodavanjeGoriva = true);
                                    final success = await V3GorivoService.dopuniRezervoar(
                                      id: id,
                                      novoLitara: novoStanje,
                                      dugDodatoRsd: dugDodato,
                                      cenaPoLitru: cenaUnos,
                                    );
                                    if (!mounted) return;

                                    setState(() => _isDodavanjeGoriva = false);
                                    Navigator.of(context).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          success
                                              ? _GorTr.tr('gorivoDodatoNovoStanje')
                                                  .replaceAll('%NOVO%', V3FormatUtils.formatGorivo(novoStanje))
                                              : _GorTr.tr('greskaPriDodavanjuGoriva'),
                                        ),
                                      ),
                                    );
                                  },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );

    dodatoCtrl.dispose();
    cenaCtrl.dispose();
    dugCtrl.dispose();
  }

  Future<void> _openEditFuelDataSheet({required V3PumpaRezervoar? rezervoar, required V3PumpaStanje? stanje}) async {
    final String? id =
        stanje?.id.isNotEmpty == true ? stanje!.id : (rezervoar?.id.isNotEmpty == true ? rezervoar!.id : null);
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_GorTr.tr('nemaRedaZaIzmenu'))),
      );
      return;
    }

    final kapacitetCtrl = TextEditingController(
      text: (stanje?.kapacitetLitri ?? rezervoar?.kapacitetMax ?? 3000).toStringAsFixed(1),
    );
    final alarmCtrl = TextEditingController(
      text: (stanje?.alarmNivoLitri ?? rezervoar?.alarmNivo ?? 500).toStringAsFixed(1),
    );
    final prethodniBrojac = stanje?.stanjeBrojacPistolj ?? 0;
    final brojacCtrl = TextEditingController(
      text: prethodniBrojac.toStringAsFixed(1),
    );
    final cenaCtrl = TextEditingController(
      text: (stanje?.cenaPoLitru ?? 0).toStringAsFixed(2),
    );
    final dugCtrl = TextEditingController(
      text: (stanje?.dugIznos ?? 0).toStringAsFixed(2),
    );
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: V3ContainerUtils.styledContainer(
            backgroundColor: _sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: _accent.withValues(alpha: 0.3)),
            padding: EdgeInsets.zero,
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sheetHandle(),
                      _sheetHeader(
                        icon: Icons.tune_rounded,
                        iconColor: _accent,
                        title: _GorTr.tr('urediGorivo'),
                        subtitle: _GorTr.tr('uneziIzmeniPodatke'),
                      ),
                      const SizedBox(height: 18),
                      _fuelField(
                        controller: kapacitetCtrl,
                        label: _GorTr.tr('kapacitetRezervoaraL'),
                        prefixIcon: Icons.straighten_rounded,
                      ),
                      _fuelField(
                        controller: alarmCtrl,
                        label: _GorTr.tr('alarmNivoL'),
                        prefixIcon: Icons.warning_amber_rounded,
                      ),
                      _fuelField(
                        controller: brojacCtrl,
                        label: _GorTr.tr('brojacPistoljaL'),
                        prefixIcon: Icons.speed_rounded,
                      ),
                      _hintText(_GorTr.tr('trenutnoStanjeSeRacunaAutomatski')),
                      const SizedBox(height: 10),
                      _fuelField(
                        controller: cenaCtrl,
                        label: _GorTr.tr('cenaPoLitru'),
                        prefixIcon: Icons.payments_outlined,
                      ),
                      _fuelField(
                        controller: dugCtrl,
                        label: _GorTr.tr('dugRsd'),
                        prefixIcon: Icons.account_balance_wallet_outlined,
                      ),
                      const SizedBox(height: 20),
                      _sheetActions(
                        cancelLabel: _GorTr.tr('otkazi'),
                        confirmLabel: _GorTr.tr('sacuvaj'),
                        confirmColor: _accent,
                        confirmForeground: Colors.black,
                        loading: _isSavingFuelData,
                        onCancel: _isSavingFuelData ? null : () => Navigator.of(context).pop(),
                        onConfirm: _isSavingFuelData
                            ? null
                            : () async {
                                if (formKey.currentState?.validate() != true) return;

                                final kapacitet = _toDoubleOrNull(kapacitetCtrl.text)!;
                                final alarm = _toDoubleOrNull(alarmCtrl.text)!;
                                final brojac = _toDoubleOrNull(brojacCtrl.text)!;
                                final cena = _toDoubleOrNull(cenaCtrl.text)!;
                                final dug = _toDoubleOrNull(dugCtrl.text)!;

                                if (kapacitet < 0 || alarm < 0 || brojac < 0 || cena < 0 || dug < 0) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(_GorTr.tr('vrednostiNeMoguBitiNegativne'))),
                                  );
                                  return;
                                }

                                if (brojac < prethodniBrojac) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(_GorTr.tr('brojacNeMozeBitiManji'))),
                                  );
                                  return;
                                }

                                setState(() => _isSavingFuelData = true);
                                final success = await V3GorivoService.updateAllFields(
                                  id: id,
                                  kapacitetLitri: kapacitet,
                                  alarmNivoLitri: alarm,
                                  brojacPistoljLitri: brojac,
                                  cenaPoLitru: cena,
                                  dugIznos: dug,
                                );
                                if (!mounted) return;

                                setState(() => _isSavingFuelData = false);
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      success
                                          ? _GorTr.tr('podaciOGorivuSuSacuvani')
                                          : _GorTr.tr('greskaPriCuvanjuPodataka'),
                                    ),
                                  ),
                                );
                              },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    kapacitetCtrl.dispose();
    alarmCtrl.dispose();
    brojacCtrl.dispose();
    cenaCtrl.dispose();
    dugCtrl.dispose();
  }

  Widget _sheetHandle() {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }

  Widget _sheetHeader({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: iconColor.withValues(alpha: 0.35)),
          ),
          child: Icon(icon, color: iconColor, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoChipRow(List<_InfoChipData> chips) {
    return Row(
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: _infoChip(chips[i])),
        ],
      ],
    );
  }

  Widget _infoChip(_InfoChipData d) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: d.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: d.color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(d.icon, size: 14, color: d.color.withValues(alpha: 0.9)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  d.label,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            d.value,
            style: TextStyle(color: d.color, fontWeight: FontWeight.bold, fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _hintText(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(
        text,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11, height: 1.3),
      ),
    );
  }

  Widget _previewBanner({required Color color, required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sheetActions({
    required String cancelLabel,
    required String confirmLabel,
    required Color confirmColor,
    Color confirmForeground = Colors.white,
    required bool loading,
    required VoidCallback? onCancel,
    required VoidCallback? onConfirm,
  }) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onCancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(cancelLabel),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: onConfirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: confirmForeground,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: confirmForeground,
                    ),
                  )
                : Text(confirmLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ),
      ],
    );
  }

  Widget _fuelField({
    required TextEditingController controller,
    required String label,
    IconData? prefixIcon,
    bool requiredField = true,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: V3InputUtils.formField(
        controller: controller,
        label: label,
        icon: prefixIcon ?? Icons.numbers,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
        showPaste: false,
        onChanged: onChanged,
        validator: (value) {
          final text = value?.trim() ?? '';
          if (text.isEmpty) {
            return requiredField ? _GorTr.tr('obaveznoPolje') : null;
          }
          if (_toDoubleOrNull(text) == null) {
            return _GorTr.tr('unesiBroj');
          }
          return null;
        },
      ),
    );
  }

  Future<void> _createInitialData() async {
    if (_isCreatingInitialData) return;

    setState(() => _isCreatingInitialData = true);
    final success = await V3GorivoService.ensureInitialData();
    if (!mounted) return;

    setState(() => _isCreatingInitialData = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? _GorTr.tr('pocetniPodaciZaGorivoSuKreirani') : _GorTr.tr('neuspesnoKreiranjePocetnihPodataka'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<_GorivoData>(
      stream: V3MasterRealtimeManager.instance.v3StreamFromRevisions<_GorivoData>(
        tables: ['v3_gorivo'],
        build: () => _GorivoData(
          stanje: V3GorivoService.getStanjeSync(),
          rezervoar: V3GorivoService.getRezervoarSync(),
        ),
      ),
      builder: (context, snapshot) {
        final data = snapshot.data ??
            _GorivoData(
              stanje: V3GorivoService.getStanjeSync(),
              rezervoar: V3GorivoService.getRezervoarSync(),
            );
        return _buildScaffold(context, data);
      },
    );
  }

  Widget _buildScaffold(BuildContext context, _GorivoData data) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: Theme.of(context).backgroundGradient,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).glassBorder),
            ),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⛽', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(
              _GorTr.tr('gorivo'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
              ),
            ),
          ],
        ),
      ),
      body: V3ContainerUtils.backgroundContainer(
        gradient: Theme.of(context).backgroundGradient,
        child: _buildBody(data.rezervoar, data.stanje),
      ),
    );
  }

  Widget _buildBody(V3PumpaRezervoar? r, V3PumpaStanje? stanje) {
    final media = MediaQuery.of(context);
    final bool isCompact = media.size.width < 360;
    final double? kapacitet = stanje?.kapacitetLitri ?? r?.kapacitetMax;
    final double? trenutno = stanje?.trenutnoStanje ?? r?.trenutnoLitara;
    final double? alarmNivo = stanje?.alarmNivoLitri ?? r?.alarmNivo;
    final bool hasFuelData = kapacitet != null && trenutno != null && alarmNivo != null;
    final bool ispodAlarma = hasFuelData ? (trenutno <= alarmNivo) : false;
    final double procenat = hasFuelData && kapacitet > 0 ? ((trenutno / kapacitet).clamp(0.0, 1.0)) : 0.0;

    final topPad = media.padding.top + kToolbarHeight + (isCompact ? 12 : 16);
    final hPad = isCompact ? 12.0 : 16.0;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(hPad, topPad, hPad, media.padding.bottom + 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasFuelData) ...[
            _FuelHeroCard(
              trenutno: trenutno,
              kapacitet: kapacitet,
              procenat: procenat,
              ispodAlarma: ispodAlarma,
              isCompact: isCompact,
            ),
            SizedBox(height: isCompact ? 14 : 16),
            _buildStatsGrid(
              alarmNivo: alarmNivo,
              ispodAlarma: ispodAlarma,
              stanje: stanje,
              isCompact: isCompact,
            ),
            SizedBox(height: isCompact ? 16 : 18),
            _buildPrimaryAction(
              onPressed: _isDodavanjeGoriva ? null : () => _openDopunaSheet(rezervoar: r, stanje: stanje),
              loading: _isDodavanjeGoriva,
              label: _isDodavanjeGoriva ? _GorTr.tr('dodavanjeDots') : _GorTr.tr('dodajGorivo'),
              icon: Icons.add_circle_rounded,
              colors: [Colors.green.shade700, Colors.green.shade500],
            ),
            if (stanje != null || r != null) ...[
              const SizedBox(height: 10),
              _buildSecondaryAction(
                onPressed: _isSavingFuelData ? null : () => _openEditFuelDataSheet(rezervoar: r, stanje: stanje),
                loading: _isSavingFuelData,
                label: _GorTr.tr('uneziIzmeniPodatke'),
                icon: Icons.edit_rounded,
              ),
            ],
          ] else ...[
            _buildEmptyState(isCompact),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isCompact) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: isCompact ? 24 : 40),
      padding: EdgeInsets.all(isCompact ? 24 : 32),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _accent.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(color: _accent.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: _accent.withValues(alpha: 0.4)),
            ),
            child: const Center(child: Text('⛽', style: TextStyle(fontSize: 34))),
          ),
          const SizedBox(height: 18),
          Text(
            _GorTr.tr('nemaPodatakaOGorivuUBazi'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 15,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isCreatingInitialData ? null : _createInitialData,
              icon: _isCreatingInitialData
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.add_rounded),
              label: Text(
                _isCreatingInitialData ? _GorTr.tr('kreiranjeDots') : _GorTr.tr('dodajPocetnePodatke'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.black,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid({
    required double alarmNivo,
    required bool ispodAlarma,
    required V3PumpaStanje? stanje,
    required bool isCompact,
  }) {
    final gap = isCompact ? 8.0 : 10.0;
    final dug = stanje?.dugIznos ?? 0;
    final cena = stanje?.cenaPoLitru;
    final brojac = stanje?.stanjeBrojacPistolj;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.warning_amber_rounded,
                label: _GorTr.tr('alarmNivoRezervoara'),
                value: '${V3FormatUtils.formatGorivo(alarmNivo)} L',
                color: ispodAlarma ? Colors.redAccent : const Color(0xFFFFB74D),
                isCompact: isCompact,
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              child: _StatTile(
                icon: Icons.speed_rounded,
                label: _GorTr.tr('stanjeBrojacaPistolja'),
                value: brojac != null ? '${V3FormatUtils.formatGorivo(brojac)} L' : '—',
                color: const Color(0xFF64B5F6),
                isCompact: isCompact,
              ),
            ),
          ],
        ),
        SizedBox(height: gap),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.payments_outlined,
                label: _GorTr.tr('cenaPoLitruEmoji'),
                value: cena != null ? '${cena.toStringAsFixed(2)} RSD' : '—',
                color: const Color(0xFFFFD54F),
                isCompact: isCompact,
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              child: _StatTile(
                icon: Icons.account_balance_wallet_outlined,
                label: _GorTr.tr('dugIznos'),
                value: stanje != null ? '${dug.toStringAsFixed(0)} RSD' : '—',
                color: dug > 0 ? const Color(0xFFEF5350) : const Color(0xFF66BB6A),
                isCompact: isCompact,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPrimaryAction({
    required VoidCallback? onPressed,
    required bool loading,
    required String label,
    required IconData icon,
    required List<Color> colors,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 54,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors:
                  onPressed == null ? [colors[0].withValues(alpha: 0.4), colors[1].withValues(alpha: 0.35)] : colors,
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: onPressed == null
                ? null
                : [
                    BoxShadow(
                      color: colors[0].withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                )
              else
                Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryAction({
    required VoidCallback? onPressed,
    required bool loading,
    required String label,
    required IconData icon,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
              )
            : Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          foregroundColor: _accent,
          side: BorderSide(color: _accent.withValues(alpha: 0.45)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

class _InfoChipData {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _InfoChipData({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
}

class _FuelHeroCard extends StatelessWidget {
  const _FuelHeroCard({
    required this.trenutno,
    required this.kapacitet,
    required this.procenat,
    required this.ispodAlarma,
    required this.isCompact,
  });

  final double trenutno;
  final double kapacitet;
  final double procenat;
  final bool ispodAlarma;
  final bool isCompact;

  Color get _statusColor {
    if (ispodAlarma) return const Color(0xFFEF5350);
    if (procenat > 0.55) return const Color(0xFF66BB6A);
    return const Color(0xFFFFA726);
  }

  List<Color> get _gradientColors {
    if (ispodAlarma) return [const Color(0xFF7F1D1D), const Color(0xFFB91C1C)];
    if (procenat > 0.55) return [const Color(0xFF14532D), const Color(0xFF15803D)];
    return [const Color(0xFF7C2D12), const Color(0xFFC2410C)];
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor;
    final gaugeSize = isCompact ? 148.0 : 168.0;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E2235),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.18), blurRadius: 22, offset: const Offset(0, 8)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: isCompact ? 14 : 18, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _gradientColors,
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(child: Text('⛽', style: TextStyle(fontSize: 20))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _GorTr.tr('gorivo'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        _GorTr.tr('odKapaciteta'),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (ispodAlarma)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white38),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_rounded, color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          _GorTr.tr('maloGoriva'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              isCompact ? 14 : 20,
              isCompact ? 18 : 22,
              isCompact ? 14 : 20,
              isCompact ? 16 : 20,
            ),
            child: Column(
              children: [
                SizedBox(
                  width: gaugeSize,
                  height: gaugeSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: Size(gaugeSize, gaugeSize),
                        painter: _FuelGaugePainter(
                          progress: procenat,
                          color: color,
                          trackColor: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${(procenat * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: color,
                              fontSize: isCompact ? 34 : 38,
                              fontWeight: FontWeight.w800,
                              height: 1.05,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: isCompact ? 14 : 18),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${V3FormatUtils.formatGorivo(trenutno)} L',
                    style: TextStyle(
                      fontSize: isCompact ? 34 : 40,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.8,
                      height: 1.05,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_GorTr.tr('odKapaciteta')} ${V3FormatUtils.formatGorivo(kapacitet)} L',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: isCompact ? 13 : 14,
                  ),
                ),
                SizedBox(height: isCompact ? 14 : 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    height: isCompact ? 12 : 14,
                    child: Stack(
                      children: [
                        Container(color: Colors.white.withValues(alpha: 0.08)),
                        FractionallySizedBox(
                          widthFactor: procenat,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [color.withValues(alpha: 0.75), color],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('0 L', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
                    Text(
                      '${V3FormatUtils.formatGorivo(kapacitet)} L',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FuelGaugePainter extends CustomPainter {
  _FuelGaugePainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final stroke = size.width * 0.1;
    final radius = (size.width - stroke) / 2;
    const startAngle = -math.pi * 0.75;
    const sweepTotal = math.pi * 1.5;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [
          color.withValues(alpha: 0.55),
          color,
          color.withValues(alpha: 0.9),
        ],
        transform: const GradientRotation(startAngle),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke + 8
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepTotal,
      false,
      trackPaint,
    );

    final sweep = sweepTotal * progress.clamp(0.0, 1.0);
    if (sweep > 0.001) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        false,
        glowPaint,
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FuelGaugePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color || oldDelegate.trackColor != trackColor;
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.isCompact,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(isCompact ? 12 : 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2235),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.28), width: 1.2),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          SizedBox(height: isCompact ? 10 : 12),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: isCompact ? 10.5 : 11,
              height: 1.25,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: isCompact ? 15 : 16,
                letterSpacing: -0.2,
              ),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _GorivoData {
  final V3PumpaStanje? stanje;
  final V3PumpaRezervoar? rezervoar;
  _GorivoData({required this.stanje, required this.rezervoar});
}
