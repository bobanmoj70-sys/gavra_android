import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/v3_vozac.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_closed_auth_service.dart';
import '../services/v3/v3_firebase_sms_service.dart';
import '../services/v3/v3_role_permission_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../services/v3_biometric_service.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_navigation_utils.dart';
import '../utils/v3_phone_utils.dart';
import 'v3_home_screen.dart';
import 'v3_vozac_screen.dart';

/// Koraci SMS verifikacije za vozača
enum _VozacAuthStep { slanjeSms, unosKoda }

/// V3 Vozač SMS Login Screen
///
/// Vozač bira sebe sa liste → ovaj ekran automatski šalje SMS
/// na [vozac.telefon1] → vozač unosi 6-cifreni kod → login.
class V3VozacSmsLoginScreen extends StatefulWidget {
  final V3Vozac vozac;

  const V3VozacSmsLoginScreen({super.key, required this.vozac});

  @override
  State<V3VozacSmsLoginScreen> createState() => _V3VozacSmsLoginScreenState();
}

class _V3VozacSmsLoginScreenState extends State<V3VozacSmsLoginScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  static const _secureStorage = FlutterSecureStorage();

  _VozacAuthStep _step = _VozacAuthStep.slanjeSms;
  bool _isLoading = false;
  String _statusMessage = '';

  String? _verificationId;
  String? _normalizedPhone;

  // Biometrija
  bool _biometricAvailable = false;
  bool _hasSavedCredentials = false;
  IconData _biometricIcon = Icons.fingerprint;

  String get _biometricKey => 'biometric_v3_vozac_sms_${widget.vozac.imePrezime}';

  @override
  void initState() {
    super.initState();
    _phoneController.text = V3PhoneUtils.normalize(widget.vozac.telefon1 ?? '');
    _checkBiometric();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
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

  Future<void> _loginWithBiometric() async {
    final raw = await _secureStorage.read(key: _biometricKey);
    if (raw == null) {
      if (mounted) V3AppSnackBar.info(context, 'ℹ️ Nema sačuvanih podataka. Prijavi se SMS-om.');
      return;
    }

    // Mora postojati aktivna Firebase sesija - bez nje bridge ne može da verifikuje
    if (FirebaseAuth.instance.currentUser == null) {
      if (mounted) V3AppSnackBar.info(context, 'ℹ️ Sesija je istekla. Prijavi se SMS-om.');
      _resetToStep1();
      return;
    }

    final authenticated = await V3BiometricService().authenticate(
      reason: 'Potvrdi identitet za prijavu kao ${widget.vozac.imePrezime}',
    );

    if (!authenticated) {
      if (mounted) V3AppSnackBar.error(context, '❌ Biometrijska autentifikacija nije uspela');
      return;
    }

    if (!mounted) return;
    await _finalizeLogin(skipBiometricSave: true);
  }

  // ─── Korak 1: Pošalji SMS ──────────────────────────────────────

  Future<void> _sendSms() async {
    final inputPhone = _phoneController.text.trim();
    if (inputPhone.isEmpty) {
      V3AppSnackBar.warning(context, 'Unesite broj telefona.');
      return;
    }

    final phone = V3ClosedAuthService.normalizePhone(inputPhone);

    if (phone.isEmpty || !V3PhoneUtils.isValid(phone)) {
      V3AppSnackBar.error(context, '❌ Vozač nema validan broj telefona.');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = '🔍 Proveravam broj u sistemu...';
    });

    try {
      final exists = await V3ClosedAuthService.phoneExists(phone);
      if (!mounted) return;

      if (!exists) {
        V3AppSnackBar.error(context, '❌ Trenutno nije moguće poslati kod. Pokušaj ponovo kasnije.');
        setState(() => _statusMessage = '');
        return;
      }

      final result = await V3FirebaseSmsService.sendSmsCode(
        phoneNumber: phone,
        onStatusUpdate: (msg) {
          if (mounted) setState(() => _statusMessage = msg);
        },
      );

      if (!mounted) return;

      if (!result.success) {
        V3AppSnackBar.error(context, result.errorMessage ?? '❌ Greška pri slanju SMS-a.');
        setState(() => _statusMessage = '');
        return;
      }

      if (result.autoVerified) {
        // Automatska verifikacija uspesna
        setState(() {
          _normalizedPhone = phone;
          _statusMessage = '✅ Auto-verifikacija uspešna! Prijavljivanje...';
        });
        await _finalizeLogin();
        return;
      }

      setState(() {
        _verificationId = result.verificationId;
        _normalizedPhone = phone;
        _step = _VozacAuthStep.unosKoda;
        _statusMessage = '';
      });

      V3AppSnackBar.info(context, '📨 SMS kod je poslat na $phone');
    } catch (e) {
      if (!mounted) return;
      V3AppSnackBar.error(context, 'Greška: $e');
      setState(() => _statusMessage = '');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Korak 2: Verifikuj OTP ────────────────────────────────────

  Future<void> _verifyOtp() async {
    final code = _otpController.text.trim();

    if (code.length != 6) {
      V3AppSnackBar.warning(context, 'Unesite 6-cifreni kod iz SMS-a.');
      return;
    }

    if (_verificationId == null || _normalizedPhone == null) {
      V3AppSnackBar.error(context, '❌ Sesija je istekla. Pokušaj ponovo.');
      _resetToStep1();
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = '🔐 Verifikujem kod...';
    });

    try {
      final otpResult = await V3FirebaseSmsService.verifySmsCode(
        verificationId: _verificationId!,
        smsCode: code,
      );

      if (!mounted) return;

      if (!otpResult.success) {
        V3AppSnackBar.error(context, otpResult.errorMessage ?? '❌ Pogrešan kod.');
        setState(() => _statusMessage = '');
        return;
      }

      setState(() => _statusMessage = '✅ Kod tačan! Prijavljujem...');
      await _finalizeLogin();
    } catch (e) {
      if (!mounted) return;
      V3AppSnackBar.error(context, 'Greška: $e');
      setState(() => _statusMessage = '');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Finalizacija logina ───────────────────────────────────────

  Future<void> _finalizeLogin({bool skipBiometricSave = false}) async {
    try {
      // Verifikuj Firebase token kroz bridge i dobij kanonski telefon
      final gateRow = await V3ClosedAuthService.bridgeFirebaseSessionToV3Auth();
      final canonicalPhone = V3ClosedAuthService.normalizePhone(
        gateRow['telefon']?.toString() ?? '',
      );

      if (!mounted) return;

      // Pronađi vozača po telefonu iz bridge odgovora
      final vozac =
          V3VozacService.getVozacByPhone(canonicalPhone) ?? V3VozacService.getVozacByName(widget.vozac.imePrezime);

      if (vozac == null) {
        V3AppSnackBar.error(context, '❌ Vozač nije pronađen u sistemu.');
        return;
      }

      // Postavi trenutnog vozača
      V3VozacService.currentVozac = vozac;

      // FCM push token
      await V3RolePermissionService.ensureDriverPermissionsOnLogin();
      await _savePushToken(vozac.id);

      // Sačuvaj za biometriju sledeći put
      if (!skipBiometricSave && _biometricAvailable) {
        await _secureStorage.write(key: _biometricKey, value: vozac.imePrezime);
        setState(() => _hasSavedCredentials = true);
      }

      await _secureStorage.write(key: 'last_v3_vozac_ime', value: vozac.imePrezime);

      if (!mounted) return;

      final prefersVozacScreen = vozac.imePrezime.toLowerCase() == 'voja';
      V3NavigationUtils.pushReplacement(
        context,
        prefersVozacScreen ? const V3VozacScreen() : const V3HomeScreen(),
      );
    } catch (e) {
      if (!mounted) return;
      V3AppSnackBar.error(context, '❌ Prijava nije uspela: $e');
      setState(() => _statusMessage = '');
    }
  }

  // ─── Pomoćne metode ────────────────────────────────────────────

  void _resetToStep1() {
    setState(() {
      _step = _VozacAuthStep.slanjeSms;
      _verificationId = null;
      _normalizedPhone = null;
      _otpController.clear();
      _statusMessage = '';
    });
  }

  Future<void> _savePushToken(String vozacId) async {
    if (vozacId.isEmpty) return;
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        await V3VozacService.updatePushToken(vozacId: vozacId, pushToken: fcmToken);
      }
    } catch (e) {
      debugPrint('[VozacSmsLogin] FCM token greška: $e');
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
              leading: _step == _VozacAuthStep.unosKoda
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: _isLoading ? null : _resetToStep1,
                    )
                  : null,
            ),
            body: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                24,
                MediaQuery.of(context).padding.top + kToolbarHeight + 24,
                24,
                24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 32),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _step == _VozacAuthStep.slanjeSms ? _buildPhoneStep() : _buildOtpStep(),
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
                  _buildSecurityNote(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── UI koraci ─────────────────────────────────────────────────

  Widget _buildPhoneStep() {
    return Column(
      key: const ValueKey('phone'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInfoBox(
          icon: Icons.sms_outlined,
          text: 'Unesite broj telefona. Poslaćemo vam SMS kod za potvrdu identiteta.',
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          enabled: !_isLoading,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Broj telefona',
            hintText: '06x xxx xxxx',
            labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.1),
            prefixIcon: const Icon(Icons.phone, color: Colors.amber),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white30),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white30),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.amber, width: 2),
            ),
          ),
          onSubmitted: (_) {
            if (!_isLoading) _sendSms();
          },
        ),
        if (_statusMessage.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildStatusMessage(_statusMessage),
        ],
        const SizedBox(height: 24),
        V3ButtonUtils.primaryButton(
          text: 'Pošalji SMS kod',
          icon: Icons.send,
          isLoading: _isLoading,
          onPressed: _sendSms,
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    return Column(
      key: const ValueKey('otp'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInfoBox(
          icon: Icons.sms_outlined,
          text: 'SMS kod je poslat na $_normalizedPhone\n\nUnesite 6-cifreni kod:',
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          autofocus: true,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
            letterSpacing: 12,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: '------',
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 32,
              letterSpacing: 12,
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.1),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white30),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white30),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.amber, width: 2),
            ),
          ),
          onSubmitted: (_) {
            if (!_isLoading) _verifyOtp();
          },
        ),
        if (_statusMessage.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildStatusMessage(_statusMessage),
        ],
        const SizedBox(height: 24),
        V3ButtonUtils.elevatedButton(
          onPressed: _isLoading ? null : _verifyOtp,
          text: 'Potvrdi kod',
          backgroundColor: Colors.amber,
          foregroundColor: Colors.black,
          isLoading: _isLoading,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ],
    );
  }

  // ─── Zajednički widgeti ────────────────────────────────────────

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
          'Verifikacija putem SMS koda.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 14),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildInfoBox({required IconData icon, required String text}) {
    return V3ContainerUtils.styledContainer(
      padding: const EdgeInsets.all(14),
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.amber, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusMessage(String message) {
    return Text(
      message,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.75),
        fontSize: 13,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  Widget _buildSecurityNote() {
    return V3ContainerUtils.styledContainer(
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
    );
  }
}
