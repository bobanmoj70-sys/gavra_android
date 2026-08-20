import 'package:flutter/material.dart';

import '../l10n/app_translations.dart';
import '../models/v3_vozac.dart';
import '../models/v3_vozilo.dart';
import '../services/v3/v3_vozac_service.dart';
import '../services/v3/v3_vozilo_service.dart';
import '../services/v3_locale_manager.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_belgrade_time.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_card_color_policy.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dialog_helper.dart';
import '../utils/v3_format_utils.dart';
import '../utils/v3_input_utils.dart';
import '../utils/v3_ui_utils.dart';

class _OdrTr {
  static final Map<String, Map<String, String>> _t = AppTranslations.ns('odrzavanjeScreen');

  static String tr(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    return _t[key]?[code] ?? _t[key]?['sr'] ?? key;
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

Color _getVoziloColor(String reg) {
  if (reg.contains('066')) return Colors.blue;
  if (reg.contains('088')) return Colors.white;
  if (reg.contains('093')) return Colors.red;
  if (reg.contains('097')) return Colors.white;
  if (reg.contains('102')) return Colors.blue;
  return Colors.grey.shade400;
}

Widget _buildTablica(String registracija, {required bool selected}) {
  final text = registracija.trim().isEmpty ? '—' : registracija.trim().toUpperCase();
  return Container(
    width: 86,
    height: 24,
    decoration: BoxDecoration(
      color: const Color(0xFFF4F4F0),
      borderRadius: BorderRadius.circular(3),
      border: Border.all(
        color: selected ? Colors.amber : const Color(0xFF1A1A1A),
        width: selected ? 2 : 1,
      ),
    ),
    child: Row(
      children: [
        Container(
          width: 14,
          decoration: const BoxDecoration(
            color: Color(0xFF003399),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(2),
              bottomLeft: Radius.circular(2),
            ),
          ),
          alignment: Alignment.center,
          child: const RotatedBox(
            quarterTurns: 3,
            child: Text(
              'SRB',
              style: TextStyle(
                color: Colors.white,
                fontSize: 6,
                fontWeight: FontWeight.w800,
                height: 1,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                text,
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 0.4,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

List<BoxShadow>? _getRegistracijaSenka(V3Vozilo v) {
  if (v.registracijaVaziDo == null) return null;
  final dana = v.danaDoIstekaRegistracije;
  if (dana >= 15 && dana <= 30) {
    return [BoxShadow(color: Colors.lime.withValues(alpha: 0.6), blurRadius: 12, spreadRadius: 3)];
  }
  return null;
}

String _formatServis(DateTime? datum, int? km) {
  if (datum == null && km == null) return '-';
  final parts = <String>[];
  if (datum != null) parts.add(V3Vozilo.formatDatum(datum));
  if (km != null) parts.add('${V3FormatUtils.formatBroj(km)} km');
  return parts.join(' · ');
}

String? _formatGumeSubtitle(DateTime? datum, int? km) {
  if (datum == null && km == null) return null;
  final parts = <String>[];
  if (datum != null) parts.add('${_OdrTr.tr('menjane')}: ${V3Vozilo.formatDatum(datum)}');
  if (km != null) parts.add('${V3FormatUtils.formatBroj(km)} km');
  return parts.join(' · ');
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class V3OdrzavanjeScreen extends StatefulWidget {
  const V3OdrzavanjeScreen({super.key});

  @override
  State<V3OdrzavanjeScreen> createState() => _V3OdrzavanjeScreenState();
}

class _V3OdrzavanjeScreenState extends State<V3OdrzavanjeScreen> {
  V3Vozilo? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(_OdrTr.tr('kolskaKnjiga')),
        centerTitle: true,
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: Colors.grey.shade900,
            onSelected: (value) {
              if (value == 'add') {
                _addVozilo();
              } else if (value == 'assign') {
                _showDodeliKombiDialog();
              } else if (value == 'delete') {
                _deleteVozilo();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'add',
                child: Row(
                  children: [
                    const Icon(Icons.add, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(_OdrTr.tr('dodajVozilo'), style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'assign',
                child: Row(
                  children: [
                    const Icon(Icons.airport_shuttle, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text(_OdrTr.tr('dodeliKombiVozacima'), style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    const Icon(Icons.delete, color: Colors.red),
                    const SizedBox(width: 8),
                    Text(_OdrTr.tr('obrisiVozilo'), style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.85),
              theme.colorScheme.secondary.withValues(alpha: 0.75),
              Colors.black87,
            ],
          ),
        ),
        child: SafeArea(
          child: StreamBuilder<List<V3Vozilo>>(
            stream: V3VoziloService.streamVozila(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                    child:
                        Text('${_OdrTr.tr('greska')}: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator(color: Colors.white));
              }

              final vozila = snapshot.data!;
              if (vozila.isEmpty) {
                return Center(child: Text(_OdrTr.tr('nemaVozila'), style: const TextStyle(color: Colors.white)));
              }

              if (_selected == null) {
                _selected = vozila.first;
              } else {
                final exists = vozila.any((v) => v.id == _selected!.id);
                _selected = exists ? vozila.firstWhere((v) => v.id == _selected!.id) : vozila.first;
              }

              return Column(
                children: [
                  _buildVoziloPicker(vozila),
                  Expanded(child: _buildKolskaKnjiga(_selected!)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ── Vozilo picker ──────────────────────────────────────────────────────────

  Widget _buildVoziloPicker(List<V3Vozilo> vozila) {
    final sorted = List<V3Vozilo>.from(vozila)
      ..sort((a, b) {
        if (a.registracija.contains('066')) return -1;
        if (b.registracija.contains('066')) return 1;
        if (a.registracija.contains('102')) return 1;
        if (b.registracija.contains('102')) return -1;
        return a.registracija.compareTo(b.registracija);
      });

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: sorted.map((v) {
            final isSel = v.id == _selected?.id;
            final color = _getVoziloColor(v.registracija);
            final borderColor = isSel ? (color == Colors.white ? Colors.black : color) : Colors.white24;
            final senka = _getRegistracijaSenka(v);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: GestureDetector(
                onTap: () => setState(() => _selected = v),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    V3ContainerUtils.styledContainer(
                      padding: const EdgeInsets.all(6),
                      backgroundColor: isSel
                          ? (color == Colors.white
                              ? Colors.grey.shade200.withValues(alpha: 0.3)
                              : color.withValues(alpha: 0.25))
                          : Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: borderColor, width: isSel ? 2 : 1),
                      boxShadow: senka,
                      child: Icon(Icons.airport_shuttle,
                          size: 32,
                          color: color,
                          shadows: [Shadow(color: Colors.black54, blurRadius: 2, offset: const Offset(1, 1))]),
                    ),
                    const SizedBox(height: 3),
                    _buildTablica(v.registracija, selected: isSel),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Kolska knjiga ──────────────────────────────────────────────────────────

  Widget _buildKolskaKnjiga(V3Vozilo v) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Zaglavlje
          _GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.displayNaziv,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 4),
                Text('${_OdrTr.tr('registracija')}: ${v.registracija}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.75))),
                if (v.godinaProizvodnje != null)
                  Text('${_OdrTr.tr('godinaLabel')}: ${v.godinaProizvodnje}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.75))),
                const SizedBox(height: 10),
                _buildVozacDodelaRow(v),
                const SizedBox(height: 10),
                V3ContainerUtils.styledContainer(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.speed, size: 16, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(_OdrTr.tr('kilometraza'),
                          style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
                      Text('${V3FormatUtils.formatBroj(v.trenutnaKm)} km',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Tablice
          _EditableField(
            icon: '🚘',
            label: _OdrTr.tr('registracija'),
            value: v.registracija.trim().isEmpty ? '-' : v.registracija.trim().toUpperCase(),
            onEdit: () => _editText('registracija', _OdrTr.tr('registracija'), v.registracija),
          ),

          // Šasija
          _EditableField(
            icon: '🔢',
            label: _OdrTr.tr('brojSasijeVin'),
            value: v.brojSasije,
            onEdit: () => _editText('broj_sasije', _OdrTr.tr('brojSasije'), v.brojSasije),
          ),

          // Registracija
          _EditableField(
            icon: '📋',
            label: _OdrTr.tr('registracijaVaziDo'),
            value: V3Vozilo.formatDatum(v.registracijaVaziDo),
            valueColor: v.registracijaIstekla
                ? Colors.red.shade300
                : v.registracijaIstice
                    ? Colors.orange.shade300
                    : null,
            badge: v.registracijaIstekla
                ? _OdrTr.tr('istekla')
                : v.registracijaIstice
                    ? '${v.danaDoIstekaRegistracije} ${_OdrTr.tr('dana')}'
                    : null,
            badgeColor: v.registracijaIstekla ? Colors.red : Colors.orange,
            onEdit: () => _editDate('registracija_vazi_do', _OdrTr.tr('registracijaVaziDo'), v.registracijaVaziDo),
          ),

          // Napomena
          _EditableField(
            icon: '📝',
            label: _OdrTr.tr('napomena'),
            value: v.napomena ?? '-',
            onEdit: () => _editText('napomena', _OdrTr.tr('napomena'), v.napomena, multiline: true),
          ),

          _SectionDivider(),

          // Servisi
          _EditableField(
            icon: '🔧',
            label: _OdrTr.tr('maliServis'),
            value: _formatServis(v.maliServisDatum, v.maliServisKm),
            onEdit: () => _editServis(
                'mali_servis', _OdrTr.tr('maliServis'), v.maliServisDatum, v.maliServisKm, v.trenutnaKm.toInt()),
          ),
          _EditableField(
            icon: '🛠️',
            label: _OdrTr.tr('velikiServis'),
            value: _formatServis(v.velikiServisDatum, v.velikiServisKm),
            onEdit: () => _editServis('veliki_servis', _OdrTr.tr('velikiServis'), v.velikiServisDatum, v.velikiServisKm,
                v.trenutnaKm.toInt()),
          ),
          _EditableField(
            icon: '⚡',
            label: _OdrTr.tr('alternator'),
            value: _formatServis(v.alternatorDatum, v.alternatorKm),
            onEdit: () => _editServis(
                'alternator', _OdrTr.tr('alternator'), v.alternatorDatum, v.alternatorKm, v.trenutnaKm.toInt()),
          ),
          _EditableField(
            icon: '🔋',
            label: _OdrTr.tr('akumulator'),
            value: _formatServis(v.akumulatorDatum, v.akumulatorKm),
            onEdit: () => _editServis(
                'akumulator', _OdrTr.tr('akumulator'), v.akumulatorDatum, v.akumulatorKm, v.trenutnaKm.toInt()),
          ),
          _EditableField(
            icon: '🛑',
            label: _OdrTr.tr('plocicePrednje'),
            value: _formatServis(v.plocicePrednjeDatum, v.plocicePrednjeKm),
            onEdit: () => _editServis('plocice_prednje', _OdrTr.tr('plocicePrednje'), v.plocicePrednjeDatum,
                v.plocicePrednjeKm, v.trenutnaKm.toInt()),
          ),
          _EditableField(
            icon: '🛑',
            label: _OdrTr.tr('plociceZadnje'),
            value: _formatServis(v.plociceZadnjeDatum, v.plociceZadnjeKm),
            onEdit: () => _editServis('plocice_zadnje', _OdrTr.tr('plociceZadnje'), v.plociceZadnjeDatum,
                v.plociceZadnjeKm, v.trenutnaKm.toInt()),
          ),
          _EditableField(
            icon: '🔩',
            label: _OdrTr.tr('trap'),
            value: _formatServis(v.trapDatum, v.trapKm),
            onEdit: () => _editServis('trap', _OdrTr.tr('trap'), v.trapDatum, v.trapKm, v.trenutnaKm.toInt()),
          ),

          _SectionDivider(),

          // Gume
          _EditableField(
            icon: '🛞',
            label: _OdrTr.tr('gumePrednje'),
            value: v.gumePrednjeOpis ?? '-',
            subtitle: _formatGumeSubtitle(v.gumePrednjeDatum, v.gumePrednjeKm),
            onEdit: () =>
                _editGume('prednje', v.gumePrednjeDatum, v.gumePrednjeOpis, v.gumePrednjeKm, v.trenutnaKm.toInt()),
          ),
          _EditableField(
            icon: '🛞',
            label: _OdrTr.tr('gumeZadnje'),
            value: v.gumeZadnjeOpis ?? '-',
            subtitle: _formatGumeSubtitle(v.gumeZadnjeDatum, v.gumeZadnjeKm),
            onEdit: () =>
                _editGume('zadnje', v.gumeZadnjeDatum, v.gumeZadnjeOpis, v.gumeZadnjeKm, v.trenutnaKm.toInt()),
          ),

          _SectionDivider(),

          // Radio
          _EditableField(
            icon: '📻',
            label: _OdrTr.tr('radioCode'),
            value: v.radio ?? '-',
            onEdit: () => _editText('radio', _OdrTr.tr('radioCode'), v.radio),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildVozacDodelaRow(V3Vozilo v) {
    final vozacId = (v.vozacId ?? '').trim();
    final vozac = vozacId.isEmpty ? null : V3VozacService.getVozacById(vozacId);
    final assigned = vozac != null;
    final label = assigned ? '${_OdrTr.tr('vozac')}: ${vozac.imePrezime}' : _OdrTr.tr('tapZaDodeluVozaca');

    return GestureDetector(
      onTap: () => _showVozacForVoziloDialog(v),
      child: V3ContainerUtils.styledContainer(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        backgroundColor: Colors.white.withValues(alpha: assigned ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        child: Row(
          children: [
            Icon(Icons.person, color: assigned ? Colors.orange.shade200 : Colors.white70, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: assigned ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            Icon(Icons.edit_outlined, color: Colors.white.withValues(alpha: 0.7), size: 16),
          ],
        ),
      ),
    );
  }

  // ── Edit handlers ─────────────────────────────────────────────────────────

  void _editText(String field, String label, String? current, {bool multiline = false}) {
    V3DialogHelper.showDialogBuilder<void>(
      context: context,
      builder: (_) => _TextDialog(
        field: field,
        label: label,
        voziloId: _selected!.id,
        currentValue: current,
        multiline: multiline,
      ),
    );
  }

  Future<void> _editDate(String field, String label, DateTime? current) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? V3BelgradeTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: label,
    );
    if (picked == null || !mounted) return;
    try {
      await V3VoziloService.updateKolskaKnjiga(
          _selected!.id, {field: V3BelgradeTime.parseIsoDatePart(picked.toIso8601String())});
      V3UIUtils.showSaveSuccess(context);
    } catch (_) {
      V3UIUtils.showSaveError(context);
    }
  }

  Future<void> _editServis(String prefix, String label, DateTime? datum, int? km, int trenutnaKm) {
    return V3DialogHelper.showBottomSheetBuilder<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ServisSheet(
        prefix: prefix,
        label: label,
        datum: datum,
        km: km,
        voziloId: _selected!.id,
        trenutnaKm: trenutnaKm,
      ),
    );
  }

  Future<void> _editGume(String pozicija, DateTime? datum, String? opis, int? km, int trenutnaKm) {
    return V3DialogHelper.showBottomSheetBuilder<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GumeSheet(
        pozicija: pozicija,
        datum: datum,
        opis: opis,
        km: km,
        voziloId: _selected!.id,
        trenutnaKm: trenutnaKm,
      ),
    );
  }

  Future<void> _addVozilo() async {
    final result = await V3DialogHelper.showDialogBuilder<V3Vozilo?>(
      context: context,
      builder: (_) => const _AddVoziloDialog(),
    );
    if (result == null || !mounted) return;
    try {
      await V3VoziloService.addUpdateVozilo(result);
      if (!mounted) return;
      V3AppSnackBar.success(context, _OdrTr.tr('voziloDodato'));
    } catch (_) {
      if (!mounted) return;
      V3UIUtils.showSaveError(context);
    }
  }

  Future<void> _deleteVozilo() async {
    final selected = _selected;
    if (selected == null) return;
    final confirmed = await V3DialogHelper.showConfirmDialog(
      context,
      title: _OdrTr.tr('potvrdiBrisanjeVozila'),
      message: _OdrTr.tr('potvrdiBrisanjeVozilaPoruka'),
      confirmText: _OdrTr.tr('obrisiVozilo'),
      cancelText: _OdrTr.tr('otkazi'),
      isDangerous: true,
    );
    if (confirmed != true || !mounted) return;
    try {
      await V3VoziloService.deleteVozilo(selected.id);
      if (!mounted) return;
      setState(() => _selected = null);
      V3AppSnackBar.success(context, _OdrTr.tr('voziloObrisano'));
    } catch (_) {
      if (!mounted) return;
      V3UIUtils.showSaveError(context);
    }
  }

  // ── Kombi dodela dialog ───────────────────────────────────────────────────

  void _showDodeliKombiDialog() {
    V3DialogHelper.showDialogBuilder<void>(
      context: context,
      builder: (_) => const _DodeliKombiDialog(),
    );
  }

  Future<void> _showVozacForVoziloDialog(V3Vozilo vozilo) async {
    final vozaci = V3VozacService.getAllVozaci();
    if (vozaci.isEmpty) {
      if (mounted) V3AppSnackBar.warning(context, _OdrTr.tr('nemaRegistrovanihVozaca'));
      return;
    }

    final trenutniId = (vozilo.vozacId ?? '').trim();
    V3Vozac? odabran = trenutniId.isEmpty ? null : V3VozacService.getVozacById(trenutniId);

    await V3DialogHelper.showBottomSheetBuilder<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                vozilo.tablicaINaziv,
                style: const TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1),
              ),
              const SizedBox(height: 6),
              Text(
                _OdrTr.tr('dodeliVozacaKombiju'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView(
                  shrinkWrap: true,
                  children: vozaci
                      .map(
                        (v) => _VozacAssignTile(
                          ime: v.imePrezime,
                          isSelected: odabran?.id == v.id,
                          color: V3CardColorPolicy.vozacColorOr(v.boja),
                          onTap: () => setS(() => odabran = odabran?.id == v.id ? null : v),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 8),
              if (trenutniId.isNotEmpty)
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      await V3VoziloService.assignVozacToVozilo(voziloId: vozilo.id);
                      if (!mounted) return;
                      V3AppSnackBar.success(context, _OdrTr.tr('kombiUklonjen'));
                    } catch (_) {
                      if (!mounted) return;
                      V3UIUtils.showSaveError(context);
                    }
                  },
                  icon: const Icon(Icons.clear, color: Colors.redAccent, size: 18),
                  label: Text(_OdrTr.tr('nijeDodeljen'), style: const TextStyle(color: Colors.redAccent)),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: V3ButtonUtils.elevatedButton(
                  onPressed: odabran == null
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          try {
                            await V3VoziloService.assignVozacToVozilo(
                              voziloId: vozilo.id,
                              vozacId: odabran!.id,
                            );
                            if (!mounted) return;
                            V3AppSnackBar.success(context, _OdrTr.tr('kombiDodeljen'));
                          } catch (_) {
                            if (!mounted) return;
                            V3UIUtils.showSaveError(context);
                          }
                        },
                  text: _OdrTr.tr('sacuvaj'),
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  foregroundColor: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Glassmorphism Card ───────────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1),
      ),
      child: child,
    );
  }
}

// ─── Section Divider ─────────────────────────────────────────────────────────

class _SectionDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Divider(color: Colors.white.withValues(alpha: 0.2), height: 1),
    );
  }
}

// ─── Editable field ───────────────────────────────────────────────────────────

class _EditableField extends StatelessWidget {
  final String icon;
  final String label;
  final String? value;
  final String? subtitle;
  final Color? valueColor;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback onEdit;

  const _EditableField({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    this.valueColor,
    this.badge,
    this.badgeColor,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6))),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          value ?? '-',
                          style:
                              TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: valueColor ?? Colors.white),
                        ),
                      ),
                      if (badge != null)
                        V3ContainerUtils.styledContainer(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          backgroundColor: badgeColor?.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: badgeColor ?? Colors.white, width: 0.8),
                          child: Text(badge!,
                              style: TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.bold, color: badgeColor ?? Colors.white)),
                        ),
                    ],
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child:
                          Text(subtitle!, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.55))),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 18, color: Colors.white70),
              onPressed: onEdit,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(
                minWidth: V3ContainerUtils.responsiveHeight(context, 32),
                minHeight: V3ContainerUtils.responsiveHeight(context, 32),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Text Dialog ─────────────────────────────────────────────────────────────

class _TextDialog extends StatefulWidget {
  final String field;
  final String label;
  final String voziloId;
  final String? currentValue;
  final bool multiline;

  const _TextDialog({
    required this.field,
    required this.label,
    required this.voziloId,
    this.currentValue,
    this.multiline = false,
  });

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentValue);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey.shade900,
      title: Text(widget.label, style: const TextStyle(color: Colors.white)),
      content: V3InputUtils.textField(
        controller: _ctrl,
        label: '${_OdrTr.tr('unesi')} ${widget.label}',
        maxLines: widget.multiline ? 4 : 1,
      ),
      actions: [
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.pop(context),
          text: _OdrTr.tr('otkazi'),
          foregroundColor: Colors.white60,
        ),
        V3ButtonUtils.textButton(
          onPressed: () async {
            final text = _ctrl.text.trim();
            if (widget.field == 'registracija' && text.isEmpty) {
              V3AppSnackBar.warning(context, _OdrTr.tr('registracijaObavezna'));
              return;
            }
            try {
              await V3VoziloService.updateKolskaKnjiga(
                widget.voziloId,
                {
                  widget.field: text.isEmpty ? null : (widget.field == 'registracija' ? text.toUpperCase() : text),
                },
              );
              if (!context.mounted) return;
              Navigator.pop(context);
              V3UIUtils.showSaveSuccess(context);
            } catch (_) {
              if (!context.mounted) return;
              Navigator.pop(context);
              V3UIUtils.showSaveError(context);
            }
          },
          text: _OdrTr.tr('sacuvaj'),
          foregroundColor: Colors.orange,
        ),
      ],
    );
  }
}

// ─── Servis Sheet ─────────────────────────────────────────────────────────────

class _ServisSheet extends StatefulWidget {
  final String prefix;
  final String label;
  final String voziloId;
  final DateTime? datum;
  final int? km;
  final int trenutnaKm;

  const _ServisSheet({
    required this.prefix,
    required this.label,
    required this.voziloId,
    this.datum,
    this.km,
    this.trenutnaKm = 0,
  });

  @override
  State<_ServisSheet> createState() => _ServisSheetState();
}

class _ServisSheetState extends State<_ServisSheet> {
  late DateTime? _datum;
  late final TextEditingController _kmCtrl;

  @override
  void initState() {
    super.initState();
    _datum = widget.datum ?? V3BelgradeTime.now();
    _kmCtrl = TextEditingController(text: (widget.km ?? widget.trenutnaKm).toString());
  }

  @override
  void dispose() {
    _kmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.label,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _datum ?? V3BelgradeTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: V3BelgradeTime.now(),
                    );
                    if (picked != null) setState(() => _datum = picked);
                  },
                  child: InputDecorator(
                    decoration: V3InputUtils.decoration(
                      label: _OdrTr.tr('datum'),
                      icon: Icons.calendar_today,
                    ),
                    child: Text(
                      _datum != null ? '${_datum!.day}.${_datum!.month}.${_datum!.year}' : _OdrTr.tr('izaberiDatum'),
                      style: V3InputUtils.fieldTextStyle,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                V3InputUtils.numberField(
                  controller: _kmCtrl,
                  label: _OdrTr.tr('kilometrazaServisa'),
                  hint: '${_OdrTr.tr('trenutno')}: ${widget.trenutnaKm} km',
                  suffixText: 'km',
                ),
                const SizedBox(height: 24),
                V3ButtonUtils.elevatedButton(
                  onPressed: () async {
                    final kmValue = int.tryParse(_kmCtrl.text);
                    final data = <String, dynamic>{
                      '${widget.prefix}_datum': V3BelgradeTime.parseIsoDatePart(_datum?.toIso8601String() ?? ''),
                      '${widget.prefix}_km': kmValue,
                    };
                    try {
                      await V3VoziloService.updateKolskaKnjiga(widget.voziloId, data);
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      V3UIUtils.showSaveSuccess(context);
                    } catch (_) {
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      V3UIUtils.showSaveError(context);
                    }
                  },
                  text: _OdrTr.tr('sacuvaj'),
                  icon: Icons.save,
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Gume Sheet ───────────────────────────────────────────────────────────────

class _GumeSheet extends StatefulWidget {
  final String pozicija;
  final String voziloId;
  final DateTime? datum;
  final String? opis;
  final int? km;
  final int trenutnaKm;

  const _GumeSheet({
    required this.pozicija,
    required this.voziloId,
    this.datum,
    this.opis,
    this.km,
    this.trenutnaKm = 0,
  });

  @override
  State<_GumeSheet> createState() => _GumeSheetState();
}

class _GumeSheetState extends State<_GumeSheet> {
  late DateTime? _datum;
  late final TextEditingController _opisCtrl;
  late final TextEditingController _kmCtrl;
  String? _tip;

  @override
  void initState() {
    super.initState();
    _datum = widget.datum ?? V3BelgradeTime.now();
    _opisCtrl = TextEditingController(text: widget.opis ?? '');
    _kmCtrl = TextEditingController(text: (widget.km ?? widget.trenutnaKm).toString());
    final o = widget.opis;
    if (o != null) {
      if (o.contains('☀️') || o.toLowerCase().contains('letn'))
        _tip = 'letnje';
      else if (o.contains('❄️') || o.toLowerCase().contains('zimsk'))
        _tip = 'zimske';
      else if (o.contains('🛤️') || o.toLowerCase().contains('m+s') || o.toLowerCase().contains('univerzal'))
        _tip = 'ms';
    }
  }

  @override
  void dispose() {
    _opisCtrl.dispose();
    _kmCtrl.dispose();
    super.dispose();
  }

  Widget _tipChip(String label, String value) {
    final isSel = _tip == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tip = isSel ? null : value),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: isSel ? Colors.orange.withValues(alpha: 0.25) : Colors.white10,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSel ? Colors.orange : Colors.white24, width: isSel ? 2 : 1),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                  color: isSel ? Colors.orange : Colors.white70,
                  fontSize: 13)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.pozicija == 'prednje' ? _OdrTr.tr('gumePrednje') : _OdrTr.tr('gumeZadnje');
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('🛞 $label',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    textAlign: TextAlign.center),
                const SizedBox(height: 20),
                Text(_OdrTr.tr('tipGuma'), style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white70)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _tipChip(_OdrTr.tr('letnje'), 'letnje'),
                    const SizedBox(width: 8),
                    _tipChip(_OdrTr.tr('zimske'), 'zimske'),
                    const SizedBox(width: 8),
                    _tipChip('🛤️ M+S', 'ms'),
                  ],
                ),
                const SizedBox(height: 16),
                V3InputUtils.textField(
                  controller: _opisCtrl,
                  label: _OdrTr.tr('markaIDimenzija'),
                  hint: _OdrTr.tr('nprMichelin'),
                  icon: Icons.description,
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _datum ?? V3BelgradeTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: V3BelgradeTime.now(),
                    );
                    if (picked != null) setState(() => _datum = picked);
                  },
                  child: InputDecorator(
                    decoration: V3InputUtils.decoration(
                      label: _OdrTr.tr('datumZamene'),
                      icon: Icons.calendar_today,
                    ),
                    child: Text(
                      _datum != null ? '${_datum!.day}.${_datum!.month}.${_datum!.year}' : _OdrTr.tr('izaberiDatum'),
                      style: V3InputUtils.fieldTextStyle,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                V3InputUtils.numberField(
                  controller: _kmCtrl,
                  label: _OdrTr.tr('kilometrazaZamene'),
                  hint: '${_OdrTr.tr('trenutno')}: ${widget.trenutnaKm} km',
                  suffixText: 'km',
                ),
                const SizedBox(height: 24),
                V3ButtonUtils.elevatedButton(
                  onPressed: () async {
                    String finalOpis = _opisCtrl.text.trim();
                    if (_tip != null && finalOpis.isEmpty) {
                      finalOpis = _tip == 'letnje'
                          ? _OdrTr.tr('letnje')
                          : _tip == 'zimske'
                              ? _OdrTr.tr('zimske')
                              : '🛤️ M+S';
                    } else if (_tip != null) {
                      final prefix = _tip == 'letnje'
                          ? '☀️'
                          : _tip == 'zimske'
                              ? '❄️'
                              : '🛤️';
                      if (!finalOpis.startsWith(prefix)) {
                        finalOpis = '$prefix $finalOpis';
                      }
                    }
                    final kmValue = int.tryParse(_kmCtrl.text);
                    final dbPrefix = 'gume_${widget.pozicija}';
                    final data = <String, dynamic>{
                      '${dbPrefix}_datum': V3BelgradeTime.parseIsoDatePart(_datum?.toIso8601String() ?? ''),
                      '${dbPrefix}_opis': finalOpis.isEmpty ? null : finalOpis,
                      '${dbPrefix}_km': kmValue,
                    };
                    try {
                      await V3VoziloService.updateKolskaKnjiga(widget.voziloId, data);
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      V3UIUtils.showSaveSuccess(context);
                    } catch (_) {
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      V3UIUtils.showSaveError(context);
                    }
                  },
                  text: _OdrTr.tr('sacuvaj'),
                  icon: Icons.save,
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Add Vozilo Dialog ────────────────────────────────────────────────────────

class _AddVoziloDialog extends StatefulWidget {
  const _AddVoziloDialog();

  @override
  State<_AddVoziloDialog> createState() => _AddVoziloDialogState();
}

class _AddVoziloDialogState extends State<_AddVoziloDialog> {
  final _formKey = GlobalKey<FormState>();
  final _regCtrl = TextEditingController();
  final _markaCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _godinaCtrl = TextEditingController();
  final _sasijaCtrl = TextEditingController();

  @override
  void dispose() {
    _regCtrl.dispose();
    _markaCtrl.dispose();
    _modelCtrl.dispose();
    _godinaCtrl.dispose();
    _sasijaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey.shade900,
      title: Text(_OdrTr.tr('dodajVozilo'), style: const TextStyle(color: Colors.white)),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              V3InputUtils.textField(
                controller: _regCtrl,
                label: _OdrTr.tr('registracija'),
                icon: Icons.directions_car,
                hint: 'BG-123-AA',
              ),
              const SizedBox(height: 12),
              V3InputUtils.textField(
                controller: _markaCtrl,
                label: _OdrTr.tr('marka'),
                icon: Icons.branding_watermark,
              ),
              const SizedBox(height: 12),
              V3InputUtils.textField(
                controller: _modelCtrl,
                label: _OdrTr.tr('model'),
                icon: Icons.model_training,
              ),
              const SizedBox(height: 12),
              V3InputUtils.numberField(
                controller: _godinaCtrl,
                label: _OdrTr.tr('godinaLabel'),
              ),
              const SizedBox(height: 12),
              V3InputUtils.textField(
                controller: _sasijaCtrl,
                label: _OdrTr.tr('brojSasijeVin'),
                icon: Icons.confirmation_number,
              ),
            ],
          ),
        ),
      ),
      actions: [
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.pop(context),
          text: _OdrTr.tr('otkazi'),
          foregroundColor: Colors.white60,
        ),
        V3ButtonUtils.textButton(
          onPressed: () {
            final reg = _regCtrl.text.trim();
            if (reg.isEmpty) {
              V3AppSnackBar.warning(context, _OdrTr.tr('registracijaObavezna'));
              return;
            }
            final vozilo = V3Vozilo(
              id: '',
              registracija: reg,
              marka: _markaCtrl.text.trim().isEmpty ? null : _markaCtrl.text.trim(),
              model: _modelCtrl.text.trim().isEmpty ? null : _modelCtrl.text.trim(),
              godinaProizvodnje: int.tryParse(_godinaCtrl.text.trim()),
              brojSasije: _sasijaCtrl.text.trim().isEmpty ? null : _sasijaCtrl.text.trim(),
            );
            Navigator.pop(context, vozilo);
          },
          text: _OdrTr.tr('sacuvaj'),
          foregroundColor: Colors.orange,
        ),
      ],
    );
  }
}

// ─── Kombi dodela dialog ───────────────────────────────────────────────────

class _DodeliKombiDialog extends StatefulWidget {
  const _DodeliKombiDialog();

  @override
  State<_DodeliKombiDialog> createState() => _DodeliKombiDialogState();
}

class _DodeliKombiDialogState extends State<_DodeliKombiDialog> {
  final Set<String> _saving = <String>{};

  Future<void> _promeniKombi(V3Vozac vozac, String? voziloId) async {
    final currentId = V3VoziloService.getVoziloForVozac(vozac.id)?.id ?? '';
    final nextId = (voziloId ?? '').trim();
    if (currentId == nextId) return;
    setState(() => _saving.add(vozac.id));
    try {
      await V3VoziloService.assignVoziloToVozac(
        vozacId: vozac.id,
        voziloId: nextId.isEmpty ? null : nextId,
      );
    } catch (_) {
      if (mounted) V3AppSnackBar.error(context, _OdrTr.tr('greskaCuvanja'));
    } finally {
      if (mounted) setState(() => _saving.remove(vozac.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<V3Vozilo>>(
      stream: V3VoziloService.streamVozila(),
      builder: (context, snapshot) {
        final vozila = snapshot.data ?? V3VoziloService.getAllVozila();
        final vozaci = V3VozacService.getAllVozaci();

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          child: V3ContainerUtils.gradientContainer(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [Color(0xFF1E2235), Color(0xFF252840)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 12, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.airport_shuttle, color: Colors.white, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _OdrTr.tr('dodeliKombi'),
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white12, height: 1),
                  Flexible(
                    child: vozaci.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _OdrTr.tr('nemaRegistrovanihVozaca'),
                              style: const TextStyle(color: Colors.white60),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shrinkWrap: true,
                            itemCount: vozaci.length,
                            itemBuilder: (context, i) {
                              final v = vozaci[i];
                              final isSaving = _saving.contains(v.id);
                              final dodeljen = V3VoziloService.getVoziloForVozac(v.id);
                              final boja = V3CardColorPolicy.vozacColorOr(v.boja);
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: boja.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: boja.withValues(alpha: 0.35)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        v.imePrezime,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    if (isSaving)
                                      const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    else
                                      DropdownButton<String>(
                                        value: dodeljen?.id ?? '',
                                        dropdownColor: const Color(0xFF252840),
                                        underline: const SizedBox.shrink(),
                                        style: TextStyle(color: boja, fontWeight: FontWeight.bold, fontSize: 13),
                                        items: [
                                          DropdownMenuItem<String>(
                                            value: '',
                                            child: Text(_OdrTr.tr('nijeDodeljen')),
                                          ),
                                          ...vozila.map(
                                            (vozilo) => DropdownMenuItem<String>(
                                              value: vozilo.id,
                                              child: Text(vozilo.registracija.trim().toUpperCase()),
                                            ),
                                          ),
                                        ],
                                        onChanged: (nova) => _promeniKombi(v, nova),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VozacAssignTile extends StatelessWidget {
  final String ime;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _VozacAssignTile({
    required this.ime,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : Colors.white.withValues(alpha: 0.15),
              width: isSelected ? 1 : 0.6,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: color.withValues(alpha: 0.3),
                child: Text(
                  ime.isNotEmpty ? ime[0].toUpperCase() : '?',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  ime,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 16,
                  ),
                ),
              ),
              if (isSelected) Icon(Icons.check_circle, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
