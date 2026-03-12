import 'package:flutter/material.dart';

import '../models/v2_adresa.dart';
import '../services/v2_adresa_supabase_service.dart';
import '../theme.dart';
import '../utils/v2_app_snack_bar.dart';

// ─── Model za stats (jedan prolaz kroz listu) ────────────────────────────────

class _AdreseStats {
  final int ukupno;
  final int belaCrkva;
  final int vrsac;

  const _AdreseStats({required this.ukupno, required this.belaCrkva, required this.vrsac});

  factory _AdreseStats.from(List<V2Adresa> adrese) {
    int bc = 0, vs = 0;
    for (final a in adrese) {
      if (a.grad == 'BC')
        bc++;
      else if (a.grad == 'VS') vs++;
    }
    return _AdreseStats(ukupno: adrese.length, belaCrkva: bc, vrsac: vs);
  }
}

// ─── Izolirani filter/search widget — setState ovdje ne trigguje StreamBuilder ─

class _AdreseFilterPanel extends StatefulWidget {
  const _AdreseFilterPanel({required this.adrese, required this.onEdit, required this.onDelete});

  final List<V2Adresa> adrese;
  final void Function(V2Adresa) onEdit;
  final void Function(V2Adresa) onDelete;

  @override
  State<_AdreseFilterPanel> createState() => _AdreseFilterPanelState();
}

class _AdreseFilterPanelState extends State<_AdreseFilterPanel> {
  String _filterGrad = 'Svi';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<V2Adresa> get _filtered {
    final q = _searchQuery.toLowerCase();
    return widget.adrese.where((a) {
      final matchSearch = q.isEmpty || a.naziv.toLowerCase().contains(q);
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
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).glassContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).glassBorder),
          ),
          child: Column(
            children: [
              // STATS — jedan prolaz kroz listu
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
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Pretraži adrese...',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.white70),
                          onPressed: () {
                            _searchController.clear();
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
                  _FilterChip(
                      label: 'Svi', selected: _filterGrad == 'Svi', onTap: () => setState(() => _filterGrad = 'Svi')),
                  const SizedBox(width: 8),
                  _FilterChip(
                      label: 'Bela Crkva',
                      selected: _filterGrad == 'BC',
                      onTap: () => setState(() => _filterGrad = 'BC')),
                  const SizedBox(width: 8),
                  _FilterChip(
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
                  itemBuilder: (context, index) => _AdresaCard(
                    adresa: filtered[index],
                    onEdit: widget.onEdit,
                    onDelete: widget.onDelete,
                  ),
                ),
        ),
      ],
    );
  }
}

// ─── Stateless helper widgeti ─────────────────────────────────────────────────

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

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

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

  final V2Adresa adresa;
  final void Function(V2Adresa) onEdit;
  final void Function(V2Adresa) onDelete;

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

// ─── Glavni screen ────────────────────────────────────────────────────────────

class V2AdreseScreen extends StatefulWidget {
  const V2AdreseScreen({super.key});

  @override
  State<V2AdreseScreen> createState() => _AdreseScreenState();
}

class _AdreseScreenState extends State<V2AdreseScreen> {
  final Stream<List<V2Adresa>> _stream = V2AdresaSupabaseService.streamSveAdrese();

  Future<void> _addAdresa() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _AdresaDialog(),
    );
    if (result == null) return;
    try {
      await V2AdresaSupabaseService.addAdresa(
        naziv: result['naziv'] as String,
        grad: result['grad'] as String,
        lat: result['latitude'] as double?,
        lng: result['longitude'] as double?,
      );
      if (mounted) V2AppSnackBar.success(context, '✅ Adresa dodana');
    } catch (e) {
      if (mounted) V2AppSnackBar.error(context, '❌ Greška: $e');
    }
  }

  Future<void> _editAdresa(V2Adresa adresa) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _AdresaDialog(
        initialNaziv: adresa.naziv,
        initialGrad: adresa.grad,
        initialLatitude: adresa.gpsLat,
        initialLongitude: adresa.gpsLng,
      ),
    );
    if (result == null) return;
    try {
      await V2AdresaSupabaseService.updateAdresa(
        adresa,
        naziv: result['naziv'] as String,
        grad: result['grad'] as String,
        lat: result['latitude'] as double?,
        lng: result['longitude'] as double?,
      );
      if (mounted) V2AppSnackBar.success(context, '✅ Adresa ažurirana');
    } catch (e) {
      if (mounted) V2AppSnackBar.error(context, '❌ Greška: $e');
    }
  }

  Future<void> _deleteAdresa(V2Adresa adresa) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Obriši adresu?'),
        content: Text('Sigurno želite da obrišete adresu: ${adresa.naziv}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Otkaži')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Obriši', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await V2AdresaSupabaseService.deleteAdresa(adresa);
      if (mounted) V2AppSnackBar.warning(context, '🗑️ Adresa obrisana');
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('23503') || e.toString().toLowerCase().contains('foreign key')
            ? '❌ Adresa se koristi i ne može se obrisati'
            : '❌ Greška: $e';
        V2AppSnackBar.error(context, msg);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<V2Adresa>>(
      stream: _stream,
      builder: (context, snapshot) {
        final adrese = snapshot.data ?? [];
        final isLoading = snapshot.connectionState == ConnectionState.waiting && adrese.isEmpty;

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: const Text('📍 Adrese'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
          ),
          body: Container(
            decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
            child: SafeArea(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _AdreseFilterPanel(
                      adrese: adrese,
                      onEdit: _editAdresa,
                      onDelete: _deleteAdresa,
                    ),
            ),
          ),
          // ANDROID 15 EDGE-TO-EDGE: Padding za gesture navigation bar
          floatingActionButton: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom),
            child: FloatingActionButton.extended(
              onPressed: _addAdresa,
              icon: const Icon(Icons.add),
              label: const Text('Dodaj'),
              backgroundColor: Colors.green,
            ),
          ),
        );
      },
    );
  }
}

/// Dialog za dodavanje/uređivanje adrese
class _AdresaDialog extends StatefulWidget {
  final String? initialNaziv;
  final String? initialGrad;
  final double? initialLatitude;
  final double? initialLongitude;

  const _AdresaDialog({
    this.initialNaziv,
    this.initialGrad,
    this.initialLatitude,
    this.initialLongitude,
  });

  @override
  State<_AdresaDialog> createState() => _AdresaDialogState();
}

class _AdresaDialogState extends State<_AdresaDialog> {
  late final TextEditingController _nazivController;
  late final TextEditingController _latitudeController;
  late final TextEditingController _longitudeController;
  String _selectedGrad = 'BC';

  @override
  void initState() {
    super.initState();
    _nazivController = TextEditingController(text: widget.initialNaziv);
    _latitudeController = TextEditingController(text: widget.initialLatitude?.toString());
    _longitudeController = TextEditingController(text: widget.initialLongitude?.toString());
    if (widget.initialGrad == 'BC' || widget.initialGrad == 'VS') {
      _selectedGrad = widget.initialGrad!;
    }
  }

  @override
  void dispose() {
    _nazivController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialNaziv != null;

    return AlertDialog(
      title: Text(isEditing ? 'Uredi adresu' : 'Nova adresa'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nazivController,
              decoration: const InputDecoration(
                labelText: 'Naziv *',
                hintText: 'npr. Bolnica, Hemofarm, Dejana Brankova 99',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: const ['BC', 'VS'].contains(_selectedGrad) ? _selectedGrad : null,
              decoration: const InputDecoration(labelText: 'Grad *'),
              items: [('BC', 'Bela Crkva'), ('VS', 'Vrsac')].map((e) {
                return DropdownMenuItem(value: e.$1, child: Text(e.$2));
              }).toList(),
              onChanged: (value) {
                if (value != null) setState(() => _selectedGrad = value);
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _latitudeController,
                    decoration: const InputDecoration(
                      labelText: 'Latitude (opciono)',
                      hintText: 'npr. 44.7568',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _longitudeController,
                    decoration: const InputDecoration(
                      labelText: 'Longitude (opciono)',
                      hintText: 'npr. 21.1622',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Otkaži'),
        ),
        ElevatedButton(
          onPressed: () {
            final naziv = _nazivController.text.trim();
            if (naziv.isEmpty) {
              V2AppSnackBar.warning(context, 'Naziv je obavezan');
              return;
            }

            double? latitude;
            double? longitude;
            if (_latitudeController.text.trim().isNotEmpty) {
              latitude = double.tryParse(_latitudeController.text.trim());
              if (latitude == null || latitude < -90 || latitude > 90) {
                V2AppSnackBar.error(context, 'Latitude mora biti između -90 i 90');
                return;
              }
            }
            if (_longitudeController.text.trim().isNotEmpty) {
              longitude = double.tryParse(_longitudeController.text.trim());
              if (longitude == null || longitude < -180 || longitude > 180) {
                V2AppSnackBar.error(context, 'Longitude mora biti između -180 i 180');
                return;
              }
            }

            Navigator.pop(context, {
              'naziv': naziv,
              'grad': _selectedGrad,
              'latitude': latitude,
              'longitude': longitude,
            });
          },
          child: Text(isEditing ? 'Sačuvaj' : 'Dodaj'),
        ),
      ],
    );
  }
}
