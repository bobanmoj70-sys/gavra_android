import 'package:flutter/material.dart';
import 'package:gavra_android/models/v3_putnik.dart';
import 'package:gavra_android/models/v3_zahtev.dart';
import 'package:gavra_android/services/v3/v3_putnik_service.dart';
import 'package:gavra_android/services/v3/v3_zahtev_service.dart';

class V2HomeScreen extends StatefulWidget {
  const V2HomeScreen({super.key});

  @override
  State<V2HomeScreen> createState() => _V2HomeScreenState();
}

class _V2HomeScreenState extends State<V2HomeScreen> {
  String _selectedDay = 'pon';
  String _selectedGrad = 'BC';

  final List<String> _days = ['pon', 'uto', 'sre', 'cet', 'pet'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🏠 V3 Dashboard'),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          _buildDayPicker(),
          _buildGradPicker(),
          const Divider(),
          Expanded(child: _buildZahteviList()),
        ],
      ),
    );
  }

  Widget _buildDayPicker() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: _days.map((day) {
          final isSelected = _selectedDay == day;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(day.toUpperCase()),
              selected: isSelected,
              onSelected: (val) => setState(() => _selectedDay = day),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGradPicker() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ChoiceChip(
          label: const Text('BC'),
          selected: _selectedGrad == 'BC',
          onSelected: (val) => setState(() => _selectedGrad = 'BC'),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('VS'),
          selected: _selectedGrad == 'VS',
          onSelected: (val) => setState(() => _selectedGrad = 'VS'),
        ),
      ],
    );
  }

  Widget _buildZahteviList() {
    return StreamBuilder<List<V3Zahtev>>(
      stream: V3ZahtevService.streamZahteviByDanAndGrad(_selectedDay, _selectedGrad),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Greška: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final zahtevi = snapshot.data!;
        if (zahtevi.isEmpty) return const Center(child: Text('Nema zahteva za ovaj dan i grad.'));

        return ListView.builder(
          itemCount: zahtevi.length,
          itemBuilder: (context, i) {
            final z = zahtevi[i];
            final p = V3PutnikService.getPutnikById(z.putnikId);
            return _buildZahtevCard(z, p);
          },
        );
      },
    );
  }

  Widget _buildZahtevCard(V3Zahtev z, V3Putnik? p) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getStatusColor(z.status),
          child: Text(z.zeljenoVreme.split(':').first, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
        title: Text(p?.imePrezime ?? 'Nepoznat putnik'),
        subtitle: Text('${z.zeljenoVreme} - ${z.status.toUpperCase()}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.check, color: Colors.green),
              onPressed: () => V3ZahtevService.updateStatus(z.id, 'odobreno'),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red),
              onPressed: () => V3ZahtevService.updateStatus(z.id, 'odbijeno'),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'odobreno':
        return Colors.green;
      case 'odbijeno':
        return Colors.red;
      case 'otkazano':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }
}
