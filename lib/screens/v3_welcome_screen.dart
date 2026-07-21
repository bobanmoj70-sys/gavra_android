import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/v3_vozac.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_app_update_service.dart';
import '../services/v3/v3_closed_auth_service.dart';
import '../services/v3/v3_device_identity_service.dart';
import '../services/v3/v3_push_token_provider.dart';
import '../services/v3/v3_putnik_service.dart';
import '../services/v3/v3_role_permission_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../services/v3_biometric_service.dart';
import '../services/v3_locale_manager.dart';
import '../services/v3_theme_manager.dart';
import '../utils/v3_animation_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_navigation_utils.dart';
import '../utils/v3_state_utils.dart';
import 'v3_home_screen.dart';
import 'v3_o_nama_screen.dart';
import 'v3_putnik_profil_screen.dart';
import 'v3_sms_login_screen.dart';

class V3WelcomeScreen extends StatefulWidget {
  const V3WelcomeScreen({super.key});

  @override
  State<V3WelcomeScreen> createState() => _V3WelcomeScreenState();
}

class _V3WelcomeScreenState extends State<V3WelcomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  static const String _biometricPhoneKey = 'v3_biometric_login_phone';
  static const String _fadeAnimationKey = 'welcome_fade';
  static const String _slideAnimationKey = 'welcome_slide';
  static const String _pulseAnimationKey = 'welcome_pulse';
  static const Duration _startupTimeout = Duration(seconds: 5);

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isAudioPlaying = false;
  bool _isResumeRefreshing = false;

  late final AnimationController _fadeController;
  late final AnimationController _slideController;
  late final AnimationController _pulseController;
  late final Animation<double> _fadeAnimation;
  Timer? _slideStartTimer;
  bool _isDisposing = false;

  String _appVersion = '';

  // Prevodi za welcome ekran (SR/EN/RU) — jednostavna mapa dok se ne uvede puni l10n sistem.
  static const Map<String, Map<String, String>> _t = {
    'welcome': {
      'sr': 'DOBRODOŠLI',
      'en': 'WELCOME',
      'ru': 'ДОБРО ПОЖАЛОВАТЬ',
      'de': 'WILLKOMMEN',
    },
    'subtitle': {
      'sr': 'Vaš pouzdani prevoz',
      'en': 'Your reliable transport',
      'ru': 'Ваш надежный транспорт',
      'de': 'Ihr zuverlässiger Transport',
    },
    'login': {'sr': 'Prijavi se', 'en': 'Log in', 'ru': 'Войти', 'de': 'Anmelden'},
    'about': {'sr': 'O nama', 'en': 'About us', 'ru': 'О нас', 'de': 'Über uns'},
    'footer1': {
      'sr': 'Designed - Developed - Crafted with balls',
      'en': 'Designed - Developed - Crafted with balls',
      'ru': 'Designed - Developed - Crafted with balls',
      'de': 'Designed - Developed - Crafted with balls',
    },
    'footer2': {
      'sr': 'by Bojan Gavrilovic',
      'en': 'by Bojan Gavrilovic',
      'ru': 'by Bojan Gavrilovic',
      'de': 'by Bojan Gavrilovic',
    },
  };

  String _tr(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    return _t[key]?[code] ?? _t[key]?['sr'] ?? key;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupAnimations();
    _loadAppVersion();
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 300))
          .then((_) => _init())
          .catchError((Object e) => debugPrint('[V3WelcomeScreen] delayed init error: $e')),
    );
  }

  void _setupAnimations() {
    _fadeController = V3AnimationUtils.getController(
      key: _fadeAnimationKey,
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _slideController = V3AnimationUtils.getController(
      key: _slideAnimationKey,
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseController = V3AnimationUtils.getController(
      key: _pulseAnimationKey,
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
    _fadeAnimation = V3AnimationUtils.createTween(
      controller: _fadeController,
      begin: 0.0,
      end: 1.0,
      curve: Curves.easeInOut,
    );
    if (!_isDisposing) {
      _fadeController.forward();
    }
    _slideStartTimer?.cancel();
    _slideStartTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || _isDisposing) return;
      _slideController.forward();
    });
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      V3StateUtils.safeSetState(this, () => _appVersion = 'v${info.version}');
    } catch (e) {
      debugPrint('[V3WelcomeScreen] loadAppVersion error: $e');
    }
  }

  Future<void> _init() async {
    final vozacRestored = await _runStartupStep<bool>(
          label: 'auto-login vozac',
          action: _tryAutoLoginVozac,
        ) ??
        false;
    if (vozacRestored) return;

    final putnikRestored = await _runStartupStep<bool>(
          label: 'auto-login putnik',
          action: _tryAutoLoginPutnik,
        ) ??
        false;
    if (putnikRestored) return;

    await _runStartupStep<void>(
      label: 'biometric auto-login',
      action: _tryBiometricAutoLogin,
    );
  }

  Future<T?> _runStartupStep<T>({
    required String label,
    required Future<T> Function() action,
  }) async {
    try {
      return await action().timeout(_startupTimeout);
    } catch (e) {
      debugPrint('[V3WelcomeScreen] startup step failed ($label): $e');
      return null;
    }
  }

  void _showSafeSnackBar(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _safePushReplacement(Widget screen) {
    if (!mounted) return;
    try {
      V3NavigationUtils.pushReplacement(context, screen);
    } catch (e) {
      debugPrint('[V3WelcomeScreen] pushReplacement error: $e');
    }
  }

  void _safePushScreen(Widget screen) {
    if (!mounted) return;
    try {
      V3NavigationUtils.pushScreen(context, screen);
    } catch (e) {
      debugPrint('[V3WelcomeScreen] pushScreen error: $e');
    }
  }

  bool _hasMissingPassengerProfileFields(Map<String, dynamic> putnik) {
    final ime = putnik['ime_prezime']?.toString().trim() ?? '';
    final tip = putnik['tip_putnika']?.toString().trim() ?? '';
    final bc = putnik['adresa_bc_id']?.toString().trim() ?? '';
    final vs = putnik['adresa_vs_id']?.toString().trim() ?? '';
    final putnikId = putnik['id']?.toString().trim() ?? '';
    final pinHash =
        putnikId == V3AppUpdateService.appleReviewUserId ? 'x' : (putnik['pin_hash']?.toString().trim() ?? '');
    return ime.isEmpty || tip.isEmpty || bc.isEmpty || vs.isEmpty || pinHash.isEmpty;
  }

  Future<Map<String, dynamic>?> _getPutnikWithAddressRefresh(String authId) async {
    Map<String, dynamic>? putnik = await V3PutnikService.getActiveById(authId).timeout(
      _startupTimeout,
      onTimeout: () => null,
    );

    for (var attempt = 0; attempt < 2; attempt++) {
      if (putnik == null || !_hasMissingPassengerProfileFields(putnik)) {
        return putnik;
      }

      await Future<void>.delayed(const Duration(milliseconds: 250));
      putnik = await V3PutnikService.getActiveById(authId).timeout(
        _startupTimeout,
        onTimeout: () => putnik,
      );
    }

    return putnik;
  }

  String _extractPassengerPhone(Map<String, dynamic> putnik) {
    final phone = (putnik['telefon_1'] ?? putnik['telefon'] ?? '').toString().trim();
    return V3ClosedAuthService.normalizePhone(phone);
  }

  void _openPassengerAddressCompletionFlow(String initialPhone) {
    _safePushScreen(
      V3SmsLoginScreen(
        title: 'Prijava',
        initialPhone: initialPhone,
        biometricKey: _biometricPhoneKey,
        onVerified: _onLoginVerified,
      ),
    );
  }

  String _extractDriverPhone(V3Vozac vozac) {
    final phone = (vozac.telefon1 ?? vozac.telefon2 ?? '').trim();
    return V3ClosedAuthService.normalizePhone(phone);
  }

  void _openDriverPinCompletionFlow(String initialPhone) {
    _safePushScreen(
      V3SmsLoginScreen(
        title: 'Prijava',
        initialPhone: initialPhone,
        biometricKey: _biometricPhoneKey,
        onVerified: _onLoginVerified,
      ),
    );
  }

  Future<void> _tryBiometricAutoLogin() async {
    try {
      const secureStorage = FlutterSecureStorage();
      final rawPhone = await secureStorage.read(key: _biometricPhoneKey);

      if (rawPhone != null && rawPhone.isNotEmpty) {
        final bio = V3BiometricService();
        final enabledForUser = await bio.isBiometricEnabled();
        final isAvailable = await bio.isBiometricAvailable();

        if (enabledForUser && isAvailable && mounted) {
          final authenticated = await bio.authenticate(
            reason: 'Potvrdi identitet za automatski ulazak',
          );

          if (authenticated && mounted) {
            await _stopAudio();
            final normalizedPhone = V3ClosedAuthService.normalizePhone(rawPhone);
            if (normalizedPhone.isEmpty) return;

            final authId = (await V3ClosedAuthService.findAuthIdByPhone(normalizedPhone) ?? '').trim();
            if (authId.isEmpty) return;

            final deviceId = await V3DeviceIdentityService.getStableDeviceId();
            final hardwareId = await V3DeviceIdentityService.getHardwareId();
            final verification = await V3ClosedAuthService.verifyLogin(
              rawPhone: normalizedPhone,
              expectedAuthId: authId,
              installationId: deviceId,
              hardwareId: hardwareId,
            ).timeout(_startupTimeout, onTimeout: () => const V3LoginVerification(ok: false, reason: 'timeout'));

            if (!verification.ok || !verification.deviceAllowed) {
              if (verification.reason == 'device_limit_reached') {
                _showSafeSnackBar('❌ Dostignut je limit od 2 uređaja po nalogu. Kontaktirajte admina.');
              } else {
                _showSafeSnackBar('❌ Telefon nije uparen sa UUID nalogom.');
              }
              return;
            }

            await _onLoginVerified(normalizedPhone, authId);
          }
        }
      }
    } catch (e) {
      debugPrint('[V3WelcomeScreen] Biometic auto-login error: $e');
    }
  }

  Future<bool> _tryAutoLoginVozac() async {
    try {
      await V3ClosedAuthService.restoreVozacFromManualSmsSession();
      final restoredVozac = V3VozacService.currentVozac;

      if (!mounted || restoredVozac == null) return false;

      if ((restoredVozac.pinHash ?? '').trim().isEmpty) {
        await _stopAudio();
        if (!mounted) return false;
        _openDriverPinCompletionFlow(_extractDriverPhone(restoredVozac));
        return true;
      }

      await _stopAudio();
      if (!mounted) return false;

      await V3RolePermissionService.ensureDriverPermissionsOnLogin();
      unawaited(_writePushTokenOnLogin(v3AuthId: restoredVozac.id, isVozac: true));
      unawaited(V3AppUpdateService.refreshUpdateInfo()
          .catchError((Object e) => debugPrint('⚠️ [WelcomeScreen] refreshUpdateInfo error: $e')));

      _safePushReplacement(const V3HomeScreen());
      return true;
    } catch (e) {
      debugPrint('[V3WelcomeScreen] auto-login vozac error: $e');
      return false;
    }
  }

  Future<bool> _tryAutoLoginPutnik() async {
    try {
      // Auto-login: manual SMS sesija + sačuvan telefon u SecureStorage
      final restored = await V3ClosedAuthService.restorePutnikFromManualSmsSession();

      if (!mounted || restored == null) return false;

      if (_hasMissingPassengerProfileFields(restored)) {
        await _stopAudio();
        if (!mounted) return false;
        _openPassengerAddressCompletionFlow(_extractPassengerPhone(restored));
        return true;
      }

      await _stopAudio();
      if (!mounted) return false;

      await V3RolePermissionService.ensurePassengerPermissionsOnLogin();

      final putnikId = restored['id']?.toString().trim() ?? '';
      if (putnikId.isNotEmpty) {
        unawaited(_writePushTokenOnLogin(v3AuthId: putnikId, isVozac: false));
      }
      unawaited(V3AppUpdateService.refreshUpdateInfo()
          .catchError((Object e) => debugPrint('⚠️ [WelcomeScreen] refreshUpdateInfo error: $e')));

      _safePushReplacement(
        V3PutnikProfilScreen(putnikData: Map<String, dynamic>.from(restored)),
      );
      return true;
    } catch (e) {
      debugPrint('[V3WelcomeScreen] auto-login putnik error: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _isDisposing = true;
    WidgetsBinding.instance.removeObserver(this);
    _slideStartTimer?.cancel();
    V3AnimationUtils.disposeController(_fadeAnimationKey);
    V3AnimationUtils.disposeController(_slideAnimationKey);
    V3AnimationUtils.disposeController(_pulseAnimationKey);
    _audioPlayer.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        unawaited(_stopAudio());
        break;
      case AppLifecycleState.resumed:
        unawaited(_refreshOnResume());
        break;
    }
  }

  Future<void> _refreshOnResume() async {
    if (_isResumeRefreshing || !mounted) return;
    _isResumeRefreshing = true;
    try {
      await _runStartupStep<void>(
        label: 'resume realtime refresh',
        action: () => V3MasterRealtimeManager.instance.initV3(),
      );
      await _runStartupStep<void>(
        label: 'resume update refresh',
        action: () => V3AppUpdateService.refreshUpdateInfo(),
      );
    } finally {
      _isResumeRefreshing = false;
    }
  }

  Future<void> _stopAudio() async {
    try {
      if (_isAudioPlaying) {
        await _audioPlayer.stop();
        V3StateUtils.safeSetState(this, () => _isAudioPlaying = false);
      }
    } catch (e) {
      debugPrint('[V3WelcomeScreen] stopAudio error: $e');
    }
  }

  Future<void> _writePushTokenOnLogin({
    required String v3AuthId,
    required bool isVozac,
  }) async {
    try {
      final installationId = (await V3PushTokenProvider.getInstallationId())?.trim() ?? '';
      if (installationId.isEmpty) return;
      final hardwareId = await V3DeviceIdentityService.getHardwareId();

      String token = '';
      var resolvedInstallationId = installationId;

      for (var attempt = 1; attempt <= 4; attempt++) {
        final tokenResult = await V3PushTokenProvider.getBestToken().timeout(
          const Duration(seconds: 10),
          onTimeout: () => null,
        );
        token = tokenResult?.token.trim() ?? '';
        resolvedInstallationId = tokenResult?.installationId?.trim() ?? installationId;

        if (token.isNotEmpty && resolvedInstallationId.isNotEmpty) {
          break;
        }

        if (attempt < 4) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }

      if (resolvedInstallationId.isEmpty) {
        debugPrint('[V3WelcomeScreen] installation id unavailable after login sync attempts.');
        return;
      }

      if (isVozac) {
        await V3VozacService.writePushTokenOnLogin(
          vozacId: v3AuthId,
          pushToken: token,
          installationId: resolvedInstallationId,
          hardwareId: hardwareId,
        ).timeout(const Duration(seconds: 4), onTimeout: () => Future.value());
        if (token.isEmpty) {
          unawaited(
            _retryPushTokenWriteAfterLogin(
              v3AuthId: v3AuthId,
              isVozac: isVozac,
              installationId: resolvedInstallationId,
            ),
          );
        }
        return;
      }

      await V3PutnikService.writePushTokenOnLogin(
        putnikId: v3AuthId,
        pushToken: token,
        installationId: resolvedInstallationId,
        hardwareId: hardwareId,
      ).timeout(const Duration(seconds: 4), onTimeout: () => Future.value());
      if (token.isEmpty) {
        unawaited(
          _retryPushTokenWriteAfterLogin(
            v3AuthId: v3AuthId,
            isVozac: isVozac,
            installationId: resolvedInstallationId,
          ),
        );
      }
    } catch (e) {
      debugPrint('[V3WelcomeScreen] push token write error: $e');
    }
  }

  Future<void> _retryPushTokenWriteAfterLogin({
    required String v3AuthId,
    required bool isVozac,
    required String installationId,
  }) async {
    try {
      await Future<void>.delayed(const Duration(seconds: 8));
      final hardwareId = await V3DeviceIdentityService.getHardwareId();

      String token = '';
      for (var attempt = 1; attempt <= 3; attempt++) {
        final tokenResult = await V3PushTokenProvider.getBestToken().timeout(
          const Duration(seconds: 10),
          onTimeout: () => null,
        );
        token = tokenResult?.token.trim() ?? '';
        if (token.isNotEmpty) break;

        if (attempt < 3) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }

      if (token.isEmpty) return;

      if (isVozac) {
        await V3VozacService.writePushTokenOnLogin(
          vozacId: v3AuthId,
          pushToken: token,
          installationId: installationId,
          hardwareId: hardwareId,
        ).timeout(const Duration(seconds: 4), onTimeout: () => Future.value());
        return;
      }

      await V3PutnikService.writePushTokenOnLogin(
        putnikId: v3AuthId,
        pushToken: token,
        installationId: installationId,
        hardwareId: hardwareId,
      ).timeout(const Duration(seconds: 4), onTimeout: () => Future.value());
    } catch (e) {
      debugPrint('[V3WelcomeScreen] delayed push token write error: $e');
    }
  }

  Future<void> _onLoginVerified(String phone, String? authId) async {
    try {
      V3Vozac? vozac;
      Map<String, dynamic>? putnik;

      final resolvedId = (authId ?? '').trim();
      if (resolvedId.isEmpty) {
        _showSafeSnackBar('❌ UUID naloga nedostaje za proveru.');
        return;
      }

      vozac = V3VozacService.getVozacById(resolvedId);
      debugPrint(
          '[V3WelcomeScreen] cached vozac: ${vozac != null}, pinHash empty: ${(vozac?.pinHash ?? '').trim().isEmpty}');
      if (vozac == null || (vozac.pinHash ?? '').trim().isEmpty) {
        final vozacDirect = await V3VozacService.getVozacByIdDirect(resolvedId).timeout(
          _startupTimeout,
          onTimeout: () => null,
        );
        debugPrint(
            '[V3WelcomeScreen] direct vozac: ${vozacDirect != null}, pinHash empty: ${(vozacDirect?.pinHash ?? '').trim().isEmpty}');
        if (vozacDirect != null && vozacDirect.id.trim() == resolvedId) {
          vozac = vozacDirect;
        }
      }

      putnik = await _getPutnikWithAddressRefresh(resolvedId);

      if (!mounted) return;

      if (vozac != null) {
        if ((vozac.pinHash ?? '').trim().isEmpty) {
          _openDriverPinCompletionFlow(phone);
          return;
        }

        V3VozacService.currentVozac = vozac;
        await V3ClosedAuthService.saveManualSmsVozacSession(
          normalizedPhone: phone,
          authId: vozac.id,
        ).timeout(_startupTimeout, onTimeout: () => Future.value());
        await V3ClosedAuthService.clearManualSmsPutnikPhone().timeout(_startupTimeout, onTimeout: () => null);
        await V3RolePermissionService.ensureDriverPermissionsOnLogin().timeout(_startupTimeout, onTimeout: () => null);
        unawaited(_writePushTokenOnLogin(v3AuthId: vozac.id, isVozac: true));
        unawaited(V3AppUpdateService.refreshUpdateInfo()
            .catchError((Object e) => debugPrint('⚠️ [WelcomeScreen] refreshUpdateInfo error: $e')));
        _safePushReplacement(const V3HomeScreen());
        return;
      }

      if (putnik == null) {
        _showSafeSnackBar(
          'Aplikacija je zatvorenog tipa i Vi niste u sistemu. Kontaktirajte admina.',
        );
        return;
      }

      if (_hasMissingPassengerProfileFields(putnik)) {
        _openPassengerAddressCompletionFlow(_extractPassengerPhone(putnik));
        return;
      }

      V3PutnikService.currentPutnik = putnik;
      await V3ClosedAuthService.saveManualSmsPutnikSession(
        normalizedPhone: phone,
        authId: resolvedId,
      ).timeout(_startupTimeout, onTimeout: () => Future.value());
      await V3ClosedAuthService.clearManualSmsVozacPhone().timeout(_startupTimeout, onTimeout: () => null);
      await V3RolePermissionService.ensurePassengerPermissionsOnLogin().timeout(_startupTimeout, onTimeout: () => null);
      final putnikId = putnik['id']?.toString().trim() ?? '';
      if (putnikId.isNotEmpty) {
        unawaited(_writePushTokenOnLogin(v3AuthId: putnikId, isVozac: false));
      }
      unawaited(V3AppUpdateService.refreshUpdateInfo()
          .catchError((Object e) => debugPrint('⚠️ [WelcomeScreen] refreshUpdateInfo error: $e')));
      V3NavigationUtils.pushAndRemoveUntil(
        context,
        V3PutnikProfilScreen(putnikData: putnik),
      );
    } catch (e) {
      debugPrint('[V3WelcomeScreen] onLoginVerified error: $e');
      _showSafeSnackBar('⚠️ Greška pri verifikaciji prijave. Pokušaj ponovo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return ValueListenableBuilder<Locale>(
      valueListenable: V3LocaleManager().localeNotifier,
      builder: (context, _, __) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: true,
          body: V3ContainerUtils.backgroundContainer(
            gradient: V3ThemeManager().currentGradient,
            child: SafeArea(
              child: Stack(
                children: [
                  SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          SizedBox(height: screenHeight * 0.04),

                          // LOGO sa shimmer efektom — klik pušta/zaustavlja kasno_je.mp3
                          FadeTransition(
                            opacity: _fadeAnimation,
                            child: GestureDetector(
                              onTap: () async {
                                try {
                                  if (_isAudioPlaying) {
                                    await _audioPlayer.stop();
                                    V3StateUtils.safeSetState(this, () => _isAudioPlaying = false);
                                  } else {
                                    await _audioPlayer.setVolume(0.5);
                                    await _audioPlayer.play(AssetSource('kasno_je.mp3'));
                                    V3StateUtils.safeSetState(this, () => _isAudioPlaying = true);
                                  }
                                } catch (e) {
                                  debugPrint('[V3WelcomeScreen] Audio error: $e');
                                }
                              },
                              child: RepaintBoundary(
                                child: AnimatedBuilder(
                                  animation: _pulseController,
                                  builder: (context, child) {
                                    return ShaderMask(
                                      shaderCallback: (bounds) {
                                        return LinearGradient(
                                          begin: Alignment(
                                            -1.5 + 3 * _pulseController.value,
                                            0,
                                          ),
                                          end: Alignment(
                                            -0.5 + 3 * _pulseController.value,
                                            0,
                                          ),
                                          colors: [
                                            Colors.white.withValues(alpha: 0.6),
                                            Colors.white,
                                            Colors.white.withValues(alpha: 0.6),
                                          ],
                                          stops: const [0.0, 0.5, 1.0],
                                        ).createShader(bounds);
                                      },
                                      blendMode: BlendMode.srcATop,
                                      child: child,
                                    );
                                  },
                                  child: Image.asset(
                                    'assets/logo_transparent.png',
                                    height: V3ContainerUtils.responsiveHeight(context, 180),
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // DOBRODOŠLI tekst — klik menja temu
                          FadeTransition(
                            opacity: _fadeAnimation,
                            child: GestureDetector(
                              onTap: () async {
                                await V3ThemeManager().nextTheme();
                                V3StateUtils.safeSetState(this, () {});
                              },
                              child: ShaderMask(
                                shaderCallback: (bounds) => LinearGradient(
                                  colors: [
                                    Colors.white,
                                    Colors.amber.shade200,
                                    Colors.white,
                                  ],
                                ).createShader(bounds),
                                child: Text(
                                  _tr('welcome'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing:
                                        {'ru', 'de'}.contains(V3LocaleManager().currentLocale.languageCode) ? 2 : 6,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          FadeTransition(
                            opacity: _fadeAnimation,
                            child: Text(
                              _tr('subtitle'),
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white.withValues(alpha: 0.7),
                                letterSpacing: 2,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          ),

                          SizedBox(height: screenHeight * 0.06),

                          // JEDNO dugme za sve — shimmer pulsing
                          FadeTransition(
                            opacity: _fadeAnimation,
                            child: GestureDetector(
                              onTap: () async {
                                await _stopAudio();
                                if (!mounted) return;
                                _safePushScreen(
                                  V3SmsLoginScreen(
                                    title: 'Prijava',
                                    biometricKey: _biometricPhoneKey,
                                    onVerified: _onLoginVerified,
                                  ),
                                );
                              },
                              child: AnimatedBuilder(
                                animation: _pulseController,
                                builder: (context, child) {
                                  final shimmerPos = _pulseController.value;
                                  return Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(vertical: 20),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      gradient: LinearGradient(
                                        begin: Alignment(
                                          -2.0 + shimmerPos * 4.0,
                                          -0.5,
                                        ),
                                        end: Alignment(
                                          -1.0 + shimmerPos * 4.0,
                                          0.5,
                                        ),
                                        colors: const [
                                          Color(0xFFFFB300),
                                          Color(0xFFFFE082),
                                          Color(0xFFFFD54F),
                                          Color(0xFFFFB300),
                                        ],
                                        stops: const [0.0, 0.4, 0.6, 1.0],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.amber.withValues(
                                            alpha: 0.35 + 0.25 * shimmerPos,
                                          ),
                                          blurRadius: 20 + 10 * shimmerPos,
                                          spreadRadius: 1 + 2 * shimmerPos,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: child,
                                  );
                                },
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.phone_android_rounded, color: Colors.black87, size: 26),
                                    const SizedBox(width: 12),
                                    Text(
                                      _tr('login'),
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // O NAMA dugme
                          FadeTransition(
                            opacity: _fadeAnimation,
                            child: GestureDetector(
                              onTap: () {
                                _safePushScreen(const V3ONamaScreen());
                              },
                              child: V3ContainerUtils.styledContainer(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                backgroundColor: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  width: 1.5,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.info_outline, color: Colors.white.withValues(alpha: 0.9), size: 22),
                                    const SizedBox(width: 10),
                                    Text(
                                      _tr('about'),
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.9),
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          SizedBox(height: screenHeight * 0.08),

                          // FOOTER
                          FadeTransition(
                            opacity: _fadeAnimation,
                            child: Column(
                              children: [
                                V3ContainerUtils.gradientContainer(
                                  width: 60,
                                  height: V3ContainerUtils.responsiveHeight(context, 3, intensity: 0.2),
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.transparent,
                                      Colors.white.withValues(alpha: 0.3),
                                      Colors.transparent,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(2),
                                  padding: EdgeInsets.zero,
                                  child: const SizedBox.shrink(),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  _tr('footer1'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    letterSpacing: 1,
                                    color: Colors.white.withValues(alpha: 0.5),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _tr('footer2'),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1,
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                V3ContainerUtils.styledContainer(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Text(
                                    '$_appVersion 2025-2026',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white.withValues(alpha: 0.5),
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _buildLanguageFlags(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLanguageFlags() {
    return ValueListenableBuilder<Locale>(
      valueListenable: V3LocaleManager().localeNotifier,
      builder: (context, locale, _) {
        final code = locale.languageCode;
        final currentFlag = code == 'en'
            ? '🇬🇧'
            : code == 'ru'
                ? '🇷🇺'
                : code == 'de'
                    ? '🇩🇪'
                    : '🇷🇸';
        return PopupMenuButton<String>(
          tooltip: '',
          offset: const Offset(0, 44),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: Colors.black.withValues(alpha: 0.85),
          onSelected: (newCode) => V3LocaleManager().changeLocale(Locale(newCode)),
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              value: 'sr',
              child: Row(
                children: [
                  const Text('🇷🇸', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Text(
                    'Srpski',
                    style: TextStyle(color: Colors.white.withValues(alpha: code == 'sr' ? 1 : 0.6)),
                  ),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'en',
              child: Row(
                children: [
                  const Text('🇬🇧', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Text(
                    'English',
                    style: TextStyle(color: Colors.white.withValues(alpha: code == 'en' ? 1 : 0.6)),
                  ),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'ru',
              child: Row(
                children: [
                  const Text('🇷🇺', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Text(
                    'Русский',
                    style: TextStyle(color: Colors.white.withValues(alpha: code == 'ru' ? 1 : 0.6)),
                  ),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'de',
              child: Row(
                children: [
                  const Text('🇩🇪', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Text(
                    'Deutsch',
                    style: TextStyle(color: Colors.white.withValues(alpha: code == 'de' ? 1 : 0.6)),
                  ),
                ],
              ),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
            ),
            child: Text(currentFlag, style: const TextStyle(fontSize: 22)),
          ),
        );
      },
    );
  }
}
