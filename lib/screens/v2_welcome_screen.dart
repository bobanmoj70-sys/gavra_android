import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/vozac.dart';
import '../services/auth_manager.dart';
import '../services/battery_optimization_service.dart';
import '../services/biometric_service.dart';
import '../services/permission_service.dart';
import '../services/theme_manager.dart';
import '../services/v2_local_notification_service.dart';
import '../services/v2_vozac_service.dart';
import '../utils/vozac_cache.dart';
import 'o_nama_screen.dart';
import 'v2_home_screen.dart';
import 'v2_putnik_login_screen.dart';
import 'v2_vozac_login_screen.dart';
import 'v2_vozac_screen.dart';

Widget _getScreenForDriver(String driverName) {
  // VozaÄi koji koriste VozacScreen umesto HomeScreen
  if (driverName == 'Voja') {
    return const VozacScreen();
  }
  return const HomeScreen();
}

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isAudioPlaying = false;
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;

  // Lista vozaÄa uÄitana iz baze
  List<Vozac> _drivers = [];
  bool _isLoadingDrivers = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Dodano za lifecycle

    _setupAnimations();
    _loadDrivers();

    // Inicijalizacija bez blokiranja - dajemo aplikaciji vremena da "udahne"
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _initServicesRecursively();
    });

    // ðŸ” ZAHTEV ZA DOZVOLAMA - pomeramo ovde iz main.dart da izbegnemo MaterialLocalizations greÅ¡ku
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      _requestPermissionsIfNeeded();
    });

    // ðŸ”‹ PROVERA BATERIJSKE OPTIMIZACIJE - pomeramo ovde iz main.dart
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      _checkBatteryOptimization();
    });
  }

  /// UÄitaj vozaÄe iz baze
  Future<void> _loadDrivers() async {
    try {
      final vozacService = V2VozacService();
      final vozaci = await vozacService.getAllVozaci().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('â±ï¸ [WelcomeScreen] getAllVozaci timeout - pokazujem prazan ekran');
          return [];
        },
      );
      if (!mounted) return;
      setState(() {
        _drivers = vozaci;
        _isLoadingDrivers = false;
      });
    } catch (e) {
      // Nema fallback-a - ako Supabase ne radi, prikaÅ¾i greÅ¡ku
      debugPrint('âŒ GreÅ¡ka pri uÄitavanju vozaÄa: $e');
      if (!mounted) return;
      setState(() {
        _drivers = []; // Prazna lista umesto hardkodovanih podataka
        _isLoadingDrivers = false;
      });
    }
  }

  /// ðŸ› ï¸ Inicijalizacija servisa jedan po jedan, bez agresivnih await-ova
  Future<void> _initServicesRecursively() async {
    try {
      // 1. Notifikacije
      unawaited(LocalNotificationService.initialize(context));

      // 2. Auto-login (dozvole su veÄ‡ traÅ¾ene pri prvom startu aplikacije)
      if (mounted) {
        _ensureNotificationPermissions();
        _checkAutoLogin();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('âš ï¸ [WelcomeScreen] Init failed: $e');
    }
  }

  Future<void> _ensureNotificationPermissions() async {
    try {
      // On Android request POST_NOTIFICATIONS runtime permission (API 33+)
      if (defaultTargetPlatform == TargetPlatform.android) {
        final status = await Permission.notification.status;
        if (!status.isGranted) {
          await Permission.notification.request();
        } else {}
      }

      // Traži dozvole za notifikacije
      try {
        await Permission.notification.request();
      } catch (e) {
        // Silently ignore permission errors
      }
    } catch (e) {
      // Silently ignore
    }
  }

  // ðŸ”„ AUTO-LOGIN BEZ PESME - Proveri da li je vozaÄ veÄ‡ logovan
  Future<void> _checkAutoLogin() async {
    // ðŸŽµ PREKINI PESMU ako se auto-login aktivira
    await _stopAudio();

    // ðŸ“± PRVO PROVERI REMEMBERED DEVICE
    final rememberedDevice = await AuthManager.getRememberedDevice();
    if (rememberedDevice != null) {
      // Auto-login sa zapamÄ‡enim ureÄ‘ajem
      final email = rememberedDevice['email']!;
      // ðŸ”„ FORSIRAJ ISPRAVNO MAPIRANJE: email -> vozaÄ ime
      try {
        final driverName = VozacCache.getImeByEmail(email);
        // Ne dozvoli auto-login ako vozaÄ nije prepoznat
        if (driverName == null || !VozacCache.isValidIme(driverName)) {
          // Ostani na welcome/login i ne auto-login
          return;
        }

        // Postavi driver session
        await AuthManager.setCurrentDriver(driverName);

        if (!mounted) return;

        // Direktno na Home Screen bez daily check-in
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (context) => _getScreenForDriver(driverName),
          ),
        );
        return;
      } catch (e) {
        debugPrint('âŒ [WelcomeScreen] Auto-login failed: $e');
        // Nastavi dalje bez auto-login-a
      }
    }

    // Koristi AuthManager za session management
    final activeDriver = await AuthManager.getCurrentDriver();

    if (activeDriver != null && activeDriver.isNotEmpty) {
      // VozaÄ je veÄ‡ logovan - direktno na odgovarajuÄ‡i ekran
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(builder: (context) => _getScreenForDriver(activeDriver)),
      );
    }
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

    // Start animations
    _fadeController.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      _slideController.forward();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Uklanjamo observer
    _fadeController.dispose();
    _slideController.dispose();
    _pulseController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // Dodano za praÄ‡enje lifecycle-a aplikacije
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
        // Aplikacija ide u pozadinu - zaustavi muziku
        _stopAudio();
        break;
      case AppLifecycleState.resumed:
        // Aplikacija se vraÄ‡a u foreground - ne radi niÅ¡ta
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // Zaustavi muziku i u ovim stanjima
        _stopAudio();
        break;
      case AppLifecycleState.hidden:
        // Zaustavi muziku kada je skrivena
        _stopAudio();
        break;
    }
  }

  // Helper metoda za zaustavljanje pesme
  Future<void> _stopAudio() async {
    try {
      if (_isAudioPlaying) {
        await _audioPlayer.stop();
        _isAudioPlaying = false;
      }
    } catch (e) {
      // Swallow audio errors silently
    }
  }

  Future<void> _loginAsDriver(String driverName) async {
    // ðŸŽµ PREKINI PESMU kada korisnik poÄne login
    await _stopAudio();

    // Uklonjena striktna validacija vozaÄa - dozvoljava sve vozaÄe

    // ðŸ“± PRVO PROVERI REMEMBERED DEVICE za ovog vozaÄa
    final rememberedDevice = await AuthManager.getRememberedDevice();
    if (rememberedDevice != null) {
      final rememberedEmail = rememberedDevice['email']!;
      final rememberedName = rememberedDevice['driverName']!;

      // ðŸ”„ FORSIRAJ REFRESH: Koristi VozacCache mapiranje za ispravno ime
      final correctName = VozacCache.getImeByEmail(rememberedEmail) ?? rememberedName;

      if (correctName == driverName) {
        // ðŸ‘† BIOMETRIJA: TraÅ¾i samo ako sesija nije aktivna (vrati se posle duÅ¾eg vremena)
        debugPrint('ðŸ” [WelcomeScreen] Proveravam sesiju za $correctName...');
        final sessionActive = await AuthManager.isSessionActive();
        debugPrint('ðŸ” [WelcomeScreen] Sesija aktivna: $sessionActive');

        if (!sessionActive) {
          // Sesija je istekla - proveri biometriju ako je ukljuÄena
          final biometricAvailable = await BiometricService.isBiometricAvailable();
          final biometricEnabled = await BiometricService.isBiometricEnabled();

          debugPrint('ðŸ” [WelcomeScreen] Biometrija: available=$biometricAvailable, enabled=$biometricEnabled');

          if (biometricAvailable && biometricEnabled) {
            final authenticated = await BiometricService.authenticate(
              reason: 'Potvrdi identitet za prijavu kao $correctName',
            );

            if (!authenticated) {
              // Korisnik je otkazao ili nije uspeo - idi na manual login
              if (!mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (context) => VozacLoginScreen(vozacIme: driverName),
                ),
              );
              return;
            }
          }
        }

        // Ovaj vozaÄ je zapamÄ‡en na ovom ureÄ‘aju - DIREKTNO AUTO-LOGIN
        debugPrint('ðŸ” [WelcomeScreen] Postavljam sesiju za $correctName');
        await AuthManager.setCurrentDriver(correctName);

        if (!mounted) return;

        // Direktno na Home Screen bez daily check-in
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (context) => _getScreenForDriver(correctName),
          ),
        );
      }
    }

    // AKO NIJE REMEMBERED DEVICE - IDI NA VOZAÄŒ LOGIN
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => VozacLoginScreen(vozacIme: driverName),
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
          gradient: ThemeManager().currentGradient,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  SizedBox(height: screenHeight * 0.04),

                  // ðŸŽ¨ LOGO sa shimmer efektom
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: GestureDetector(
                      onTap: () async {
                        try {
                          if (_isAudioPlaying) {
                            await _audioPlayer.stop();
                            _isAudioPlaying = false;
                          } else {
                            await _audioPlayer.setVolume(0.5);
                            await _audioPlayer.play(AssetSource('kasno_je.mp3'));
                            _isAudioPlaying = true;
                          }
                        } catch (_) {}
                      },
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return ShaderMask(
                            shaderCallback: (bounds) {
                              return LinearGradient(
                                begin: Alignment(-1.5 + 3 * _pulseController.value, 0),
                                end: Alignment(-0.5 + 3 * _pulseController.value, 0),
                                colors: [
                                  Colors.white.withOpacity(0.6),
                                  Colors.white,
                                  Colors.white.withOpacity(0.6),
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

                  const SizedBox(height: 16),

                  // ðŸŽ¯ DOBRODOÅ LI tekst - klikabilno za promenu teme
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: GestureDetector(
                      onTap: () async {
                        await ThemeManager().nextTheme();
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
                          'DOBRODOÅ LI',
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

                  // Subtitle
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Text(
                      'VaÅ¡ pouzdani prevoz',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.7),
                        letterSpacing: 2,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ),

                  SizedBox(height: screenHeight * 0.05),

                  // ðŸš€ GLAVNO DUGME - PRIJAVA PUTNIKA
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const V2PutnikLoginScreen(),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.amber,
                              Colors.amber.shade700,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.amber.withOpacity(0.4),
                              blurRadius: 15,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.login,
                              color: Colors.white,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            const Text(
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

                  // ðŸ“± SEKUNDARNA DUGMAD - O nama i VozaÄi
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Row(
                      children: [
                        // O NAMA
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const ONamaScreen()),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.2),
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: Colors.white.withOpacity(0.9),
                                    size: 28,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'O nama',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.9),
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

                        // VOZAÄŒI
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _showDriverSelectionDialog(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.2),
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.local_taxi,
                                    color: Colors.white.withOpacity(0.9),
                                    size: 28,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'VozaÄi',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.9),
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

                  // ðŸ“ FOOTER
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
                                Colors.white.withOpacity(0.3),
                                Colors.transparent,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Designed â€¢ Developed â€¢ Crafted with balls',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'by Bojan Gavrilovic',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'v6.0.15 â€¢ 2025-2026',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.5),
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

  // ðŸš— Dijalog za izbor vozaÄa
  void _showDriverSelectionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
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
                color: Colors.white.withOpacity(0.2),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Izaberi vozaÄa',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                if (_isLoadingDrivers)
                  const CircularProgressIndicator(color: Colors.white)
                else
                  ..._drivers.map((driver) {
                    // Odredi ikonu na osnovu imena vozaÄa
                    IconData getIconForDriver(String name) {
                      switch (name.toLowerCase()) {
                        case 'bruda':
                          return Icons.local_taxi;
                        case 'bilevski':
                          return Icons.directions_car;
                        case 'bojan':
                          return Icons.airport_shuttle;
                        default:
                          return Icons.person;
                      }
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pop(context); // Zatvori dijalog
                          _loginAsDriver(driver.ime);
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                (driver.color ?? Colors.blue).withOpacity(0.8),
                                Colors.white.withOpacity(0.1),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: (driver.color ?? Colors.blue).withOpacity(0.6),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                getIconForDriver(driver.ime),
                                color: Colors.white,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                driver.ime,
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
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'OtkaÅ¾i',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// ðŸ” Zahtev za dozvolama ako su potrebne
  Future<void> _requestPermissionsIfNeeded() async {
    try {
      final permissionsChecked = await PermissionService.checkAllPermissionsGranted();
      if (!permissionsChecked && mounted) {
        await PermissionService.requestAllPermissionsOnFirstLaunch(context);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('âš ï¸ [WelcomeScreen] Permission request failed: $e');
      }
    }
  }

  /// ðŸ”‹ Show battery optimization warning for Huawei/Xiaomi phones
  Future<void> _checkBatteryOptimization() async {
    try {
      final shouldShow = await BatteryOptimizationService.shouldShowWarning();
      if (shouldShow && mounted) {
        await BatteryOptimizationService.showWarningDialog(context);
      }
    } catch (_) {
      // Battery optimization check failed - silent
    }
  }
}
