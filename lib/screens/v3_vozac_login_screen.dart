import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../globals.dart';
import '../models/v3_vozac.dart';
import '../services/v3/v3_vozac_service.dart';
import '../services/v3_biometric_service.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_error_utils.dart';
import '../utils/v3_navigation_utils.dart';
import '../utils/v3_phone_utils.dart';
import '../utils/v3_state_utils.dart';
import '../utils/v3_text_utils.dart';
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
    V3TextUtils.disposeController('email');
    V3TextUtils.disposeController('telefon');
    V3TextUtils.disposeController('sifra');
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
      'email': V3TextUtils.getControllerText('email').trim(),
      'telefon': V3TextUtils.getControllerText('telefon').trim(),
      'sifra': V3TextUtils.getControllerText('sifra'),
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
    V3TextUtils.setControllerText('email', data['email']?.toString() ?? '');
    V3TextUtils.setControllerText('telefon', data['telefon']?.toString() ?? '');
    V3TextUtils.setControllerText('sifra', data['sifra']?.toString() ?? '');

    await _login(saveBiometric: false);
  }

  // ─── Login logika ───────────────────────────────────────────────

  Future<void> _login({bool saveBiometric = true}) async {
    if (!_formKey.currentState!.validate()) return;

    V3StateUtils.safeSetState(this, () => _isLoading = true);

    try {
      // Učitaj vozača iz cache-a po imenu
      final vozac = V3VozacService.getVozacByName(widget.vozac.imePrezime);

      if (vozac == null) {
        if (mounted) {
          V3AppSnackBar.error(context, '❌ Vozač "${widget.vozac.imePrezime}" nije pronađen.');
        }
        return;
      }

      final email = V3TextUtils.getControllerText('email').trim().toLowerCase();
      final telefon = _normalizePhone(V3TextUtils.getControllerText('telefon').trim());
      final sifra = V3TextUtils.getControllerText('sifra');

      // Provjera emaila
      if ((vozac.email ?? '').toLowerCase() != email) {
        V3ErrorUtils.validationError(this, context, '❌ Pogrešan email.');
        return;
      }

      // Provjera telefona — prihvata telefon_1 ili telefon_2
      final stored1 = _normalizePhone(vozac.telefon1 ?? '');
      final stored2 = _normalizePhone(vozac.telefon2 ?? '');
      final telefonMatch = (stored1.isNotEmpty && stored1 == telefon) || (stored2.isNotEmpty && stored2 == telefon);
      if (stored1.isNotEmpty && !telefonMatch) {
        V3ErrorUtils.validationError(this, context, '❌ Pogrešan broj telefona.');
        return;
      }

      // Provjera šifre (ako postoji)
      final storedSifra = vozac.sifra ?? '';
      if (storedSifra.isNotEmpty && storedSifra != sifra) {
        V3ErrorUtils.validationError(this, context, '❌ Pogrešna šifra.');
        return;
      }

      // ✅ LOGIN USPJEŠAN
      V3VozacService.currentVozac = vozac;

      // 🎯 HIBRIDNI PUSH TOKEN SISTEM (FCM + HMS)
      await _saveHybridPushTokens(vozac.id);

      // Zapamti zadnjeg prijavljenog vozača za auto-login pri sljedećem startu
      await _secureStorage.write(key: 'last_v3_vozac_ime', value: vozac.imePrezime);

      // Sačuvaj za biometriju
      if (saveBiometric && _biometricAvailable) {
        await _saveBiometricCredentials();
      }

      if (!mounted) return;

      final prefersVozacScreen = vozac.imePrezime.toLowerCase() == 'voja';
      V3NavigationUtils.pushReplacement(
        context,
        prefersVozacScreen ? const V3VozacScreen() : const V3HomeScreen(),
      );
    } catch (e) {
      V3AppSnackBar.error(context, 'Greška: $e');
    } finally {
      V3StateUtils.safeSetState(this, () => _isLoading = false);
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────

  String _normalizePhone(String phone) => V3PhoneUtils.normalize(phone);

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
                  controller: V3TextUtils.emailController,
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
                  controller: V3TextUtils.telefonController,
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
                  controller: V3TextUtils.sifraController,
                  style: const TextStyle(color: Colors.white),
                  obscureText: !_sifraVisible,
                  decoration: _inputDecoration('Šifra', Icons.lock).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _sifraVisible ? Icons.visibility_off : Icons.visibility,
                        color: Colors.amber,
                      ),
                      onPressed: () => V3StateUtils.safeSetState(this, () => _sifraVisible = !_sifraVisible),
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

  /// 🎯 Hibridni push token sistem - čuva FCM i HMS tokene
  Future<void> _saveHybridPushTokens(String vozacId) async {
    if (vozacId.isEmpty) return;

    String? fcmToken;
    String? hmsToken;
    String pushType = 'none';

    // 1. Pokušaj FCM token (Google/Samsung/Xiaomi)
    try {
      fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        pushType = 'fcm';
        debugPrint('[VozacLogin] FCM token: ${fcmToken.substring(0, 20)}...');
      }
    } catch (e) {
      debugPrint('[VozacLogin] FCM token greška: $e');
    }

    // 2. Pokušaj HMS token (Huawei)
    try {
      // Huawei Push Kit - za sada placeholder zbog API promene
      // hmsToken = await HuaweiPush.getToken("");
      debugPrint('[VozacLogin] HMS token - potrebna API ažuriranje');
    } catch (e) {
      debugPrint('[VozacLogin] HMS token greška: $e');
    }

    // 3. Sačuvaj u bazu (update samo non-null vrednosti)
    try {
      final updateData = <String, dynamic>{};

      if (fcmToken != null) {
        updateData['push_token'] = fcmToken;
        updateData['push_type'] = 'fcm';
      }

      // HMS token placeholder - trenutno nije implementiran
      // if (hmsToken != null) {
      //   updateData['hms_token'] = hmsToken;
      //   updateData['push_type'] = 'hms';
      // }

      // Hybrid mode - kada imamo oba tokena
      // if (fcmToken != null && hmsToken != null) {
      //   updateData['push_type'] = 'hybrid';
      // }

      if (updateData.isNotEmpty) {
        await supabase.from('v3_vozaci').update(updateData).eq('id', vozacId);
        debugPrint('[VozacLogin] Push tokeni sačuvani: ${updateData.keys.join(', ')}');
      } else {
        debugPrint('[VozacLogin] ⚠️ Nijedan push token nije dostupan!');
      }
    } catch (e) {
      debugPrint('[VozacLogin] Database update greška: $e');
    }
  }
}
