import 'package:flutter/material.dart';
import 'package:gavra_android/models/v3_putnik.dart';
import 'package:gavra_android/services/v3/v3_putnik_service.dart';
import 'package:gavra_android/services/realtime/v3_master_realtime_manager.dart';
import 'package:gavra_android/utils/v2_app_snack_bar.dart';
import 'package:url_launcher/url_launcher.dart';

class V2PutniciScreen extends StatefulWidget {
  const V2PutniciScreen({super.key});

  @override
  State<V2PutniciScreen> createState() => _V2PutniciScreenState();
}

class _V2PutniciScreenState extends State<V2PutniciScreen> {
  String _selectedFilter = 'svi';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('👥 Putnici (V3)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () => _showAddPutnikDialog(),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterChips(),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Pretraga po imenu...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(child: _buildPutniciList()),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final filters = ['svi', 'radnik', 'ucenik', 'dnevni', 'posiljka'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: filters.map((f) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(f.toUpperCase()),
              selected: _selectedFilter == f,
              onSelected: (val) => setState(() => _selectedFilter = f),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPutniciList() {
    return StreamBuilder<void>(
      stream: V3MasterRealtimeManager.instance.onChange,
      builder: (context, snapshot) {
        var list = V3MasterRealtimeManager.instance.putniciCache.values
            .map((v) => V3Putnik.fromJson(v))
            .where((p) => p.aktivna)
            .toList();

        // Filter po tipu
        if (_selectedFilter != 'svi') {
          list = list.where((p) => p.tipPutnika == _selectedFilter).toList();
        }

        // Filter po search termu
        final search = _searchController.text.trim().toLowerCase();
        if (search.isNotEmpty) {
          list = list.where((p) => p.imePrezime.toLowerCase().contains(search)).toList();
        }

        list.sort((a, b) => a.imePrezime.toLowerCase().compareTo(b.imePrezime.toLowerCase()));

        if (list.isEmpty) return const Center(child: Text('Nema putnika.'));

        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, i) {
            final p = list[i];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _getTipColor(p.tipPutnika),
                  child: const Icon(Icons.person, color: Colors.white),
                ),
                title: Text(p.imePrezime, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${p.tipPutnika.toUpperCase()} | ${p.telefon1 ?? "Nema tel"}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (p.telefon1 != null)
                      IconButton(
                        icon: const Icon(Icons.phone, color: Colors.green),
                        onPressed: () => launchUrl(Uri.parse('tel:${p.telefon1}')),
                      ),
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () => _showAddPutnikDialog(p),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Color _getTipColor(String tip) {
    switch (tip) {
      case 'radnik': return Colors.blue;
      case 'ucenik': return Colors.orange;
      case 'dnevni': return Colors.green;
      case 'posiljka': return Colors.purple;
      default: return Colors.grey;
    }
  }

  Future<void> _showAddPutnikDialog([V3Putnik? p]) async {
    // Implementacija dijaloga za dodavanje/izmenu putnika
    V2AppSnackBar.info(context, 'Funkcionalnost u pripremi za V3');
  }
}
