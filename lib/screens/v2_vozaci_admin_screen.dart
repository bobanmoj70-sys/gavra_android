import 'package:flutter/material.dart';
import 'package:gavra_android/models/v3_vozac.dart';
import 'package:gavra_android/services/v3/v3_vozac_service.dart';
import 'package:gavra_android/utils/v2_app_snack_bar.dart';

class V2VozaciAdminScreen extends StatefulWidget {
  const V2VozaciAdminScreen({super.key});

  @override
  State<V2VozaciAdminScreen> createState() => _V2VozaciAdminScreenState();
}

class _V2VozaciAdminScreenState extends State<V2VozaciAdminScreen> {
  final _formKey = GlobalKey<FormState>();
  final _imeController = TextEditingController();
  final _emailController = TextEditingController();
  final _sifraController = TextEditingController();
  final _telefonController = TextEditingController();
  Color _selectedColor = Colors.blue;

  final List<Color> _availableColors = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.pink,
    Colors.amber,
    Colors.indigo,
    Colors.brown,
  ];

  @override
  void dispose() {
    _imeController.dispose();
    _emailController.dispose();
    _sifraController.dispose();
    _telefonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('👨‍✈️ Administracija Vozača (V3)', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add, color: Colors.green, size: 30),
            onPressed: () => _showVozacDialog(),
          ),
        ],
      ),
      body: StreamBuilder<List<V3Vozac>>(
        stream: V3VozacService.streamVozaci(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Greška: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final vozaci = snapshot.data!.where((v) => v.aktivno).toList();
          if (vozaci.isEmpty) {
            return const Center(child: Text('Nema aktivnih vozača.', style: TextStyle(color: Colors.white70)));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: vozaci.length,
            itemBuilder: (context, i) {
              final v = vozaci[i];
              final boja = _hexToColor(v.boja);
              return Card(
                color: Colors.white.withValues(alpha: 0.1),
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: boja.withValues(alpha: 0.5), width: 1),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: boja,
                    child: Text(v.imePrezime[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
                  ),
                  title: Text(v.imePrezime, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    '${v.email}\nTel: ${v.telefon ?? "N/A"}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.edit, color: boja),
                        onPressed: () => _showVozacDialog(v),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                        onPressed: () => _confirmDeactivate(v),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Color _hexToColor(String? hex) {
    if (hex == null || hex.isEmpty) return Colors.blue;
    try {
      final h = hex.replaceAll('#', '');
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) {
      return Colors.blue;
    }
  }

  String _colorToHex(Color color) {
    return color.value.toRadixString(16).padLeft(8, '0').substring(2);
  }

  void _clearForm() {
    _imeController.clear();
    _emailController.clear();
    _sifraController.clear();
    _telefonController.clear();
    _selectedColor = Colors.blue;
  }

  Future<void> _showVozacDialog([V3Vozac? v]) async {
    if (v != null) {
      _imeController.text = v.imePrezime;
      _emailController.text = v.email ?? '';
      _sifraController.text = v.sifra ?? '';
      _telefonController.text = v.telefon ?? '';
      _selectedColor = _hexToColor(v.boja);
    } else {
      _clearForm();
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: Text(v == null ? 'Dodaj vozača' : 'Izmeni vozača', style: const TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTextField(_imeController, 'Ime i prezime', Icons.person),
                  const SizedBox(height: 12),
                  _buildTextField(_emailController, 'Email', Icons.email, keyboard: TextInputType.emailAddress),
                  const SizedBox(height: 12),
                  _buildTextField(_sifraController, 'Šifra (za App)', Icons.lock, obscure: true),
                  const SizedBox(height: 12),
                  _buildTextField(_telefonController, 'Telefon', Icons.phone, keyboard: TextInputType.phone),
                  const SizedBox(height: 16),
                  const Text('Boja:', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _availableColors.map((color) {
                      final isSelected = _selectedColor.value == color.value;
                      return GestureDetector(
                        onTap: () => setDialogState(() => _selectedColor = color),
                        child: Container(
                          width: 35,
                          height: 35,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: isSelected ? Colors.white : Colors.transparent, width: 2),
                          ),
                          child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Otkaži')),
            ElevatedButton(
              onPressed: () async {
                if (!_formKey.currentState!.validate()) return;

                final novVozac = V3Vozac(
                  id: v?.id ?? '',
                  imePrezime: _imeController.text.trim(),
                  email: _emailController.text.trim().toLowerCase(),
                  sifra: _sifraController.text.trim(),
                  telefon: _telefonController.text.trim(),
                  boja: _colorToHex(_selectedColor),
                  aktivno: true,
                );

                try {
                  await V3VozacService.addUpdateVozac(novVozac);
                  if (mounted) {
                    Navigator.pop(ctx);
                    V2AppSnackBar.success(context, v == null ? '✅ Vozač dodat' : '✅ Vozač ažuriran');
                  }
                } catch (e) {
                  if (mounted) V2AppSnackBar.error(context, '❌ Greška: $e');
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Sačuvaj'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, IconData icon,
      {bool obscure = false, TextInputType? keyboard}) {
    return TextFormField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white),
      obscureText: obscure,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: Colors.blueAccent),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.1),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
      validator: (val) => val == null || val.isEmpty ? 'Obavezno polje' : null,
    );
  }

  Future<void> _confirmDeactivate(V3Vozac v) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Deaktivacija', style: TextStyle(color: Colors.white)),
        content: Text('Da li ste sigurni da želite da deaktivirate vozača ${v.imePrezime}?',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('NE')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('DA'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await V3VozacService.deactivateVozac(v.id);
        if (mounted) V2AppSnackBar.success(context, '✅ Vozač deaktiviran');
      } catch (e) {
        if (mounted) V2AppSnackBar.error(context, '❌ Greška: $e');
      }
    }
  }
}
