import 'package:flutter/material.dart';

import '../config/route_config.dart';
import '../constants/day_constants.dart';
import '../services/vozac_raspored_service.dart';
import '../services/vozac_service.dart';
import '../utils/app_snack_bar.dart';

/// 🗓️ Ekran za upravljanje rasporedom vozača
/// Admin dodaje/briše koji vozač vozi koji termin
class VozacRasporedScreen extends StatefulWidget {
  const VozacRasporedScreen({super.key});

  @override
  State<VozacRasporedScreen> createState() => _VozacRasporedScreenState();
}

class _VozacRasporedScreenState extends State<VozacRasporedScreen> {
  final _service = VozacRasporedService();

  List<VozacRasporedEntry> _raspored = [];
  List<String> _vozaci = [];
  bool _isLoading = true;

  // Za dodavanje novog
  String _selDan = 'pon';
  String _selGrad = 'BC';
  String _selVreme = '07:00';
  String? _selVozac;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final data = await _service.loadAll();
    final vozaciList = await VozacService().getAllVozaci();
    if (mounted) {
      setState(() {
        _raspored = data.where((r) => r.putnikId == null).toList(); // samo termin-level
        _vozaci = vozaciList.map((v) => v.ime).toList();
        _selVozac ??= _vozaci.isNotEmpty ? _vozaci.first : null;
        _isLoading = false;
      });
    }
  }

  List<String> get _vremeOptions {
    final bc = RouteConfig.bcVremenaZimski;
    final vs = RouteConfig.vsVremenaZimski;
    final all = {...bc, ...vs}.toList()..sort();
    return all;
  }

  Future<void> _dodaj() async {
    if (_selVozac == null) return;
    final entry = VozacRasporedEntry(
      dan: _selDan,
      grad: _selGrad,
      vreme: _selVreme,
      vozac: _selVozac!,
    );
    await _service.upsert(entry);
    AppSnackBar.success(context, '✅ Dodato: $_selVozac — $_selDan $_selGrad $_selVreme');
    _load();
  }

  Future<void> _obrisi(VozacRasporedEntry entry) async {
    await _service.deleteTermin(
      dan: entry.dan,
      grad: entry.grad,
      vreme: entry.vreme,
      vozac: entry.vozac,
    );
    AppSnackBar.success(context, '🗑️ Obrisano');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Raspored vozača'),
        backgroundColor: Colors.blueGrey[900],
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.blueGrey[900],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // FORMA ZA DODAVANJE
                Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withOpacity(0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Dodaj raspored',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          // DAN
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selDan,
                              dropdownColor: Colors.blueGrey[800],
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDecor('Dan'),
                              items: DayConstants.dayNamesInternal
                                  .map((d) => DropdownMenuItem(
                                        value: d,
                                        child: Text(d,
                                            style: const TextStyle(
                                                color: Colors.white)),
                                      ))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _selDan = v!),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // GRAD
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selGrad,
                              dropdownColor: Colors.blueGrey[800],
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDecor('Grad'),
                              items: ['BC', 'VS']
                                  .map((g) => DropdownMenuItem(
                                        value: g,
                                        child: Text(g,
                                            style: const TextStyle(
                                                color: Colors.white)),
                                      ))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _selGrad = v!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          // VREME
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _vremeOptions.contains(_selVreme)
                                  ? _selVreme
                                  : _vremeOptions.first,
                              dropdownColor: Colors.blueGrey[800],
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDecor('Vreme'),
                              items: _vremeOptions
                                  .map((v) => DropdownMenuItem(
                                        value: v,
                                        child: Text(v,
                                            style: const TextStyle(
                                                color: Colors.white)),
                                      ))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _selVreme = v!),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // VOZAC
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selVozac,
                              dropdownColor: Colors.blueGrey[800],
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDecor('Vozač'),
                              items: _vozaci
                                  .map((v) => DropdownMenuItem(
                                        value: v,
                                        child: Text(v,
                                            style: const TextStyle(
                                                color: Colors.white)),
                                      ))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _selVozac = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _dodaj,
                          icon: const Icon(Icons.add),
                          label: const Text('Dodaj'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // LISTA RASPOREDA
                Expanded(
                  child: _raspored.isEmpty
                      ? const Center(
                          child: Text(
                            'Nema rasporeda.\nSvi vozači vide sve putnike.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white54, fontSize: 15),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _raspored.length,
                          itemBuilder: (context, i) {
                            final r = _raspored[i];
                            return Card(
                              color: Colors.white.withOpacity(0.08),
                              margin: const EdgeInsets.only(bottom: 6),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.blue.withOpacity(0.3),
                                  child: Text(
                                    r.vozac.substring(0, 1).toUpperCase(),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                                title: Text(
                                  '${r.vozac}  •  ${r.grad} ${r.vreme}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  r.dan,
                                  style: const TextStyle(color: Colors.white54),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  onPressed: () => _obrisi(r),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  InputDecoration _inputDecor(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(8),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.blue),
        borderRadius: BorderRadius.circular(8),
      ),
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }
}
