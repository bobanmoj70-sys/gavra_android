?import 'package:flutter/material.dart';

import '../models/v2_vozac.dart';
import '../services/v2_vozac_service.dart';
import '../theme.dart';
import '../utils/v2_app_snack_bar.dart';

///  VOZACI ADMIN SCREEN - Admin panel za upravljanje vozacima
/// Ovde dodajes/brises vozace, emailove, sifre, telefone, boje
class VozaciAdminScreen extends StatefulWidget {
  const VozaciAdminScreen({super.key});

  @override
  State<VozaciAdminScreen> createState() => _VozaciAdminScreenState();
}

class _VozaciAdminScreenState extends State<VozaciAdminScreen> {
  // Forma za novog vozaca
  final _formKey = GlobalKey<FormState>();
  final _imeController = TextEditingController();
  final _emailController = TextEditingController();
  final _sifraController = TextEditingController();
  final _telefonController = TextEditingController();
  Color _selectedColor = Colors.blue;

  // Predefinisane boje za izbor
  final List<Color> _availableColors = [
    const Color(0xFF7C4DFF), // ljubicasta
    const Color(0xFFFF9800), // narandzasta
    const Color(0xFF00E5FF), // cyan
    const Color(0xFFFF1493), // pink
    const Color(0xFFFFD700), // zuta (Gold)
    const Color(0xFF4CAF50), // zelena
    const Color(0xFFE91E63), // crvena-pink
    const Color(0xFF2196F3), // plava
    const Color(0xFFFFEB3B), // svetla zuta
    const Color(0xFF9C27B0), // tamno ljubicasta
  ];

  final V2VozacService _vozacService = V2VozacService();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _imeController.dispose();
    _emailController.dispose();
    _sifraController.dispose();
    _telefonController.dispose();
    super.dispose();
  }

  /// Dodaj novog vozaca
  Future<void> _addVozac() async {
    if (!_formKey.currentState!.validate()) return;

    final noviVozac = Vozac(
      ime: _imeController.text.trim(),
      email: _emailController.text.trim().toLowerCase(),
      sifra: _sifraController.text,
      brojTelefona: _telefonController.text.trim(),
      boja: _selectedColor.value.toRadixString(16).padLeft(8, '0').substring(2),
    );

    try {
      final vozacSvc = V2VozacService();
      await vozacSvc.addVozac(noviVozac);
      if (!mounted) return;
      AppSnackBar.info(context, 'Vozac dodan');
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.error(context, 'Greska: $e');
      return;
    }

    _imeController.clear();
    _emailController.clear();
    _sifraController.clear();
    _telefonController.clear();
    _selectedColor = Colors.blue;

    if (mounted) {
      Navigator.pop(context);
      AppSnackBar.success(context, 'Vozac ${noviVozac.ime} dodat!');
    }
  }

  /// Obrisi vozaca
  Future<void> _deleteVozac(int index) async {
    // Trebam pristup svim vozacima iz StreamBuilder-a
    // Za sada emo koristiti prvi vozac kao test
    // U pravoj implementaciji, trebalo bi prosle?'ivanje vozaca kao parametra

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Greska', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Brisanje vozaca nije dostupno u ovoj verziji.\nKoristite web admin panel.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Edituj vozaca
  Future<void> _editVozac(int index) async {
    // Dohvati trenutni vozac stream podatke
    final vozaci = await _vozacService.getAllVozaci();
    if (index < 0 || index >= vozaci.length) return;

    final vozac = vozaci[index];

    // Popuni formu
    _imeController.text = vozac.ime;
    _emailController.text = vozac.email ?? '';
    _sifraController.text = vozac.sifra ?? '';
    _telefonController.text = vozac.brojTelefona ?? '';
    _selectedColor = vozac.color ?? Colors.blue;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => _buildVozacDialog(
        title: 'Izmeni vozaca',
        onSave: () async {
          if (!_formKey.currentState!.validate()) return;

          final updatedVozac = Vozac(
            id: vozac.id,
            ime: _imeController.text.trim(),
            email: _emailController.text.trim().toLowerCase(),
            sifra: _sifraController.text,
            brojTelefona: _telefonController.text.trim(),
            boja: _selectedColor.value.toRadixString(16).padLeft(8, '0').substring(2),
          );

          try {
            await _vozacService.updateVozac(updatedVozac);
            if (!mounted) return;
            Navigator.pop(context);
            AppSnackBar.info(context, 'Vozac azuriran');
          } catch (e) {
            if (!mounted) return;
            AppSnackBar.error(context, 'Greska: $e');
          }
        },
      ),
    );
  }

  /// Dialog za dodavanje/editovanje vozaca
  Widget _buildVozacDialog({required String title, required VoidCallback onSave}) {
    return StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Ime
                TextFormField(
                  controller: _imeController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('Ime vozaca', Icons.person),
                  validator: (v) => v?.isEmpty == true ? 'Unesite ime' : null,
                ),
                const SizedBox(height: 12),

                // Email
                TextFormField(
                  controller: _emailController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.emailAddress,
                  decoration: _inputDecoration('Email', Icons.email),
                  validator: (v) {
                    if (v?.isEmpty == true) return 'Unesite email';
                    if (!v!.contains('@')) return 'Neispravan email';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Sifra
                TextFormField(
                  controller: _sifraController,
                  style: const TextStyle(color: Colors.white),
                  obscureText: true,
                  decoration: _inputDecoration('Sifra', Icons.lock),
                ),
                const SizedBox(height: 12),

                // Telefon
                TextFormField(
                  controller: _telefonController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.phone,
                  decoration: _inputDecoration('Telefon', Icons.phone),
                ),
                const SizedBox(height: 16),

                // Boja
                const Text('Izaberi boju:', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _availableColors.map((color) {
                    final isSelected = _selectedColor.value == color.value;
                    return GestureDetector(
                      onTap: () {
                        setDialogState(() {
                          _selectedColor = color;
                        });
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow: isSelected ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 8)] : null,
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
          TextButton(
            onPressed: () {
              _imeController.clear();
              _emailController.clear();
              _sifraController.clear();
              _telefonController.clear();
              Navigator.pop(context);
            },
            child: const Text('Otkazi'),
          ),
          ElevatedButton(
            onPressed: onSave,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Sacuvaj'),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
      prefixIcon: Icon(icon, color: Colors.blue),
      filled: true,
      fillColor: Colors.white.withOpacity(0.1),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.blue.withOpacity(0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.blue),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: tripleBlueFashionGradient,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          centerTitle: true,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                ' Vozaci Admin',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.add_circle, color: Colors.green, size: 32),
                onPressed: () {
                  _imeController.clear();
                  _emailController.clear();
                  _sifraController.clear();
                  _telefonController.clear();
                  _selectedColor = Colors.blue;

                  showDialog(
                    context: context,
                    builder: (ctx) => _buildVozacDialog(
                      title: 'Dodaj vozaca',
                      onSave: _addVozac,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        body: StreamBuilder<List<Vozac>>(
          stream: _vozacService.streamAllVozaci(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Greska pri ucitavanju vozaca: ${snapshot.error}',
                  style: const TextStyle(color: Colors.white),
                ),
              );
            }

            final vozaci = snapshot.data ?? [];

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                //  SEKCIJA VOZACA
                Row(
                  children: [
                    const Text(
                      ' VOZACI',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${vozaci.length}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (vozaci.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Nema vozaca.\nKlikni + da dodas.',
                        style: TextStyle(color: Colors.white70, fontSize: 18),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  ...vozaci.asMap().entries.map((entry) {
                    final index = entry.key;
                    final vozac = entry.value;
                    final boja = vozac.color ?? Colors.blue;

                    return Card(
                      color: Colors.white.withOpacity(0.1),
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: boja.withOpacity(0.6), width: 1.5),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            // Avatar
                            CircleAvatar(
                              backgroundColor: boja,
                              radius: 22,
                              child: Text(
                                vozac.ime[0].toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Ime vozaca + ikone u istom redu
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          vozac.ime,
                                          style: TextStyle(
                                            color: boja,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                      // Actions - olovka i kanta
                                      IconButton(
                                        icon: Icon(Icons.edit, color: boja, size: 20),
                                        onPressed: () => _editVozac(index),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                                        onPressed: () => _deleteVozac(index),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Icon(Icons.email, size: 14, color: Colors.white54),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          vozac.email ?? '-',
                                          style: const TextStyle(color: Colors.white, fontSize: 12),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Icon(Icons.phone, size: 14, color: Colors.white54),
                                      const SizedBox(width: 6),
                                      Text(
                                        vozac.brojTelefona ?? '-',
                                        style: const TextStyle(color: Colors.white, fontSize: 13),
                                      ),
                                      if (vozac.sifra?.isNotEmpty == true)
                                        const Padding(
                                          padding: EdgeInsets.only(left: 6),
                                          child: Text('', style: TextStyle(fontSize: 12)),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }
}
