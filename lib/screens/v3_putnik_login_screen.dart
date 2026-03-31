import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../globals.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v2_theme_manager.dart';
import '../services/v3/v3_pin_zahtev_service.dart';
import '../services/v3/v3_putnik_service.dart';
import '../services/v3/v3_role_permission_service.dart';
import '../services/v3_biometric_service.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dialog_helper.dart';
import '../utils/v3_dialog_utils.dart';
import '../utils/v3_input_utils.dart';
import '../utils/v3_navigation_utils.dart';
import '../utils/v3_phone_utils.dart';
import '../utils/v3_state_utils.dart';
import '../utils/v3_stream_utils.dart';
import '../utils/v3_text_utils.dart';
import 'v3_putnik_profil_screen.dart';

enum _LoginStep { telefon, email, pin, zahtevPoslat }

class V3PutnikLoginScreen extends StatefulWidget {
  const V3PutnikLoginScreen({super.key});

  @override
  State<V3PutnikLoginScreen> createState() => _V3PutnikLoginScreenState();
}

class _V3PutnikLoginScreenState extends State<V3PutnikLoginScreen> with WidgetsBindingObserver {
  _LoginStep _currentStep = _LoginStep.telefon;
  bool _isLoading = false;
  bool _isResumeRefreshing = false;
  String? _errorMessage;
  String? _infoMessage;

  Map<String, dynamic>? _putnikData;

  // Biometrija
  final _biometric = V3BiometricService();
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  String _biometricTypeText = 'biometriju';
  IconData _biometricIcon = Icons.fingerprint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkBiometric();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshOnResume());
    }
  }

  Future<void> _refreshOnResume() async {
    if (_isResumeRefreshing || !mounted) return;
    _isResumeRefreshing = true;
    try {
      await V3MasterRealtimeManager.instance.initV3();
    } catch (e) {
      debugPrint('[V3PutnikLoginScreen] refreshOnResume error: $e');
    } finally {
      _isResumeRefreshing = false;
    }
  }

  Future<void> _checkBiometric() async {
    final available = await _biometric.isBiometricAvailable();
    final enabled = await _biometric.isBiometricEnabled();
    if (!available || !mounted) return;
    final info = await _biometric.getBiometricInfo();
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _biometricEnabled = enabled;
      _biometricTypeText = info.text;
      _biometricIcon = info.icon;
    });
    // Ako je biometrija uključena, odmah pokušaj automatski
    if (enabled) {
      _loginWithBiometric(auto: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    V3StreamUtils.cancelSubscription('putnik_login_pin');
    V3TextUtils.disposeController('telefon');
    V3TextUtils.disposeController('email');
    V3TextUtils.disposeController('pin');
    super.dispose();
  }

  String _normalizePhone(String phone) => V3PhoneUtils.normalize(phone);

  // Korak 1: Provjeri telefon u v3_putnici
  Future<void> _checkTelefon() async {
    final telefon = V3TextUtils.getControllerText('telefon').trim();
    if (telefon.isEmpty) {
      V3StateUtils.safeSetState(this, () => _errorMessage = 'Unesite broj telefona');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final normalized = _normalizePhone(telefon);
      // Tražimo u v3_putnici cache-u ili direktno u DB
      Map<String, dynamic>? found;

      // Prvo cache
      final cache = V3MasterRealtimeManager.instance.putniciCache;
      for (final row in cache.values) {
        final t = _normalizePhone(row['telefon_1']?.toString() ?? '');
        final t2 = _normalizePhone(row['telefon_2']?.toString() ?? '');
        if (t == normalized || (t2.isNotEmpty && t2 == normalized)) {
          found = Map<String, dynamic>.from(row);
          break;
        }
      }

      // Ako nema u cache-u, pitaj DB direktno
      if (found == null) {
        final rows =
            await supabase.from('v3_putnici').select().or('telefon_1.eq.$normalized,telefon_2.eq.$normalized').limit(1);
        if (rows.isNotEmpty) found = Map<String, dynamic>.from(rows.first);
      }

      if (!mounted) return;

      if (found == null) {
        V3StateUtils.safeSetState(
            this, () => _errorMessage = 'Niste pronađeni u sistemu.\nKontaktirajte admina za registraciju.');
        return;
      }

      _putnikData = found;
      final email = found['email'] as String?;
      final pin = found['pin'] as String?;

      if (email == null || email.trim().isEmpty) {
        // Nema email — traži ga
        setState(() {
          _currentStep = _LoginStep.email;
          _infoMessage = 'Pronađeni ste! Unesite email za kontakt.';
        });
      } else if (pin == null || pin.isEmpty) {
        // Ima email ali nema PIN — proveri zahtev
        final imaZahtev = await V3PinZahtevService.imaZahtevKojiCekaAsync(found['id'].toString());
        if (!mounted) return;
        if (imaZahtev) {
          setState(() {
            _currentStep = _LoginStep.zahtevPoslat;
            _infoMessage = 'Vaš zahtev za PIN je već poslat. Molimo sačekajte da admin odobri.';
          });
          _listenForPin();
        } else {
          _showPinRequestDialog();
        }
      } else {
        setState(() {
          _currentStep = _LoginStep.pin;
          _infoMessage = 'Pronađeni ste! Unesite svoj 4-cifreni PIN.';
        });
      }
    } catch (e) {
      V3StateUtils.safeSetState(this, () => _errorMessage = 'Greška pri povezivanju: $e');
    } finally {
      V3StateUtils.safeSetState(this, () => _isLoading = false);
    }
  }

  Future<void> _saveEmail() async {
    final email = V3TextUtils.getControllerText('email').trim();
    if (email.isEmpty) {
      V3StateUtils.safeSetState(this, () => _errorMessage = 'Unesite email adresu');
      return;
    }
    final emailRegex = RegExp(r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(email)) {
      V3StateUtils.safeSetState(this, () => _errorMessage = 'Unesite validnu email adresu');
      return;
    }
    final emailLower = email.toLowerCase();
    final local = emailLower.split('@')[0];
    final domain = emailLower.split('@')[1];
    if (local.length < 3 || domain.split('.')[0].length < 3) {
      V3StateUtils.safeSetState(this, () => _errorMessage = 'Email adresa je previše kratka');
      return;
    }
    if (RegExp(r'^(.)\1{2,}').hasMatch(local)) {
      V3StateUtils.safeSetState(this, () => _errorMessage = 'Unesite stvarnu email adresu');
      return;
    }
    const fakeDomains = ['test.com', 'fake.com', 'example.com', 'asdf.com', 'qwer.com', 'aaa.com'];
    if (fakeDomains.any((d) => domain == d)) {
      V3StateUtils.safeSetState(this, () => _errorMessage = 'Unesite stvarnu email adresu');
      return;
    }

    V3StateUtils.batchUpdate(this, () {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final putnikId = _putnikData!['id'].toString();
      final success = await V3PinZahtevService.azurirajEmail(putnikId, email);
      if (!mounted) return;
      if (!success) {
        V3StateUtils.safeSetState(this, () => _errorMessage = 'Greška pri čuvanju emaila');
        return;
      }
      _putnikData!['email'] = email;
      final pin = _putnikData!['pin'] as String?;
      if (pin == null || pin.isEmpty) {
        _showPinRequestDialog();
      } else {
        setState(() {
          _currentStep = _LoginStep.pin;
          _infoMessage = 'Email sačuvan! Unesite svoj 4-cifreni PIN.';
        });
      }
    } catch (e) {
      V3StateUtils.safeSetState(this, () => _errorMessage = 'Greška: $e');
    } finally {
      V3StateUtils.safeSetState(this, () => _isLoading = false);
    }
  }

  void _showPinRequestDialog() async {
    final result = await V3DialogHelper.showConfirmDialog(
      context,
      title: 'PIN nije dodeljen',
      message: 'Nemate dodeljeni PIN za pristup.\n\nŽelite li da pošaljete zahtev adminu za dodelu PIN-a?',
      confirmText: 'Pošalji zahtev',
      cancelText: 'Odustani',
    );

    if (result == true) {
      _sendPinRequest();
    }
  }

  Future<void> _sendPinRequest() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final putnikId = _putnikData!['id'].toString();
      final telefon = _normalizePhone(V3TextUtils.getControllerText('telefon').trim());
      final success = await V3PinZahtevService.posaljiZahtev(
        putnikId: putnikId,
        telefon: telefon,
        gcmId: 'app',
      );
      if (!mounted) return;
      if (success) {
        setState(() {
          _currentStep = _LoginStep.zahtevPoslat;
          _infoMessage = 'Zahtev je uspešno poslat! Admin će vam dodeliti PIN.';
        });
        _listenForPin();
      } else {
        V3StateUtils.safeSetState(this, () => _errorMessage = 'Greška pri slanju zahteva');
      }
    } catch (e) {
      V3StateUtils.safeSetState(this, () => _errorMessage = 'Greška: $e');
    } finally {
      V3StateUtils.safeSetState(this, () => _isLoading = false);
    }
  }

  void _listenForPin() {
    V3StreamUtils.cancelSubscription('putnik_login_pin');
    final putnikId = _putnikData?['id']?.toString();
    V3StreamUtils.subscribeToPinRequests(
        key: 'putnik_login',
        pinStream: V3PinZahtevService.streamZahteviKojiCekaju(),
        onPinUpdate: (lista) {
          if (!mounted) return;
          // Kada zahtev nestane iz liste čekanja — PIN je odobren
          final josCeka = lista.any((z) => z['putnik_id']?.toString() == putnikId);
          if (!josCeka && _currentStep == _LoginStep.zahtevPoslat) {
            V3StreamUtils.cancelSubscription('putnik_login_pin');
            setState(() {
              _currentStep = _LoginStep.pin;
              _infoMessage = '✅ PIN je dodeljen! Unesite PIN koji ste dobili.';
              _errorMessage = null;
            });
          }
        });
  }

  // Biometrijski login
  Future<void> _loginWithBiometric({bool auto = false}) async {
    if (!_biometricAvailable || !_biometricEnabled) return;
    final creds = await _biometric.getSavedCredentials();
    if (creds == null) {
      // Sačuvani kredencijali ne postoje — resetuj
      await _biometric.clearCredentials();
      V3StateUtils.safeSetState(this, () => _biometricEnabled = false);
      return;
    }
    final ok = await _biometric.authenticate(
      reason: 'Prijavite se kao putnik pomoću $_biometricTypeText',
    );
    if (!ok || !mounted) return;

    // Popuni polja i uradi login
    V3TextUtils.setControllerText('telefon', creds['phone']!);
    V3TextUtils.setControllerText('pin', creds['pin']!);

    // Pronadi putnika
    final normalized = _normalizePhone(creds['phone']!);
    Map<String, dynamic>? found;
    final cache = V3MasterRealtimeManager.instance.putniciCache;
    for (final row in cache.values) {
      final t = _normalizePhone(row['telefon_1']?.toString() ?? '');
      final t2 = _normalizePhone(row['telefon_2']?.toString() ?? '');
      if (t == normalized || (t2.isNotEmpty && t2 == normalized)) {
        found = Map<String, dynamic>.from(row);
        break;
      }
    }
    found ??= await supabase
        .from('v3_putnici')
        .select()
        .or('telefon_1.eq.$normalized,telefon_2.eq.$normalized')
        .limit(1)
        .maybeSingle();

    if (!mounted) return;
    if (found == null) {
      V3StateUtils.safeSetState(this, () => _errorMessage = 'Sacuvani podaci su zastarjeli. Prijavite se rucno.');
      await _biometric.clearCredentials();
      V3StateUtils.safeSetState(this, () => _biometricEnabled = false);
      return;
    }

    _putnikData = found;
    setState(() {
      _currentStep = _LoginStep.pin;
      _infoMessage = null;
    });
    // Direktno uradi login (bez setup dialoga jer je biometrija vec ukljucena)
    await _loginWithPin(skipBiometricSetup: true);
  }

  Future<void> _showBiometricSetupDialog({required String phone, required String pin}) async {
    if (!mounted) return;
    final result = await V3DialogUtils.showChoiceDialog(
      context: context,
      title: 'Brza prijava',
      titleIcon: _biometricIcon,
      content: 'Želite li se sledeći put prijaviti pomoću $_biometricTypeText?\n\nNe morate unositi telefon i PIN.',
      choices: {
        'no': 'Ne, hvala',
        'remember': 'Samo me zapamti',
        'biometric': 'Uključi biometriju',
      },
    );

    if (result == 'biometric') {
      await _biometric.saveCredentials(phone, pin, isBiometric: true);
      V3StateUtils.safeSetState(this, () => _biometricEnabled = true);
    } else if (result == 'remember') {
      await _biometric.saveCredentials(phone, pin, isBiometric: false);
    }
  }

  Future<void> _showRememberMeDialog({required String phone, required String pin}) async {
    if (!mounted) return;
    final ok = await V3DialogHelper.showConfirmDialog(
      context,
      title: 'Zapamti me',
      message:
          'Želite li da aplikacija zapamti vaše podatke?\n\nSledeći put ćete se prijaviti automatski bez kucanja PIN-a.',
      confirmText: 'Zapamti me',
      cancelText: 'Ne, hvala',
    );
    if (ok == true) {
      await _biometric.saveCredentials(phone, pin, isBiometric: false);
    }
  }

  // Korak 2: Login sa PIN-om
  Future<void> _loginWithPin({bool skipBiometricSetup = false}) async {
    final pin = V3TextUtils.getControllerText('pin').trim();
    if (pin.isEmpty) {
      V3StateUtils.safeSetState(this, () => _errorMessage = 'Unesite PIN');
      return;
    }
    if (pin.length != 4) {
      V3StateUtils.safeSetState(this, () => _errorMessage = 'PIN mora imati 4 cifre');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final storedPin = _putnikData!['pin']?.toString() ?? '';
      if (pin != storedPin) {
        // Proveri ponovo iz DB (možda je PIN promenjen)
        final fresh = await supabase.from('v3_putnici').select('pin').eq('id', _putnikData!['id']).single();
        if (!mounted) return;
        if (pin != fresh['pin']?.toString()) {
          V3StateUtils.safeSetState(this, () => _errorMessage = 'Pogrešan PIN. Pokušajte ponovo.');
          return;
        }
      }

      if (!mounted) return;
      V3AppSnackBar.success(context, 'Dobrodošli, ${_putnikData!['ime_prezime'] ?? 'Putniče'}!');

      V3PutnikService.currentPutnik = _putnikData;

      // Najpre tražimo dozvolu (važno za iOS - token nije dostupan bez odobrenja)
      await V3RolePermissionService.ensurePassengerPermissionsOnLogin();

      // Snimi FCM push token (nakon što je dozvola odobrena)
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          await supabase.from('v3_putnici').update({'push_token': token}).eq('id', _putnikData!['id']);
          _putnikData!['push_token'] = token;
        }
      } catch (e) {
        debugPrint('[PutnikLogin] push_token greška: $e');
      }

      // Ponudi biometrijsku prijavu ili Remember Me
      if (!skipBiometricSetup) {
        if (_biometricAvailable && !_biometricEnabled) {
          await _showBiometricSetupDialog(
            phone: _normalizePhone(V3TextUtils.getControllerText('telefon').trim()),
            pin: pin,
          );
        } else if (!_biometricAvailable || !_biometricEnabled) {
          // Ako biometrija nije dostupna ili je korisnik odbio ranije, ponudi bar "Zapamti me"
          final isRememberMe = await _biometric.isRememberMeEnabled();
          if (!isRememberMe) {
            await _showRememberMeDialog(
              phone: _normalizePhone(V3TextUtils.getControllerText('telefon').trim()),
              pin: pin,
            );
          }
        }
      }

      if (!mounted) return;
      V3NavigationUtils.pushReplacement(
        context,
        V3PutnikProfilScreen(putnikData: _putnikData!),
      );
    } catch (e) {
      V3StateUtils.safeSetState(this, () => _errorMessage = 'Greška pri prijavi: $e');
    } finally {
      V3StateUtils.safeSetState(this, () => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return V3ContainerUtils.backgroundContainer(
      gradient: V2ThemeManager().currentGradient,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 24),
                _stepIcon(),
                const SizedBox(height: 16),
                _stepTitle(),
                const SizedBox(height: 8),
                _stepSubtitle(),
                const SizedBox(height: 12),
                V3ContainerUtils.styledContainer(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.amber, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Za App Review vozača: vratite se nazad i izaberite "Vozači" na početnom ekranu.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                _stepIndicator(),
                const SizedBox(height: 24),
                if (_infoMessage != null) ...[
                  _infoBox(_infoMessage!, Colors.green),
                  const SizedBox(height: 16),
                ],
                _buildStepContent(),
                const SizedBox(height: 16),
                if (_errorMessage != null) ...[
                  _infoBox(_errorMessage!, Colors.red),
                  const SizedBox(height: 16),
                ],
                if (_currentStep != _LoginStep.zahtevPoslat)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _onMainButton,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLoading
                          ? SizedBox(
                              width: V3ContainerUtils.responsiveHeight(context, 24),
                              height: V3ContainerUtils.responsiveHeight(context, 24),
                              child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                            )
                          : Text(
                              _currentStep == _LoginStep.telefon
                                  ? '➡️ Nastavi'
                                  : _currentStep == _LoginStep.email
                                      ? '💾 Sačuvaj email'
                                      : '🔓 Pristupi',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                if (_currentStep == _LoginStep.zahtevPoslat) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.amber),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('↩️ Nazad na početnu', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                _infoHint(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case _LoginStep.telefon:
        return V3InputUtils.textField(
          fieldKey: const ValueKey('putnik_telefon_field'),
          controller: V3TextUtils.telefonController,
          label: 'Broj telefona',
          hint: '06x xxx xxxx',
          icon: Icons.phone_android,
          keyboardType: TextInputType.phone,
          onSubmitted: (_) => _checkTelefon(),
        );
      case _LoginStep.email:
        return V3InputUtils.textField(
          fieldKey: const ValueKey('putnik_email_field'),
          controller: V3TextUtils.emailController,
          label: 'Email adresa',
          hint: 'vašemail@example.com',
          icon: Icons.email,
          keyboardType: TextInputType.emailAddress,
          onSubmitted: (_) => _saveEmail(),
        );
      case _LoginStep.pin:
        return Column(
          children: [
            V3InputUtils.pinField(
              controller: V3TextUtils.pinController,
              label: 'PIN kod',
              hint: '• • • •',
              maxLength: 4,
              onSubmitted: (_) => _loginWithPin(),
            ),
            const SizedBox(height: 12),
            if (_biometricAvailable && _biometricEnabled) ...[
              OutlinedButton.icon(
                onPressed: _isLoading ? null : () => _loginWithBiometric(),
                icon: Icon(_biometricIcon, color: Colors.amber),
                label: Text(
                  'Prijava pomoću $_biometricTypeText',
                  style: const TextStyle(color: Colors.amber),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.amber),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                ),
              ),
              const SizedBox(height: 12),
            ],
            GestureDetector(
              onTap: _showForgotPinDialog,
              child: Text(
                'Zaboravio/la sam PIN',
                style: TextStyle(
                  color: Colors.amber.withValues(alpha: 0.9),
                  fontSize: 14,
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.amber.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        );
      case _LoginStep.zahtevPoslat:
        return _zahtevPoslatContent();
    }
  }

  void _onMainButton() {
    if (_currentStep == _LoginStep.telefon) {
      _checkTelefon();
    } else if (_currentStep == _LoginStep.email) {
      _saveEmail();
    } else if (_currentStep == _LoginStep.pin) {
      _loginWithPin();
    }
  }

  void _showForgotPinDialog() {
    V3DialogHelper.showCustomDialog<void>(
      context: context,
      title: 'Zaboravili ste PIN?',
      titleIcon: Icons.help_outline,
      backgroundColor: const Color(0xFF1a1a2e),
      content: const Text(
        'Možemo poslati zahtev adminu da vam dodeli novi PIN.',
        style: TextStyle(color: Colors.white70),
      ),
      actions: [
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.pop(context),
          text: 'Odustani',
          foregroundColor: Colors.grey,
        ),
        V3ButtonUtils.amberButton(
          onPressed: () {
            Navigator.pop(context);
            _sendPinRequest();
          },
          text: 'Zatraži novi PIN',
        ),
      ],
    );
  }

  Widget _stepIcon() {
    final icon = switch (_currentStep) {
      _LoginStep.telefon => Icons.phone_android,
      _LoginStep.email => Icons.email,
      _LoginStep.pin => Icons.lock,
      _LoginStep.zahtevPoslat => Icons.mark_email_read,
    };
    return Icon(icon, color: Colors.amber, size: 60);
  }

  Widget _stepTitle() {
    final title = switch (_currentStep) {
      _LoginStep.telefon => 'Prijava putnika',
      _LoginStep.email => 'Vaš email',
      _LoginStep.pin => 'Unesite PIN',
      _LoginStep.zahtevPoslat => 'Zahtev poslat',
    };
    return Text(title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold));
  }

  Widget _stepSubtitle() {
    final sub = switch (_currentStep) {
      _LoginStep.telefon => 'Unesite broj telefona sa kojim ste registrovani',
      _LoginStep.email => 'Potreban nam je vaš email za kontakt',
      _LoginStep.pin => 'Unesite svoj 4-cifreni PIN',
      _LoginStep.zahtevPoslat => 'Sačekajte odobrenje od admina',
    };
    return Text(sub,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14), textAlign: TextAlign.center);
  }

  Widget _stepIndicator() {
    final idx = _currentStep.index;
    dot(bool a) => V3ContainerUtils.iconContainer(
          width: 12,
          height: V3ContainerUtils.responsiveHeight(context, 12),
          backgroundColor: a ? Colors.amber : Colors.white.withValues(alpha: 0.3),
          borderRadiusGeometry: const BorderRadius.all(Radius.circular(6)),
        );
    line(bool a) => V3ContainerUtils.styledContainer(
          width: 40,
          height: V3ContainerUtils.responsiveHeight(context, 2, intensity: 0.2),
          backgroundColor: a ? Colors.amber : Colors.white.withValues(alpha: 0.3),
          child: const SizedBox(),
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        dot(idx >= 0),
        line(idx >= 1),
        dot(idx >= 1),
        line(idx >= 2),
        dot(idx >= 2),
        line(idx >= 3),
        dot(idx >= 3),
      ],
    );
  }

  Widget _infoBox(String msg, Color color) {
    return V3ContainerUtils.styledContainer(
      padding: const EdgeInsets.all(12),
      backgroundColor: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.5)),
      child: Row(
        children: [
          Icon(
            color == Colors.green ? Icons.check_circle_outline : Icons.error_outline,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: TextStyle(color: color, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _zahtevPoslatContent() {
    return V3ContainerUtils.styledContainer(
      padding: const EdgeInsets.all(24),
      backgroundColor: Colors.green.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 64),
          const SizedBox(height: 16),
          const Text(
            'Zahtev je poslat!',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Admin će pregledati vaš zahtev i dodeliti vam PIN.\nBićete obavešteni kada PIN bude spreman.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _infoHint() {
    final hint = switch (_currentStep) {
      _LoginStep.telefon => 'Unesite broj telefona koji ste dali prilikom registracije.',
      _LoginStep.email => 'Email koristimo za obaveštenja i komunikaciju sa adminom.',
      _LoginStep.pin => 'PIN ste dobili od admina. Ako ste ga zaboravili, koristite opciju ispod.',
      _LoginStep.zahtevPoslat => 'Možete zatvoriti aplikaciju. Obaveštavamo vas kada PIN bude dodeljen.',
    };
    return V3ContainerUtils.styledContainer(
      padding: const EdgeInsets.all(12),
      backgroundColor: Colors.white.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.white54, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(hint, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12))),
        ],
      ),
    );
  }
}
