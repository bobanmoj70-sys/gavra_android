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

  void _selectVozilo(V2Vozilo? vozilo) {
    setState(() => _selectedVozilo = vozilo);
  }

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
          // Sinhronizuj _selectedVozilo sa svježim podacima
          final sel = _selectedVozilo == null
              ? null
              : vozila.firstWhere((v) => v.id == _selectedVozilo!.id, orElse: () => vozila.first);
          if (sel != _selectedVozilo) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _selectedVozilo = sel);
            });
          }
          return Column(
            children: [
              _buildVoziloDropdown(vozila),
              Expanded(
                child: _selectedVozilo == null
                    ? const Center(child: Text('Izaberi vozilo', style: TextStyle(color: Colors.grey)))
                    : _buildKolskaKnjiga(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildVoziloDropdown(List<V2Vozilo> vozila) {
    // Sortiraj: 066 levo, 102 desno, ostali po redu
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
            final isSelected = _selectedVozilo?.id == vozilo.id;
            final color = _odrzavanjeGetVoziloColor(vozilo.registarskiBroj);
            final borderColor = _odrzavanjeGetVoziloBorderColor(vozilo.registarskiBroj, isSelected, color);
            final tablicaImage = _odrzavanjeGetTablicaImage(vozilo.registarskiBroj);
            final registracijaSenka = _odrzavanjeGetRegistracijaSenka(vozilo);

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: GestureDetector(
                onTap: () => _selectVozilo(vozilo),
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
                        boxShadow: registracijaSenka, // ⚠️ Informativna senka 15-30 dana
                      ),
                      child: Icon(
                        Icons.airport_shuttle,
                        size: 32,
                        color: color,
                        shadows: [
                          Shadow(
                            color: Colors.grey.shade600,
                            blurRadius: 2,
                            offset: const Offset(1, 1),
                          ),
                        ],
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
                        child: Image.asset(
                          tablicaImage,
                          width: 60,
                          height: 15,
                          fit: BoxFit.contain,
                        ),
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

  Widget _buildKolskaKnjiga() {
    final v = _selectedVozilo!;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header sa osnovnim info
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    v.displayNaziv,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Registracija: ${v.registarskiBroj}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  if (v.godinaProizvodnje != null)
                    Text(
                      'Godina: ${v.godinaProizvodnje}',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
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
                        Text(
                          'Trenutna kilometraža: ',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
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
            onEdit: () => _editTextField('broj_sasije', 'Broj šasije', v.brojSasije),
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
            onEdit: () => _editDateField('registracija_vazi_do', 'Registracija važi do', v.registracijaVaziDo),
          ),

          _odrzavanjeBuildEditableField(
            icon: '📝',
            label: 'Napomena',
            value: v.napomena ?? '-',
            onEdit: () => _editTextField('napomena', 'Napomena', v.napomena, multiline: true),
          ),

          const Divider(height: 32),

          _odrzavanjeBuildEditableField(
            icon: '🔧',
            label: 'Mali servis',
            value: _odrzavanjeFormatServis(v.maliServisDatum, v.maliServisKm),
            onEdit: () => _editServisField('mali_servis', 'Mali servis', v.maliServisDatum, v.maliServisKm),
          ),

          _odrzavanjeBuildEditableField(
            icon: '🛠️',
            label: 'Veliki servis',
            value: _odrzavanjeFormatServis(v.velikiServisDatum, v.velikiServisKm),
            onEdit: () => _editServisField('veliki_servis', 'Veliki servis', v.velikiServisDatum, v.velikiServisKm),
          ),

          _odrzavanjeBuildEditableField(
            icon: '⚡',
            label: 'Alternator',
            value: _odrzavanjeFormatServis(v.alternatorDatum, v.alternatorKm),
            onEdit: () => _editServisField('alternator', 'Alternator', v.alternatorDatum, v.alternatorKm),
          ),

          _odrzavanjeBuildEditableField(
            icon: '🔋',
            label: 'Akumulator',
            value: _odrzavanjeFormatServis(v.akumulatorDatum, v.akumulatorKm),
            onEdit: () => _editServisField('akumulator', 'Akumulator', v.akumulatorDatum, v.akumulatorKm),
          ),

          _odrzavanjeBuildEditableField(
            icon: '🛑',
            label: 'Pločice prednje',
            value: _odrzavanjeFormatServis(v.plocicePrednjeDatum, v.plocicePrednjeKm),
            onEdit: () =>
                _editServisField('plocice_prednje', 'Pločice prednje', v.plocicePrednjeDatum, v.plocicePrednjeKm),
          ),

          _odrzavanjeBuildEditableField(
            icon: '🛑',
            label: 'Pločice zadnje',
            value: _odrzavanjeFormatServis(v.plociceZadnjeDatum, v.plociceZadnjeKm),
            onEdit: () => _editServisField('plocice_zadnje', 'Pločice zadnje', v.plociceZadnjeDatum, v.plociceZadnjeKm),
          ),

          _odrzavanjeBuildEditableField(
            icon: '🔩',
            label: 'Trap',
            value: _odrzavanjeFormatServis(v.trapDatum, v.trapKm),
            onEdit: () => _editServisField('trap', 'Trap', v.trapDatum, v.trapKm),
          ),

          const Divider(height: 32),

          _odrzavanjeBuildEditableField(
            icon: '🛥',
            label: 'Gume prednje',
            value: v.gumePrednjeOpis ?? v.gumeOpis ?? '-',
            subtitle: _odrzavanjeFormatGumeSubtitle(v.gumePrednjeDatum ?? v.gumeDatum, v.gumePrednjeKm),
            onEdit: () => _editGumeField(
              'prednje',
              v.gumePrednjeDatum ?? v.gumeDatum,
              v.gumePrednjeOpis ?? v.gumeOpis,
              v.gumePrednjeKm,
            ),
          ),

          _odrzavanjeBuildEditableField(
            icon: '🛥',
            label: 'Gume zadnje',
            value: v.gumeZadnjeOpis ?? '-',
            subtitle: _odrzavanjeFormatGumeSubtitle(v.gumeZadnjeDatum, v.gumeZadnjeKm),
            onEdit: () => _editGumeField('zadnje', v.gumeZadnjeDatum, v.gumeZadnjeOpis, v.gumeZadnjeKm),
          ),

          const Divider(height: 32),

          _odrzavanjeBuildEditableField(
            icon: '📻',
            label: 'Radio code',
            value: v.radio,
            onEdit: () => _editTextField('radio', 'Radio code', v.radio),
          ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  void _editTextField(String field, String label, String? currentValue, {bool multiline = false}) {
    final controller = TextEditingController(text: currentValue);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: 'Unesi $label',
          ),
          maxLines: multiline ? 4 : 1,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Otkaži'),
          ),
          TextButton(
            onPressed: () async {
              final success = await V2VozilaService.updateKolskaKnjiga(
                _selectedVozilo!.id,
                {field: controller.text.isEmpty ? null : controller.text},
              );
              if (!dialogCtx.mounted) return;
              Navigator.pop(dialogCtx);
              if (success && mounted) {
                V2AppSnackBar.success(context, '✅ Sačuvano');
              }
            },
            child: const Text('Sačuvaj'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
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

  Future<void> _editServisField(String prefix, String label, DateTime? datum, int? km) async {
    DateTime? selectedDatum = datum ?? DateTime.now();
    final currentVanKm = _selectedVozilo?.kilometraza?.toInt();
    final kmController = TextEditingController(text: (km ?? currentVanKm)?.toString() ?? '');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // Datum
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDatum ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setStateDialog(() => selectedDatum = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Datum',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          selectedDatum != null
                              ? '${selectedDatum!.day}.${selectedDatum!.month}.${selectedDatum!.year}'
                              : 'Izaberi datum',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Kilometraža
                    TextField(
                      controller: kmController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Kilometraža servisa',
                        hintText: currentVanKm != null ? 'Trenutno: $currentVanKm km' : null,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.speed),
                        suffixText: 'km',
                      ),
                    ),
                    const SizedBox(height: 24),

                    ElevatedButton.icon(
                      onPressed: () async {
                        final kmValue = int.tryParse(kmController.text);

                        final Map<String, dynamic> updateData = {
                          '${prefix}_datum': selectedDatum?.toIso8601String().split('T')[0],
                          '${prefix}_km': kmValue,
                        };

                        // Ako je uneta kilometraža veća od trenutne u bazi, ažuriraj i nju
                        if (kmValue != null && kmValue > (_selectedVozilo?.kilometraza ?? 0)) {
                          updateData['kilometraza'] = kmValue.toDouble();
                        }

                        final success = await V2VozilaService.updateKolskaKnjiga(
                          _selectedVozilo!.id,
                          updateData,
                        );

                        // Dodaj u istoriju
                        if (success && (selectedDatum != null || kmValue != null)) {
                          await V2VozilaService.addIstorijuServisa(
                            voziloId: _selectedVozilo!.id,
                            tip: prefix,
                            datum: selectedDatum,
                            km: kmValue,
                          );
                        }

                        if (!context.mounted) return;
                        Navigator.pop(context);
                        if (success) {
                          V2AppSnackBar.success(context, '✅ Sačuvano');
                        }
                      },
                      icon: const Icon(Icons.save),
                      label: const Text('Sačuvaj'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    kmController.dispose();
  }

  Future<void> _editGumeField(String pozicija, DateTime? datum, String? opis, int? km) async {
    DateTime? selectedDatum = datum ?? DateTime.now();
    final opisController = TextEditingController(text: opis ?? '');
    final currentVanKm = _selectedVozilo?.kilometraza?.toInt();
    final kmController = TextEditingController(text: (km ?? currentVanKm)?.toString() ?? '');
    final isPrednje = pozicija == 'prednje';
    final label = isPrednje ? 'Gume prednje' : 'Gume zadnje';

    // Tipovi guma sa emoji
    String? selectedTip;
    // Pokušaj prepoznati tip iz opisa
    if (opis != null) {
      if (opis.contains('☀️') || opis.toLowerCase().contains('letn')) {
        selectedTip = 'letnje';
      } else if (opis.contains('❄️') || opis.toLowerCase().contains('zimsk')) {
        selectedTip = 'zimske';
      } else if (opis.contains('🛤️') ||
          opis.toLowerCase().contains('m+s') ||
          opis.toLowerCase().contains('univerzal')) {
        selectedTip = 'ms';
      }
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '🛄 $label',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // Tip guma - brzi izbor
                    const Text('Tip guma:', style: TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _odrzavanjeBuildTipGumaChip(
                            '☀️ Letnje',
                            'letnje',
                            selectedTip,
                            (tip) => setStateDialog(() => selectedTip = tip),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _odrzavanjeBuildTipGumaChip(
                            '❄️ Zimske',
                            'zimske',
                            selectedTip,
                            (tip) => setStateDialog(() => selectedTip = tip),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _odrzavanjeBuildTipGumaChip(
                            '🛤️ M+S',
                            'ms',
                            selectedTip,
                            (tip) => setStateDialog(() => selectedTip = tip),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Opis guma
                    TextField(
                      controller: opisController,
                      decoration: const InputDecoration(
                        labelText: 'Marka i dimenzija',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.description),
                        hintText: 'npr. Michelin 215/65 R16',
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),

                    // Datum zamene
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDatum ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setStateDialog(() => selectedDatum = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Datum zamene',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          selectedDatum != null
                              ? '${selectedDatum!.day}.${selectedDatum!.month}.${selectedDatum!.year}'
                              : 'Izaberi datum',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Kilometraža
                    TextField(
                      controller: kmController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Kilometraža zamene',
                        hintText: currentVanKm != null ? 'Trenutno: $currentVanKm km' : null,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.speed),
                        suffixText: 'km',
                      ),
                    ),
                    const SizedBox(height: 24),

                    ElevatedButton.icon(
                      onPressed: () async {
                        // Složi opis sa tipom guma
                        String finalOpis = '';
                        if (selectedTip != null) {
                          final tipEmoji = selectedTip == 'letnje'
                              ? '☀️'
                              : selectedTip == 'zimske'
                                  ? '❄️'
                                  : '🛤️';
                          finalOpis = tipEmoji;
                        }
                        if (opisController.text.isNotEmpty) {
                          finalOpis += finalOpis.isNotEmpty ? ' ${opisController.text}' : opisController.text;
                        }

                        final kmValue = int.tryParse(kmController.text);

                        // Sačuvaj u vozila tabelu
                        final Map<String, dynamic> updateData = isPrednje
                            ? {
                                'gume_prednje_datum': selectedDatum?.toIso8601String().split('T')[0],
                                'gume_prednje_opis': finalOpis.isEmpty ? null : finalOpis,
                                'gume_prednje_km': kmValue,
                              }
                            : {
                                'gume_zadnje_datum': selectedDatum?.toIso8601String().split('T')[0],
                                'gume_zadnje_opis': finalOpis.isEmpty ? null : finalOpis,
                                'gume_zadnje_km': kmValue,
                              };

                        // Ako je uneta kilometraža veća od trenutne u bazi, ažuriraj i nju
                        if (kmValue != null && kmValue > (_selectedVozilo?.kilometraza ?? 0)) {
                          updateData['kilometraza'] = kmValue.toDouble();
                        }

                        final success = await V2VozilaService.updateKolskaKnjiga(
                          _selectedVozilo!.id,
                          updateData,
                        );

                        // Dodaj u istoriju
                        if (success && selectedDatum != null) {
                          await V2VozilaService.addIstorijuServisa(
                            voziloId: _selectedVozilo!.id,
                            tip: isPrednje ? 'gume_prednje' : 'gume_zadnje',
                            datum: selectedDatum,
                            km: kmValue,
                            opis: finalOpis.isEmpty ? null : finalOpis,
                            pozicija: pozicija,
                          );
                        }

                        if (!context.mounted) return;
                        Navigator.pop(context);
                        if (success) {
                          V2AppSnackBar.success(context, '✅ Sačuvano');
                        }
                      },
                      icon: const Icon(Icons.save),
                      label: const Text('Sačuvaj'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    opisController.dispose();
    kmController.dispose();
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

int? _odrzavanjeGetDanaDoIsteka(V2Vozilo vozilo) {
  if (vozilo.registracijaVaziDo == null) return null;
  return vozilo.registracijaVaziDo!.difference(DateTime.now()).inDays;
}

// Informativna senka za 15-30 dana do isteka (žuta/limeta)
List<BoxShadow>? _odrzavanjeGetRegistracijaSenka(V2Vozilo vozilo) {
  final danaDoIsteka = _odrzavanjeGetDanaDoIsteka(vozilo);
  if (danaDoIsteka == null) return null;
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
