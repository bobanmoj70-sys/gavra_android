import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/v3_vozac.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_closed_auth_service.dart';
import '../services/v3/v3_push_token_provider.dart';
import '../services/v3/v3_putnik_service.dart';
import '../services/v3/v3_role_permission_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../services/v3_biometric_service.dart';
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
    unawaited(() async {
      try {
        await V3MasterRealtimeManager.instance.initV3();
      } catch (e) {
        debugPrint('[V3WelcomeScreen] initV3 error: $e');
      }
    }());

    final vozacRestored = await _tryAutoLoginVozac();
    if (vozacRestored) return;

    final putnikRestored = await _tryAutoLoginPutnik();
    if (putnikRestored) return;

    await _tryBiometricAutoLogin();
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

      await _stopAudio();
      if (!mounted) return false;

      await V3RolePermissionService.ensureDriverPermissionsOnLogin();
      unawaited(_writePushTokenOnLogin(v3AuthId: restoredVozac.id, isVozac: true));

      V3NavigationUtils.pushReplacement(
        context,
        const V3HomeScreen(),
      );
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

      await _stopAudio();
      if (!mounted) return false;

      final putnikId = restored['id']?.toString().trim() ?? '';
      if (putnikId.isNotEmpty) {
        unawaited(_writePushTokenOnLogin(v3AuthId: putnikId, isVozac: false));
      }

      V3NavigationUtils.pushReplacement(
        context,
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
    _isResumeRefreshing = false;
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

      String token = '';
      var apnsToken = '';
      var resolvedInstallationId = installationId;

      for (var attempt = 1; attempt <= 4; attempt++) {
        final tokenResult = await V3PushTokenProvider.getBestToken().timeout(
          const Duration(seconds: 10),
          onTimeout: () => null,
        );
        token = tokenResult?.token.trim() ?? '';
        apnsToken = tokenResult?.apnsToken?.trim() ?? '';
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
          pushToken2: apnsToken,
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
        pushToken2: apnsToken,
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

      String token = '';
      var apnsToken = '';
      for (var attempt = 1; attempt <= 3; attempt++) {
        final tokenResult = await V3PushTokenProvider.getBestToken().timeout(
          const Duration(seconds: 10),
          onTimeout: () => null,
        );
        token = tokenResult?.token.trim() ?? '';
        apnsToken = tokenResult?.apnsToken?.trim() ?? '';
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
          pushToken2: apnsToken,
        ).timeout(const Duration(seconds: 4), onTimeout: () => Future.value());
        return;
      }

      await V3PutnikService.writePushTokenOnLogin(
        putnikId: v3AuthId,
        pushToken: token,
        installationId: installationId,
        pushToken2: apnsToken,
      ).timeout(const Duration(seconds: 4), onTimeout: () => Future.value());
    } catch (e) {
      debugPrint('[V3WelcomeScreen] delayed push token write error: $e');
    }
  }

  Future<void> _onLoginVerified(String phone, String? authId) async {
    V3Vozac? vozac;
    Map<String, dynamic>? putnik;

    final resolvedId = (authId ?? '').trim();
    if (resolvedId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ UUID naloga nedostaje za proveru.')),
        );
      }
      return;
    }

    final verifiedId = await V3ClosedAuthService.findAuthIdByPhoneViaEdge(
      phone,
      expectedAuthId: resolvedId,
    );

    if ((verifiedId ?? '').trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Telefon nije uparen sa UUID nalogom.')),
        );
      }
      return;
    }

    if (resolvedId.isNotEmpty) {
      vozac = V3VozacService.getVozacById(resolvedId);
      if (vozac == null) {
        final vozacDirect = await V3VozacService.getVozacByIdDirect(resolvedId);
        if (vozacDirect != null && vozacDirect.id.trim() == resolvedId) {
          vozac = vozacDirect;
        }
      }
    }

    if (resolvedId.isNotEmpty) {
      putnik = await V3PutnikService.getActiveById(resolvedId);
    }

    if (!mounted) return;

    if (vozac != null) {
      V3VozacService.currentVozac = vozac;
      await V3ClosedAuthService.saveManualSmsVozacSession(
        normalizedPhone: phone,
        authId: vozac.id,
      );
      await V3ClosedAuthService.clearManualSmsPutnikPhone();
      await V3RolePermissionService.ensureDriverPermissionsOnLogin();
      unawaited(_writePushTokenOnLogin(v3AuthId: vozac.id, isVozac: true));
      if (!mounted) return;
      V3NavigationUtils.pushReplacement(
        context,
        const V3HomeScreen(),
      );
      return;
    }

    if (putnik == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ UUID nije mapiran ni na vozača ni na putnika.')),
        );
      }
      return;
    }

    V3PutnikService.currentPutnik = putnik;
    await V3ClosedAuthService.saveManualSmsPutnikSession(
      normalizedPhone: phone,
      authId: resolvedId,
    );
    await V3ClosedAuthService.clearManualSmsVozacPhone();
    await V3RolePermissionService.ensurePassengerPermissionsOnLogin();
    final putnikId = putnik['id']?.toString().trim() ?? '';
    if (putnikId.isNotEmpty) {
      unawaited(_writePushTokenOnLogin(v3AuthId: putnikId, isVozac: false));
    }
    if (!mounted) return;
    V3NavigationUtils.pushReplacement(
      context,
      V3PutnikProfilScreen(putnikData: putnik),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: V3ContainerUtils.backgroundContainer(
        gradient: V3ThemeManager().currentGradient,
        child: SafeArea(
          child: SingleChildScrollView(
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

                  // DOBRODOŠLI tekst — klik mijenja temu
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
                        child: const Text(
                          'DOBRODOŠLI',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 6,
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
                      'Vaš pouzdani prevoz',
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
                        V3NavigationUtils.pushScreen(
                          context,
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
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.phone_android_rounded, color: Colors.black87, size: 26),
                            SizedBox(width: 12),
                            Text(
                              'Prijavi se',
                              style: TextStyle(
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
                        V3NavigationUtils.pushScreen(
                          context,
                          const V3ONamaScreen(),
                        );
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
                              'O nama',
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
                          'Designed - Developed - Crafted with balls',
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 1,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'by Bojan Gavrilovic',
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
        ),
      ),
    );
  }
}
