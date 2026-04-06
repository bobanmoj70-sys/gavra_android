import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/v3_vozac.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_vozac_service.dart';
import '../services/v3_theme_manager.dart';
import '../utils/v3_animation_utils.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_navigation_utils.dart';
import '../utils/v3_state_utils.dart';
import '../utils/v3_stream_utils.dart';
import 'v3_o_nama_screen.dart';
import 'v3_putnik_auth_screen.dart';
import 'v3_vozac_login_screen.dart';

class V3WelcomeScreen extends StatefulWidget {
  const V3WelcomeScreen({super.key});

  @override
  State<V3WelcomeScreen> createState() => _V3WelcomeScreenState();
}

class _V3WelcomeScreenState extends State<V3WelcomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isAudioPlaying = false;
  bool _isResumeRefreshing = false;

  late final AnimationController _fadeController;
  late final AnimationController _slideController;
  late final AnimationController _pulseController;
  late final Animation<double> _fadeAnimation;

  String _appVersion = '';
  bool _isLoading = true;
  List<V3Vozac> _vozaci = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribeToVozaciRealtime();
    _setupAnimations();
    _loadAppVersion();
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 300))
          .then((_) => _init())
          .catchError((Object e) => debugPrint('[V3WelcomeScreen] delayed init error: $e')),
    );
  }

  List<V3Vozac> _sortedActiveVozaci() {
    return V3VozacService.getAllVozaci().where((v) => v.aktivno && v.imePrezime.isNotEmpty).toList()
      ..sort((a, b) => a.imePrezime.compareTo(b.imePrezime));
  }

  void _subscribeToVozaciRealtime() {
    V3StreamUtils.subscribe<int>(
      key: 'welcome_vozaci_realtime',
      stream: V3MasterRealtimeManager.instance.tableRevisionStream('v3_vozaci'),
      onData: (_) {
        if (!mounted) return;
        V3StateUtils.safeSetState(this, () {
          _vozaci = _sortedActiveVozaci();
        });
      },
    );
  }

  void _setupAnimations() {
    _fadeController = V3AnimationUtils.createFadeController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _slideController = V3AnimationUtils.createSlideController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseController = V3AnimationUtils.getController(
      key: 'welcome_pulse',
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
    _fadeAnimation = V3AnimationUtils.createTween(
      controller: _fadeController,
      begin: 0.0,
      end: 1.0,
      curve: Curves.easeInOut,
    );
    _fadeController.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _slideController.forward();
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
    V3StateUtils.safeSetState(this, () => _isLoading = true);

    try {
      await V3MasterRealtimeManager.instance.initV3().timeout(const Duration(seconds: 15));
    } on TimeoutException catch (e) {
      debugPrint('[V3WelcomeScreen] initV3 timeout: $e');
    } catch (e) {
      debugPrint('[V3WelcomeScreen] initV3 error: $e');
    }

    debugPrint('[V3WelcomeScreen] _init() started - waiting for vozaciCache...');

    int retries = 0;
    while (V3MasterRealtimeManager.instance.vozaciCache.isEmpty && retries < 40) {
      await Future.delayed(const Duration(milliseconds: 300));
      retries++;

      if (retries % 10 == 0) {
        debugPrint(
            '[V3WelcomeScreen] Retry ${retries}/40 - vozaciCache still empty. Cache size: ${V3MasterRealtimeManager.instance.vozaciCache.length}');
      }
    }

    if (V3MasterRealtimeManager.instance.vozaciCache.isEmpty) {
      debugPrint('[V3WelcomeScreen] TIMEOUT! vozaciCache is still empty after ${retries} retries');
    }

    final vozaci = _sortedActiveVozaci();

    debugPrint('[V3WelcomeScreen] Loaded ${vozaci.length} active vozaci');

    if (mounted) {
      setState(() {
        _vozaci = vozaci;
        _isLoading = false;
      });
    }

    // Fresh start: nema auto-login prečica sa welcome ekrana.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    V3StreamUtils.cancelSubscription('welcome_vozaci_realtime');
    V3AnimationUtils.disposeController('fade');
    V3AnimationUtils.disposeController('slide');
    V3AnimationUtils.disposeController('welcome_pulse');
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
      final rm = V3MasterRealtimeManager.instance;
      await rm.recoverOnResume().timeout(const Duration(seconds: 20));

      if (!mounted) return;

      final vozaci = _sortedActiveVozaci();

      V3StateUtils.safeSetState(this, () {
        _vozaci = vozaci;
      });
    } catch (e) {
      debugPrint('[V3WelcomeScreen] refreshOnResume error: $e');
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

  Future<void> _loginAsVozac(V3Vozac vozac) async {
    await _stopAudio();
    if (!mounted) return;
    V3NavigationUtils.pushScreen(context, V3VozacLoginScreen(vozac: vozac));
  }

  Future<void> _showVozacDialog() async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: V3ContainerUtils.gradientContainer(
          gradient: const LinearGradient(
            colors: [Color(0xFF1a1a2e), Color(0xFF16213e)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          padding: const EdgeInsets.all(20),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Izaberi vozača',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              if (_isLoading)
                const CircularProgressIndicator(color: Colors.white)
              else if (_vozaci.isEmpty)
                Text(
                  'Nema dostupnih vozača.\nPovežite se na internet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                )
              else
                ..._vozaci.map((vozac) {
                  final color = vozac.boja != null
                      ? Color(
                          int.tryParse(
                                vozac.boja!.replaceFirst('#', '0xFF'),
                              ) ??
                              0xFF2196F3,
                        )
                      : Colors.blue;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        unawaited(_loginAsVozac(vozac));
                      },
                      child: V3ContainerUtils.gradientContainer(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 20,
                        ),
                        gradient: LinearGradient(
                          colors: [
                            color.withValues(alpha: 0.8),
                            Colors.white.withValues(alpha: 0.1),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: color.withValues(alpha: 0.6),
                          width: 1.5,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.local_taxi,
                              color: Colors.white,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              vozac.imePrezime,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 16),
              V3ButtonUtils.textButton(
                onPressed: () => Navigator.pop(ctx),
                text: 'Otkaži',
                foregroundColor: Colors.white.withValues(alpha: 0.7),
                fontSize: 16,
              ),
            ],
          ),
        ),
      ),
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

                  SizedBox(height: screenHeight * 0.05),

                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: V3ContainerUtils.styledContainer(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      child: Text(
                        '🍎 Apple Review hint: Za test vozača kliknite "🍎 Vozači" (donje desno dugme).\nPutnički login je odvojeno dugme "Putnici • Prijavi se".',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // PRIJAVI SE dugme (amber) — za putnike
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: GestureDetector(
                      onTap: () {
                        V3NavigationUtils.pushScreen(
                          context,
                          const V3PutnikAuthScreen(),
                        );
                      },
                      child: V3ContainerUtils.gradientContainer(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                        gradient: LinearGradient(
                          colors: [Colors.amber, Colors.amber.shade700],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.amber.withValues(alpha: 0.4),
                            blurRadius: 15,
                            offset: const Offset(0, 6),
                          ),
                        ],
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.login, color: Colors.white, size: 22),
                            SizedBox(width: 10),
                            Text(
                              'Putnici • Prijavi se',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // O NAMA + VOZAČI row
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Row(
                      children: [
                        Expanded(
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
                              child: Column(
                                children: [
                                  Icon(Icons.info_outline, color: Colors.white.withValues(alpha: 0.9), size: 28),
                                  const SizedBox(height: 8),
                                  Text(
                                    'O nama',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.9),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => unawaited(_showVozacDialog()),
                            child: V3ContainerUtils.styledContainer(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                                width: 1.5,
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.local_taxi, color: Colors.white.withValues(alpha: 0.9), size: 28),
                                  const SizedBox(height: 8),
                                  Text(
                                    '🍎 Vozači',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.9),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
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
                          'Designed Developed Crafted with balls',
                          style: TextStyle(
                            fontSize: 10,
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
