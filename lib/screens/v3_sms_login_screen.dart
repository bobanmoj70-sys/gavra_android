import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/v3_adresa.dart';
import '../models/v3_putnik.dart';
import '../services/v3/v3_adresa_service.dart';
import '../services/v3/v3_closed_auth_service.dart';
import '../services/v3/v3_putnik_service.dart';
import '../services/v3_biometric_service.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_input_utils.dart';
import '../utils/v3_phone_utils.dart';
import '../widgets/v3_update_banner.dart';

enum _SmsStep { unosTelefona, unosProfila }

/// Unified SMS login screen za putnike i vozače.
///
/// [title]         – naslov appbar-a
/// [initialPhone]  – pre-popunjen telefon (vozač)
/// [header]        – widget iznad forme (vozač header sa imenom)
/// [biometricKey]  – ključ za SecureStorage biometrije (null = bez biometrije)
/// [onVerified]    – callback nakon uspešne verifikacije, prima normalizovan telefon + auth id (ako postoji)
class V3SmsLoginScreen extends StatefulWidget {
  final String title;
  final String? initialPhone;
  final Widget? header;
  final String? biometricKey;
  final Future<void> Function(String canonicalPhone, String? authId) onVerified;

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
  final _imeController = TextEditingController();
  final _prezimeController = TextEditingController();
  static const _secureStorage = FlutterSecureStorage();

  _SmsStep _step = _SmsStep.unosTelefona;
  bool _isLoading = false;
  String _statusMessage = '';
  String? _targetAuthId;
  String? _normalizedPhone;
  String _selectedTip = '';
  V3Adresa? _selectedBcAdresa;
  V3Adresa? _selectedVsAdresa;
  String _missingProfileMessage = '';
  bool _isBackendReady = false;

  // Biometrija
  bool _biometricChecked = false;
  bool _biometricDeviceSupported = false;
  bool _biometricAvailable = false;
  bool _biometricEnabledForUser = false;
  bool _hasSavedCredentials = false;
  bool _autoBiometricAttempted = false;
  IconData _biometricIcon = Icons.fingerprint;

  bool get _biometricEnabled => widget.biometricKey != null;

  @override
  void initState() {
    super.initState();
    if (widget.initialPhone != null) {
      _phoneController.text = V3PhoneUtils.normalize(widget.initialPhone!);
    }
    unawaited(_waitForBackendReady());
    if (_biometricEnabled) _checkBiometric();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _imeController.dispose();
    _prezimeController.dispose();
    super.dispose();
  }

  bool get _canSubmitPhoneStep => !_isLoading;

  Future<void> _waitForBackendReady() async {
    while (mounted && !_isBackendReady) {
      final ready = await V3ClosedAuthService.ensureClientReady();
      if (!mounted) return;

      if (ready) {
        setState(() => _isBackendReady = true);
        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
  }

  // ─── Biometrija ────────────────────────────────────────────────

  Future<void> _checkBiometric() async {
    final bio = V3BiometricService();
    final supported = await bio.isDeviceSupported();
    final available = await bio.isBiometricAvailable();
    final enabledForUser = await bio.isBiometricEnabled();
    final savedPhone = widget.biometricKey != null ? await _secureStorage.read(key: widget.biometricKey!) : null;
    final hasCreds = (savedPhone ?? '').trim().isNotEmpty && enabledForUser;
    final info = await bio.getBiometricInfo();
    if (mounted) {
      setState(() {
        _biometricChecked = true;
        _biometricDeviceSupported = supported;
        _biometricAvailable = available;
        _biometricEnabledForUser = enabledForUser;
        _hasSavedCredentials = hasCreds;
        _biometricIcon = info.icon;
      });
      _tryAutoBiometricLogin();
    }
  }

  void _tryAutoBiometricLogin() {
    if (_autoBiometricAttempted) return;
    if (!_biometricEnabled || !_biometricAvailable || !_biometricEnabledForUser || !_hasSavedCredentials) return;

    _autoBiometricAttempted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isLoading || _step != _SmsStep.unosTelefona) return;
      _loginWithBiometric(silentFailure: true);
    });
  }

  Future<void> _loginWithBiometric({bool silentFailure = false}) async {
    if (widget.biometricKey == null) return;

    if (!_biometricEnabledForUser) {
      if (!silentFailure && mounted) {
        V3AppSnackBar.info(context, 'ℹ️ Biometrija nije uključena za ovaj nalog.');
      }
      return;
    }

    final raw = await _secureStorage.read(key: widget.biometricKey!);
    if (raw == null) {
      if (!silentFailure && mounted) {
        V3AppSnackBar.info(context, 'ℹ️ Nema sačuvanih podataka. Prijavi se brojem telefona.');
      }
      return;
    }

    final authenticated = await V3BiometricService().authenticate(
      reason: 'Potvrdi identitet za prijavu',
    );

    if (!authenticated) {
      if (!silentFailure && mounted) {
        V3AppSnackBar.error(context, '❌ Biometrijska autentifikacija nije uspela');
      }
      return;
    }

    final normalized = V3ClosedAuthService.normalizePhone(raw);
    if (normalized.isEmpty) {
      if (!silentFailure && mounted) {
        V3AppSnackBar.error(context, '❌ Sačuvan telefon nije ispravan. Prijavi se brojem telefona.');
      }
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
    if (!_canSubmitPhoneStep) {
      return;
    }

    final input = _phoneController.text.trim();
    if (input.isEmpty) {
      V3AppSnackBar.warning(context, 'Unesite broj telefona.');
      return;
    }

    final phone = V3ClosedAuthService.normalizePhone(input);
    if (phone.isEmpty) {
      V3AppSnackBar.warning(context, 'Unesite broj telefona.');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = '🔍 Proveravam broj...';
    });

    try {
      final authId = await V3ClosedAuthService.findAuthIdByPhoneViaEdge(phone);
      if (authId == null) {
        if (!mounted) return;
        V3AppSnackBar.error(context, '❌ Broj telefona i UUID reda nisu pronađeni.');
        setState(() => _statusMessage = '');
        return;
      }

      setState(() {
        _targetAuthId = authId;
        _normalizedPhone = phone;
        _statusMessage = '';
      });

      await _advanceAfterPhoneAuth();
    } catch (e) {
      if (!mounted) return;
      debugPrint('[V3SmsLogin] _sendSms error: $e');
      V3AppSnackBar.error(context, '❌ Trenutno ne možemo da obradimo zahtev. Pokušajte ponovo.');
      setState(() => _statusMessage = '');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _advanceAfterPhoneAuth() async {
    final phone = V3ClosedAuthService.normalizePhone(_normalizedPhone ?? '');
    if (phone.isEmpty) {
      if (mounted) {
        V3AppSnackBar.error(context, '❌ Sesija je istekla. Počni ponovo.');
        _resetToStep1();
      }
      return;
    }
    if (!mounted) return;
    await _finalize();
  }

  Future<void> _saveOnboarding() async {
    final ime = _imeController.text.trim();
    final prezime = _prezimeController.text.trim();
    final fullName = '$ime $prezime'.trim();
    final phone = V3ClosedAuthService.normalizePhone(_normalizedPhone ?? '');
    final authId = (_targetAuthId ?? '').trim();

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

    if (authId.isEmpty) {
      V3AppSnackBar.error(context, '❌ Sesija je istekla. Počni ponovo.');
      _resetToStep1();
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = '💾 Čuvam profil...';
    });

    try {
      final existing = await V3PutnikService.getActiveById(authId);
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

      final refreshed = await V3PutnikService.getActiveById(authId);
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
      await _finalize();
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

  Future<void> _finalize({bool skipBiometricSave = false}) async {
    try {
      final phone = V3ClosedAuthService.normalizePhone(_normalizedPhone ?? '');
      if (phone.isEmpty) {
        V3AppSnackBar.error(context, '❌ Sesija je istekla. Počni ponovo.');
        _resetToStep1();
        return;
      }

      if (!mounted) return;

      // Automatski sačuvaj biometriju za sledeći put (bez pitanja)
      if (_biometricEnabled && !skipBiometricSave && _biometricAvailable) {
        await _secureStorage.write(key: widget.biometricKey!, value: phone);
        await V3BiometricService().setBiometricEnabled(true);
        if (mounted) {
          setState(() {
            _biometricEnabledForUser = true;
            _hasSavedCredentials = true;
          });
        }
      }

      await widget.onVerified(phone, _targetAuthId);
    } catch (e) {
      if (!mounted) return;
      debugPrint('[V3SmsLogin] _finalize error: $e');
      V3AppSnackBar.error(context, '❌ Prijava trenutno nije moguća. Pokušajte ponovo.');
      setState(() => _statusMessage = '');
    }
  }

  void _resetToStep1() {
    setState(() {
      _step = _SmsStep.unosTelefona;
      _targetAuthId = null;
      _normalizedPhone = null;
      _imeController.clear();
      _prezimeController.clear();
      _selectedTip = '';
      _selectedBcAdresa = null;
      _selectedVsAdresa = null;
      _missingProfileMessage = '';
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
              const V3UpdateBanner(),
              if (widget.header != null) ...[
                widget.header!,
                const SizedBox(height: 32),
              ],
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: switch (_step) {
                  _SmsStep.unosTelefona => _buildPhoneStep(),
                  _SmsStep.unosProfila => _buildProfileStep(),
                },
              ),
              if (_biometricEnabled && _biometricChecked && _biometricDeviceSupported && !_biometricAvailable) ...[
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
          text: 'Unesite broj telefona za prijavu.',
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
            suffixIcon: IconButton(
              tooltip: 'Nalepi',
              icon: const Icon(Icons.content_paste_rounded, color: Colors.amber),
              onPressed: _isLoading ? null : () => V3InputUtils.pasteFromClipboardIntoController(_phoneController),
            ),
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
            if (_canSubmitPhoneStep) _sendSms();
          },
        ),
        if (_statusMessage.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildStatusMessage(_statusMessage),
        ],
        const SizedBox(height: 24),
        V3ButtonUtils.primaryButton(
          text: 'Nastavi',
          icon: Icons.send,
          isLoading: _isLoading,
          onPressed: _canSubmitPhoneStep ? _sendSms : null,
        ),
        if (_biometricEnabled && _biometricChecked && _biometricAvailable && _hasSavedCredentials) ...[
          const SizedBox(height: 10),
          V3ButtonUtils.amberButton(
            text: 'Prijava biometrijom',
            icon: _biometricIcon,
            isLoading: _isLoading,
            onPressed: _isLoading ? null : () => _loginWithBiometric(),
          ),
        ],
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
