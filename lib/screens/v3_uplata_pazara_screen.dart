import 'package:flutter/material.dart';

import '../models/v3_vozac.dart';
import '../services/v3/v3_finansije_service.dart';
import '../services/v3/v3_uplata_pazara_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_dan_helper.dart';
import '../utils/v3_error_utils.dart';
import '../utils/v3_input_utils.dart';

/// Admin ekran za unos uplata pazara po vozacu i danu.
class V3UplataPazaraScreen extends StatefulWidget {
  const V3UplataPazaraScreen({super.key});

  @override
  State<V3UplataPazaraScreen> createState() => _V3UplataPazaraScreenState();
}

class _V3UplataPazaraScreenState extends State<V3UplataPazaraScreen> {
  V3Vozac? _selectedVozac;
  DateTime _selectedDate = DateTime.now();
  final _iznosController = TextEditingController();

  double _ukupnoNaplaceno = 0;
  double? _predao;
  bool _isLoading = false;
  bool _isSaving = false;

  List<V3Vozac> _vozaci = [];

  @override
  void initState() {
    super.initState();
    _vozaci = V3VozacService.getAllVozaci();
    if (_vozaci.isNotEmpty) {
      _selectedVozac = _vozaci.first;
      _loadData();
    }
  }

  @override
  void dispose() {
    _iznosController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final vozac = _selectedVozac;
    if (vozac == null) return;

    setState(() => _isLoading = true);

    try {
      final pazar = V3FinansijeService.getPazarPoVozacuZaDan(_selectedDate);
      final ukupno = pazar[vozac.id] ?? 0;

      final predao = await V3UplataPazaraService.getPredaoZaDan(
        vozacId: vozac.id,
        datum: _selectedDate,
      );

      if (!mounted) return;
      setState(() {
        _ukupnoNaplaceno = ukupno;
        _predao = predao;
        _iznosController.text = predao != null ? predao.toStringAsFixed(0) : '';
      });
    } catch (e) {
      V3ErrorUtils.safeError(this, context, 'Greška pri učitavanju: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(data: ThemeData.dark(), child: child!),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      await _loadData();
    }
  }

  Future<void> _save() async {
    final vozac = _selectedVozac;
    if (vozac == null) return;

    final predaoVal = double.tryParse(_iznosController.text.replaceAll(',', '.'));
    if (predaoVal == null || predaoVal <= 0) {
      V3AppSnackBar.warning(context, 'Unesite iznos veći od 0 din.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await V3UplataPazaraService.sacuvajDnevnuUplatu(
        vozacId: vozac.id,
        datum: _selectedDate,
        predao: predaoVal,
        ukupno: _ukupnoNaplaceno,
      );
      if (!mounted) return;
      setState(() => _predao = predaoVal);
      V3AppSnackBar.success(context, 'Uplata pazara sačuvana');
    } catch (e) {
      V3ErrorUtils.safeError(this, context, 'Greška pri čuvanju: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _zatraziUnosOdVozaca() async {
    final vozac = _selectedVozac;
    if (vozac == null) {
      debugPrint('[Admin] _zatraziUnosOdVozaca: nije izabran vozač');
      return;
    }

    debugPrint('[Admin] _zatraziUnosOdVozaca: vozacId=${vozac.id}, datum=$_selectedDate, ukupno=$_ukupnoNaplaceno');

    setState(() => _isSaving = true);
    try {
      await V3UplataPazaraService.sacuvajDnevnuUplatu(
        vozacId: vozac.id,
        datum: _selectedDate,
        predao: 0,
        ukupno: _ukupnoNaplaceno,
        zahtevanUnos: true,
      );
      if (!mounted) return;
      V3AppSnackBar.success(context, 'Zahtev prosleđen vozaču!');
      debugPrint('[Admin] _zatraziUnosOdVozaca: uspešno sačuvano');
    } catch (e) {
      debugPrint('[Admin] _zatraziUnosOdVozaca: greška $e');
      V3ErrorUtils.safeError(this, context, 'Greška pri slanju zahteva: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final predaoVal = double.tryParse(_iznosController.text.replaceAll(',', '.'));
    final razlika = predaoVal != null ? predaoVal - _ukupnoNaplaceno : null;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text('Uplata pazara'),
      ),
      body: _isLoading && _vozaci.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Vozac dropdown
                  DropdownButtonFormField<V3Vozac>(
                    value: _selectedVozac,
                    dropdownColor: const Color(0xFF2A2A2A),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Vozač',
                      labelStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: _vozaci.map((v) {
                      return DropdownMenuItem(
                        value: v,
                        child: Text(v.imePrezime, style: const TextStyle(color: Colors.white)),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _selectedVozac = v);
                      _loadData();
                    },
                  ),
                  const SizedBox(height: 16),

                  // Datum
                  InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Datum',
                        labelStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.08),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        V3DanHelper.formatDatumPuni(_selectedDate),
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Iznos predaje
                  V3InputUtils.numberField(
                    controller: _iznosController,
                    label: 'Predao',
                    suffixText: 'din',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),

                  // Razlika
                  if (razlika != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          razlika >= 0 ? 'Višak:' : 'Manjak:',
                          style: TextStyle(
                            color: razlika >= 0 ? Colors.greenAccent : Colors.redAccent,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${razlika.abs().toStringAsFixed(0)} din',
                          style: TextStyle(
                            color: razlika >= 0 ? Colors.greenAccent : Colors.redAccent,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Dugme sacuvaj
                  SizedBox(
                    width: double.infinity,
                    child: V3ButtonUtils.primaryButton(
                      onPressed: _isSaving ? null : _save,
                      text: _isSaving ? 'ÄŒuvanje...' : 'SaÄuvaj',
                      isLoading: _isSaving,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Dugme Zatraži unos
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent.withValues(alpha: 0.2),
                        foregroundColor: Colors.orangeAccent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: _isSaving ? null : _zatraziUnosOdVozaca,
                      icon: const Icon(Icons.send_to_mobile),
                      label: const Text('Zatraži unos od vozača',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
