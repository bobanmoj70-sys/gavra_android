import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/v3/v3_closed_auth_service.dart';
import '../services/v3/v3_firebase_sms_service.dart';
import '../services/v3/v3_putnik_service.dart';
import '../services/v3/v3_role_permission_service.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_input_utils.dart';
import '../utils/v3_navigation_utils.dart';
import '../utils/v3_phone_utils.dart';
import 'v3_putnik_profil_screen.dart';

/// Koraci SMS verifikacije
enum _AuthStep { unosTelefona, unosKoda }

class V3PutnikAuthScreen extends StatefulWidget {
  const V3PutnikAuthScreen({super.key});

  @override
  State<V3PutnikAuthScreen> createState() => _V3PutnikAuthScreenState();
}

class _V3PutnikAuthScreenState extends State<V3PutnikAuthScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  _AuthStep _step = _AuthStep.unosTelefona;
  bool _isLoading = false;
  String _statusMessage = '';

  /// verificationId koji stigne od Firebase nakon slanja SMS-a
  String? _verificationId;

  /// Normalizovani telefon koji je prošao proveru baze
  String? _normalizedPhone;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  // ─── Korak 1: Proveri telefon u bazi + pošalji SMS ─────────────

  Future<void> _sendSms() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      V3AppSnackBar.warning(context, 'Unesite broj telefona.');
      return;
    }

    final normalized = V3ClosedAuthService.normalizePhone(phone);

    if (!V3PhoneUtils.isValid(normalized)) {
      V3AppSnackBar.error(context, '❌ Neispravan format broja telefona.');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = '🔍 Proveravam broj u sistemu...';
    });

    try {
      // 1. Proveri da li telefon postoji u našoj bazi
      final exists = await V3ClosedAuthService.phoneExists(normalized);
      if (!mounted) return;

      if (!exists) {
        V3AppSnackBar.error(context, '❌ Trenutno nije moguće poslati kod. Pokušaj ponovo kasnije.');
        setState(() => _statusMessage = '');
        return;
      }

      // 2. Pošalji Firebase SMS
      final result = await V3FirebaseSmsService.sendSmsCode(
        phoneNumber: normalized,
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

      // 3. Pređi na korak unosa koda
      setState(() {
        _verificationId = result.verificationId;
        _normalizedPhone = normalized;
        _step = _AuthStep.unosKoda;
        _statusMessage = '';
      });

      V3AppSnackBar.info(context, '📨 SMS kod je poslat na $normalized');
    } catch (e) {
      if (!mounted) return;
      V3AppSnackBar.error(context, 'Greška: $e');
      setState(() => _statusMessage = '');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Korak 2: Verifikuj OTP kod ────────────────────────────────

  Future<void> _verifyOtp() async {
    final code = _otpController.text.trim();

    if (code.length != 6) {
      V3AppSnackBar.warning(context, 'Unesite 6-cifreni kod iz SMS-a.');
      return;
    }

    if (_verificationId == null || _normalizedPhone == null) {
      V3AppSnackBar.error(context, '❌ Sesija je istekla. Počni ponovo.');
      _resetToStep1();
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = '🔐 Verifikujem kod...';
    });

    try {
      // 1. Verifikuj OTP kod u Firebase
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

      setState(() => _statusMessage = '✅ Kod tačan! Učitavam profil...');

      final gateRow = await V3ClosedAuthService.bridgeFirebaseSessionToV3Auth(
        fallbackPhone: _normalizedPhone!,
      );
      final canonicalPhone = V3ClosedAuthService.normalizePhone(
        gateRow['telefon']?.toString() ?? _normalizedPhone!,
      );
      if (canonicalPhone.isEmpty) {
        V3AppSnackBar.error(context, '❌ Kapija autorizacije nije vratila validan telefon.');
        setState(() => _statusMessage = '');
        return;
      }

      // 2. Učitaj putnika iz naše baze
      final putnik = await V3PutnikService.getByPhoneOrCache(canonicalPhone);

      if (!mounted) return;

      if (putnik == null) {
        V3AppSnackBar.error(context, '❌ Profil nije pronađen za ovaj broj.');
        setState(() => _statusMessage = '');
        return;
      }

      // 3. Postavi trenutnog putnika i dozvole
      V3PutnikService.currentPutnik = putnik;
      await V3ClosedAuthService.saveFirebasePutnikPhone(canonicalPhone);
      await V3RolePermissionService.ensurePassengerPermissionsOnLogin();

      if (!mounted) return;

      V3NavigationUtils.pushReplacement(
        context,
        V3PutnikProfilScreen(putnikData: putnik),
      );
    } catch (e) {
      if (!mounted) return;
      V3AppSnackBar.error(context, 'Greška: $e');
      setState(() => _statusMessage = '');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Pomoćne metode ─────────────────────────────────────────────

  void _resetToStep1() {
    setState(() {
      _step = _AuthStep.unosTelefona;
      _verificationId = null;
      _normalizedPhone = null;
      _otpController.clear();
      _statusMessage = '';
    });
  }

  // ─── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return V3ContainerUtils.backgroundContainer(
      gradient: Theme.of(context).backgroundGradient,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            '🔐 Putnik prijava',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          // Dugme nazad u koraku 2 → vraća na korak 1
          leading: _step == _AuthStep.unosKoda
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
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _step == _AuthStep.unosTelefona ? _buildPhoneStep() : _buildOtpStep(),
          ),
        ),
      ),
    );
  }

  // ─── Korak 1 UI ─────────────────────────────────────────────────

  Widget _buildPhoneStep() {
    return Column(
      key: const ValueKey('phone'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        _buildInfoBox(
          icon: Icons.sms_outlined,
          text: 'Unesite broj telefona. Poslaćemo vam SMS kod za potvrdu identiteta.',
        ),
        const SizedBox(height: 24),
        V3InputUtils.formField(
          controller: _phoneController,
          label: 'Broj telefona',
          icon: Icons.phone,
          hint: '06x xxx xxxx',
          keyboardType: TextInputType.phone,
          validator: (_) => null,
          onSubmitted: (_) {
            if (!_isLoading) _sendSms();
          },
        ),
        if (_statusMessage.isNotEmpty) ...[
          const SizedBox(height: 12),
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

  // ─── Korak 2 UI ─────────────────────────────────────────────────

  Widget _buildOtpStep() {
    return Column(
      key: const ValueKey('otp'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        _buildInfoBox(
          icon: Icons.sms_outlined,
          text: 'SMS kod je poslat na $_normalizedPhone\n\nUnesite 6-cifreni kod:',
        ),
        const SizedBox(height: 24),
        // OTP input
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
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
        V3ButtonUtils.primaryButton(
          text: 'Potvrdi kod',
          icon: Icons.verified_user_outlined,
          isLoading: _isLoading,
          onPressed: _verifyOtp,
        ),
        const SizedBox(height: 12),
        // Pošalji ponovo
        TextButton.icon(
          onPressed: _isLoading ? null : _resetToStep1,
          icon: const Icon(Icons.refresh, color: Colors.white60, size: 18),
          label: const Text(
            'Nisam dobio SMS – pošalji ponovo',
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ),
      ],
    );
  }

  // ─── Zajednički widgeti ──────────────────────────────────────────

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
}
