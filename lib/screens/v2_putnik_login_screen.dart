import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../globals.dart';
import '../services/realtime/v2_master_realtime_manager.dart';
import '../services/v2_biometric_service.dart';
import '../services/v2_pin_zahtev_service.dart';
import '../services/v2_push_token_service.dart'; // V2PutnikPushService spojen ovde
import '../services/v2_realtime_notification_service.dart';
import '../services/v2_statistika_istorija_service.dart';
import '../theme.dart';
import 'v2_putnik_profil_screen.dart';

class V2PutnikLoginScreen extends StatefulWidget {
  const V2PutnikLoginScreen({super.key});

  @override
  State<V2PutnikLoginScreen> createState() => _V2PutnikLoginScreenState();
}

enum _LoginStep { telefon, email, pin, izborPutnika, zahtevPoslat }

class _V2PutnikLoginScreenState extends State<V2PutnikLoginScreen> {
  final _telefonController = TextEditingController();
  final _emailController = TextEditingController();
  final _pinController = TextEditingController();

  _LoginStep _currentStep = _LoginStep.telefon;
  bool _isLoading = false;
  String? _errorMessage;
  String? _infoMessage;

  // Podaci o pronadenom putniku
  Map<String, dynamic>? _putnikData;
  // Lista mogucih putnika (kod deljenih brojeva/pina)
  List<Map<String, dynamic>>? _putnikCandidates;

  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  String _biometricTypeText = 'otisak prsta';

  // Pretplata na push notifikacije — čeka odobrenje PIN-a
  StreamSubscription<Map<String, dynamic>>? _pinOdobrenSub;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
    _checkSavedLogin();
  }

  /// Proveri dostupnost biometrije
  Future<void> _checkBiometric() async {
    final available = await V2BiometricService.isBiometricAvailable();
    final enabled = await V2BiometricService.isBiometricEnabled();
    final typeText = await V2BiometricService.getBiometricTypeText();

    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricEnabled = enabled;
        _biometricTypeText = typeText;
      });
    }
  }

  /// Proveri da li je V2Putnik vec ulogovan
  Future<void> _checkSavedLogin() async {
    if (_biometricAvailable && _biometricEnabled) {
      final credentials = await V2BiometricService.getSavedCredentials();
      if (credentials != null) {
        // Pokušaj biometrijsku autentifikaciju
        final authenticated = await V2BiometricService.authenticate(
          reason: 'Prijavite se pomocu $_biometricTypeText',
        );

        if (authenticated && mounted) {
          // Ako je obavezno ažuriranje aktivno — ne raditi auto-login
          if (updateInfoNotifier.value?.isForced == true) return;
          _telefonController.text = credentials['phone']!;
          _pinController.text = credentials['pin']!;
          if (!mounted) return;
          await _loginWithPin(showBiometricPrompt: false);
          return;
        }
      }
    }

    // Fallback na SharedPreferences auto-login
    final prefs = await SharedPreferences.getInstance();
    final savedPhone = prefs.getString('registrovani_putnik_telefon');
    final savedPin = prefs.getString('registrovani_putnik_pin');

    if (savedPhone != null && savedPhone.isNotEmpty && savedPin != null && savedPin.isNotEmpty) {
      // Ako je obavezno ažuriranje aktivno — ne raditi auto-login
      if (updateInfoNotifier.value?.isForced == true) return;
      // Automatski probaj login
      _telefonController.text = savedPhone;
      _pinController.text = savedPin;
      if (!mounted) return;
      await _loginWithPin(showBiometricPrompt: true);
    }
  }

  /// Normalizuje broj telefona za poredenje
  static String _normalizePhone(String telefon) {
    var cleaned = telefon.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (cleaned.startsWith('+381')) {
      cleaned = '0${cleaned.substring(4)}';
    } else if (cleaned.startsWith('00381')) {
      cleaned = '0${cleaned.substring(5)}';
    }
    return cleaned;
  }

  /// Korak 1: Proveri telefon
  Future<void> _checkTelefon() async {
    final telefon = _telefonController.text.trim();

    if (telefon.isEmpty) {
      setState(() => _errorMessage = 'Unesite broj telefona');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      // Traži putnika po telefonu kroz sve v2_ tabele
      final response = await V2MasterRealtimeManager.instance.v2FindByTelefon(telefon);

      if (response != null) {
        _putnikData = Map<String, dynamic>.from(response);

        final email = response['email'] as String?;
        final pin = response['pin'] as String?;

        if (email == null || email.isEmpty) {
          // Nema email - traži ga
          setState(() {
            _currentStep = _LoginStep.email;
            _infoMessage = 'Pronadeni ste! Unesite email za kontakt.';
          });
        } else if (pin == null || pin.isEmpty) {
          // Ima email ali nema PIN
          final imaZahtev = await V2PinZahtevService.imaZahtevKojiCekuAsync(response['id']);
          if (imaZahtev) {
            setState(() {
              _currentStep = _LoginStep.zahtevPoslat;
              _infoMessage = 'Vaš zahtev za PIN je vec poslat. Molimo sacekajte da admin odobri.';
            });
            _listenForPinOdobren();
          } else {
            // Ponudi da pošalje zahtev
            _showPinRequestDialog();
          }
        } else {
          // Ima i email i PIN - traži PIN za login
          setState(() {
            _currentStep = _LoginStep.pin;
            _infoMessage = 'Unesite svoj 4-cifreni PIN';
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Niste pronadeni u sistemu.\nKontaktirajte admina za registraciju.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Greška pri povezivanju: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Korak 2: Sacuvaj email i proveri dalje
  Future<void> _saveEmail() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      setState(() => _errorMessage = 'Unesite email adresu');
      return;
    }

    // Validacija email formata (strožija)
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(email)) {
      setState(() => _errorMessage = 'Unesite validnu email adresu');
      return;
    }

    // Dodatne provere za ocigledne gluposti
    final emailLower = email.toLowerCase();
    final localPart = emailLower.split('@')[0]; // deo pre @
    final domainPart = emailLower.split('@')[1]; // deo posle @

    // Blokiraj prekratke delove (aaa@aaa.aa)
    if (localPart.length < 3 || domainPart.split('.')[0].length < 3) {
      setState(() => _errorMessage = 'Email adresa je previše kratka');
      return;
    }

    // Blokiraj ponavljajuce karaktere (aaa@, bbb@, 111@)
    if (RegExp(r'^(.)\1{2,}').hasMatch(localPart)) {
      setState(() => _errorMessage = 'Unesite stvarnu email adresu');
      return;
    }

    // Blokiraj test/fake domene
    final fakeDomains = ['test.com', 'fake.com', 'example.com', 'asdf.com', 'qwer.com', 'aaa.com', 'bbb.com'];
    if (fakeDomains.any((d) => domainPart == d)) {
      setState(() => _errorMessage = 'Unesite stvarnu email adresu');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final putnikId = _putnikData!['id'] as String;
      final putnikTabela = _putnikData!['_tabela'] as String? ?? 'v2_radnici';

      // Sacuvaj email u bazi
      final success = await V2PinZahtevService.azurirajEmail(
        putnikId: putnikId,
        email: email,
        putnikTabela: putnikTabela,
      );

      if (success) {
        _putnikData!['email'] = email;

        final pin = _putnikData!['pin'] as String?;
        if (pin == null || pin.isEmpty) {
          // Nema PIN - ponudi da pošalje zahtev
          _showPinRequestDialog();
        } else {
          // Ima PIN - idi na unos PIN-a
          setState(() {
            _currentStep = _LoginStep.pin;
            _infoMessage = 'Email sacuvan! Unesite svoj 4-cifreni PIN';
          });
        }
      } else {
        setState(() => _errorMessage = 'Greška pri cuvanju email-a');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Greška: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Prikaži dialog za slanje zahteva za PIN
  void _showPinRequestDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.vpn_key, color: Colors.amber),
            SizedBox(width: 8),
            Expanded(
              child: Text('PIN nije dodeljen', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        content: const Text(
          'Nemate dodeljeni PIN za pristup.\n\nželite li da pošaljete zahtev adminu za dodelu PIN-a?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              Navigator.pop(context); // Vrati na pocetni ekran
            },
            child: const Text('Odustani', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              _sendPinRequest();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            child: const Text('Pošalji zahtev', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  /// Pošalji zahtev za PIN
  Future<void> _sendPinRequest() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final putnikId = _putnikData!['id'] as String;
      final email = _putnikData!['email'] as String? ?? _emailController.text.trim();
      final telefon = _putnikData!['telefon'] as String? ?? _telefonController.text.trim();
      final putnikTabela = _putnikData!['_tabela'] as String?;

      final success = await V2PinZahtevService.posaljiZahtev(
        putnikId: putnikId,
        email: email,
        telefon: telefon,
        putnikTabela: putnikTabela,
      );

      if (success) {
        setState(() {
          _currentStep = _LoginStep.zahtevPoslat;
          _infoMessage = 'Zahtev je uspešno poslat! Admin ce vam dodeliti PIN.';
        });
        _listenForPinOdobren();
      } else {
        setState(() => _errorMessage = 'Greška pri slanju zahteva');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Greška: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Slušaj push notifikacije dok je putnik na zahtevPoslat ekranu
  void _listenForPinOdobren() {
    _pinOdobrenSub?.cancel();
    final putnikId = _putnikData?['id'] as String?;
    _pinOdobrenSub = V2RealtimeNotificationService.notificationStream.listen((data) {
      if (!mounted) return;
      final type = data['type'] as String?;
      final noId = data['putnik_id'] as String?;
      if (type == 'pin_odobren' && (putnikId == null || noId == putnikId)) {
        _pinOdobrenSub?.cancel();
        _pinOdobrenSub = null;
        setState(() {
          _currentStep = _LoginStep.pin;
          _infoMessage = '✅ PIN je dodeljen! Unesite PIN koji ste dobili.';
          _errorMessage = null;
        });
      }
    });
  }

  /// Korak 3: Login sa PIN-om
  Future<void> _loginWithPin({bool showBiometricPrompt = true}) async {
    final telefon = _telefonController.text.trim();
    final pin = _pinController.text.trim();

    if (pin.isEmpty) {
      setState(() => _errorMessage = 'Unesite PIN');
      return;
    }

    if (pin.length != 4) {
      setState(() => _errorMessage = 'PIN mora imati 4 cifre');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final normalizedInput = _normalizePhone(telefon);

      // Traži putnika po PIN-u kroz sve v2_ tabele, pa filtriraj po telefonu
      final tabele = ['v2_radnici', 'v2_ucenici', 'v2_dnevni', 'v2_posiljke'];
      List<Map<String, dynamic>> matches = [];
      for (final tabela in tabele) {
        final found = await V2MasterRealtimeManager.instance.v2GetByPin(pin, tabela);
        if (found != null) {
          final storedPhone = found['telefon'] as String? ?? '';
          if (_normalizePhone(storedPhone) == normalizedInput) {
            matches.add(found);
          }
        }
      }

      if (matches.length > 1) {
        // Postoji više putnika na istom broju i PIN-u (npr. radnici koriste broj vlasnika)
        setState(() {
          _putnikCandidates = matches;
          _currentStep = _LoginStep.izborPutnika;
          _infoMessage = 'Pronadeno je više korisnika na ovom broju. Izaberite svoj profil:';
        });
        return;
      }

      final response = matches.isNotEmpty ? matches.first : null;

      if (response != null) {
        await _performLogin(response, telefon, pin, showBiometricPrompt);
      } else {
        setState(() {
          _errorMessage = 'Pogrešan PIN ili broj telefona. Pokušajte ponovo.';
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Greška pri povezivanju: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Pomocna funkcija za izVrsavanje logina nakon uspešne identifikacije
  Future<void> _performLogin(
    Map<String, dynamic> response,
    String telefon,
    String pin,
    bool showBiometricPrompt,
  ) async {
    try {
      // Sacuvaj za auto-login
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('registrovani_putnik_telefon', telefon);
      await prefs.setString('registrovani_putnik_pin', pin);

      final putnikId = response['id'];
      final putnikIme = response['putnik_ime'] ?? response['ime_prezime'] ?? 'Putnik';

      if (putnikId != null) {
        await prefs.setString('registrovani_putnik_id', putnikId.toString());
        await prefs.setString('registrovani_putnik_ime', putnikIme.toString());
      }

      if (putnikId != null) {
        final tabela = response['_tabela'] as String? ?? response['putnik_tabela'] as String?;
        await V2PutnikPushService.registerPutnikToken(putnikId, putnikTabela: tabela);
        unawaited(V2StatistikaIstorijaService.logGeneric(
          tip: 'login',
          putnikId: putnikId.toString(),
          detalji: 'Putnik se prijavio (PIN)',
        ));
      }
      if (showBiometricPrompt && _biometricAvailable && !_biometricEnabled && mounted) {
        await _showBiometricSetupDialog(telefon, pin);
      }

      if (mounted) {
        // Idi na profil ekran — ukloni ceo stack da back ne vraća na login/welcome
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => V2PutnikProfilScreen(
              putnikData: response,
            ),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      setState(() => _errorMessage = 'Greška pri prijavi: $e');
    }
  }

  /// Ponudi setup biometrijske prijave
  Future<void> _showBiometricSetupDialog(String phone, String pin) async {
    final biometricIcon = await V2BiometricService.getBiometricIcon();

    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Text(biometricIcon, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Brza prijava?',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: Text(
          'želite li ubuduce da se prijavljujete pomocu $_biometricTypeText?\n\nNecete morati da unosite PIN svaki put.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Ne, hvala', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            child: Text('Ukljuci $_biometricTypeText', style: const TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (result == true) {
      await V2BiometricService.saveCredentials(phone: phone, pin: pin);
      _biometricEnabled = true;
    }
  }

  @override
  void dispose() {
    _pinOdobrenSub?.cancel();
    _telefonController.dispose();
    _emailController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: Theme.of(context).backgroundGradient,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
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
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                Icon(
                  _getStepIcon(),
                  color: Colors.amber,
                  size: 60,
                ),
                const SizedBox(height: 16),
                Text(
                  _getStepTitle(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _getStepSubtitle(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                _buildStepIndicator(),
                const SizedBox(height: 24),
                if (_infoMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _infoMessage!,
                            style: const TextStyle(color: Colors.green, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                _buildStepContent(),
                const SizedBox(height: 16),
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_currentStep != _LoginStep.zahtevPoslat)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _getStepAction(),
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
                          : Text(
                              _getStepButtonText(),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                if (_currentStep == _LoginStep.zahtevPoslat) ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.amber),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '⬅️ Nazad na pocetnu',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.white54, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _getInfoText(),
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
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

  Widget _buildStepIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildStepDot(0, _currentStep.index >= 0),
        _buildStepLine(_currentStep.index >= 1),
        _buildStepDot(1, _currentStep.index >= 1),
        _buildStepLine(_currentStep.index >= 2),
        _buildStepDot(2, _currentStep.index >= 2),
      ],
    );
  }

  static Widget _buildStepDot(int _, bool active) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? Colors.amber : Colors.white.withValues(alpha: 0.3),
      ),
    );
  }

  static Widget _buildStepLine(bool active) {
    return Container(
      width: 40,
      height: 2,
      color: active ? Colors.amber : Colors.white.withValues(alpha: 0.3),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case _LoginStep.telefon:
        return _buildTelefonInput();
      case _LoginStep.email:
        return _buildEmailInput();
      case _LoginStep.pin:
        return _buildPinInput();
      case _LoginStep.izborPutnika:
        return _buildIzborPutnikaContent();
      case _LoginStep.zahtevPoslat:
        return _buildZahtevPoslatContent();
    }
  }

  Widget _buildIzborPutnikaContent() {
    if (_putnikCandidates == null) return const SizedBox();

    return Column(
      children: _putnikCandidates!.map((p) {
        final ime = p['putnik_ime'] as String? ?? 'Nepoznat';
        final tip = p['tip'] as String? ?? '';

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _performLogin(
                p,
                _telefonController.text.trim(),
                _pinController.text.trim(),
                true,
              ),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.amber,
                      child: Text(
                        ime.substring(0, 1).toUpperCase(),
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ime,
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            tip.toUpperCase(),
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.amber),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTelefonInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: TextField(
        controller: _telefonController,
        style: const TextStyle(color: Colors.white, fontSize: 18),
        keyboardType: TextInputType.phone,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          hintText: '06x xxx xxxx',
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
          prefixIcon: const Icon(Icons.phone, color: Colors.amber),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        onSubmitted: (_) => _checkTelefon(),
      ),
    );
  }

  Widget _buildEmailInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: TextField(
        controller: _emailController,
        style: const TextStyle(color: Colors.white, fontSize: 18),
        keyboardType: TextInputType.emailAddress,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          hintText: 'vašemail@example.com',
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
          prefixIcon: const Icon(Icons.email, color: Colors.amber),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        onSubmitted: (_) => _saveEmail(),
      ),
    );
  }

  Widget _buildPinInput() {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
          ),
          child: TextField(
            controller: _pinController,
            style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 4,
            obscureText: true,
            decoration: InputDecoration(
              hintText: '• • • •',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), letterSpacing: 8),
              prefixIcon: const Icon(Icons.lock, color: Colors.amber),
              border: InputBorder.none,
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            onSubmitted: (_) => _loginWithPin(),
          ),
        ),
        const SizedBox(height: 16),
        if (_biometricAvailable && _biometricEnabled)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlinedButton.icon(
              onPressed: _loginWithBiometric,
              icon: const Icon(Icons.fingerprint, size: 28),
              label: Text('Prijavi se pomocu $_biometricTypeText'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.amber,
                side: const BorderSide(color: Colors.amber),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
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
  }

  /// Login sa biometrijom
  Future<void> _loginWithBiometric() async {
    final credentials = await V2BiometricService.getSavedCredentials();
    if (credentials == null) {
      setState(() => _errorMessage = 'Nema sacuvanih podataka za biometrijsku prijavu');
      return;
    }

    final authenticated = await V2BiometricService.authenticate(
      reason: 'Prijavite se pomocu $_biometricTypeText',
    );

    if (authenticated && mounted) {
      _telefonController.text = credentials['phone']!;
      _pinController.text = credentials['pin']!;
      await _loginWithPin(showBiometricPrompt: false);
    }
  }

  /// Dialog za zaboravljen PIN
  void _showForgotPinDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Colors.amber),
            SizedBox(width: 8),
            Text('Zaboravili ste PIN?', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'Možemo poslati zahtev adminu da vam dodeli novi PIN.\n\nNakon što admin odobri zahtev, moci cete da se prijavite sa novim PIN-om.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Odustani', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              _sendPinResetRequest();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            child: const Text('Zatraži novi PIN', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  /// Pošalji zahtev za reset PIN-a
  Future<void> _sendPinResetRequest() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final putnikId = _putnikData!['id'] as String;
      final email = _putnikData!['email'] as String? ?? '';
      final telefon = _putnikData!['telefon'] as String? ?? _telefonController.text.trim();
      final putnikTabela = _putnikData!['_tabela'] as String?;

      final imaZahtev = await V2PinZahtevService.imaZahtevKojiCekuAsync(putnikId);
      if (imaZahtev) {
        setState(() {
          _currentStep = _LoginStep.zahtevPoslat;
          _infoMessage = 'Vec ste poslali zahtev za PIN. Molimo sacekajte da admin odobri.';
        });
        _listenForPinOdobren();
        return;
      }

      final success = await V2PinZahtevService.posaljiZahtev(
        putnikId: putnikId,
        email: email,
        telefon: telefon,
        putnikTabela: putnikTabela,
      );

      if (success) {
        setState(() {
          _currentStep = _LoginStep.zahtevPoslat;
          _infoMessage = 'Zahtev za novi PIN je uspešno poslat! Admin ce vam dodeliti novi PIN.';
        });
        _listenForPinOdobren();
      } else {
        setState(() => _errorMessage = 'Greška pri slanju zahteva. Pokušajte ponovo.');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Greška: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildZahtevPoslatContent() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Zahtev je poslat!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Admin ce pregledati vaš zahtev i dodeliti vam PIN.\nBicete obavešteni kada PIN bude spreman.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _getStepIcon() {
    switch (_currentStep) {
      case _LoginStep.telefon:
        return Icons.phone_android;
      case _LoginStep.email:
        return Icons.email;
      case _LoginStep.pin:
        return Icons.lock;
      case _LoginStep.izborPutnika:
        return Icons.people;
      case _LoginStep.zahtevPoslat:
        return Icons.mark_email_read;
    }
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case _LoginStep.telefon:
        return 'Prijava putnika';
      case _LoginStep.email:
        return 'Vaš email';
      case _LoginStep.pin:
        return 'Unesite PIN';
      case _LoginStep.izborPutnika:
        return 'Ko se prijavljuje?';
      case _LoginStep.zahtevPoslat:
        return 'Zahtev poslat';
    }
  }

  String _getStepSubtitle() {
    switch (_currentStep) {
      case _LoginStep.telefon:
        return 'Unesite broj telefona sa kojim ste registrovani';
      case _LoginStep.email:
        return 'Potreban nam je vaš email za kontakt';
      case _LoginStep.pin:
        return 'Unesite svoj 4-cifreni PIN';
      case _LoginStep.izborPutnika:
        return 'Izaberite svoj profil sa liste ispod';
      case _LoginStep.zahtevPoslat:
        return 'Sacekajte odobrenje od admina';
    }
  }

  String _getStepButtonText() {
    switch (_currentStep) {
      case _LoginStep.telefon:
        return '➡️ Nastavi';
      case _LoginStep.email:
        return '💾 Sacuvaj email';
      case _LoginStep.pin:
        return '🔑 Pristupi';
      case _LoginStep.izborPutnika:
        return '';
      case _LoginStep.zahtevPoslat:
        return '';
    }
  }

  VoidCallback? _getStepAction() {
    switch (_currentStep) {
      case _LoginStep.telefon:
        return _checkTelefon;
      case _LoginStep.email:
        return _saveEmail;
      case _LoginStep.pin:
        return _loginWithPin;
      case _LoginStep.izborPutnika:
        return null;
      case _LoginStep.zahtevPoslat:
        return null;
    }
  }

  String _getInfoText() {
    switch (_currentStep) {
      case _LoginStep.telefon:
        return 'Unesite broj telefona koji ste dali prilikom registracije.';
      case _LoginStep.email:
        return 'Email koristimo za obaveštenja i Google Play interno testiranje.';
      case _LoginStep.pin:
        return 'PIN ste dobili od admina. Ako ste ga zaboravili, kontaktirajte nas.';
      case _LoginStep.izborPutnika:
        return 'Više osoba koristi isti broj telefona. Kliknite na svoje ime za ulaz.';
      case _LoginStep.zahtevPoslat:
        return 'Možete zatvoriti aplikaciju. Obavesticemo vas kada PIN bude dodeljen.';
    }
  }
}
