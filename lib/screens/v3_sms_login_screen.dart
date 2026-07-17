import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/v3_adresa.dart';
import '../models/v3_putnik.dart';
import '../services/v3/v3_adresa_service.dart';
import '../services/v3/v3_closed_auth_service.dart';
import '../services/v3/v3_device_identity_service.dart';
import '../services/v3/v3_push_token_edge_service.dart';
import '../services/v3/v3_push_token_provider.dart';
import '../services/v3/v3_putnik_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../services/v3_biometric_service.dart';
import '../services/v3_locale_manager.dart';
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
  final _pinController = TextEditingController();
  final _pinConfirmController = TextEditingController();
  static const _secureStorage = FlutterSecureStorage();

  _SmsStep _step = _SmsStep.unosTelefona;
  bool _isLoading = false;
  String _statusMessage = '';
  String? _targetAuthId;
  String? _normalizedPhone;
  String _selectedTip = '';
  V3Adresa? _selectedBcAdresa;
  V3Adresa? _selectedVsAdresa;
  String? _missingProfileStaticMessageKey;
  List<String> _missingProfileFieldKeys = <String>[];
  bool _missingProfileUseRequiredTemplate = false;
  bool _addressOnlyOnboarding = false;
  bool _requireBcAddress = false;
  bool _requireVsAddress = false;
  bool _requirePin = false;
  bool _vozacPinOnlyOnboarding = false;
  bool _devicePinVerificationOnly = false;
  int _devicePinAttempts = 0;
  static const _maxDevicePinAttempts = 5;
  bool _isBackendReady = false;

  int? _minutesUntil(String? isoTimestamp) {
    if (isoTimestamp == null || isoTimestamp.isEmpty) return null;
    final target = DateTime.tryParse(isoTimestamp);
    if (target == null) return null;
    final diff = target.difference(DateTime.now());
    if (diff.isNegative) return null;
    final minutes = diff.inSeconds / 60;
    return minutes.ceil();
  }

  // ─── Lokalizacija ───────────────────────────────────────────────

  static const Map<String, Map<String, String>> _t = {
    'prijava': {'sr': 'Prijava', 'en': 'Login'},
    'unesitePhone': {'sr': 'Unesite broj telefona za prijavu.', 'en': 'Enter your phone number to log in.'},
    'povezivanje': {
      'sr': 'Povezivanje sa serverom u toku, sačekajte...',
      'en': 'Connecting to server, please wait...',
    },
    'brojTelefona': {'sr': 'Broj telefona', 'en': 'Phone number'},
    'nalepi': {'sr': 'Nalepi', 'en': 'Paste'},
    'nastavi': {'sr': 'Nastavi', 'en': 'Continue'},
    'ucitavanje': {'sr': 'Učitavanje...', 'en': 'Loading...'},
    'prijavaBiometrijom': {'sr': 'Prijava biometrijom', 'en': 'Log in with biometrics'},
    'biometrijaNijePodesena': {
      'sr': 'Biometrija nije podešena na uređaju. Uključite je u podešavanjima telefona.',
      'en': 'Biometrics is not set up on this device. Enable it in your phone settings.',
    },
    'sigurnosnaObavestenja': {
      'sr': 'Poštovani korisnici, zbog dodatnih bezbednosnih usklađivanja sa zahtevima platformi (Google Play i '
          'iOS), kao i završetka sertifikacionih procedura radi veće zaštite vaših podataka, produžen je period '
          'ograničene dostupnosti aplikacije. Ove mere su uvedene kako bi se smanjio rizik od zloupotreba, '
          'uključujući pokušaje phishing napada, krađe vaših podataka i neovlašćenog oglašavanja. Hvala vam na strpljenju i razumevanju.',
      'en': 'Dear users, due to additional security alignment with platform requirements (Google Play and iOS), '
          'as well as the completion of certification procedures for stronger data protection, the period of '
          'limited app availability has been extended. These measures were introduced to reduce the risk of '
          'misuse, including phishing attempts, data theft and unauthorized advertising. Thank you for your '
          'patience and understanding.',
    },
    'unesitePodatke': {'sr': 'Unesite podatke za nalog', 'en': 'Enter account details for'},
    'ime': {'sr': 'Ime', 'en': 'First name'},
    'prezime': {'sr': 'Prezime', 'en': 'Last name'},
    'kategorija': {'sr': 'Kategorija', 'en': 'Category'},
    'izaberiteKategoriju': {'sr': 'Izaberite kategoriju', 'en': 'Select category'},
    'radnik': {'sr': '👷 Radnik', 'en': '👷 Worker'},
    'ucenik': {'sr': '🎒 Učenik', 'en': '🎒 Student'},
    'dnevni': {'sr': '📅 Dnevni', 'en': '📅 Daily'},
    'posiljka': {'sr': '📦 Pošiljka', 'en': '📦 Parcel'},
    'adresaBc': {'sr': 'Adresa BC *', 'en': 'BC address *'},
    'adresaVs': {'sr': 'Adresa VS *', 'en': 'VS address *'},
    'noviPin': {'sr': 'Novi PIN kod (6 cifara) *', 'en': 'New PIN code (6 digits) *'},
    'unesitePin': {'sr': 'Unesite PIN kod (6 cifara) *', 'en': 'Enter PIN code (6 digits) *'},
    'ponoviPin': {'sr': 'Ponovi PIN kod *', 'en': 'Repeat PIN code *'},
    'sacuvajNastavi': {'sr': 'Sačuvaj i nastavi', 'en': 'Save and continue'},
    'adresaBcKratko': {'sr': 'adresa BC', 'en': 'BC address'},
    'adresaVsKratko': {'sr': 'adresa VS', 'en': 'VS address'},
    'pinKod': {'sr': 'PIN kod', 'en': 'PIN code'},
    'tip': {'sr': 'tip', 'en': 'category'},
    'dopunitePolja': {'sr': 'Dopunite', 'en': 'Please complete'},
    'daNastavite': {'sr': 'da nastavite.', 'en': 'to continue.'},
    'dopuniteObavezna': {'sr': 'Dopunite obavezna polja', 'en': 'Please complete required fields'},
    'potvrdaIdentiteta': {
      'sr': 'Za potvrdu identiteta unesite Vaš PIN kod (6 cifara).',
      'en': 'To confirm your identity, enter your PIN code (6 digits).',
    },
    'podesitePin': {
      'sr': 'Iz sigurnosnih razloga potrebno je da podesite PIN kod (6 cifara).',
      'en': 'For security reasons you need to set up a PIN code (6 digits).',
    },
    'imeKratko': {'sr': 'ime', 'en': 'name'},
    'kategorijuKratko': {'sr': 'kategoriju', 'en': 'category'},
    'deviceLimitReached': {
      'sr': '❌ Dostignut je limit od 2 uređaja po nalogu. Kontaktirajte admina.',
      'en': '❌ Device limit of 2 per account reached. Contact admin.',
    },
    'telefonNijeUparen': {
      'sr': '❌ Telefon nije uparen sa UUID nalogom.',
      'en': '❌ Phone is not paired with the account.',
    },
    'nisteUSistemu': {
      'sr': '❌ Aplikacija je zatvorenog tipa i Vi niste u sistemu. Kontaktirajte admina.',
      'en': '❌ This is a closed application and you are not in the system. Contact admin.',
    },
    'unosNijeKompletan': {
      'sr': '❌ Upis nije kompletan. Nedostaje:',
      'en': '❌ Entry is incomplete. Missing:',
    },
    'greskaCuvanjePin': {
      'sr': '❌ Greška pri čuvanju PIN koda. Pokušaj ponovo.',
      'en': '❌ Error saving PIN code. Please try again.',
    },
    'profilSacuvan': {'sr': '✅ Profil sačuvan.', 'en': '✅ Profile saved.'},
    'cuvanjeProfilaGreska': {
      'sr': '❌ Čuvanje profila trenutno nije moguće. Pokušajte ponovo.',
      'en': '❌ Saving profile is currently not possible. Please try again.',
    },
    'sesijaIstekla': {
      'sr': '❌ Sesija je istekla. Počni ponovo.',
      'en': '❌ Session expired. Please start again.',
    },
    'uuidNedostaje': {
      'sr': '❌ UUID naloga nedostaje. Prijavi se ponovo.',
      'en': '❌ Account UUID is missing. Please log in again.',
    },
    'prijavaNijeMoguca': {
      'sr': '❌ Prijava trenutno nije moguća. Pokušajte ponovo.',
      'en': '❌ Login is currently not possible. Please try again.',
    },
    'biometrijaNijeUspela': {
      'sr': '❌ Biometrijska autentifikacija nije uspela',
      'en': '❌ Biometric authentication failed',
    },
    'sacuvanTelefonNijeIspravan': {
      'sr': '❌ Sačuvan telefon nije ispravan. Prijavi se brojem telefona.',
      'en': '❌ Saved phone number is invalid. Please log in using your phone number.',
    },
    'brojNijePronadjen': {
      'sr': '❌ Broj telefona i UUID reda nisu pronađeni.',
      'en': '❌ Phone number and account UUID were not found.',
    },
    'uneseiteBrojTelefona': {'sr': 'Unesite broj telefona.', 'en': 'Enter your phone number.'},
    'proveravamBroj': {'sr': '🔍 Proveravam broj...', 'en': '🔍 Checking number...'},
    'zahtevGreska': {
      'sr': '❌ Trenutno ne možemo da obradimo zahtev. Pokušajte ponovo.',
      'en': '❌ We cannot process your request right now. Please try again.',
    },
    'pinNisuIsti': {'sr': 'PIN-ovi se ne poklapaju.', 'en': 'PIN codes do not match.'},
    'cuvamPin': {'sr': '💾 Čuvam PIN...', 'en': '💾 Saving PIN...'},
    'pinPodesen': {'sr': '✅ PIN je uspešno podešen.', 'en': '✅ PIN successfully set.'},
    'pinMora6Cifara': {'sr': 'PIN mora imati tačno 6 cifara.', 'en': 'PIN must be exactly 6 digits.'},
    'previseGreskihPokusaja': {
      'sr': '❌ Previše pogrešnih pokušaja. Kontaktirajte admina.',
      'en': '❌ Too many failed attempts. Please contact admin.',
    },
    'proveravamPin': {'sr': '🔐 Proveravam PIN...', 'en': '🔐 Verifying PIN...'},
    'previseGreskihPokusajaZa': {
      'sr': '❌ Previše pogrešnih pokušaja. Pokušajte ponovo za',
      'en': '❌ Too many failed attempts. Please try again in',
    },
    'pinNijeIspravanPreostalo': {
      'sr': '❌ PIN nije ispravan. Preostalo pokušaja:',
      'en': '❌ Incorrect PIN. Attempts remaining:',
    },
    'identitetUredjajaNedostupan': {
      'sr': '❌ Identitet uređaja nije dostupan.',
      'en': '❌ Device identity is not available.',
    },
    'pinPotvrdjenUredjaj': {
      'sr': '✅ PIN potvrđen. Uređaj je verifikovan.',
      'en': '✅ PIN confirmed. Device verified.',
    },
    'pinPotvrdaGreska': {
      'sr': '❌ PIN potvrda trenutno nije moguća. Pokušajte ponovo.',
      'en': '❌ PIN confirmation is currently not possible. Please try again.',
    },
    'uneseiteImePrezime': {'sr': 'Unesite ime i prezime.', 'en': 'Enter first and last name.'},
    'izaberiteTipPutnika': {'sr': 'Izaberite tip putnika.', 'en': 'Select passenger category.'},
    'izaberiteAdreseBcVs': {
      'sr': 'Izaberite po jednu adresu za BC i VS.',
      'en': 'Select one address each for BC and VS.',
    },
    'izaberiBcAdresu': {'sr': 'Izaberi BC adresu.', 'en': 'Select BC address.'},
    'izaberiVsAdresu': {'sr': 'Izaberi VS adresu.', 'en': 'Select VS address.'},
  };

  String _tr(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    return _t[key]?[code] ?? _t[key]?['sr'] ?? key;
  }

  String _buildMissingProfileMessage() {
    if (_missingProfileStaticMessageKey != null) {
      return _tr(_missingProfileStaticMessageKey!);
    }
    if (_missingProfileFieldKeys.isEmpty) {
      return '';
    }
    final translatedFields = _missingProfileFieldKeys.map(_tr).join(', ');
    if (_missingProfileUseRequiredTemplate) {
      return '${_tr('dopuniteObavezna')}: $translatedFields.';
    }
    return '${_tr('dopunitePolja')}: $translatedFields ${_tr('daNastavite')}';
  }

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
    _pinController.dispose();
    _pinConfirmController.dispose();
    super.dispose();
  }

  bool get _canSubmitPhoneStep => !_isLoading && _isBackendReady;

  Future<void> _waitForBackendReady() async {
    debugPrint('[V3SmsLogin] _waitForBackendReady started');
    while (mounted && !_isBackendReady) {
      final ready = await V3ClosedAuthService.ensureClientReady();
      debugPrint('[V3SmsLogin] ensureClientReady returned: $ready');
      if (!mounted) return;

      if (ready) {
        setState(() => _isBackendReady = true);
        debugPrint('[V3SmsLogin] _isBackendReady set to true');
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
        V3AppSnackBar.error(context, _tr('biometrijaNijeUspela'));
      }
      return;
    }

    final normalized = V3ClosedAuthService.normalizePhone(raw);
    if (normalized.isEmpty) {
      if (!silentFailure && mounted) {
        V3AppSnackBar.error(context, _tr('sacuvanTelefonNijeIspravan'));
      }
      return;
    }

    if (mounted) {
      setState(() => _normalizedPhone = normalized);
    }

    final authId = (await V3ClosedAuthService.findAuthIdByPhone(normalized) ?? '').trim();
    if (authId.isEmpty) {
      if (!silentFailure && mounted) {
        V3AppSnackBar.error(context, _tr('brojNijePronadjen'));
      }
      return;
    }

    if (mounted) {
      setState(() => _targetAuthId = authId);
    }

    if (!mounted) return;
    await _advanceAfterPhoneAuth(skipBiometricSave: true);
  }

  // ─── Korak 1: Proveri telefon + pošalji SMS ────────────────────

  Future<void> _sendSms() async {
    debugPrint(
        '[V3SmsLogin] _sendSms called, _canSubmitPhoneStep=$_canSubmitPhoneStep, _isLoading=$_isLoading, _isBackendReady=$_isBackendReady');
    if (!_canSubmitPhoneStep) {
      debugPrint('[V3SmsLogin] _sendSms blocked: _isLoading=$_isLoading, _isBackendReady=$_isBackendReady');
      return;
    }

    final input = _phoneController.text.trim();
    if (input.isEmpty) {
      V3AppSnackBar.warning(context, _tr('uneseiteBrojTelefona'));
      return;
    }

    final phone = V3ClosedAuthService.normalizePhone(input);
    if (phone.isEmpty) {
      V3AppSnackBar.warning(context, _tr('uneseiteBrojTelefona'));
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = _tr('proveravamBroj');
    });

    try {
      final authId = (await V3ClosedAuthService.findAuthIdByPhone(phone) ?? '').trim();
      if (authId.isEmpty) {
        if (!mounted) return;
        V3AppSnackBar.error(context, _tr('brojNijePronadjen'));
        setState(() => _statusMessage = '');
        return;
      }

      setState(() {
        _targetAuthId = authId;
        _normalizedPhone = phone;
        _statusMessage = '';
      });

      debugPrint('[V3SmsLogin] About to call _advanceAfterPhoneAuth');
      await _advanceAfterPhoneAuth();
      debugPrint('[V3SmsLogin] _advanceAfterPhoneAuth completed');
    } catch (e) {
      if (!mounted) return;
      debugPrint('[V3SmsLogin] _sendSms error: $e');
      V3AppSnackBar.error(context, _tr('zahtevGreska'));
      setState(() => _statusMessage = '');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _advanceAfterPhoneAuth({bool skipBiometricSave = false}) async {
    debugPrint('[V3SmsLogin] _advanceAfterPhoneAuth started');
    final phone = V3ClosedAuthService.normalizePhone(_normalizedPhone ?? '');
    final authId = (_targetAuthId ?? '').trim();
    debugPrint('[V3SmsLogin] phone empty: ${phone.isEmpty}, authId empty: ${authId.isEmpty}');
    if (phone.isEmpty) {
      if (mounted) {
        V3AppSnackBar.error(context, _tr('sesijaIstekla'));
        _resetToStep1();
      }
      return;
    }
    if (authId.isEmpty) {
      if (mounted) {
        V3AppSnackBar.error(context, _tr('uuidNedostaje'));
        _resetToStep1();
      }
      return;
    }

    debugPrint('[V3SmsLogin] Verifying device identity...');
    final deviceId = await V3DeviceIdentityService.getStableDeviceId();
    final hardwareId = await V3DeviceIdentityService.getHardwareId();
    final verification = await V3ClosedAuthService.verifyLogin(
      rawPhone: phone,
      expectedAuthId: authId,
      installationId: deviceId,
      hardwareId: hardwareId,
    );
    if (!verification.ok || !verification.deviceAllowed) {
      if (!mounted) return;
      if (verification.reason == 'device_pin_required') {
        setState(() {
          _isLoading = false;
          _addressOnlyOnboarding = true;
          _requireBcAddress = false;
          _requireVsAddress = false;
          _requirePin = true;
          _vozacPinOnlyOnboarding = false;
          _devicePinVerificationOnly = true;
          _devicePinAttempts = 0;
          _missingProfileStaticMessageKey = 'potvrdaIdentiteta';
          _missingProfileFieldKeys = <String>[];
          _missingProfileUseRequiredTemplate = false;
          _step = _SmsStep.unosProfila;
        });
        return;
      }
      if (verification.reason == 'device_limit_reached') {
        V3AppSnackBar.error(
          context,
          _tr('deviceLimitReached'),
        );
      } else {
        V3AppSnackBar.error(context, _tr('telefonNijeUparen'));
      }
      _resetToStep1();
      return;
    }

    debugPrint('[V3SmsLogin] Calling getActiveById...');
    final putnik = await V3PutnikService.getActiveById(authId);
    debugPrint('[V3SmsLogin] getActiveById returned: ${putnik != null ? 'data' : 'null'}');
    if (!mounted) return;

    if (putnik == null) {
      // Putnik nije pronađen - možda je vozač
      debugPrint('[V3SmsLogin] putnik is null, checking vozac...');
      var vozac = V3VozacService.getVozacById(authId);
      vozac ??= await V3VozacService.getVozacByIdDirect(authId);

      if (vozac == null) {
        debugPrint('[V3SmsLogin] vozac also null - user not in system');
        if (!mounted) return;
        V3AppSnackBar.error(
          context,
          _tr('nisteUSistemu'),
        );
        _resetToStep1();
        return;
      }

      if ((vozac.pinHash ?? '').trim().isEmpty) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _addressOnlyOnboarding = true;
          _requireBcAddress = false;
          _requireVsAddress = false;
          _requirePin = true;
          _vozacPinOnlyOnboarding = true;
          _devicePinVerificationOnly = false;
          _missingProfileStaticMessageKey = 'podesitePin';
          _missingProfileFieldKeys = <String>[];
          _missingProfileUseRequiredTemplate = false;
          _step = _SmsStep.unosProfila;
        });
        return;
      }

      debugPrint('[V3SmsLogin] calling onVerified for vozac');
      await widget.onVerified(phone, authId);
      return;
    }

    final missingIme = (putnik['ime_prezime']?.toString().trim() ?? '').isEmpty;
    final missingTip = (putnik['tip_putnika']?.toString().trim() ?? '').isEmpty;
    final missingBc = (putnik['adresa_bc_id']?.toString().trim() ?? '').isEmpty;
    final missingVs = (putnik['adresa_vs_id']?.toString().trim() ?? '').isEmpty;
    final missingPin = (putnik['pin_hash']?.toString().trim() ?? '').isEmpty;

    if (missingIme || missingTip || missingBc || missingVs || missingPin) {
      final bcId = putnik['adresa_bc_id']?.toString().trim() ?? '';
      final vsId = putnik['adresa_vs_id']?.toString().trim() ?? '';
      final existingIme = putnik['ime_prezime']?.toString().trim() ?? '';
      final existingTip = putnik['tip_putnika']?.toString().trim() ?? '';

      // Razdvoji ime i prezime ako postoje
      final imeParts = existingIme.split(' ');
      if (imeParts.isNotEmpty) {
        _imeController.text = imeParts.first;
        if (imeParts.length > 1) {
          _prezimeController.text = imeParts.sublist(1).join(' ');
        }
      }
      _selectedTip = existingTip;

      setState(() {
        _isLoading = false;
        _addressOnlyOnboarding = !missingIme && !missingTip;
        _requireBcAddress = missingBc;
        _requireVsAddress = missingVs;
        _requirePin = missingPin;
        _vozacPinOnlyOnboarding = false;
        _devicePinVerificationOnly = false;
        _selectedBcAdresa = bcId.isEmpty ? null : V3AdresaService.getAdresaById(bcId);
        _selectedVsAdresa = vsId.isEmpty ? null : V3AdresaService.getAdresaById(vsId);

        // Poruka na osnovu šta nedostaje
        final missingFieldKeys = <String>[];
        if (missingIme) missingFieldKeys.add('imeKratko');
        if (missingTip) missingFieldKeys.add('kategorijuKratko');
        if (missingBc) missingFieldKeys.add('adresaBcKratko');
        if (missingVs) missingFieldKeys.add('adresaVsKratko');
        if (missingPin) missingFieldKeys.add('pinKod');
        _missingProfileStaticMessageKey = null;
        _missingProfileFieldKeys = missingFieldKeys;
        _missingProfileUseRequiredTemplate = false;
        _step = _SmsStep.unosProfila;
      });
      return;
    }

    if (!mounted) return;
    await _finalize(skipBiometricSave: skipBiometricSave);
  }

  String? _trimToNull(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  V3Putnik _buildPutnikFromExistingRow(
    Map<String, dynamic> existing, {
    required String phoneFallback,
    String? imePrezimeOverride,
    String? tipPutnikaOverride,
    String? adresaBcIdOverride,
    String? adresaVsIdOverride,
  }) {
    final fallbackPhone = phoneFallback.trim();
    final existingPhone1 = _trimToNull(existing['telefon_1']);
    final overrideIme = (imePrezimeOverride ?? '').trim();
    final overrideTip = (tipPutnikaOverride ?? '').trim();

    return V3Putnik(
      id: existing['id']?.toString() ?? '',
      imePrezime: overrideIme.isNotEmpty ? overrideIme : (existing['ime_prezime']?.toString().trim() ?? ''),
      telefon1: existingPhone1 ?? (fallbackPhone.isEmpty ? null : fallbackPhone),
      telefon2: _trimToNull(existing['telefon_2']),
      tipPutnika: overrideTip.isNotEmpty ? overrideTip : ((existing['tip_putnika']?.toString().trim() ?? 'radnik')),
      adresaBcId: _trimToNull(adresaBcIdOverride) ?? _trimToNull(existing['adresa_bc_id']),
      adresaVsId: _trimToNull(adresaVsIdOverride) ?? _trimToNull(existing['adresa_vs_id']),
      adresaBcId2: _trimToNull(existing['adresa_bc_id_2']),
      adresaVsId2: _trimToNull(existing['adresa_vs_id_2']),
      cenaPoDanu: (existing['cena_po_danu'] as num?)?.toDouble() ?? 0.0,
      cenaPoPokupljenju: (existing['cena_po_pokupljenju'] as num?)?.toDouble() ?? 0.0,
      pushToken: _trimToNull(existing['push_token']),
      pushToken2: _trimToNull(existing['push_token_2']),
    );
  }

  Future<void> _saveVozacPinOnly({
    required String phone,
    required String authId,
  }) async {
    final pin = _pinController.text.trim();
    final pinConfirm = _pinConfirmController.text.trim();

    if (!V3ClosedAuthService.isValidPin(pin)) {
      V3AppSnackBar.warning(context, _tr('pinMora6Cifara'));
      return;
    }
    if (pin != pinConfirm) {
      V3AppSnackBar.warning(context, _tr('pinNisuIsti'));
      return;
    }
    if (phone.isEmpty || authId.isEmpty) {
      V3AppSnackBar.error(context, _tr('sesijaIstekla'));
      _resetToStep1();
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = _tr('cuvamPin');
    });

    final saved = await V3ClosedAuthService.setPin(v3AuthId: authId, pin: pin);
    if (!mounted) return;

    if (!saved) {
      V3AppSnackBar.error(context, _tr('greskaCuvanjePin'));
      setState(() {
        _isLoading = false;
        _statusMessage = '';
      });
      return;
    }

    V3AppSnackBar.success(context, _tr('pinPodesen'));
    await widget.onVerified(phone, authId);
  }

  Future<void> _saveDevicePinVerification({
    required String phone,
    required String authId,
  }) async {
    final pin = _pinController.text.trim();

    if (!V3ClosedAuthService.isValidPin(pin)) {
      V3AppSnackBar.warning(context, _tr('pinMora6Cifara'));
      return;
    }
    if (phone.isEmpty || authId.isEmpty) {
      V3AppSnackBar.error(context, _tr('sesijaIstekla'));
      _resetToStep1();
      return;
    }
    if (_devicePinAttempts >= _maxDevicePinAttempts) {
      V3AppSnackBar.error(
        context,
        _tr('previseGreskihPokusaja'),
      );
      _resetToStep1();
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = _tr('proveravamPin');
    });

    try {
      final result = await V3ClosedAuthService.verifyPin(v3AuthId: authId, pin: pin);
      if (!result.ok) {
        if (!mounted) return;
        _pinController.clear();
        _pinConfirmController.clear();

        if (result.reason == 'pin_locked') {
          final minutes = _minutesUntil(result.lockedUntil);
          V3AppSnackBar.error(
            context,
            '${_tr('previseGreskihPokusajaZa')}${minutes != null ? ' $minutes min' : ''}.',
          );
          _resetToStep1();
          return;
        }

        _devicePinAttempts++;
        final remaining = _maxDevicePinAttempts - _devicePinAttempts;
        if (remaining <= 0) {
          V3AppSnackBar.error(
            context,
            _tr('previseGreskihPokusaja'),
          );
          _resetToStep1();
          return;
        }
        V3AppSnackBar.error(context, '${_tr('pinNijeIspravanPreostalo')} $remaining.');
        setState(() {
          _statusMessage = '';
          _isLoading = false;
        });
        return;
      }

      final installationId = (await V3DeviceIdentityService.getStableDeviceId()).trim();
      final hardwareId = await V3DeviceIdentityService.getHardwareId();
      final pushTokenResult = await V3PushTokenProvider.getBestToken().timeout(
        const Duration(seconds: 10),
        onTimeout: () => null,
      );
      final pushToken = pushTokenResult?.token.trim() ?? '';
      final resolvedInstallationId = pushTokenResult?.installationId?.trim() ?? installationId;

      if (resolvedInstallationId.isEmpty) {
        if (!mounted) return;
        V3AppSnackBar.error(context, _tr('identitetUredjajaNedostupan'));
        setState(() {
          _statusMessage = '';
          _isLoading = false;
        });
        return;
      }

      await V3PushTokenEdgeService.writeLoginColumns(
        v3AuthId: authId,
        pushToken: pushToken,
        installationId: resolvedInstallationId,
        hardwareId: hardwareId,
        pinVerified: true,
      );

      if (!mounted) return;
      V3AppSnackBar.success(context, _tr('pinPotvrdjenUredjaj'));
      await widget.onVerified(phone, authId);
    } catch (e) {
      if (!mounted) return;
      debugPrint('[V3SmsLogin] _saveDevicePinVerification error: $e');
      V3AppSnackBar.error(context, _tr('pinPotvrdaGreska'));
      setState(() {
        _statusMessage = '';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveOnboarding() async {
    final phone = V3ClosedAuthService.normalizePhone(_normalizedPhone ?? '');
    final authId = (_targetAuthId ?? '').trim();

    if (_devicePinVerificationOnly) {
      await _saveDevicePinVerification(phone: phone, authId: authId);
      return;
    }

    if (_vozacPinOnlyOnboarding) {
      await _saveVozacPinOnly(phone: phone, authId: authId);
      return;
    }

    final ime = _imeController.text.trim();
    final prezime = _prezimeController.text.trim();
    final fullName = '$ime $prezime'.trim();

    if (!_addressOnlyOnboarding) {
      if (ime.isEmpty || prezime.isEmpty) {
        V3AppSnackBar.warning(context, _tr('uneseiteImePrezime'));
        return;
      }

      if (_selectedTip.isEmpty) {
        V3AppSnackBar.warning(context, _tr('izaberiteTipPutnika'));
        return;
      }

      if (_selectedBcAdresa == null || _selectedVsAdresa == null) {
        V3AppSnackBar.warning(context, _tr('izaberiteAdreseBcVs'));
        return;
      }
    } else {
      if (_requireBcAddress && _selectedBcAdresa == null) {
        V3AppSnackBar.warning(context, _tr('izaberiBcAdresu'));
        return;
      }
      if (_requireVsAddress && _selectedVsAdresa == null) {
        V3AppSnackBar.warning(context, _tr('izaberiVsAdresu'));
        return;
      }
    }

    if (_requirePin) {
      final pin = _pinController.text.trim();
      final pinConfirm = _pinConfirmController.text.trim();
      if (!V3ClosedAuthService.isValidPin(pin)) {
        V3AppSnackBar.warning(context, _tr('pinMora6Cifara'));
        return;
      }
      if (pin != pinConfirm) {
        V3AppSnackBar.warning(context, _tr('pinNisuIsti'));
        return;
      }
    }

    if (phone.isEmpty) {
      V3AppSnackBar.error(context, _tr('sesijaIstekla'));
      _resetToStep1();
      return;
    }

    if (authId.isEmpty) {
      V3AppSnackBar.error(context, _tr('sesijaIstekla'));
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
        V3AppSnackBar.error(context,
            '❌ Niste dobili odobrenje za korišćenje aplikacije. Molimo pošaljite poruku adminu sa sledećim podacima: ime, prezime, broj telefona.');
        _resetToStep1();
        return;
      }

      final existingBcId = existing['adresa_bc_id']?.toString().trim() ?? '';
      final existingVsId = existing['adresa_vs_id']?.toString().trim() ?? '';

      final targetBcId = _addressOnlyOnboarding
          ? (_requireBcAddress ? (_selectedBcAdresa?.id ?? '') : existingBcId)
          : (_selectedBcAdresa?.id ?? '');
      final targetVsId = _addressOnlyOnboarding
          ? (_requireVsAddress ? (_selectedVsAdresa?.id ?? '') : existingVsId)
          : (_selectedVsAdresa?.id ?? '');

      final putnik = _buildPutnikFromExistingRow(
        existing,
        phoneFallback: phone,
        imePrezimeOverride: _addressOnlyOnboarding ? null : fullName,
        tipPutnikaOverride: _addressOnlyOnboarding ? null : _selectedTip,
        adresaBcIdOverride: targetBcId,
        adresaVsIdOverride: targetVsId,
      );

      await V3PutnikService.addUpdatePutnik(putnik);

      if (_requirePin) {
        final pinSaved = await V3ClosedAuthService.setPin(
          v3AuthId: authId,
          pin: _pinController.text.trim(),
        );
        if (!pinSaved) {
          if (!mounted) return;
          V3AppSnackBar.error(context, _tr('greskaCuvanjePin'));
          setState(() => _statusMessage = '');
          return;
        }
      }

      final refreshed = await V3PutnikService.getActiveById(authId);
      final missingAfterSave = _missingRequiredProfileFields(
        refreshed,
        includeIdentityFields: !_addressOnlyOnboarding,
      );
      if (missingAfterSave.isNotEmpty) {
        if (!mounted) return;
        final translatedMissing = missingAfterSave.map(_tr).join(', ');
        V3AppSnackBar.error(context, '${_tr('unosNijeKompletan')} $translatedMissing.');
        setState(() {
          _missingProfileStaticMessageKey = null;
          _missingProfileFieldKeys = missingAfterSave;
          _missingProfileUseRequiredTemplate = true;
          _statusMessage = '';
        });
        return;
      }

      if (!mounted) return;

      V3AppSnackBar.success(context, _tr('profilSacuvan'));
      await _finalize();
      if (mounted) {
        setState(() => _statusMessage = '');
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('[V3SmsLogin] _saveOnboarding error: $e');
      V3AppSnackBar.error(context, _tr('cuvanjeProfilaGreska'));
      setState(() => _statusMessage = '');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Finalizacija ──────────────────────────────────────────────

  Future<void> _finalize({bool skipBiometricSave = false}) async {
    try {
      final phone = V3ClosedAuthService.normalizePhone(_normalizedPhone ?? '');
      final authId = (_targetAuthId ?? '').trim();
      if (phone.isEmpty) {
        V3AppSnackBar.error(context, _tr('sesijaIstekla'));
        _resetToStep1();
        return;
      }

      if (authId.isEmpty) {
        V3AppSnackBar.error(context, _tr('uuidNedostaje'));
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

      await widget.onVerified(phone, authId);
    } catch (e) {
      if (!mounted) return;
      debugPrint('[V3SmsLogin] _finalize error: $e');
      V3AppSnackBar.error(context, _tr('prijavaNijeMoguca'));
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
      _missingProfileStaticMessageKey = null;
      _missingProfileFieldKeys = <String>[];
      _missingProfileUseRequiredTemplate = false;
      _addressOnlyOnboarding = false;
      _requireBcAddress = false;
      _requireVsAddress = false;
      _requirePin = false;
      _vozacPinOnlyOnboarding = false;
      _devicePinVerificationOnly = false;
      _devicePinAttempts = 0;
      _statusMessage = '';
    });
  }

  List<String> _missingRequiredProfileFields(
    Map<String, dynamic>? putnik, {
    bool includeIdentityFields = true,
  }) {
    if (putnik == null) {
      return includeIdentityFields
          ? ['imeKratko', 'tip', 'adresaBcKratko', 'adresaVsKratko', 'pinKod']
          : ['adresaBcKratko', 'adresaVsKratko', 'pinKod'];
    }

    final missing = <String>[];
    final ime = putnik['ime_prezime']?.toString().trim() ?? '';
    final tip = putnik['tip_putnika']?.toString().trim() ?? '';
    final bc = putnik['adresa_bc_id']?.toString().trim() ?? '';
    final vs = putnik['adresa_vs_id']?.toString().trim() ?? '';
    final pinHash = putnik['pin_hash']?.toString().trim() ?? '';

    if (includeIdentityFields) {
      if (ime.isEmpty) missing.add('imeKratko');
      if (tip.isEmpty) missing.add('tip');
    }
    if (bc.isEmpty) missing.add('adresaBcKratko');
    if (vs.isEmpty) missing.add('adresaVsKratko');
    if (pinHash.isEmpty) missing.add('pinKod');
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
            widget.title.trim().toLowerCase() == 'prijava' ? _tr('prijava') : widget.title,
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
                Text(
                  _tr('biometrijaNijePodesena'),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
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
          icon: _isBackendReady ? Icons.sms_outlined : Icons.hourglass_top,
          text: _isBackendReady ? _tr('unesitePhone') : _tr('povezivanje'),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          enabled: !_isLoading,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: _tr('brojTelefona'),
            hintText: '06x xxx xxxx',
            labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.1),
            prefixIcon: const Icon(Icons.phone, color: Colors.amber),
            suffixIcon: IconButton(
              tooltip: _tr('nalepi'),
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
          text: _isBackendReady ? _tr('nastavi') : _tr('ucitavanje'),
          icon: _isBackendReady ? Icons.send : Icons.hourglass_empty,
          isLoading: !_isBackendReady || _isLoading,
          onPressed: _canSubmitPhoneStep ? _sendSms : null,
        ),
        if (_biometricEnabled && _biometricChecked && _biometricAvailable && _hasSavedCredentials) ...[
          const SizedBox(height: 10),
          V3ButtonUtils.amberButton(
            text: _tr('prijavaBiometrijom'),
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
                _tr('sigurnosnaObavestenja'),
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
    final hideProfileFields = _vozacPinOnlyOnboarding || _devicePinVerificationOnly;
    final showIdentityFields = !_addressOnlyOnboarding && !hideProfileFields;
    final showBcDropdown = (!_addressOnlyOnboarding || _requireBcAddress) && !hideProfileFields;
    final showVsDropdown = (!_addressOnlyOnboarding || _requireVsAddress) && !hideProfileFields;

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

    final missingProfileMessage = _buildMissingProfileMessage();

    return Column(
      key: const ValueKey('profile'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInfoBox(
          icon: Icons.person_outline,
          text: missingProfileMessage.isEmpty ? '${_tr('unesitePodatke')} ($_normalizedPhone).' : missingProfileMessage,
        ),
        const SizedBox(height: 24),
        if (showIdentityFields) ...[
          TextField(
            controller: _imeController,
            enabled: !_isLoading,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: _tr('ime'),
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
              labelText: _tr('prezime'),
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
              labelText: _tr('kategorija'),
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
            items: [
              DropdownMenuItem(value: '', child: Text(_tr('izaberiteKategoriju'))),
              DropdownMenuItem(value: 'radnik', child: Text(_tr('radnik'))),
              DropdownMenuItem(value: 'ucenik', child: Text(_tr('ucenik'))),
              DropdownMenuItem(value: 'dnevni', child: Text(_tr('dnevni'))),
              DropdownMenuItem(value: 'posiljka', child: Text(_tr('posiljka'))),
            ],
            onChanged: _isLoading
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => _selectedTip = value);
                  },
          ),
          const SizedBox(height: 12),
        ],
        if (showBcDropdown) ...[
          V3ContainerUtils.gradientContainer(
            gradient: Theme.of(context).backgroundGradient,
            borderRadius: BorderRadius.circular(12),
            child: DropdownButtonFormField<V3Adresa>(
              value: _selectedBcAdresa,
              isExpanded: true,
              dropdownColor: const Color(0xFF1E1E1E),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: _tr('adresaBc'),
                labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                filled: true,
                fillColor: Colors.transparent,
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
          ),
          const SizedBox(height: 12),
        ],
        if (showVsDropdown) ...[
          V3ContainerUtils.gradientContainer(
            gradient: Theme.of(context).backgroundGradient,
            borderRadius: BorderRadius.circular(12),
            child: DropdownButtonFormField<V3Adresa>(
              value: _selectedVsAdresa,
              isExpanded: true,
              dropdownColor: const Color(0xFF1E1E1E),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: _tr('adresaVs'),
                labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                filled: true,
                fillColor: Colors.transparent,
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
          ),
          const SizedBox(height: 12),
        ],
        if (_requirePin) ...[
          TextField(
            controller: _pinController,
            enabled: !_isLoading,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: _devicePinVerificationOnly ? _tr('unesitePin') : _tr('noviPin'),
              labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.1),
              prefixIcon: const Icon(Icons.lock_outline, color: Colors.amber),
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
          if (!_devicePinVerificationOnly) ...[
            TextField(
              controller: _pinConfirmController,
              enabled: !_isLoading,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: _tr('ponoviPin'),
                labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.1),
                prefixIcon: const Icon(Icons.lock_reset_outlined, color: Colors.amber),
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
          ],
        ],
        if (_statusMessage.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildStatusMessage(_statusMessage),
        ],
        const SizedBox(height: 24),
        V3ButtonUtils.primaryButton(
          text: _tr('sacuvajNastavi'),
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
