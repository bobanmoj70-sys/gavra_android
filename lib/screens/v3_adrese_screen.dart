import 'package:flutter/material.dart';
import 'package:gavra_android/models/v3_adresa.dart';
import 'package:gavra_android/services/v3/v3_adresa_service.dart';
import 'package:gavra_android/utils/v2_app_snack_bar.dart';

class V3AdreseScreen extends StatefulWidget {
  const V3AdreseScreen({super.key});

  @override
  State<V3AdreseScreen> createState() => _AdreseScreenState();
}

class _AdreseScreenState extends State<V3AdreseScreen> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📍 V3 Adrese'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_location_alt),
            onPressed: () => _showAdresaDialog(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Pretraži adrese...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _filter = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<V3Adresa>>(
              stream: V3AdresaService.streamAdrese(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('Greška: ${snapshot.error}'));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final list = snapshot.data!
                    .where((a) =>
                        a.naziv.toLowerCase().contains(_filter) || (a.grad?.toLowerCase().contains(_filter) ?? false))
                    .toList();

                if (list.isEmpty) return const Center(child: Text('Nema adresa'));

                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final adresa = list[i];
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.location_on)),
                      title: Text(adresa.naziv),
                      subtitle: Text(adresa.grad ?? ''),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _showAdresaDialog(adresa: adresa),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _confirmDelete(adresa),
                          ),
                        ],
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

  Future<void> _showAdresaDialog({V3Adresa? adresa}) async {
    final result = await showDialog<Map<String, dynamic>>(
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
        if (mounted) V2AppSnackBar.success(context, adresa == null ? '✅ Adresa dodata' : '✅ Adresa izmenjena');
      } catch (e) {
        if (mounted) V2AppSnackBar.error(context, '❌ Greška: $e');
      }
    }
  }

  Future<void> _confirmDelete(V3Adresa adresa) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Potvrda brisanja'),
        content: Text('Da li ste sigurni da želite obrisati adresu "${adresa.naziv}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('NE')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DA', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await V3AdresaService.deleteAdresa(adresa.id);
        if (mounted) V2AppSnackBar.success(context, '🗑️ Adresa obrisana');
      } catch (e) {
        if (mounted) V2AppSnackBar.error(context, '❌ Greška: $e');
      }
    }
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
  late final TextEditingController _grad;
  late final TextEditingController _lat;
  late final TextEditingController _lng;

  @override
  void initState() {
    super.initState();
    _naziv = TextEditingController(text: widget.adresa?.naziv ?? '');
    _grad = TextEditingController(text: widget.adresa?.grad ?? 'BRČKO');
    _lat = TextEditingController(text: widget.adresa?.gpsLat?.toString() ?? '');
    _lng = TextEditingController(text: widget.adresa?.gpsLng?.toString() ?? '');
  }

  @override
  void dispose() {
    _naziv.dispose();
    _grad.dispose();
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
            TextField(controller: _grad, decoration: const InputDecoration(labelText: 'Grad')),
            TextField(controller: _lat, decoration: const InputDecoration(labelText: 'Latitude (opciono)'), keyboardType: TextInputType.number),
            TextField(controller: _lng, decoration: const InputDecoration(labelText: 'Longitude (opciono)'), keyboardType: TextInputType.number),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ODUSTANI')),
        ElevatedButton(
          onPressed: () {
            if (_naziv.text.isEmpty || _grad.text.isEmpty) {
              return;
            }
            Navigator.pop(context, {
              'naziv': _naziv.text,
              'grad': _grad.text,
              'lat': double.tryParse(_lat.text),
              'lng': double.tryParse(_lng.text),
            });
          },
          child: const Text('SAČUVAJ'),
        ),
      ],
    );
  }
}
