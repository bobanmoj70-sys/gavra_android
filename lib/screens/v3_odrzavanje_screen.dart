import 'package:flutter/material.dart';

import '../models/v3_vozilo.dart';
import '../services/v3/v3_vozilo_service.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_dan_helper.dart';
import '../utils/v3_format_utils.dart';
import '../utils/v3_input_utils.dart';
import '../utils/v3_ui_utils.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

Color _getVoziloColor(String reg) {
  if (reg.contains('066')) return Colors.blue;
  if (reg.contains('088')) return Colors.white;
  if (reg.contains('093')) return Colors.red;
  if (reg.contains('097')) return Colors.white;
  if (reg.contains('102')) return Colors.blue;
  return Colors.grey.shade400;
}

String _getTablicaImage(String reg) {
  if (reg.contains('066')) return 'assets/tablica_066.png';
  if (reg.contains('088')) return 'assets/tablica_088.png';
  if (reg.contains('093')) return 'assets/tablica_093.png';
  if (reg.contains('097')) return 'assets/tablica_097.png';
  if (reg.contains('102')) return 'assets/tablica_102.png';
  return 'assets/tablica_066.png';
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
  if (datum != null) parts.add('Menjane: ${V3Vozilo.formatDatum(datum)}');
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
        title: const Text('📖 Kolska knjiga'),
        centerTitle: true,
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
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
                return Center(child: Text('Greška: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator(color: Colors.white));
              }

              final vozila = snapshot.data!.where((v) => v.aktivno).toList();
              if (vozila.isEmpty) {
                return const Center(child: Text('Nema aktivnih vozila.', style: TextStyle(color: Colors.white)));
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
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isSel
                            ? (color == Colors.white
                                ? Colors.grey.shade200.withValues(alpha: 0.3)
                                : color.withValues(alpha: 0.25))
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor, width: isSel ? 2 : 1),
                        boxShadow: senka,
                      ),
                      child: Icon(Icons.airport_shuttle,
                          size: 32,
                          color: color,
                          shadows: [Shadow(color: Colors.black54, blurRadius: 2, offset: const Offset(1, 1))]),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: isSel ? Colors.amber : Colors.transparent,
                          width: isSel ? 2 : 0,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child:
                            Image.asset(_getTablicaImage(v.registracija), width: 60, height: 15, fit: BoxFit.contain),
                      ),
                    ),
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
                Text('Registracija: ${v.registracija}', style: TextStyle(color: Colors.white.withValues(alpha: 0.75))),
                if (v.godinaProizvodnje != null)
                  Text('Godina: ${v.godinaProizvodnje}', style: TextStyle(color: Colors.white.withValues(alpha: 0.75))),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.speed, size: 16, color: Colors.white),
                      const SizedBox(width: 6),
                      Text('Kilometraža: ', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
                      Text('${V3FormatUtils.formatBroj(v.trenutnaKm)} km',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Šasija
          _EditableField(
            icon: '🔢',
            label: 'Broj šasije (VIN)',
            value: v.brojSasije,
            onEdit: () => _editText('broj_sasije', 'Broj šasije', v.brojSasije),
          ),

          // Registracija
          _EditableField(
            icon: '📋',
            label: 'Registracija važi do',
            value: V3Vozilo.formatDatum(v.registracijaVaziDo),
            valueColor: v.registracijaIstekla
                ? Colors.red.shade300
                : v.registracijaIstice
                    ? Colors.orange.shade300
                    : null,
            badge: v.registracijaIstekla
                ? 'ISTEKLA!'
                : v.registracijaIstice
                    ? '${v.danaDoIstekaRegistracije} dana'
                    : null,
            badgeColor: v.registracijaIstekla ? Colors.red : Colors.orange,
            onEdit: () => _editDate('registracija_vazi_do', 'Registracija važi do', v.registracijaVaziDo),
          ),

          // Napomena
          _EditableField(
            icon: '📝',
            label: 'Napomena',
            value: v.napomena ?? '-',
            onEdit: () => _editText('napomena', 'Napomena', v.napomena, multiline: true),
          ),

          _SectionDivider(),

          // Servisi
          _EditableField(
            icon: '🔧',
            label: 'Mali servis',
            value: _formatServis(v.maliServisDatum, v.maliServisKm),
            onEdit: () =>
                _editServis('mali_servis', 'Mali servis', v.maliServisDatum, v.maliServisKm, v.trenutnaKm.toInt()),
          ),
          _EditableField(
            icon: '🛠️',
            label: 'Veliki servis',
            value: _formatServis(v.velikiServisDatum, v.velikiServisKm),
            onEdit: () => _editServis(
                'veliki_servis', 'Veliki servis', v.velikiServisDatum, v.velikiServisKm, v.trenutnaKm.toInt()),
          ),
          _EditableField(
            icon: '⚡',
            label: 'Alternator',
            value: _formatServis(v.alternatorDatum, v.alternatorKm),
            onEdit: () =>
                _editServis('alternator', 'Alternator', v.alternatorDatum, v.alternatorKm, v.trenutnaKm.toInt()),
          ),
          _EditableField(
            icon: '🔋',
            label: 'Akumulator',
            value: _formatServis(v.akumulatorDatum, v.akumulatorKm),
            onEdit: () =>
                _editServis('akumulator', 'Akumulator', v.akumulatorDatum, v.akumulatorKm, v.trenutnaKm.toInt()),
          ),
          _EditableField(
            icon: '🛑',
            label: 'Pločice prednje',
            value: _formatServis(v.plocicePrednjeDatum, v.plocicePrednjeKm),
            onEdit: () => _editServis(
                'plocice_prednje', 'Pločice prednje', v.plocicePrednjeDatum, v.plocicePrednjeKm, v.trenutnaKm.toInt()),
          ),
          _EditableField(
            icon: '🛑',
            label: 'Pločice zadnje',
            value: _formatServis(v.plociceZadnjeDatum, v.plociceZadnjeKm),
            onEdit: () => _editServis(
                'plocice_zadnje', 'Pločice zadnje', v.plociceZadnjeDatum, v.plociceZadnjeKm, v.trenutnaKm.toInt()),
          ),
          _EditableField(
            icon: '🔩',
            label: 'Trap',
            value: _formatServis(v.trapDatum, v.trapKm),
            onEdit: () => _editServis('trap', 'Trap', v.trapDatum, v.trapKm, v.trenutnaKm.toInt()),
          ),

          _SectionDivider(),

          // Gume
          _EditableField(
            icon: '🛞',
            label: 'Gume prednje',
            value: v.gumePrednjeOpis ?? '-',
            subtitle: _formatGumeSubtitle(v.gumePrednjeDatum, v.gumePrednjeKm),
            onEdit: () =>
                _editGume('prednje', v.gumePrednjeDatum, v.gumePrednjeOpis, v.gumePrednjeKm, v.trenutnaKm.toInt()),
          ),
          _EditableField(
            icon: '🛞',
            label: 'Gume zadnje',
            value: v.gumeZadnjeOpis ?? '-',
            subtitle: _formatGumeSubtitle(v.gumeZadnjeDatum, v.gumeZadnjeKm),
            onEdit: () =>
                _editGume('zadnje', v.gumeZadnjeDatum, v.gumeZadnjeOpis, v.gumeZadnjeKm, v.trenutnaKm.toInt()),
          ),

          _SectionDivider(),

          // Radio
          _EditableField(
            icon: '📻',
            label: 'Radio code',
            value: v.radio ?? '-',
            onEdit: () => _editText('radio', 'Radio code', v.radio),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  // ── Edit handlers ─────────────────────────────────────────────────────────

  void _editText(String field, String label, String? current, {bool multiline = false}) {
    showDialog<void>(
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
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: label,
    );
    if (picked == null || !mounted) return;
    try {
      await V3VoziloService.updateKolskaKnjiga(
          _selected!.id, {field: V3DanHelper.parseIsoDatePart(picked.toIso8601String())});
      V3UIUtils.showSaveSuccess(context);
    } catch (_) {
      V3UIUtils.showSaveError(context);
    }
  }

  Future<void> _editServis(String prefix, String label, DateTime? datum, int? km, int trenutnaKm) {
    return showModalBottomSheet<void>(
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
    return showModalBottomSheet<void>(
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
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeColor?.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: badgeColor ?? Colors.white, width: 0.8),
                          ),
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
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
        label: 'Unesi ${widget.label}',
        maxLines: widget.multiline ? 4 : 1,
      ),
      actions: [
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.pop(context),
          text: 'Otkaži',
          foregroundColor: Colors.white60,
        ),
        V3ButtonUtils.textButton(
          onPressed: () async {
            try {
              await V3VoziloService.updateKolskaKnjiga(
                widget.voziloId,
                {widget.field: _ctrl.text.isEmpty ? null : _ctrl.text},
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
          text: 'Sačuvaj',
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
    _datum = widget.datum ?? DateTime.now();
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
                      initialDate: _datum ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => _datum = picked);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Datum',
                      labelStyle: const TextStyle(color: Colors.white60),
                      border: const OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                      prefixIcon: const Icon(Icons.calendar_today, color: Colors.white60),
                    ),
                    child: Text(
                      _datum != null ? '${_datum!.day}.${_datum!.month}.${_datum!.year}' : 'Izaberi datum',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                V3InputUtils.numberField(
                  controller: _kmCtrl,
                  label: 'Kilometraža servisa',
                  hint: 'Trenutno: ${widget.trenutnaKm} km',
                  suffixText: 'km',
                ),
                const SizedBox(height: 24),
                V3ButtonUtils.elevatedButton(
                  onPressed: () async {
                    final kmValue = int.tryParse(_kmCtrl.text);
                    final data = <String, dynamic>{
                      '${widget.prefix}_datum': V3DanHelper.parseIsoDatePart(_datum?.toIso8601String() ?? ''),
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
                  text: 'Sačuvaj',
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
    _datum = widget.datum ?? DateTime.now();
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
    final label = widget.pozicija == 'prednje' ? 'Gume prednje' : 'Gume zadnje';
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
                const Text('Tip guma:', style: TextStyle(fontWeight: FontWeight.w500, color: Colors.white70)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _tipChip('☀️ Letnje', 'letnje'),
                    const SizedBox(width: 8),
                    _tipChip('❄️ Zimske', 'zimske'),
                    const SizedBox(width: 8),
                    _tipChip('🛤️ M+S', 'ms'),
                  ],
                ),
                const SizedBox(height: 16),
                V3InputUtils.textField(
                  controller: _opisCtrl,
                  label: 'Marka i dimenzija',
                  hint: 'npr. Michelin 215/65 R16',
                  icon: Icons.description,
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _datum ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => _datum = picked);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Datum zamene',
                      labelStyle: const TextStyle(color: Colors.white60),
                      border: const OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                      prefixIcon: const Icon(Icons.calendar_today, color: Colors.white60),
                    ),
                    child: Text(
                      _datum != null ? '${_datum!.day}.${_datum!.month}.${_datum!.year}' : 'Izaberi datum',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                V3InputUtils.numberField(
                  controller: _kmCtrl,
                  label: 'Kilometraža zamene',
                  hint: 'Trenutno: ${widget.trenutnaKm} km',
                  suffixText: 'km',
                ),
                const SizedBox(height: 24),
                V3ButtonUtils.elevatedButton(
                  onPressed: () async {
                    String finalOpis = _opisCtrl.text.trim();
                    if (_tip != null && finalOpis.isEmpty) {
                      finalOpis = _tip == 'letnje'
                          ? '☀️ Letnje'
                          : _tip == 'zimske'
                              ? '❄️ Zimske'
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
                      '${dbPrefix}_datum': V3DanHelper.parseIsoDatePart(_datum?.toIso8601String() ?? ''),
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
                  text: 'Sačuvaj',
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
