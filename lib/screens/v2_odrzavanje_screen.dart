import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/v2_vozila_service.dart';
import '../utils/v2_app_snack_bar.dart';

/// 🛥 KOLSKA KNJIGA
/// Tehničko praćenje vozila - servisi, registracija, gume...
class V2OdrzavanjeScreen extends StatefulWidget {
  const V2OdrzavanjeScreen({super.key});

  @override
  State<V2OdrzavanjeScreen> createState() => _OdrzavanjeScreenState();
}

class _OdrzavanjeScreenState extends State<V2OdrzavanjeScreen> {
  V2Vozilo? _selectedVozilo;

  late final Stream<List<V2Vozilo>> _streamVozila = V2VozilaService.streamVozila();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📖 Kolska knjiga'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<List<V2Vozilo>>(
        stream: _streamVozila,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final vozila = snapshot.data!;
          if (vozila.isEmpty) return const Center(child: Text('Nema vozila u bazi'));
          // Sinhronizuj _selectedVozilo sa svježim podacima — bez addPostFrameCallback
          final sel = _selectedVozilo == null
              ? null
              : vozila.firstWhere((v) => v.id == _selectedVozilo!.id, orElse: () => vozila.first);
          if (sel != _selectedVozilo) _selectedVozilo = sel;
          return Column(
            children: [
              _odrzavanjeVoziloDropdown(
                vozila: vozila,
                selectedId: _selectedVozilo?.id,
                onSelect: (v) => setState(() => _selectedVozilo = v),
              ),
              Expanded(
                child: _selectedVozilo == null
                    ? const Center(child: Text('Izaberi vozilo', style: TextStyle(color: Colors.grey)))
                    : _odrzavanjeKolskaKnjiga(
                        vozilo: _selectedVozilo!,
                        onEditText: _editTextField,
                        onEditDate: _editDateField,
                        onEditServis: _editServisField,
                        onEditGume: _editGumeField,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _editTextField(String field, String label, String? currentValue, {bool multiline = false}) {
    showDialog<void>(
      context: context,
      builder: (_) => _OdrzavanjeTextDialog(
        field: field,
        label: label,
        currentValue: currentValue,
        multiline: multiline,
        voziloId: _selectedVozilo!.id,
      ),
    );
  }

  Future<void> _editDateField(String field, String label, DateTime? currentValue) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: currentValue ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: label,
    );

    if (picked == null || !mounted) return;
    final success = await V2VozilaService.updateKolskaKnjiga(
      _selectedVozilo!.id,
      {field: picked.toIso8601String().split('T')[0]},
    );
    if (success && mounted) {
      V2AppSnackBar.success(context, '✅ Sačuvano');
    }
  }

  Future<void> _editServisField(String prefix, String label, DateTime? datum, int? km) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OdrzavanjeServisSheet(
        prefix: prefix,
        label: label,
        datum: datum,
        km: km,
        voziloId: _selectedVozilo!.id,
        trenutnaKm: _selectedVozilo?.kilometraza?.toInt(),
      ),
    );
  }

  Future<void> _editGumeField(String pozicija, DateTime? datum, String? opis, int? km) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OdrzavanjeGumeSheet(
        pozicija: pozicija,
        datum: datum,
        opis: opis,
        km: km,
        voziloId: _selectedVozilo!.id,
        trenutnaKm: _selectedVozilo?.kilometraza?.toInt(),
      ),
    );
  }
}

// ─── Top-level helpers ────────────────────────────────────────────────────────

final _odrzavanjeFormatBroja = NumberFormat('#,###', 'sr');

// Boje vozila - 066 plava, 088 beli, 093 crvena, 097 bela, 102 plava
Color _odrzavanjeGetVoziloColor(String registarskiBroj) {
  if (registarskiBroj.contains('066')) return Colors.blue;
  if (registarskiBroj.contains('088')) return Colors.white;
  if (registarskiBroj.contains('093')) return Colors.red;
  if (registarskiBroj.contains('097')) return Colors.white;
  if (registarskiBroj.contains('102')) return Colors.blue;
  return Colors.grey.shade400;
}

// Informativna senka za 15-30 dana do isteka (žuta/limeta)
List<BoxShadow>? _odrzavanjeGetRegistracijaSenka(V2Vozilo vozilo) {
  if (vozilo.registracijaVaziDo == null) return null;
  final danaDoIsteka = vozilo.registracijaVaziDo!.difference(DateTime.now()).inDays;
  if (danaDoIsteka >= 15 && danaDoIsteka <= 30) {
    return [
      BoxShadow(
        color: Colors.lime.withValues(alpha: 0.6),
        blurRadius: 12,
        spreadRadius: 3,
      ),
    ];
  }
  return null;
}

String _odrzavanjeGetTablicaImage(String registarskiBroj) {
  if (registarskiBroj.contains('066')) return 'assets/tablica_066.png';
  if (registarskiBroj.contains('088')) return 'assets/tablica_088.png';
  if (registarskiBroj.contains('093')) return 'assets/tablica_093.png';
  if (registarskiBroj.contains('097')) return 'assets/tablica_097.png';
  if (registarskiBroj.contains('102')) return 'assets/tablica_102.png';
  return 'assets/tablica_066.png';
}

Color _odrzavanjeGetVoziloBorderColor(String registarskiBroj, bool isSelected, Color color) {
  if (isSelected) return color == Colors.white ? Colors.black : color;
  if (color == Colors.white) return Colors.grey.shade600;
  return Colors.grey.shade300;
}

String _odrzavanjeFormatServis(DateTime? datum, int? km) {
  if (datum == null && km == null) return '-';
  final parts = <String>[];
  if (datum != null) parts.add(V2Vozilo.formatDatum(datum));
  if (km != null) parts.add('${_odrzavanjeFormatBroja.format(km)} km');
  return parts.join(' · ');
}

String? _odrzavanjeFormatGumeSubtitle(DateTime? datum, int? km) {
  if (datum == null && km == null) return null;
  final parts = <String>[];
  if (datum != null) parts.add('Menjane: ${V2Vozilo.formatDatum(datum)}');
  if (km != null) parts.add('${_odrzavanjeFormatBroja.format(km)} km');
  return parts.join(' · ');
}

Widget _odrzavanjeBuildEditableField({
  required String icon,
  required String label,
  required String? value,
  String? subtitle,
  Color? valueColor,
  String? badge,
  Color? badgeColor,
  required VoidCallback onEdit,
}) {
  return Card(
    child: ListTile(
      leading: Text(icon, style: const TextStyle(fontSize: 24)),
      title: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  value ?? '-',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: valueColor,
                  ),
                ),
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor?.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: badgeColor,
                    ),
                  ),
                ),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.edit, size: 20),
        onPressed: onEdit,
      ),
    ),
  );
}

Widget _odrzavanjeBuildTipGumaChip(String label, String value, String? selected, Function(String?) onTap) {
  final isSelected = selected == value;
  return InkWell(
    onTap: () => onTap(isSelected ? null : value),
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: isSelected ? Colors.blue.shade100 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? Colors.blue : Colors.grey.shade300,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.blue.shade800 : Colors.black87,
        ),
      ),
    ),
  );
}

// ─── top-level: vozilo dropdown ───────────────────────────────────────────────────

Widget _odrzavanjeVoziloDropdown({
  required List<V2Vozilo> vozila,
  required String? selectedId,
  required void Function(V2Vozilo) onSelect,
}) {
  final sortedVozila = List<V2Vozilo>.from(vozila)
    ..sort((a, b) {
      if (a.registarskiBroj.contains('066')) return -1;
      if (b.registarskiBroj.contains('066')) return 1;
      if (a.registarskiBroj.contains('102')) return 1;
      if (b.registarskiBroj.contains('102')) return -1;
      return a.registarskiBroj.compareTo(b.registarskiBroj);
    });
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: sortedVozila.map((vozilo) {
          final isSelected = selectedId == vozilo.id;
          final color = _odrzavanjeGetVoziloColor(vozilo.registarskiBroj);
          final borderColor = _odrzavanjeGetVoziloBorderColor(vozilo.registarskiBroj, isSelected, color);
          final tablicaImage = _odrzavanjeGetTablicaImage(vozilo.registarskiBroj);
          final registracijaSenka = _odrzavanjeGetRegistracijaSenka(vozilo);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: GestureDetector(
              onTap: () => onSelect(vozilo),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (color == Colors.white ? Colors.grey.shade200 : color.withValues(alpha: 0.2))
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
                      boxShadow: registracijaSenka,
                    ),
                    child: Icon(
                      Icons.airport_shuttle,
                      size: 32,
                      color: color,
                      shadows: [Shadow(color: Colors.grey.shade600, blurRadius: 2, offset: const Offset(1, 1))],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: isSelected ? Colors.amber : Colors.transparent,
                        width: isSelected ? 2 : 0,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: Image.asset(tablicaImage, width: 60, height: 15, fit: BoxFit.contain),
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

// ─── top-level: kolska knjiga ────────────────────────────────────────────────────

Widget _odrzavanjeKolskaKnjiga({
  required V2Vozilo vozilo,
  required void Function(String, String, String?, {bool multiline}) onEditText,
  required Future<void> Function(String, String, DateTime?) onEditDate,
  required Future<void> Function(String, String, DateTime?, int?) onEditServis,
  required Future<void> Function(String, DateTime?, String?, int?) onEditGume,
}) {
  final v = vozilo;
  return SingleChildScrollView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.displayNaziv, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Registracija: ${v.registarskiBroj}', style: TextStyle(color: Colors.grey.shade700)),
                if (v.godinaProizvodnje != null)
                  Text('Godina: ${v.godinaProizvodnje}', style: TextStyle(color: Colors.grey.shade700)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.speed, size: 16, color: Colors.blue),
                      const SizedBox(width: 6),
                      Text('Trenutna kilometraža: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      Text(
                        '${_odrzavanjeFormatBroja.format(v.kilometraza ?? 0)} km',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _odrzavanjeBuildEditableField(
          icon: '🔢',
          label: 'Broj šasije (VIN)',
          value: v.brojSasije,
          onEdit: () => onEditText('broj_sasije', 'Broj šasije', v.brojSasije),
        ),
        _odrzavanjeBuildEditableField(
          icon: '📋',
          label: 'Registracija važi do',
          value: V2Vozilo.formatDatum(v.registracijaVaziDo),
          valueColor: v.registracijaIstekla
              ? Colors.red
              : v.registracijaIstice
                  ? Colors.orange
                  : null,
          badge: v.registracijaIstekla
              ? 'ISTEKLA!'
              : v.registracijaIstice
                  ? '${v.danaDoIstekaRegistracije} dana'
                  : null,
          badgeColor: v.registracijaIstekla ? Colors.red : Colors.orange,
          onEdit: () => onEditDate('registracija_vazi_do', 'Registracija važi do', v.registracijaVaziDo),
        ),
        _odrzavanjeBuildEditableField(
          icon: '📝',
          label: 'Napomena',
          value: v.napomena ?? '-',
          onEdit: () => onEditText('napomena', 'Napomena', v.napomena, multiline: true),
        ),
        const Divider(height: 32),
        _odrzavanjeBuildEditableField(
          icon: '🔧',
          label: 'Mali servis',
          value: _odrzavanjeFormatServis(v.maliServisDatum, v.maliServisKm),
          onEdit: () => onEditServis('mali_servis', 'Mali servis', v.maliServisDatum, v.maliServisKm),
        ),
        _odrzavanjeBuildEditableField(
          icon: '🛠️',
          label: 'Veliki servis',
          value: _odrzavanjeFormatServis(v.velikiServisDatum, v.velikiServisKm),
          onEdit: () => onEditServis('veliki_servis', 'Veliki servis', v.velikiServisDatum, v.velikiServisKm),
        ),
        _odrzavanjeBuildEditableField(
          icon: '⚡',
          label: 'Alternator',
          value: _odrzavanjeFormatServis(v.alternatorDatum, v.alternatorKm),
          onEdit: () => onEditServis('alternator', 'Alternator', v.alternatorDatum, v.alternatorKm),
        ),
        _odrzavanjeBuildEditableField(
          icon: '🔋',
          label: 'Akumulator',
          value: _odrzavanjeFormatServis(v.akumulatorDatum, v.akumulatorKm),
          onEdit: () => onEditServis('akumulator', 'Akumulator', v.akumulatorDatum, v.akumulatorKm),
        ),
        _odrzavanjeBuildEditableField(
          icon: '🛑',
          label: 'Pločice prednje',
          value: _odrzavanjeFormatServis(v.plocicePrednjeDatum, v.plocicePrednjeKm),
          onEdit: () => onEditServis('plocice_prednje', 'Pločice prednje', v.plocicePrednjeDatum, v.plocicePrednjeKm),
        ),
        _odrzavanjeBuildEditableField(
          icon: '🛑',
          label: 'Pločice zadnje',
          value: _odrzavanjeFormatServis(v.plociceZadnjeDatum, v.plociceZadnjeKm),
          onEdit: () => onEditServis('plocice_zadnje', 'Pločice zadnje', v.plociceZadnjeDatum, v.plociceZadnjeKm),
        ),
        _odrzavanjeBuildEditableField(
          icon: '🔩',
          label: 'Trap',
          value: _odrzavanjeFormatServis(v.trapDatum, v.trapKm),
          onEdit: () => onEditServis('trap', 'Trap', v.trapDatum, v.trapKm),
        ),
        const Divider(height: 32),
        _odrzavanjeBuildEditableField(
          icon: '🛥',
          label: 'Gume prednje',
          value: v.gumePrednjeOpis ?? v.gumeOpis ?? '-',
          subtitle: _odrzavanjeFormatGumeSubtitle(v.gumePrednjeDatum ?? v.gumeDatum, v.gumePrednjeKm),
          onEdit: () => onEditGume(
              'prednje', v.gumePrednjeDatum ?? v.gumeDatum, v.gumePrednjeOpis ?? v.gumeOpis, v.gumePrednjeKm),
        ),
        _odrzavanjeBuildEditableField(
          icon: '🛥',
          label: 'Gume zadnje',
          value: v.gumeZadnjeOpis ?? '-',
          subtitle: _odrzavanjeFormatGumeSubtitle(v.gumeZadnjeDatum, v.gumeZadnjeKm),
          onEdit: () => onEditGume('zadnje', v.gumeZadnjeDatum, v.gumeZadnjeOpis, v.gumeZadnjeKm),
        ),
        const Divider(height: 32),
        _odrzavanjeBuildEditableField(
          icon: '📻',
          label: 'Radio code',
          value: v.radio,
          onEdit: () => onEditText('radio', 'Radio code', v.radio),
        ),
        const SizedBox(height: 80),
      ],
    ),
  );
}

// ─── _OdrzavanjeTextDialog ────────────────────────────────────────────────────────

class _OdrzavanjeTextDialog extends StatefulWidget {
  const _OdrzavanjeTextDialog({
    required this.field,
    required this.label,
    required this.voziloId,
    this.currentValue,
    this.multiline = false,
  });
  final String field;
  final String label;
  final String voziloId;
  final String? currentValue;
  final bool multiline;

  @override
  State<_OdrzavanjeTextDialog> createState() => _OdrzavanjeTextDialogState();
}

class _OdrzavanjeTextDialogState extends State<_OdrzavanjeTextDialog> {
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
      title: Text(widget.label),
      content: TextField(
        controller: _ctrl,
        decoration: InputDecoration(border: const OutlineInputBorder(), hintText: 'Unesi ${widget.label}'),
        maxLines: widget.multiline ? 4 : 1,
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Otkaži'),
        ),
        TextButton(
          onPressed: () async {
            final success = await V2VozilaService.updateKolskaKnjiga(
              widget.voziloId,
              {widget.field: _ctrl.text.isEmpty ? null : _ctrl.text},
            );
            if (!context.mounted) return;
            Navigator.pop(context);
            if (success) V2AppSnackBar.success(context, '✅ Sačuvano');
          },
          child: const Text('Sačuvaj'),
        ),
      ],
    );
  }
}

// ─── _OdrzavanjeServisSheet ──────────────────────────────────────────────────────

class _OdrzavanjeServisSheet extends StatefulWidget {
  const _OdrzavanjeServisSheet({
    required this.prefix,
    required this.label,
    required this.voziloId,
    this.datum,
    this.km,
    this.trenutnaKm,
  });
  final String prefix;
  final String label;
  final String voziloId;
  final DateTime? datum;
  final int? km;
  final int? trenutnaKm;

  @override
  State<_OdrzavanjeServisSheet> createState() => _OdrzavanjeServisSheetState();
}

class _OdrzavanjeServisSheetState extends State<_OdrzavanjeServisSheet> {
  late DateTime? _datum;
  late final TextEditingController _kmCtrl;

  @override
  void initState() {
    super.initState();
    _datum = widget.datum ?? DateTime.now();
    _kmCtrl = TextEditingController(
      text: (widget.km ?? widget.trenutnaKm)?.toString() ?? '',
    );
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
        color: Theme.of(context).scaffoldBackgroundColor,
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
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
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
                    decoration: const InputDecoration(
                      labelText: 'Datum',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(_datum != null ? '${_datum!.day}.${_datum!.month}.${_datum!.year}' : 'Izaberi datum'),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _kmCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Kilometraža servisa',
                    hintText: widget.trenutnaKm != null ? 'Trenutno: ${widget.trenutnaKm} km' : null,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.speed),
                    suffixText: 'km',
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () async {
                    final kmValue = int.tryParse(_kmCtrl.text);
                    final updateData = <String, dynamic>{
                      '${widget.prefix}_datum': _datum?.toIso8601String().split('T')[0],
                      '${widget.prefix}_km': kmValue,
                    };
                    if (kmValue != null && kmValue > (widget.trenutnaKm ?? 0)) {
                      updateData['kilometraza'] = kmValue.toDouble();
                    }
                    final success = await V2VozilaService.updateKolskaKnjiga(widget.voziloId, updateData);
                    if (success && (_datum != null || kmValue != null)) {
                      await V2VozilaService.addIstorijuServisa(
                        voziloId: widget.voziloId,
                        tip: widget.prefix,
                        datum: _datum,
                        km: kmValue,
                      );
                    }
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    if (success) V2AppSnackBar.success(context, '✅ Sačuvano');
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('Sačuvaj'),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── _OdrzavanjeGumeSheet ─────────────────────────────────────────────────────────

class _OdrzavanjeGumeSheet extends StatefulWidget {
  const _OdrzavanjeGumeSheet({
    required this.pozicija,
    required this.voziloId,
    this.datum,
    this.opis,
    this.km,
    this.trenutnaKm,
  });
  final String pozicija;
  final String voziloId;
  final DateTime? datum;
  final String? opis;
  final int? km;
  final int? trenutnaKm;

  @override
  State<_OdrzavanjeGumeSheet> createState() => _OdrzavanjeGumeSheetState();
}

class _OdrzavanjeGumeSheetState extends State<_OdrzavanjeGumeSheet> {
  late DateTime? _datum;
  late final TextEditingController _opisCtrl;
  late final TextEditingController _kmCtrl;
  String? _tip;

  @override
  void initState() {
    super.initState();
    _datum = widget.datum ?? DateTime.now();
    _opisCtrl = TextEditingController(text: widget.opis ?? '');
    _kmCtrl = TextEditingController(text: (widget.km ?? widget.trenutnaKm)?.toString() ?? '');
    // Prepoznaj tip iz opisa
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

  @override
  Widget build(BuildContext context) {
    final isPrednje = widget.pozicija == 'prednje';
    final label = isPrednje ? 'Gume prednje' : 'Gume zadnje';
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
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
                Text('🛄 $label',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                const SizedBox(height: 24),
                const Text('Tip guma:', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        child:
                            _odrzavanjeBuildTipGumaChip('☀️ Letnje', 'letnje', _tip, (t) => setState(() => _tip = t))),
                    const SizedBox(width: 8),
                    Expanded(
                        child:
                            _odrzavanjeBuildTipGumaChip('❄️ Zimske', 'zimske', _tip, (t) => setState(() => _tip = t))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _odrzavanjeBuildTipGumaChip('🛤️ M+S', 'ms', _tip, (t) => setState(() => _tip = t))),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _opisCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Marka i dimenzija',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.description),
                    hintText: 'npr. Michelin 215/65 R16',
                  ),
                  maxLines: 2,
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
                    decoration: const InputDecoration(
                      labelText: 'Datum zamene',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(_datum != null ? '${_datum!.day}.${_datum!.month}.${_datum!.year}' : 'Izaberi datum'),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _kmCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Kilometraža zamene',
                    hintText: widget.trenutnaKm != null ? 'Trenutno: ${widget.trenutnaKm} km' : null,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.speed),
                    suffixText: 'km',
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () async {
                    String finalOpis = '';
                    if (_tip != null) {
                      finalOpis = _tip == 'letnje'
                          ? '☀️'
                          : _tip == 'zimske'
                              ? '❄️'
                              : '🛤️';
                    }
                    if (_opisCtrl.text.isNotEmpty) {
                      finalOpis += finalOpis.isNotEmpty ? ' ${_opisCtrl.text}' : _opisCtrl.text;
                    }
                    final kmValue = int.tryParse(_kmCtrl.text);
                    final updateData = isPrednje
                        ? <String, dynamic>{
                            'gume_prednje_datum': _datum?.toIso8601String().split('T')[0],
                            'gume_prednje_opis': finalOpis.isEmpty ? null : finalOpis,
                            'gume_prednje_km': kmValue,
                          }
                        : <String, dynamic>{
                            'gume_zadnje_datum': _datum?.toIso8601String().split('T')[0],
                            'gume_zadnje_opis': finalOpis.isEmpty ? null : finalOpis,
                            'gume_zadnje_km': kmValue,
                          };
                    if (kmValue != null && kmValue > (widget.trenutnaKm ?? 0)) {
                      updateData['kilometraza'] = kmValue.toDouble();
                    }
                    final success = await V2VozilaService.updateKolskaKnjiga(widget.voziloId, updateData);
                    if (success && _datum != null) {
                      await V2VozilaService.addIstorijuServisa(
                        voziloId: widget.voziloId,
                        tip: isPrednje ? 'gume_prednje' : 'gume_zadnje',
                        datum: _datum,
                        km: kmValue,
                        opis: finalOpis.isEmpty ? null : finalOpis,
                        pozicija: widget.pozicija,
                      );
                    }
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    if (success) V2AppSnackBar.success(context, '✅ Sačuvano');
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('Sačuvaj'),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
