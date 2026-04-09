import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/v3_putnik.dart';
import '../services/v3/v3_closed_auth_service.dart';
import '../services/v3/v3_firebase_sms_service.dart';
import '../services/v3/v3_putnik_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../services/v3_biometric_service.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_phone_utils.dart';

enum _SmsStep { unosTelefona, unosKoda, unosProfila }

/// Unified SMS login screen za putnike i vozače.
///
/// [title]         – naslov appbar-a
/// [initialPhone]  – pre-popunjen telefon (vozač)
/// [header]        – widget iznad forme (vozač header sa imenom)
/// [biometricKey]  – ključ za SecureStorage biometrije (null = bez biometrije)
/// [onVerified]    – callback nakon uspešne verifikacije, prima normalizovan telefon
class V3SmsLoginScreen extends StatefulWidget {
  final String title;
  final String? initialPhone;
  final Widget? header;
  final String? biometricKey;
  final Future<void> Function(String canonicalPhone) onVerified;

  const V3SmsLoginScreen({
    super.key,
    required this.title,
    required this.onVerified,
    this.initialPhone,
    this.header,
    this.biometricKey,
  });

  @override
  State<V3SmsLoginScreen> createState() => _V3SmsLoginScreenState();
}

class _V3SmsLoginScreenState extends State<V3SmsLoginScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _imeController = TextEditingController();
  final _prezimeController = TextEditingController();
  static const _secureStorage = FlutterSecureStorage();
  static const int _smsCooldownSeconds = 30;

  _SmsStep _step = _SmsStep.unosTelefona;
  bool _isLoading = false;
  String _statusMessage = '';
  String? _verificationId;
  String? _normalizedPhone;
  String _selectedTip = 'radnik';
  DateTime? _nextSmsAllowedAt;
  Timer? _cooldownTimer;

  // Biometrija
  bool _biometricAvailable = false;
  bool _hasSavedCredentials = false;
  IconData _biometricIcon = Icons.fingerprint;

  bool get _biometricEnabled => widget.biometricKey != null;

  @override
  void initState() {
    super.initState();
    if (widget.initialPhone != null) {
      _phoneController.text = V3PhoneUtils.normalize(widget.initialPhone!);
    }
    if (_biometricEnabled) _checkBiometric();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _phoneController.dispose();
    _otpController.dispose();
    _imeController.dispose();
    _prezimeController.dispose();
    super.dispose();
  }

  int get _cooldownRemainingSeconds {
    final until = _nextSmsAllowedAt;
    if (until == null) return 0;
    final now = DateTime.now();
    if (!until.isAfter(now)) return 0;
    return until.difference(now).inSeconds + 1;
  }

  bool get _isSmsCooldownActive => _cooldownRemainingSeconds > 0;

  void _startSmsCooldown() {
    _nextSmsAllowedAt = DateTime.now().add(const Duration(seconds: _smsCooldownSeconds));
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!_isSmsCooldownActive) {
        _cooldownTimer?.cancel();
      }
      setState(() {});
    });
    setState(() {});
  }

  // ─── Biometrija ────────────────────────────────────────────────

  Future<void> _checkBiometric() async {
    final bio = V3BiometricService();
    final available = await bio.isBiometricAvailable();
    final hasCreds = widget.biometricKey != null ? await _secureStorage.read(key: widget.biometricKey!) != null : false;
    final info = await bio.getBiometricInfo();
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _hasSavedCredentials = hasCreds;
        _biometricIcon = info.icon;
      });
    }
  }

  Future<void> _loginWithBiometric() async {
    if (widget.biometricKey == null) return;

    final raw = await _secureStorage.read(key: widget.biometricKey!);
    if (raw == null) {
      if (mounted) V3AppSnackBar.info(context, 'ℹ️ Nema sačuvanih podataka. Prijavi se SMS-om.');
      return;
    }

    if (FirebaseAuth.instance.currentUser == null) {
      await _secureStorage.delete(key: widget.biometricKey!);
      if (mounted) {
        setState(() => _hasSavedCredentials = false);
        V3AppSnackBar.info(context, 'ℹ️ Sesija je istekla. Prijavi se SMS-om.');
        _resetToStep1();
      }
      return;
    }

    final authenticated = await V3BiometricService().authenticate(
      reason: 'Potvrdi identitet za prijavu',
    );

    if (!authenticated) {
      if (mounted) V3AppSnackBar.error(context, '❌ Biometrijska autentifikacija nije uspela');
      return;
    }

    final normalized = V3ClosedAuthService.normalizePhone(raw);
    if (normalized.isEmpty) {
      if (mounted) V3AppSnackBar.error(context, '❌ Sačuvan telefon nije ispravan. Prijavi se SMS-om.');
      return;
    }

    if (mounted) {
      setState(() => _normalizedPhone = normalized);
    }

    if (!mounted) return;
    await _finalize(skipBiometricSave: true);
  }

  // ─── Korak 1: Proveri telefon + pošalji SMS ────────────────────

  Future<void> _sendSms() async {
    if (_isSmsCooldownActive) {
      final sec = _cooldownRemainingSeconds;
      V3AppSnackBar.info(context, 'Sačekajte $sec s pre novog zahteva.');
      return;
    }

    final input = _phoneController.text.trim();
    if (input.isEmpty) {
      V3AppSnackBar.warning(context, 'Unesite broj telefona.');
      return;
    }

    final phone = V3ClosedAuthService.normalizePhone(input);
    if (!V3PhoneUtils.isValid(phone)) {
      V3AppSnackBar.error(context, '❌ Neispravan format broja telefona.');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = '🔍 Proveravam broj...';
    });

    try {
      final exists = await V3ClosedAuthService.phoneExists(phone);
      if (!mounted) return;
      if (!exists) {
        V3AppSnackBar.error(context, '❌ Broj nije registrovan u sistemu.');
        setState(() => _statusMessage = '');
        return;
      }

      setState(() => _statusMessage = '📨 Pripremam verifikaciju...');

      final result = await V3FirebaseSmsService.sendSmsCode(
        phoneNumber: phone,
        onStatusUpdate: (msg) {
          if (mounted) setState(() => _statusMessage = msg);
        },
      );

      if (!mounted) return;

      _startSmsCooldown();

      if (!result.success) {
        V3AppSnackBar.error(context, result.errorMessage ?? '❌ Greška pri slanju SMS-a.');
        setState(() => _statusMessage = '');
        return;
      }

      if (result.autoVerified) {
        setState(() {
          _normalizedPhone = phone;
          _statusMessage = '✅ Auto-verifikacija uspešna!';
        });
        await _advanceAfterVerifiedOtp();
        return;
      }

      setState(() {
        _verificationId = result.verificationId;
        _normalizedPhone = phone;
        _step = _SmsStep.unosKoda;
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
      V3AppSnackBar.error(context, '❌ Sesija je istekla. Počni ponovo.');
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

      setState(() => _statusMessage = '✅ Kod tačan!');
      await _advanceAfterVerifiedOtp();
    } catch (e) {
      if (!mounted) return;
      V3AppSnackBar.error(context, 'Greška: $e');
      setState(() => _statusMessage = '');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _advanceAfterVerifiedOtp() async {
    final phone = V3ClosedAuthService.normalizePhone(_normalizedPhone ?? '');
    if (phone.isEmpty) {
      if (mounted) {
        V3AppSnackBar.error(context, '❌ Sesija je istekla. Počni ponovo.');
        _resetToStep1();
      }
      return;
    }

    final vozac = await V3VozacService.getVozacByPhoneDirect(phone);
    if (vozac != null) {
      await _syncFirebaseUidForAuthorizedPhone(phone);
      if (!mounted) return;
      await _finalize();
      return;
    }

    final putnik = await V3PutnikService.getByPhoneDirect(phone);
    if (putnik == null) {
      if (!mounted) return;
      V3AppSnackBar.error(context, '❌ Broj nije autorizovan za pristup.');
      _resetToStep1();
      return;
    }

    await _syncFirebaseUidForAuthorizedPhone(phone);

    final hasName = (putnik['ime_prezime']?.toString().trim().isNotEmpty ?? false);
    final hasTip = (putnik['tip_putnika']?.toString().trim().isNotEmpty ?? false);

    if (hasName && hasTip) {
      if (!mounted) return;
      await _finalize();
      return;
    }

    final existingName = putnik['ime_prezime']?.toString().trim() ?? '';
    if (existingName.isNotEmpty) {
      final parts = existingName.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      if (parts.isNotEmpty) {
        _imeController.text = parts.first;
        _prezimeController.text = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      }
    }

    final existingTip = putnik['tip_putnika']?.toString().trim() ?? '';
    if (existingTip == 'radnik' || existingTip == 'ucenik' || existingTip == 'dnevni') {
      _selectedTip = existingTip;
    }

    if (!mounted) return;
    setState(() {
      _step = _SmsStep.unosProfila;
      _statusMessage = '';
    });
  }

  Future<void> _saveOnboarding() async {
    final ime = _imeController.text.trim();
    final prezime = _prezimeController.text.trim();
    final fullName = '$ime $prezime'.trim();
    final phone = V3ClosedAuthService.normalizePhone(_normalizedPhone ?? '');

    if (ime.isEmpty || prezime.isEmpty) {
      V3AppSnackBar.warning(context, 'Unesite ime i prezime.');
      return;
    }

    if (phone.isEmpty) {
      V3AppSnackBar.error(context, '❌ Sesija je istekla. Počni ponovo.');
      _resetToStep1();
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = '💾 Čuvam profil...';
    });

    try {
      final existing = await V3PutnikService.getByPhoneDirect(phone);
      if (existing == null) {
        if (!mounted) return;
        V3AppSnackBar.error(context, '❌ Broj nije autorizovan za unos profila.');
        _resetToStep1();
        return;
      }

      final putnik = V3Putnik(
        id: (existing['id'] as String?) ?? '',
        imePrezime: fullName,
        telefon1: phone,
        tipPutnika: _selectedTip,
      );

      await V3PutnikService.addUpdatePutnik(putnik);
      if (!mounted) return;

      V3AppSnackBar.success(context, '✅ Profil sačuvan.');
      await _finalize();
    } catch (e) {
      if (!mounted) return;
      V3AppSnackBar.error(context, '❌ Čuvanje profila nije uspelo: $e');
      setState(() => _statusMessage = '');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _syncFirebaseUidForAuthorizedPhone(String phone) async {
    final normalizedPhone = V3ClosedAuthService.normalizePhone(phone);
    if (normalizedPhone.isEmpty) return;

    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return;

    try {
      final result = await Supabase.instance.client.rpc(
        'v3_auth_bind_firebase_uid',
        params: {
          'p_telefon': normalizedPhone,
          'p_firebase_uid': uid,
        },
      );
      if (result != true) {
        debugPrint('[V3SmsLoginScreen] firebase_uid sync skipped for phone=$normalizedPhone');
      }
    } catch (e) {
      debugPrint('[V3SmsLoginScreen] firebase_uid sync error: $e');
    }
  }

  // ─── Finalizacija ──────────────────────────────────────────────

  Future<void> _finalize({bool skipBiometricSave = false}) async {
    try {
      final phone = V3ClosedAuthService.normalizePhone(_normalizedPhone ?? '');
      if (phone.isEmpty) {
        V3AppSnackBar.error(context, '❌ Sesija je istekla. Počni ponovo.');
        _resetToStep1();
        return;
      }

      if (!mounted) return;

      // Sačuvaj biometriju za sledeći put
      if (_biometricEnabled && !skipBiometricSave && _biometricAvailable) {
        await _secureStorage.write(key: widget.biometricKey!, value: phone);
        if (mounted) setState(() => _hasSavedCredentials = true);
      }

      await widget.onVerified(phone);
    } catch (e) {
      if (!mounted) return;
      V3AppSnackBar.error(context, '❌ Prijava nije uspela: $e');
      setState(() => _statusMessage = '');
    }
  }

  void _resetToStep1() {
    setState(() {
      _step = _SmsStep.unosTelefona;
      _verificationId = null;
      _normalizedPhone = null;
      _imeController.clear();
      _prezimeController.clear();
      _selectedTip = 'radnik';
      _otpController.clear();
      _statusMessage = '';
    });
  }

  // ─── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return V3ContainerUtils.backgroundContainer(
      gradient: Theme.of(context).backgroundGradient,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            widget.title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.header != null) ...[
                widget.header!,
                const SizedBox(height: 32),
              ],
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: switch (_step) {
                  _SmsStep.unosTelefona => _buildPhoneStep(),
                  _SmsStep.unosKoda => _buildOtpStep(),
                  _SmsStep.unosProfila => _buildProfileStep(),
                },
              ),
              if (_biometricEnabled && _biometricAvailable && _hasSavedCredentials) ...[
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
            ],
          ),
        ),
      ),
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
          const SizedBox(height: 12),
          _buildStatusMessage(_statusMessage),
        ],
        const SizedBox(height: 24),
        V3ButtonUtils.primaryButton(
          text: _isSmsCooldownActive ? 'Pošalji SMS kod (${_cooldownRemainingSeconds}s)' : 'Pošalji SMS kod',
          icon: Icons.send,
          isLoading: _isLoading || _isSmsCooldownActive,
          onPressed: _isSmsCooldownActive ? null : _sendSms,
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
        V3ButtonUtils.primaryButton(
          text: 'Potvrdi kod',
          icon: Icons.verified_user_outlined,
          isLoading: _isLoading,
          onPressed: _verifyOtp,
        ),
      ],
    );
  }

  Widget _buildProfileStep() {
    return Column(
      key: const ValueKey('profile'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInfoBox(
          icon: Icons.person_outline,
          text: 'Unesite podatke za nalog ($_normalizedPhone).',
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _imeController,
          enabled: !_isLoading,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Ime',
            labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.1),
            prefixIcon: const Icon(Icons.badge_outlined, color: Colors.amber),
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
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _prezimeController,
          enabled: !_isLoading,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Prezime',
            labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.1),
            prefixIcon: const Icon(Icons.account_circle_outlined, color: Colors.amber),
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
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _selectedTip,
          dropdownColor: const Color(0xFF1E1E1E),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Kategorija',
            labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.1),
            prefixIcon: const Icon(Icons.category_outlined, color: Colors.amber),
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
          items: const [
            DropdownMenuItem(value: 'radnik', child: Text('👷 Radnik')),
            DropdownMenuItem(value: 'ucenik', child: Text('🎒 Učenik')),
            DropdownMenuItem(value: 'dnevni', child: Text('📅 Dnevni')),
          ],
          onChanged: _isLoading
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() => _selectedTip = value);
                },
        ),
        if (_statusMessage.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildStatusMessage(_statusMessage),
        ],
        const SizedBox(height: 24),
        V3ButtonUtils.primaryButton(
          text: 'Sačuvaj i nastavi',
          icon: Icons.check_circle_outline,
          isLoading: _isLoading,
          onPressed: _saveOnboarding,
        ),
      ],
    );
  }

  // ─── Zajednički widgeti ────────────────────────────────────────

  Widget _buildInfoBox({required IconData icon, required String text}) {
    return V3ContainerUtils.styledContainer(
      padding: const EdgeInsets.all(14),
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.amber, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              textAlign: TextAlign.center,
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
