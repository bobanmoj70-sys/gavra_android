import 'package:flutter/material.dart';
import 'package:gavra_android/models/v3_adresa.dart';
import 'package:gavra_android/services/v3/v3_adresa_service.dart';
import 'package:gavra_android/theme.dart';

import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dialog_helper.dart';
import '../utils/v3_error_utils.dart';
import '../utils/v3_string_utils.dart';
import '../utils/v3_text_utils.dart';

class V3AdreseScreen extends StatefulWidget {
  const V3AdreseScreen({super.key});

  @override
  State<V3AdreseScreen> createState() => _AdreseScreenState();
}

class _AdreseScreenState extends State<V3AdreseScreen> {
  final String _filter = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('📍 Adrese'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: V3ContainerUtils.backgroundContainer(
        gradient: Theme.of(context).backgroundGradient,
        child: SafeArea(
          child: StreamBuilder<List<V3Adresa>>(
            stream: V3AdresaService.streamAdrese(),
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return Center(child: Text('Greška: ${snapshot.error}', style: const TextStyle(color: Colors.white70)));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final sve = snapshot.data!;
              return _AdreseFilterPanel(
                adrese: sve,
                onEdit: (a) => _showAdresaDialog(adresa: a),
                onDelete: _confirmDelete,
              );
            },
          ),
        ),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom),
        child: FloatingActionButton.extended(
          onPressed: () => _showAdresaDialog(),
          icon: const Icon(Icons.add),
          label: const Text('Dodaj'),
          backgroundColor: Colors.green,
        ),
      ),
    );
  }

  Future<void> _showAdresaDialog({V3Adresa? adresa}) async {
    final result = await V3DialogHelper.showDialogBuilder<Map<String, dynamic>>(
      context: context,
      builder: (context) => _AdresaDialog(adresa: adresa),
    );

    if (result != null) {
      try {
        await V3AdresaService.addUpdateAdresa(
          id: adresa?.id,
          naziv: result['naziv'],
          grad: result['grad'],
          lat: result['lat'],
          lng: result['lng'],
        );
        if (mounted) V3AppSnackBar.success(context, adresa == null ? '✅ Adresa dodata' : '✅ Adresa izmenjena');
      } catch (e) {
        V3ErrorUtils.asyncError(this, context, e);
      }
    }
  }

  Future<void> _confirmDelete(V3Adresa adresa) async {
    final confirm = await V3DialogHelper.showConfirmDialog(
      context,
      title: 'Potvrda brisanja',
      message: 'Da li ste sigurni da želite obrisati adresu "${adresa.naziv}"?',
      confirmText: 'DA',
      cancelText: 'NE',
      isDangerous: true,
    );

    if (confirm == true) {
      try {
        await V3AdresaService.deleteAdresa(adresa.id);
        if (mounted) V3AppSnackBar.success(context, '🗑️ Adresa obrisana');
      } catch (e) {
        V3ErrorUtils.asyncError(this, context, e);
      }
    }
  }
}

// ─── Stats model ──────────────────────────────────────────────────────────────
class _AdreseStats {
  final int ukupno;
  final int belaCrkva;
  final int vrsac;

  const _AdreseStats({required this.ukupno, required this.belaCrkva, required this.vrsac});

  factory _AdreseStats.from(List<V3Adresa> adrese) {
    int bc = 0, vs = 0;
    for (final a in adrese) {
      if (a.grad == 'BC')
        bc++;
      else if (a.grad == 'VS') vs++;
    }
    return _AdreseStats(ukupno: adrese.length, belaCrkva: bc, vrsac: vs);
  }
}

// ─── Filter panel ─────────────────────────────────────────────────────────────
class _AdreseFilterPanel extends StatefulWidget {
  const _AdreseFilterPanel({required this.adrese, required this.onEdit, required this.onDelete});
  final List<V3Adresa> adrese;
  final void Function(V3Adresa) onEdit;
  final void Function(V3Adresa) onDelete;

  @override
  State<_AdreseFilterPanel> createState() => _AdreseFilterPanelState();
}

class _AdreseFilterPanelState extends State<_AdreseFilterPanel> {
  String _filterGrad = 'Svi';
  String _searchQuery = '';

  @override
  void dispose() {
    V3TextUtils.disposeController('adrese_search');
    super.dispose();
  }

  List<V3Adresa> get _filtered {
    final q = _searchQuery;
    return widget.adrese.where((a) {
      final matchSearch = V3StringUtils.containsSearch(a.naziv, q);
      final matchGrad = _filterGrad == 'Svi' || (a.grad ?? '') == _filterGrad;
      return matchSearch && matchGrad;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final stats = _AdreseStats.from(widget.adrese);
    final filtered = _filtered;

    return Column(
      children: [
        V3ContainerUtils.styledContainer(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          backgroundColor: Theme.of(context).glassContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).glassBorder),
          child: Column(
            children: [
              // STATS
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatCard(label: 'Ukupno', value: stats.ukupno, color: Colors.blue),
                  _StatCard(label: 'B. Crkva', value: stats.belaCrkva, color: Colors.green),
                  _StatCard(label: 'Vrsac', value: stats.vrsac, color: Colors.orange),
                ],
              ),
              const SizedBox(height: 12),
              // SEARCH
              TextField(
                controller: V3TextUtils.adreseSearchController,
                decoration: InputDecoration(
                  hintText: 'Pretraži adrese...',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.white70),
                          onPressed: () {
                            V3TextUtils.clearController('adrese_search');
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.blue, width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.3),
                ),
                style: const TextStyle(color: Colors.white, fontSize: 16),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
              const SizedBox(height: 12),
              // FILTER CHIPS
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _GradChip(
                      label: 'Svi', selected: _filterGrad == 'Svi', onTap: () => setState(() => _filterGrad = 'Svi')),
                  const SizedBox(width: 8),
                  _GradChip(
                      label: 'Bela Crkva',
                      selected: _filterGrad == 'BC',
                      onTap: () => setState(() => _filterGrad = 'BC')),
                  const SizedBox(width: 8),
                  _GradChip(
                      label: 'Vrsac', selected: _filterGrad == 'VS', onTap: () => setState(() => _filterGrad = 'VS')),
                ],
              ),
            ],
          ),
        ),
        // LISTA
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('Nema adresa', style: TextStyle(color: Colors.white70)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) => _AdresaCard(
                    adresa: filtered[i],
                    onEdit: widget.onEdit,
                    onDelete: widget.onDelete,
                  ),
                ),
        ),
      ],
    );
  }
}

// ─── Helper widgeti ───────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text('$value', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      );
}

class _GradChip extends StatelessWidget {
  const _GradChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        backgroundColor: Colors.black.withValues(alpha: 0.3),
        selectedColor: Colors.blue.withValues(alpha: 0.6),
        checkmarkColor: Colors.white,
        side: BorderSide(
          color: selected ? Colors.blue : Colors.white.withValues(alpha: 0.3),
          width: selected ? 2 : 1,
        ),
        labelStyle: TextStyle(
          color: Colors.white,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          fontSize: 14,
        ),
      );
}

class _AdresaCard extends StatelessWidget {
  const _AdresaCard({required this.adresa, required this.onEdit, required this.onDelete});
  final V3Adresa adresa;
  final void Function(V3Adresa) onEdit;
  final void Function(V3Adresa) onDelete;

  static String _gradLabel(String? grad) => switch (grad) {
        'BC' => 'Bela Crkva',
        'VS' => 'Vrsac',
        _ => grad ?? '',
      };

  @override
  Widget build(BuildContext context) {
    final isBC = adresa.grad == 'BC';
    final color = isBC ? Colors.green : Colors.orange;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.2),
          child: Icon(Icons.location_on, color: color),
        ),
        title: Text(adresa.naziv, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text(_gradLabel(adresa.grad), style: TextStyle(color: Colors.grey[400], fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 20), onPressed: () => onEdit(adresa)),
            IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () => onDelete(adresa)),
          ],
        ),
      ),
    );
  }
}

class _AdresaDialog extends StatefulWidget {
  final V3Adresa? adresa;
  const _AdresaDialog({this.adresa});

  @override
  State<_AdresaDialog> createState() => _AdresaDialogState();
}

class _AdresaDialogState extends State<_AdresaDialog> {
  late final TextEditingController _naziv;
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  late String _selectedGrad;

  @override
  void initState() {
    super.initState();
    _naziv = TextEditingController(text: widget.adresa?.naziv ?? '');
    final existingGrad = widget.adresa?.grad ?? '';
    _selectedGrad = (existingGrad == 'VS') ? 'VS' : 'BC';
    _lat = TextEditingController(text: widget.adresa?.gpsLat?.toString() ?? '');
    _lng = TextEditingController(text: widget.adresa?.gpsLng?.toString() ?? '');
  }

  @override
  void dispose() {
    _naziv.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.adresa == null ? 'Nova Adresa' : 'Izmeni Adresu'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _naziv, decoration: const InputDecoration(labelText: 'Naziv adrese')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedGrad,
              decoration: const InputDecoration(labelText: 'Grad'),
              items: const [
                DropdownMenuItem(value: 'BC', child: Text('Bela Crkva')),
                DropdownMenuItem(value: 'VS', child: Text('Vršac')),
              ],
              onChanged: (v) => setState(() => _selectedGrad = v!),
            ),
            const SizedBox(height: 4),
            TextField(
                controller: _lat,
                decoration: const InputDecoration(labelText: 'Latitude (opciono)'),
                keyboardType: TextInputType.number),
            TextField(
                controller: _lng,
                decoration: const InputDecoration(labelText: 'Longitude (opciono)'),
                keyboardType: TextInputType.number),
          ],
        ),
      ),
      actions: [
        V3ButtonUtils.textButton(onPressed: () => Navigator.pop(context), text: 'ODUSTANI'),
        V3ButtonUtils.primaryButton(
          onPressed: () {
            if (_naziv.text.isEmpty) {
              return;
            }
            Navigator.pop(context, {
              'naziv': _naziv.text,
              'grad': _selectedGrad,
              'lat': double.tryParse(_lat.text),
              'lng': double.tryParse(_lng.text),
            });
          },
          text: 'SAČUVAJ',
        ),
      ],
    );
  }
}
