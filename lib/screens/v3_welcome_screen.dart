import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../globals.dart';
import '../models/v3_vozac.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v2_theme_manager.dart';
import '../services/v3/v3_vozac_service.dart';
import 'v3_home_screen.dart';
import 'v3_o_nama_screen.dart';
import 'v3_putnik_login_screen.dart';

class V3WelcomeScreen extends StatefulWidget {
  const V3WelcomeScreen({super.key});

  @override
  State<V3WelcomeScreen> createState() => _V3WelcomeScreenState();
}

class _V3WelcomeScreenState extends State<V3WelcomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isAudioPlaying = false;

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
    _setupAnimations();
    _loadAppVersion();
    updateInfoNotifier.addListener(_onUpdateInfo);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onUpdateInfo());
    Future.delayed(const Duration(milliseconds: 300), _init);

    // Zahtjev za dozvolama
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      _requestPermissionsIfNeeded();
    });
  }

  void _setupAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    )..repeat();
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _fadeController.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _slideController.forward();
    });
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = 'v${info.version}');
    } catch (_) {}
  }

  Future<void> _init() async {
    if (mounted) setState(() => _isLoading = true);

    int retries = 0;
    while (V3MasterRealtimeManager.instance.vozaciCache.isEmpty && retries < 20) {
      await Future.delayed(const Duration(milliseconds: 300));
      retries++;
    }

    final vozaci = V3VozacService.getAllVozaci().where((v) => v.aktivno && v.imePrezime.isNotEmpty).toList()
      ..sort((a, b) => a.imePrezime.compareTo(b.imePrezime));

    if (mounted) {
      setState(() {
        _vozaci = vozaci;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    updateInfoNotifier.removeListener(_onUpdateInfo);
    _fadeController.dispose();
    _slideController.dispose();
    _pulseController.dispose();
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
        break;
    }
  }

  Future<void> _stopAudio() async {
    try {
      if (_isAudioPlaying) {
        await _audioPlayer.stop();
        if (mounted) setState(() => _isAudioPlaying = false);
      }
    } catch (_) {}
  }

  /// Dialog za obavezno ažuriranje (isti kao V2)
  void _onUpdateInfo() {
    final info = updateInfoNotifier.value;
    if (info == null || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: !info.isForced,
      builder: (ctx) => PopScope(
        canPop: !info.isForced,
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: info.isForced
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
                    )
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1A1A2E), Color(0xFF0F3460)],
                    ),
              boxShadow: [
                BoxShadow(
                  color: (info.isForced ? Colors.red : Colors.blue).withValues(alpha: 0.3),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (info.isForced ? Colors.red : Colors.blue).withValues(alpha: 0.15),
                      border: Border.all(
                        color: (info.isForced ? Colors.red : Colors.blue).withValues(alpha: 0.5),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      info.isForced ? Icons.system_update : Icons.new_releases_rounded,
                      color: info.isForced ? Colors.redAccent : Colors.blueAccent,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    info.isForced ? 'Obavezno ažuriranje' : 'Nova verzija dostupna',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: (info.isForced ? Colors.red : Colors.blue).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: (info.isForced ? Colors.red : Colors.blue).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      'v${info.latestVersion}',
                      style: TextStyle(
                        color: info.isForced ? Colors.redAccent : Colors.blueAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    info.isForced
                        ? 'Ova verzija aplikacije više nije podržana. Molimo ažurirajte da biste nastavili sa korišćenjem.'
                        : 'Preporučujemo da ažurirate aplikaciju radi boljih performansi i novih funkcija.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 14,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      if (!info.isForced) ...[
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                              ),
                            ),
                            child: Text(
                              'Kasnije',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 15),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            // Otvori store stranicu
                            if (!info.isForced) Navigator.of(ctx).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: info.isForced ? Colors.redAccent : Colors.blueAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Ažuriraj',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _requestPermissionsIfNeeded() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final status = await Permission.notification.status;
        if (!status.isGranted) {
          await Permission.notification.request();
        }
      }
    } catch (_) {}
  }

  void _loginAsVozac(V3Vozac vozac) {
    V3VozacService.currentVozac = vozac;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const V3HomeScreen()),
    );
  }

  Future<void> _showVozacDialog() async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1a1a2e), Color(0xFF16213e)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
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
          ),
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
                        _loginAsVozac(vozac);
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 20,
                        ),
                        decoration: BoxDecoration(
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
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Otkaži',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 16,
                  ),
                ),
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
      resizeToAvoidBottomInset: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: V2ThemeManager().currentGradient,
        ),
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
                            if (mounted) setState(() => _isAudioPlaying = false);
                          } else {
                            await _audioPlayer.setVolume(0.5);
                            await _audioPlayer.play(AssetSource('kasno_je.mp3'));
                            if (mounted) setState(() => _isAudioPlaying = true);
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
                            height: 180,
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
                        await V2ThemeManager().nextTheme();
                        if (mounted) setState(() {});
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

                  // PRIJAVI SE dugme (amber) — za putnike
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const V3PutnikLoginScreen()),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                        decoration: BoxDecoration(
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
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.login, color: Colors.white, size: 22),
                            SizedBox(width: 10),
                            Text(
                              'Prijavi se',
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
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const V3ONamaScreen()),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  width: 1.5,
                                ),
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
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.local_taxi, color: Colors.white.withValues(alpha: 0.9), size: 28),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Vozači',
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
                        Container(
                          width: 60,
                          height: 3,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                Colors.white.withValues(alpha: 0.3),
                                Colors.transparent,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
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
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
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
