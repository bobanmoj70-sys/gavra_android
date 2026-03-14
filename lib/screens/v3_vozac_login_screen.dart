import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/v3_vozac.dart';
import '../services/v3/v3_vozac_service.dart';
import '../services/v3_biometric_service.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import 'v3_home_screen.dart';
import 'v3_vozac_screen.dart';

/// V3 Vozač Login Screen
/// Email + telefon + šifra validacija iz V3 cache-a
/// Biometrijska prijava per-vozač (flutter_secure_storage)
class V3VozacLoginScreen extends StatefulWidget {
  final V3Vozac vozac;

  const V3VozacLoginScreen({super.key, required this.vozac});

  @override
  State<V3VozacLoginScreen> createState() => _V3VozacLoginScreenState();
}

class _V3VozacLoginScreenState extends State<V3VozacLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _telefonController = TextEditingController();
  final _sifraController = TextEditingController();
  static const _secureStorage = FlutterSecureStorage();

  bool _isLoading = false;
  bool _sifraVisible = false;

  // Biometrija
  bool _biometricAvailable = false;
  bool _hasSavedCredentials = false;
  IconData _biometricIcon = Icons.fingerprint;

  // Per-vozač secure storage ključ
  String get _biometricKey => 'biometric_v3_vozac_${widget.vozac.imePrezime}';

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _telefonController.dispose();
    _sifraController.dispose();
    super.dispose();
  }

  // ─── Biometrija ────────────────────────────────────────────────

  Future<void> _checkBiometric() async {
    final bio = V3BiometricService();
    final available = await bio.isBiometricAvailable();
    final hasCreds = await _hasBiometricCredentials();
    final info = await bio.getBiometricInfo();

    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _hasSavedCredentials = hasCreds;
        _biometricIcon = info.icon;
      });

      if (available && hasCreds) {
        await _loginWithBiometric();
      }
    }
  }

  Future<bool> _hasBiometricCredentials() async {
    final val = await _secureStorage.read(key: _biometricKey);
    return val != null;
  }

  Future<void> _saveBiometricCredentials() async {
    if (!_biometricAvailable) return;
    final data = jsonEncode({
      'email': _emailController.text.trim(),
      'telefon': _telefonController.text.trim(),
      'sifra': _sifraController.text,
    });
    await _secureStorage.write(key: _biometricKey, value: data);
  }

  Future<void> _loginWithBiometric() async {
    final raw = await _secureStorage.read(key: _biometricKey);
    if (raw == null) {
      if (mounted) {
        V3AppSnackBar.info(context, 'ℹ️ Nema sačuvanih kredencijala. Prijavi se ručno.');
      }
      return;
    }

    final authenticated = await V3BiometricService().authenticate(
      reason: 'Potvrdi identitet za prijavu kao ${widget.vozac.imePrezime}',
    );

    if (!authenticated) {
      if (mounted) {
        V3AppSnackBar.error(context, '❌ Biometrijska autentifikacija nije uspjela');
      }
      return;
    }

    if (!mounted) return;

    final data = jsonDecode(raw) as Map<String, dynamic>;
    _emailController.text = data['email']?.toString() ?? '';
    _telefonController.text = data['telefon']?.toString() ?? '';
    _sifraController.text = data['sifra']?.toString() ?? '';

    await _login(saveBiometric: false);
  }

  // ─── Login logika ───────────────────────────────────────────────

  Future<void> _login({bool saveBiometric = true}) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Učitaj vozača iz cache-a po imenu
      final vozac = V3VozacService.getVozacByName(widget.vozac.imePrezime);

      if (vozac == null) {
        if (mounted) {
          V3AppSnackBar.error(context, '❌ Vozač "${widget.vozac.imePrezime}" nije pronađen.');
        }
        return;
      }

      final email = _emailController.text.trim().toLowerCase();
      final telefon = _normalizePhone(_telefonController.text.trim());
      final sifra = _sifraController.text;

      // Provjera emaila
      if ((vozac.email ?? '').toLowerCase() != email) {
        if (mounted) V3AppSnackBar.error(context, '❌ Pogrešan email.');
        return;
      }

      // Provjera telefona
      final storedTelefon = _normalizePhone(vozac.telefon ?? '');
      if (storedTelefon.isNotEmpty && storedTelefon != telefon) {
        if (mounted) V3AppSnackBar.error(context, '❌ Pogrešan broj telefona.');
        return;
      }

      // Provjera šifre (ako postoji)
      final storedSifra = vozac.sifra ?? '';
      if (storedSifra.isNotEmpty && storedSifra != sifra) {
        if (mounted) V3AppSnackBar.error(context, '❌ Pogrešna šifra.');
        return;
      }

      // ✅ LOGIN USPJEŠAN
      V3VozacService.currentVozac = vozac;

      // Zapamti zadnjeg prijavljenog vozača za auto-login pri sljedećem startu
      await _secureStorage.write(key: 'last_v3_vozac_ime', value: vozac.imePrezime);

      // Sačuvaj za biometriju
      if (saveBiometric && _biometricAvailable) {
        await _saveBiometricCredentials();
      }

      if (!mounted) return;

      final prefersVozacScreen = vozac.imePrezime.toLowerCase() == 'voja';
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => prefersVozacScreen ? const V3VozacScreen() : const V3HomeScreen(),
        ),
      );
    } catch (e) {
      if (mounted) V3AppSnackBar.error(context, '❌ Greška: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────

  String _normalizePhone(String phone) {
    return phone.replaceAll(RegExp(r'[\s\-\(\)]'), '').replaceAll(RegExp(r'^0+'), '');
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
      prefixIcon: Icon(icon, color: Colors.amber),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.1),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.amber),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            '🔐 Prijava',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            MediaQuery.of(context).padding.top + kToolbarHeight + 24,
            24,
            24,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Avatar / header ──────────────────────────────
                _buildHeader(),
                const SizedBox(height: 32),

                // ── Email ────────────────────────────────────────
                TextFormField(
                  controller: _emailController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.emailAddress,
                  decoration: _inputDecoration('Email adresa', Icons.email),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Unesite email';
                    if (!v.contains('@') || !v.contains('.')) return 'Neispravan email';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // ── Telefon ──────────────────────────────────────
                TextFormField(
                  controller: _telefonController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.phone,
                  decoration: _inputDecoration('Broj telefona', Icons.phone),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Unesite telefon';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // ── Šifra ────────────────────────────────────────
                TextFormField(
                  controller: _sifraController,
                  style: const TextStyle(color: Colors.white),
                  obscureText: !_sifraVisible,
                  decoration: _inputDecoration('Šifra', Icons.lock).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _sifraVisible ? Icons.visibility_off : Icons.visibility,
                        color: Colors.amber,
                      ),
                      onPressed: () => setState(() => _sifraVisible = !_sifraVisible),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // ── Prijavi se dugme ─────────────────────────────
                ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                        )
                      : const Text(
                          'Prijavi se',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                ),

                // ── Biometrija ───────────────────────────────────
                if (_biometricAvailable && _hasSavedCredentials) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _loginWithBiometric,
                    icon: Icon(_biometricIcon, color: Colors.amber),
                    label: const Text(
                      'Prijava biometrijom',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.amber),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // ── Info box ─────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.white.withValues(alpha: 0.5), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Unesi podatke koje je admin postavio za tebe.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final boja = widget.vozac.boja != null
        ? Color(int.tryParse(widget.vozac.boja!.replaceFirst('#', '0xFF')) ?? 0xFF2196F3)
        : Colors.amber;
    final initials = widget.vozac.imePrezime
        .trim()
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();

    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: boja.withValues(alpha: 0.25),
            border: Border.all(color: boja.withValues(alpha: 0.6), width: 2.5),
          ),
          child: Center(
            child: Text(
              initials,
              style: TextStyle(
                color: boja,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Dobrodošao, ${widget.vozac.imePrezime}!',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'Potvrdi svoje podatke za prijavu',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
