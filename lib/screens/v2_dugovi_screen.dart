import 'package:flutter/material.dart';
import 'package:gavra_android/models/v3_dug.dart';
import 'package:gavra_android/services/v3/v3_dug_service.dart';
import 'package:gavra_android/utils/v2_app_snack_bar.dart';
import 'package:intl/intl.dart';

class V2DugoviScreen extends StatefulWidget {
  const V2DugoviScreen({super.key});

  @override
  State<V2DugoviScreen> createState() => _V2DugoviScreenState();
}

class _V2DugoviScreenState extends State<V2DugoviScreen> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('💳 V3 Dugovanja'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Pretraži putnike...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _filter = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<V3Dug>>(
              stream: V3DugService.streamDugovi(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('Greška: ${snapshot.error}'));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final list = snapshot.data!.where((d) => d.putnikIme.toLowerCase().contains(_filter)).toList();

                if (list.isEmpty) return const Center(child: Text('Nema aktivnih dugova'));

                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final dug = list[i];
                    return ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.redAccent,
                        child: Icon(Icons.money_off, color: Colors.white),
                      ),
                      title: Text(dug.putnikIme, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        'Iznos: ${dug.iznos.toStringAsFixed(2)} KM\nDatum: ${DateFormat('dd.MM.yyyy HH:mm').format(dug.datum)}',
                      ),
                      isThreeLine: true,
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                        onPressed: () => _markAsPaid(dug),
                        child: const Text('NAPLATI', style: TextStyle(color: Colors.white)),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _markAsPaid(V3Dug dug) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Potvrda naplate'),
        content: Text('Da li je putnik ${dug.putnikIme} platio dug od ${dug.iznos.toStringAsFixed(2)} KM?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('NE')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DA', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await V3DugService.markAsPaid(dug.id);
        if (mounted) V2AppSnackBar.success(context, '✅ Dug naplaćen i arhiviran');
      } catch (e) {
        if (mounted) V2AppSnackBar.error(context, '❌ Greška: $e');
      }
    }
  }
}
