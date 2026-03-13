import 'package:flutter/material.dart';
import 'package:gavra_android/models/v3_vozilo.dart';
import 'package:gavra_android/services/v3/v3_vozilo_service.dart';
import 'package:gavra_android/utils/v2_app_snack_bar.dart';

class V3OdrzavanjeScreen extends StatefulWidget {
  const V3OdrzavanjeScreen({super.key});

  @override
  State<V3OdrzavanjeScreen> createState() => _V3OdrzavanjeScreenState();
}

class _V3OdrzavanjeScreenState extends State<V3OdrzavanjeScreen> {
  V3Vozilo? _selectedVozilo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📖 Kolska knjiga (V3)'),
      ),
      body: StreamBuilder<List<V3Vozilo>>(
        stream: V3VoziloService.streamVozila(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Greška: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final vozila = snapshot.data!.where((v) => v.aktivno).toList();
          if (vozila.isEmpty) return const Center(child: Text('Nema aktivnih vozila.'));

          // Inicijalna selekcija ili sinhronizacija
          if (_selectedVozilo == null) {
            _selectedVozilo = vozila.first;
          } else {
            final exists = vozila.any((v) => v.id == _selectedVozilo!.id);
            if (!exists) {
              _selectedVozilo = vozila.first;
            } else {
              _selectedVozilo = vozila.firstWhere((v) => v.id == _selectedVozilo!.id);
            }
          }

          return Column(
            children: [
              _buildVoziloDropdown(vozila),
              const Divider(),
              if (_selectedVozilo != null) Expanded(child: _buildDetailsView(_selectedVozilo!)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildVoziloDropdown(List<V3Vozilo> vozila) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: DropdownButtonFormField<V3Vozilo>(
        value: _selectedVozilo,
        decoration: const InputDecoration(labelText: 'Izaberi vozilo', border: OutlineInputBorder()),
        items: vozila.map((v) => DropdownMenuItem(value: v, child: Text('${v.naziv} (${v.registracija})'))).toList(),
        onChanged: (val) => setState(() => _selectedVozilo = val),
      ),
    );
  }

  Widget _buildDetailsView(V3Vozilo v) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildInfoCard('Osnovni podaci', [
          _row('Model:', v.model ?? 'N/A'),
          _row('Marka:', v.marka ?? 'N/A'),
        ]),
        const SizedBox(height: 16),
        _buildInfoCard('Tehnički podaci', [
          _row('Kilometraža:', '${v.trenutnaKm} km', highlight: true),
        ]),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => _editVozilo(v),
          icon: const Icon(Icons.edit),
          label: const Text('IZMENI PODATKE'),
        ),
      ],
    );
  }

  Widget _buildInfoCard(String title, List<Widget> children) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value,
              style: TextStyle(
                  fontWeight: highlight ? FontWeight.bold : FontWeight.normal, color: highlight ? Colors.red : null)),
        ],
      ),
    );
  }

  void _editVozilo(V3Vozilo v) {
    V2AppSnackBar.info(context, 'Izmena podataka u pripremi za V3');
  }
}
