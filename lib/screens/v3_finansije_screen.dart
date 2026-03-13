import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:gavra_android/models/v3_finansije.dart';
import 'package:gavra_android/services/v3/v3_finansije_service.dart';
import 'package:gavra_android/utils/v2_app_snack_bar.dart';

class V3FinansijeScreen extends StatefulWidget {
  const V3FinansijeScreen({super.key});

  @override
  State<V3FinansijeScreen> createState() => _V3FinansijeScreenState();
}

class _V3FinansijeScreenState extends State<V3FinansijeScreen> {
  final NumberFormat _fmt = NumberFormat('#,###', 'sr');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('💰 V3 Finansije'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _addUnosDialog(),
          ),
        ],
      ),
      body: StreamBuilder<V3FinansijskiIzvestaj>(
        stream: V3FinansijeService.streamIzvestaj(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Greška: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final izvestaj = snapshot.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSummaryCard('DANAS', izvestaj.prihodDanas, izvestaj.trosakDanas, Colors.blue),
                const SizedBox(height: 16),
                _buildSummaryCard('OVAJ MESEC', izvestaj.prihodMesec, izvestaj.trosakMesec, Colors.green),
                const SizedBox(height: 24),
                const Text('Troškovi po kategoriji', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Divider(),
                ...izvestaj.troskoviPoKategoriji.entries.map((e) => ListTile(
                      title: Text(e.key.toUpperCase()),
                      trailing: Text('${_fmt.format(e.value)} KM', style: const TextStyle(fontWeight: FontWeight.bold)),
                    )),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard(String title, double prihod, double trosak, Color color) {
    final neto = prihod - trosak;
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Center(
              child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _row('Prihod:', prihod, Colors.green),
                _row('Trošak:', trosak, Colors.red),
                const Divider(),
                _row('NETO:', neto, neto >= 0 ? Colors.green : Colors.red, isBold: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, double val, Color color, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(
            '${_fmt.format(val)} KM',
            style: TextStyle(color: color, fontWeight: isBold ? FontWeight.bold : FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Future<void> _addUnosDialog() async {
    final result = await showDialog<V3FinansijskiUnos>(
      context: context,
      builder: (context) => const _AddUnosDialog(),
    );

    if (result != null) {
      try {
        await V3FinansijeService.addUnos(result);
        if (mounted) V2AppSnackBar.success(context, '✅ Finansijski unos dodat');
      } catch (e) {
        if (mounted) V2AppSnackBar.error(context, '❌ Greška: $e');
      }
    }
  }
}

class _AddUnosDialog extends StatefulWidget {
  const _AddUnosDialog();

  @override
  State<_AddUnosDialog> createState() => _AddUnosDialogState();
}

class _AddUnosDialogState extends State<_AddUnosDialog> {
  String _tip = 'trosak';
  String _kategorija = 'ostalo';
  final _iznos = TextEditingController();
  final _opis = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novi unos'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _tip,
              items: const [
                DropdownMenuItem(value: 'prihod', child: Text('Prihod')),
                DropdownMenuItem(value: 'trosak', child: Text('Trošak')),
              ],
              onChanged: (v) => setState(() => _tip = v!),
              decoration: const InputDecoration(labelText: 'Tip'),
            ),
            DropdownButtonFormField<String>(
              value: _kategorija,
              items: const [
                DropdownMenuItem(value: 'gorivo', child: Text('Gorivo')),
                DropdownMenuItem(value: 'odrzavanje', child: Text('Održavanje')),
                DropdownMenuItem(value: 'ostalo', child: Text('Ostalo')),
              ],
              onChanged: (v) => setState(() => _kategorija = v!),
              decoration: const InputDecoration(labelText: 'Kategorija'),
            ),
            TextField(controller: _iznos, decoration: const InputDecoration(labelText: 'Iznos (KM)'), keyboardType: TextInputType.number),
            TextField(controller: _opis, decoration: const InputDecoration(labelText: 'Opis (opciono)')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ODUSTANI')),
        ElevatedButton(
          onPressed: () {
            final val = double.tryParse(_iznos.text);
            if (val == null) return;
            Navigator.pop(context, V3FinansijskiUnos(
              id: '',
              tip: _tip,
              kategorija: _kategorija,
              iznos: val,
              opis: _opis.text,
              datum: DateTime.now(),
              createdAt: DateTime.now(),
            ));
          },
          child: const Text('DODAJ'),
        ),
      ],
    );
  }
}
