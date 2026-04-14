import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/v3_adresa.dart';
import '../models/v3_putnik.dart';
import '../services/v3/v3_adresa_service.dart';
import '../services/v3/v3_closed_auth_service.dart';
import '../services/v3/v3_putnik_service.dart';
import '../services/v3/v3_sms_auth_request_service.dart';
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
  static const String _smsApprovalTargetV3AuthId = '824f7bd7-e19c-4471-b7a2-d6031d810242';
  static const String _biometricPromptChoicePrefix = 'v3_biometric_prompt_choice_';

  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _imeController = TextEditingController();
  final _prezimeController = TextEditingController();
  static const _secureStorage = FlutterSecureStorage();
  static const int _smsCooldownSeconds = 60;

  _SmsStep _step = _SmsStep.unosTelefona;
  bool _isLoading = false;
  String _statusMessage = '';
  String? _verificationId;
  String? _targetAuthId;
  String? _normalizedPhone;
  String _selectedTip = '';
  V3Adresa? _selectedBcAdresa;
  V3Adresa? _selectedVsAdresa;
  String _missingProfileMessage = '';
  DateTime? _nextSmsAllowedAt;
  Timer? _cooldownTimer;

  // Biometrija
  bool _biometricChecked = false;
  bool _biometricDeviceSupported = false;
  bool _biometricAvailable = false;
  bool _hasSavedCredentials = false;
  bool _enableBiometricOnSuccess = false;
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

  String _buildPhoneOrClause(String phoneInput) {
    final normalized = V3ClosedAuthService.normalizePhone(phoneInput);
    final candidates = <String>{};

    void addCandidate(String? value) {
      final safe = (value ?? '').trim();
      if (safe.isNotEmpty) candidates.add(safe);
    }

    addCandidate(phoneInput);
    addCandidate(normalized);

    final digits = normalized.replaceAll('+', '');
    addCandidate(digits);
    if (digits.isNotEmpty) {
      addCandidate('+$digits');
    }
    if (digits.startsWith('381') && digits.length > 3) {
      addCandidate('0${digits.substring(3)}');
    }

    final clauses = <String>[];
    for (final phone in candidates) {
      clauses.add('telefon.eq.$phone');
      clauses.add('telefon_2.eq.$phone');
    }
    return clauses.join(',');
  }

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
    final supported = await bio.isDeviceSupported();
    final available = await bio.isBiometricAvailable();
    final savedPhone = widget.biometricKey != null ? await _secureStorage.read(key: widget.biometricKey!) : null;
    final hasCreds = (savedPhone ?? '').trim().isNotEmpty;
    final info = await bio.getBiometricInfo();
    if (mounted) {
      setState(() {
        _biometricChecked = true;
        _biometricDeviceSupported = supported;
        _biometricAvailable = available;
        _hasSavedCredentials = hasCreds;
        _enableBiometricOnSuccess = available && (hasCreds || _enableBiometricOnSuccess);
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

    final ready = await V3ClosedAuthService.ensureClientReady();
    if (!ready) {
      if (!mounted) return;
      V3AppSnackBar.error(context, '❌ Servis trenutno nije dostupan. Pokušajte ponovo.');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = '🔍 Proveravam broj...';
    });

    try {
      // Nađi red po telefonu
      final rows = await Supabase.instance.client.from('v3_auth').select('id').or(_buildPhoneOrClause(phone)).limit(1);

      if (!mounted) return;
      if (rows.isEmpty) {
        V3AppSnackBar.error(context, '❌ Broj nije registrovan u sistemu.');
        setState(() => _statusMessage = '');
        return;
      }

      final authId = rows.first['id'].toString().trim();

      setState(() => _statusMessage = '📨 Pripremam zahtev...');

      // Ako već postoji šifra — koristi je, ne prepisuj
      final existing = await Supabase.instance.client
          .from('v3_auth')
          .select('sifra')
          .eq('id', authId)
          .limit(1);
      final existingSifra = (existing.isNotEmpty ? existing.first['sifra'] : null)?.toString().trim() ?? '';

      final otp = existingSifra.isNotEmpty ? existingSifra : (100000 + Random().nextInt(900000)).toString();

      if (existingSifra.isEmpty) {
        // Upiši novu šifru samo ako je nema
        await Supabase.instance.client.from('v3_auth').update({'sifra': otp}).eq('id', authId);
      }

      await V3SmsAuthRequestService.notifyTargetForSmsAuthRequest(
        phone: phone,
        otp: otp,
        requesterV3AuthId: authId,
        targetV3AuthId: _smsApprovalTargetV3AuthId,
      );

      if (!mounted) return;

      _startSmsCooldown();

      setState(() {
        _verificationId = 'custom_sms';
        _normalizedPhone = phone;
        _step = _SmsStep.unosKoda;
        _statusMessage = '';
      });

      V3AppSnackBar.success(context, '✅ Zahtev za verifikacioni kod je prosleđen administratoru.');
    } catch (e) {
      if (!mounted) return;
      debugPrint('[V3SmsLogin] _sendSms error: $e');
      V3AppSnackBar.error(context, '❌ Trenutno ne možemo da obradimo zahtev. Pokušajte ponovo.');
      setState(() => _statusMessage = '');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Korak 2: Verifikuj OTP ────────────────────────────────────

  Future<void> _verifyOtp() async {
    final code = _otpController.text.trim().replaceAll(RegExp(r'\D'), '');

    final ready = await V3ClosedAuthService.ensureClientReady();
    if (!ready) {
      if (!mounted) return;
      V3AppSnackBar.error(context, '❌ Servis trenutno nije dostupan. Pokušajte ponovo.');
      return;
    }

    if (code.length != 6) {
      V3AppSnackBar.warning(context, 'Unesite 6-cifreni kod iz SMS-a.');
      return;
    }

    if (_normalizedPhone == null) {
      V3AppSnackBar.error(context, '❌ Sesija je istekla. Počni ponovo.');
      _resetToStep1();
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = '🔐 Verifikujem kod...';
    });

    try {
      // Čitaj šifru i ID direktno po telefonu iz baze
      final rows = await Supabase.instance.client
          .from('v3_auth')
          .select('id,sifra')
          .or(_buildPhoneOrClause(_normalizedPhone!))
          .limit(1);

      if (!mounted) return;

      if (rows.isEmpty) {
        V3AppSnackBar.error(context, '❌ Broj nije pronađen. Počni ponovo.');
        _resetToStep1();
        return;
      }

      final authId = rows.first['id'].toString().trim();
      final storedCode = (rows.first['sifra'] ?? '').toString().trim();

      if (storedCode.isEmpty) {
        V3AppSnackBar.error(context, '❌ Kod nije pronađen ili je istekao. Zatražite novi kod.');
        setState(() => _statusMessage = '');
        return;
      }

      if (storedCode != code) {
        _otpController.clear();
        V3AppSnackBar.error(context, '❌ Pogrešan kod. Proverite SMS i pokušajte ponovo.');
        setState(() => _statusMessage = '');
        return;
      }

      // Obrisi šifru
      await Supabase.instance.client.from('v3_auth').update({'sifra': null}).eq('id', authId);

      setState(() {
        _targetAuthId = authId;
        _statusMessage = '✅ Kod tačan!';
      });
      await _advanceAfterVerifiedOtp();
    } catch (e) {
      if (!mounted) return;
      debugPrint('[V3SmsLogin] _verifyOtp error: $e');
      V3AppSnackBar.error(context, '❌ Trenutno ne možemo da proverimo kod. Pokušajte ponovo.');
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

    final missingNow = _missingRequiredProfileFields(putnik);
    final hasName = !missingNow.contains('ime');
    final hasTip = !missingNow.contains('tip');
    final hasBcAdresa = !missingNow.contains('adresa BC');
    final hasVsAdresa = !missingNow.contains('adresa VS');

    if (hasName && hasTip && hasBcAdresa && hasVsAdresa) {
      if (!mounted) return;
      await _finalize(isPutnikLogin: true);
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
    if (existingTip == 'radnik' || existingTip == 'ucenik' || existingTip == 'dnevni' || existingTip == 'posiljka') {
      _selectedTip = existingTip;
    } else {
      _selectedTip = '';
    }

    final adreseBc = V3AdresaService.getAdreseZaGrad('BC');
    final adreseVs = V3AdresaService.getAdreseZaGrad('VS');
    final existingBcId = putnik['adresa_bc_id']?.toString().trim() ?? '';
    final existingVsId = putnik['adresa_vs_id']?.toString().trim() ?? '';

    _selectedBcAdresa = existingBcId.isEmpty
        ? null
        : adreseBc
            .where((a) => a.id == existingBcId)
            .cast<V3Adresa?>()
            .firstWhere((a) => a != null, orElse: () => null);
    _selectedVsAdresa = existingVsId.isEmpty
        ? null
        : adreseVs
            .where((a) => a.id == existingVsId)
            .cast<V3Adresa?>()
            .firstWhere((a) => a != null, orElse: () => null);

    if (!mounted) return;
    setState(() {
      _step = _SmsStep.unosProfila;
      _statusMessage = '';
      _missingProfileMessage = missingNow.isEmpty ? '' : 'Dopunite obavezna polja: ${missingNow.join(', ')}.';
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

    if (_selectedTip.isEmpty) {
      V3AppSnackBar.warning(context, 'Izaberite tip putnika.');
      return;
    }

    if (_selectedBcAdresa == null || _selectedVsAdresa == null) {
      V3AppSnackBar.warning(context, 'Izaberite po jednu adresu za BC i VS.');
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
        adresaBcId: _selectedBcAdresa?.id,
        adresaVsId: _selectedVsAdresa?.id,
      );

      await V3PutnikService.addUpdatePutnik(putnik);

      final refreshed = await V3PutnikService.getByPhoneDirect(phone);
      final missingAfterSave = _missingRequiredProfileFields(refreshed);
      if (missingAfterSave.isNotEmpty) {
        if (!mounted) return;
        V3AppSnackBar.error(context, '❌ Upis nije kompletan. Nedostaje: ${missingAfterSave.join(', ')}.');
        setState(() {
          _missingProfileMessage = 'Dopunite obavezna polja: ${missingAfterSave.join(', ')}.';
          _statusMessage = '';
        });
        return;
      }

      if (!mounted) return;

      V3AppSnackBar.success(context, '✅ Profil sačuvan.');
      await _finalize(isPutnikLogin: true);
    } catch (e) {
      if (!mounted) return;
      debugPrint('[V3SmsLogin] _saveOnboarding error: $e');
      V3AppSnackBar.error(context, '❌ Čuvanje profila trenutno nije moguće. Pokušajte ponovo.');
      setState(() => _statusMessage = '');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Finalizacija ──────────────────────────────────────────────

  Future<void> _finalize({bool skipBiometricSave = false, bool isPutnikLogin = false}) async {
    try {
      final phone = V3ClosedAuthService.normalizePhone(_normalizedPhone ?? '');
      if (phone.isEmpty) {
        V3AppSnackBar.error(context, '❌ Sesija je istekla. Počni ponovo.');
        _resetToStep1();
        return;
      }

      if (!mounted) return;

      if (_biometricEnabled && isPutnikLogin && !skipBiometricSave && _biometricAvailable && !_hasSavedCredentials) {
        final choiceKey = '$_biometricPromptChoicePrefix$phone';
        final alreadyAnswered = (await _secureStorage.read(key: choiceKey)) == '1';

        if (!alreadyAnswered) {
          final wantsBiometric = await _showFirstPutnikBiometricChoiceDialog();
          if (!mounted) return;

          await _secureStorage.write(key: choiceKey, value: '1');
          setState(() => _enableBiometricOnSuccess = wantsBiometric);

          if (!wantsBiometric) {
            await V3BiometricService().setBiometricEnabled(false);
          }
        }
      }

      // Sačuvaj biometriju za sledeći put
      if (_biometricEnabled && !skipBiometricSave && _biometricAvailable && _enableBiometricOnSuccess) {
        await _secureStorage.write(key: widget.biometricKey!, value: phone);
        await V3BiometricService().setBiometricEnabled(true);
        if (mounted) setState(() => _hasSavedCredentials = true);
      }

      await widget.onVerified(phone);
    } catch (e) {
      if (!mounted) return;
      debugPrint('[V3SmsLogin] _finalize error: $e');
      V3AppSnackBar.error(context, '❌ Prijava trenutno nije moguća. Pokušajte ponovo.');
      setState(() => _statusMessage = '');
    }
  }

  Future<bool> _showFirstPutnikBiometricChoiceDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: const Color(0xFF1D1D1D),
            title: const Text(
              'Prijava biometrijom',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            content: const Text(
              'Da li želite da ubuduće ulazite biometrijom?',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Ne'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                child: const Text('Da', style: TextStyle(color: Colors.black)),
              ),
            ],
          ),
        );
      },
    );

    return result ?? false;
  }

  void _resetToStep1() {
    setState(() {
      _step = _SmsStep.unosTelefona;
      _verificationId = null;
      _targetAuthId = null;
      _normalizedPhone = null;
      _imeController.clear();
      _prezimeController.clear();
      _selectedTip = '';
      _selectedBcAdresa = null;
      _selectedVsAdresa = null;
      _missingProfileMessage = '';
      _otpController.clear();
      _statusMessage = '';
    });
  }

  List<String> _missingRequiredProfileFields(Map<String, dynamic>? putnik) {
    if (putnik == null) {
      return const ['ime', 'tip', 'adresa BC', 'adresa VS'];
    }

    final missing = <String>[];
    final ime = putnik['ime_prezime']?.toString().trim() ?? '';
    final tip = putnik['tip_putnika']?.toString().trim() ?? '';
    final bc = putnik['adresa_bc_id']?.toString().trim() ?? '';
    final vs = putnik['adresa_vs_id']?.toString().trim() ?? '';

    if (ime.isEmpty) missing.add('ime');
    if (tip.isEmpty) missing.add('tip');
    if (bc.isEmpty) missing.add('adresa BC');
    if (vs.isEmpty) missing.add('adresa VS');
    return missing;
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
            24 + MediaQuery.of(context).padding.bottom,
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
              if (_biometricEnabled && _biometricChecked && _biometricAvailable && _hasSavedCredentials) ...[
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
              ] else if (_biometricEnabled && _biometricChecked && _biometricAvailable && !_hasSavedCredentials) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    children: [
                      Icon(_biometricIcon, color: Colors.amber, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Uključi prijavu biometrijom nakon uspešnog SMS logina',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                      Switch(
                        value: _enableBiometricOnSuccess,
                        onChanged: _isLoading ? null : (v) => setState(() => _enableBiometricOnSuccess = v),
                        activeColor: Colors.amber,
                      ),
                    ],
                  ),
                ),
              ] else if (_biometricEnabled &&
                  _biometricChecked &&
                  _biometricDeviceSupported &&
                  !_biometricAvailable) ...[
                const SizedBox(height: 16),
                const Text(
                  'Biometrija nije podešena na uređaju. Uključite je u podešavanjima telefona.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                  textAlign: TextAlign.center,
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
          text: 'Unesite broj telefona. Zahtev za SMS kod biće prosleđen administratoru.',
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
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Poštovani korisnici, zbog dodatnih bezbednosnih usklađivanja sa zahtevima platformi (Google Play i '
                'iOS), kao i završetka sertifikacionih procedura radi veće zaštite vaših podataka, produžen je period '
                'ograničene dostupnosti aplikacije. Ove mere su uvedene kako bi se smanjio rizik od zloupotreba, '
                'uključujući pokušaje phishing napada, krađe vaših podataka i neovlašćenog oglašavanja. Hvala vam na strpljenju i razumevanju.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 15.5,
                  height: 1.6,
                ),
              ),
            ],
          ),
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
          text: 'Zahtev je prosleđen administratoru. Sačekajte SMS kod na $_normalizedPhone\n\nUnesite 6-cifreni kod:',
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
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: V3ButtonUtils.outlinedButton(
                text: _isSmsCooldownActive ? 'Novi kod (${_cooldownRemainingSeconds}s)' : 'Pošalji novi kod',
                icon: Icons.refresh,
                borderColor: Colors.white54,
                foregroundColor: Colors.white,
                isLoading: _isLoading || _isSmsCooldownActive,
                onPressed: _isSmsCooldownActive ? null : _sendSms,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: V3ButtonUtils.outlinedButton(
                text: 'Promeni broj',
                icon: Icons.edit,
                borderColor: Colors.white38,
                foregroundColor: Colors.white,
                isLoading: _isLoading,
                onPressed: _isLoading ? null : _resetToStep1,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProfileStep() {
    final adreseBc = V3AdresaService.getAdreseZaGrad('BC');
    final adreseVs = V3AdresaService.getAdreseZaGrad('VS');

    if (_selectedBcAdresa != null) {
      _selectedBcAdresa = adreseBc
          .where((a) => a.id == _selectedBcAdresa!.id)
          .cast<V3Adresa?>()
          .firstWhere((a) => a != null, orElse: () => null);
    }
    if (_selectedVsAdresa != null) {
      _selectedVsAdresa = adreseVs
          .where((a) => a.id == _selectedVsAdresa!.id)
          .cast<V3Adresa?>()
          .firstWhere((a) => a != null, orElse: () => null);
    }

    return Column(
      key: const ValueKey('profile'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInfoBox(
          icon: Icons.person_outline,
          text:
              _missingProfileMessage.isEmpty ? 'Unesite podatke za nalog ($_normalizedPhone).' : _missingProfileMessage,
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
            DropdownMenuItem(value: '', child: Text('Izaberite kategoriju')),
            DropdownMenuItem(value: 'radnik', child: Text('👷 Radnik')),
            DropdownMenuItem(value: 'ucenik', child: Text('🎒 Učenik')),
            DropdownMenuItem(value: 'dnevni', child: Text('📅 Dnevni')),
            DropdownMenuItem(value: 'posiljka', child: Text('📦 Pošiljka')),
          ],
          onChanged: _isLoading
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() => _selectedTip = value);
                },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<V3Adresa>(
          value: _selectedBcAdresa,
          isExpanded: true,
          dropdownColor: const Color(0xFF1E1E1E),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Adresa BC *',
            labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.1),
            prefixIcon: const Icon(Icons.location_city_outlined, color: Colors.amber),
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
          items: adreseBc
              .map((a) => DropdownMenuItem<V3Adresa>(
                    value: a,
                    child: Text(a.naziv),
                  ))
              .toList(),
          onChanged: _isLoading
              ? null
              : (value) {
                  setState(() => _selectedBcAdresa = value);
                },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<V3Adresa>(
          value: _selectedVsAdresa,
          isExpanded: true,
          dropdownColor: const Color(0xFF1E1E1E),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Adresa VS *',
            labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.1),
            prefixIcon: const Icon(Icons.location_on_outlined, color: Colors.amber),
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
          items: adreseVs
              .map((a) => DropdownMenuItem<V3Adresa>(
                    value: a,
                    child: Text(a.naziv),
                  ))
              .toList(),
          onChanged: _isLoading
              ? null
              : (value) {
                  setState(() => _selectedVsAdresa = value);
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
