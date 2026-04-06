import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/v3_vozac.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_role_permission_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../services/v3_biometric_service.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_error_utils.dart';
import '../utils/v3_input_utils.dart';
import '../utils/v3_navigation_utils.dart';
import '../utils/v3_phone_utils.dart';
import '../utils/v3_state_utils.dart';
import '../utils/v3_text_utils.dart';
import 'v3_home_screen.dart';
import 'v3_vozac_screen.dart';

/// V3 Vozač Login Screen
/// Samo Telefon + Šifra sa biometrijom
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
    V3TextUtils.disposeController('vozac_telefon');
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
    }
  }

  Future<bool> _hasBiometricCredentials() async {
    final val = await _secureStorage.read(key: _biometricKey);
    return val != null;
  }

  Future<void> _saveBiometricCredentials() async {
    if (!_biometricAvailable) return;
    final data = jsonEncode({
      'telefon': V3TextUtils.getControllerText('vozac_telefon').trim(),
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
        V3AppSnackBar.error(context, '❌ Biometrijska autentifikacija nije uspela');
      }
      return;
    }

    if (!mounted) return;

    final data = jsonDecode(raw) as Map<String, dynamic>;
    V3TextUtils.setControllerText('vozac_telefon', data['telefon']?.toString() ?? '');

    await _login(saveBiometric: false);
  }

  String _normalizePhone(String raw) => V3PhoneUtils.normalize(raw.trim());

  // ─── Login logika (Supabase) ───────────────────────────────────

  Future<void> _login({bool saveBiometric = true}) async {
    if (!_formKey.currentState!.validate()) return;

    V3StateUtils.safeSetState(this, () => _isLoading = true);

    try {
      final telefon = V3TextUtils.getControllerText('vozac_telefon').trim();

      if (telefon.isEmpty) {
        if (mounted) {
          V3ErrorUtils.validationError(this, context, '❌ Unesite telefon.');
        }
        return;
      }

      final vozacFromCache = V3VozacService.getVozacByName(widget.vozac.imePrezime);
      if (vozacFromCache == null) {
        if (mounted) V3AppSnackBar.error(context, '❌ Prijava nije uspela. Proveri podatke i pokušaj ponovo.');
        return;
      }

      final enteredPhone = _normalizePhone(telefon);
      final tel1 = _normalizePhone(vozacFromCache.telefon1 ?? '');
      final tel2 = _normalizePhone(vozacFromCache.telefon2 ?? '');
      final phoneMatch = enteredPhone.isNotEmpty && (enteredPhone == tel1 || (tel2.isNotEmpty && enteredPhone == tel2));
      if (!phoneMatch) {
        if (mounted) {
          V3ErrorUtils.validationError(this, context, '❌ Prijava nije uspela. Proveri podatke i pokušaj ponovo.');
        }
        return;
      }

      // Učitaj kompletan model vozača zbog ostatka aplikacije
      final vozac = V3VozacService.getVozacByName(widget.vozac.imePrezime);
      if (vozac == null) {
        if (mounted) V3AppSnackBar.error(context, '❌ Prijava nije uspela. Proveri podatke i pokušaj ponovo.');
        return;
      }

      // ✅ KONAČNA DOPUŠTANJA UNUTAR APLIKACIJE
      V3VozacService.currentVozac = vozac;

      // Push Tokeni (FCM)
      await V3RolePermissionService.ensureDriverPermissionsOnLogin();
      await _savePushToken(vozac.id);

      // Keširanje korisnika za buduće
      await _secureStorage.write(key: 'last_v3_vozac_ime', value: vozac.imePrezime);

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
      if (mounted) {
        V3AppSnackBar.error(context, '❌ Prijava trenutno nije dostupna. Pokušaj ponovo kasnije.');
      }
    } finally {
      if (mounted) {
        V3StateUtils.safeSetState(this, () => _isLoading = false);
      }
    }
  }

  // ─── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: V3MasterRealtimeManager.instance.tableRevisionStream('v3_vozaci'),
      builder: (context, _) {
        return V3ContainerUtils.backgroundContainer(
          gradient: Theme.of(context).backgroundGradient,
          child: Scaffold(
            extendBodyBehindAppBar: true,
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: const Text(
                '🔐 Panel Vozača',
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
                    _buildHeader(),
                    const SizedBox(height: 32),
                    V3InputUtils.phoneField(
                      controller: V3TextUtils.vozacTelefonController,
                      label: 'Broj telefona',
                    ),
                    const SizedBox(height: 32),
                    V3ButtonUtils.elevatedButton(
                      onPressed: _isLoading ? null : _login,
                      text: 'Prijavi se',
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      isLoading: _isLoading,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    if (_biometricAvailable && _hasSavedCredentials) ...[
                      const SizedBox(height: 16),
                      V3ButtonUtils.outlinedButton(
                        onPressed: _isLoading ? null : _loginWithBiometric,
                        text: 'Prijava biometrijom',
                        icon: _biometricIcon,
                        borderColor: Colors.amber,
                        foregroundColor: Colors.white,
                        isLoading: _isLoading,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ],
                    const SizedBox(height: 16),
                    V3ContainerUtils.styledContainer(
                      padding: const EdgeInsets.all(12),
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                      child: Row(
                        children: [
                          Icon(Icons.shield_outlined, color: Colors.amber.withValues(alpha: 0.8), size: 24),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Prijavljujete se na novi visoko-bezbednosni server.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 13,
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
      },
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
        V3ContainerUtils.iconContainer(
          width: V3ContainerUtils.responsiveHeight(context, 72),
          height: V3ContainerUtils.responsiveHeight(context, 72),
          backgroundColor: boja.withValues(alpha: 0.25),
          border: Border.all(color: boja.withValues(alpha: 0.6), width: 2.5),
          borderRadiusGeometry: BorderRadius.circular(36),
          alignment: Alignment.center,
          child: Text(
            initials,
            style: TextStyle(color: boja, fontSize: 26, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Dobrodošao, ${widget.vozac.imePrezime}!',
          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'Unesi telefon za prijavu.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 14),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// Čuva FCM push token
  Future<void> _savePushToken(String vozacId) async {
    if (vozacId.isEmpty) return;

    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('[VozacLogin] FCM token greška: $e');
    }

    try {
      final updateData = <String, dynamic>{};
      if (fcmToken != null) {
        updateData['push_token'] = fcmToken;
        await V3VozacService.updatePushToken(
          vozacId: vozacId,
          pushToken: updateData['push_token'] as String?,
        );
      }
    } catch (e) {
      debugPrint('[VozacLogin] Database update greška: $e');
    }
  }
}
