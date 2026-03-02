import 'package:flutter/material.dart';

import '../globals.dart';
import '../models/v2_adresa.dart';
import '../services/v2_adresa_supabase_service.dart';
import '../theme.dart';
import '../utils/v2_app_snack_bar.dart';

/// ADRESE SCREEN - Upravljanje dozvoljenim adresama
/// Omogućava dodavanje, uređivanje i brisanje adresa direktno iz aplikacije
class V2AdreseScreen extends StatefulWidget {
  const V2AdreseScreen({super.key});

  @override
  State<V2AdreseScreen> createState() => _AdreseScreenState();
}

class _AdreseScreenState extends State<V2AdreseScreen> {
  String _filterGrad = 'Svi';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  late final Stream<List<V2Adresa>> _streamAdrese;

  @override
  void initState() {
    super.initState();
    _streamAdrese = V2AdresaSupabaseService.streamSveAdrese();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<V2Adresa> _getFilteredAdrese(List<V2Adresa> adrese) {
    return adrese.where((adresa) {
      final naziv = (adresa.naziv).toLowerCase();
      final grad = adresa.grad ?? '';

      final matchesSearch = _searchQuery.isEmpty || naziv.contains(_searchQuery.toLowerCase());
      final matchesGrad = _filterGrad == 'Svi' || grad == _filterGrad;

      return matchesSearch && matchesGrad;
    }).toList();
  }

  Future<void> _addAdresa() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _AdresaDialog(),
    );

    if (result != null) {
      try {
        final insertData = {
          'naziv': result['naziv'],
          'grad': result['grad'],
        };

        // Add coordinates if provided
        if (result['latitude'] != null) {
          insertData['gps_lat'] = result['latitude'];
        }
        if (result['longitude'] != null) {
          insertData['gps_lng'] = result['longitude'];
        }

        await supabase.from('v2_adrese').insert(insertData);

        if (mounted) {
          AppSnackBar.success(context, '✅ V2Adresa dodana');
        }
      } catch (e) {
        if (mounted) {
          AppSnackBar.error(context, 'Greška: $e');
        }
      }
    }
  }

  Future<void> _editAdresa(V2Adresa adresa) async {
    final result = await showDialog<Map<String, dynamic>>(
      // Changed to Map<String, dynamic> to include doubles
      context: context,
      builder: (context) => _AdresaDialog(
        initialNaziv: adresa.naziv,
        initialGrad: adresa.grad,
        initialLatitude: adresa.gpsLat,
        initialLongitude: adresa.gpsLng,
      ),
    );

    if (result != null) {
      try {
        final updateData = {
          'naziv': result['naziv'],
          'grad': result['grad'],
        };

        // Add coordinates if provided
        if (result['latitude'] != null) {
          updateData['gps_lat'] = result['latitude'];
        }
        if (result['longitude'] != null) {
          updateData['gps_lng'] = result['longitude'];
        }

        await supabase.from('v2_adrese').update(updateData).eq('id', adresa.id);

        if (mounted) {
          AppSnackBar.success(context, '✅ V2Adresa ažurirana');
        }
      } catch (e) {
        if (mounted) {
          AppSnackBar.error(context, 'Greška: $e');
        }
      }
    }
  }

  Future<void> _deleteAdresa(V2Adresa adresa) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Obriši adresu?'),
        content: Text('Sigurno želite da obrišete adresu: ${adresa.naziv}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Otkaži'),
          ),
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
      await supabase.from('v2_adrese').delete().eq('id', adresa.id);
      if (mounted) {
        AppSnackBar.warning(context, '🗑️ V2Adresa obrisana');
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('23503') || e.toString().toLowerCase().contains('foreign key')
            ? '❌ V2Adresa se koristi i ne može se obrisati'
            : '❌ Greška: $e';
        AppSnackBar.error(context, msg);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<V2Adresa>>(
      stream: _streamAdrese,
      builder: (context, snapshot) {
        final adrese = snapshot.data ?? [];
        final isLoading = snapshot.connectionState == ConnectionState.waiting && adrese.isEmpty;

        final belaCrkvaCount = adrese.where((a) => a.grad == 'BC').length;
        final vrsacCount = adrese.where((a) => a.grad == 'VS').length;
        final filteredAdrese = _getFilteredAdrese(adrese);

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: const Text('📍 Adrese'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
          ),
          body: Container(
            decoration: BoxDecoration(
              gradient: Theme.of(context).backgroundGradient,
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // Header sa statistikom
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatCard('Ukupno', adrese.length.toString(), Colors.blue),
                            _buildStatCard('B. Crkva', belaCrkvaCount.toString(), Colors.green),
                            _buildStatCard('Vrsac', vrsacCount.toString(), Colors.orange),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Search bar
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
                          onChanged: (value) => setState(() => _searchQuery = value),
                        ),
                        const SizedBox(height: 12),
                        // Filter dugmad
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildFilterChip('Svi', _filterGrad == 'Svi'),
                            const SizedBox(width: 8),
                            _buildFilterChip('Bela Crkva', _filterGrad == 'BC', value: 'BC'),
                            const SizedBox(width: 8),
                            _buildFilterChip('Vrsac', _filterGrad == 'VS', value: 'VS'),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Lista adresa
                  Expanded(
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : filteredAdrese.isEmpty
                            ? const Center(
                                child: Text(
                                  'Nema adresa',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: filteredAdrese.length,
                                itemBuilder: (context, index) {
                                  final adresa = filteredAdrese[index];
                                  return _buildAdresaCard(adresa);
                                },
                              ),
                  ),
                ],
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

  static Widget _buildStatCard(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, bool selected, {String? value}) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (v) {
        setState(() => _filterGrad = value ?? label);
      },
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

  Widget _buildAdresaCard(V2Adresa adresa) {
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
          backgroundColor:
              adresa.grad == 'BC' ? Colors.green.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
          child: Icon(
            Icons.location_on,
            color: adresa.grad == 'BC' ? Colors.green : Colors.orange,
          ),
        ),
        title: Text(
          adresa.naziv,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          adresa.grad ?? '',
          style: TextStyle(color: Colors.grey[400], fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
              onPressed: () => _editAdresa(adresa),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red, size: 20),
              onPressed: () => _deleteAdresa(adresa),
            ),
          ],
        ),
      ),
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
    if (widget.initialGrad != null) {
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
              value: _selectedGrad.isNotEmpty ? _selectedGrad : null,
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
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
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
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
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
              AppSnackBar.warning(context, 'Naziv je obavezan');
              return;
            }

            double? latitude;
            double? longitude;
            if (_latitudeController.text.trim().isNotEmpty) {
              latitude = double.tryParse(_latitudeController.text.trim());
              if (latitude == null || latitude < -90 || latitude > 90) {
                AppSnackBar.error(context, 'Latitude mora biti između -90 i 90');
                return;
              }
            }
            if (_longitudeController.text.trim().isNotEmpty) {
              longitude = double.tryParse(_longitudeController.text.trim());
              if (longitude == null || longitude < -180 || longitude > 180) {
                AppSnackBar.error(context, 'Longitude mora biti između -180 i 180');
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
