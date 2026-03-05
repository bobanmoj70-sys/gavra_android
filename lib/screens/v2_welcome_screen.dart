import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../globals.dart';
import '../models/v2_vozac.dart';
import '../services/realtime/v2_master_realtime_manager.dart';
import '../services/v2_app_settings_service.dart';
import '../services/v2_auth_manager.dart';
import '../services/v2_battery_optimization_service.dart';
import '../services/v2_biometric_service.dart';
import '../services/v2_local_notification_service.dart';
import '../services/v2_permission_service.dart';
import '../services/v2_theme_manager.dart';
import '../utils/v2_vozac_cache.dart';
import 'v2_home_screen.dart';
import 'v2_o_nama_screen.dart';
import 'v2_putnik_login_screen.dart';
import 'v2_vozac_login_screen.dart';
import 'v2_vozac_screen.dart';

Widget _getScreenForDriver(String driverName) {
  // Vozači koji koriste V2VozacScreen umesto V2HomeScreen
  if (V2VozacCache.prefersVozacScreen(driverName)) {
    return const V2VozacScreen();
  }
  return const V2HomeScreen();
}

class V2WelcomeScreen extends StatefulWidget {
  const V2WelcomeScreen({super.key});

  @override
  State<V2WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<V2WelcomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isAudioPlaying = false;
  late final AnimationController _fadeController;
  late final AnimationController _pulseController;
  late final Animation<double> _fadeAnimation;
  bool _updateDialogShown = false;

  // Lista vozača učitana iz baze
  List<V2Vozac> _drivers = [];
  bool _isLoadingDrivers = true;
  String _appVersion = '';
  StreamSubscription<String>? _cacheReadySub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Dodano za lifecycle

    _setupAnimations();
    _loadDrivers(fromInitState: true);
    _loadAppVersion();
    updateInfoNotifier.addListener(_onUpdateInfo);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onUpdateInfo());

    // Inicijalizacija bez blokiranja - dajemo aplikaciji vremena da "udahne"
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _initServicesRecursively();
    });

    // "ZAHTEV ZA DOZVOLAMA - pomeramo ovde iz main.dart da izbegnemo MaterialLocalizations grešku
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      _requestPermissionsIfNeeded();
    });

    // "< PROVERA BATERIJSKE OPTIMIZACIJE - pomeramo ovde iz main.dart
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      _checkBatteryOptimization();
    });
  }

  /// Učitaj vozače direktno iz master cache-a (0 DB upita).
  /// [fromInitState] = true: postavlja fields direktno bez setState (widget još nije build-ovan).
  void _loadDrivers({bool fromInitState = false}) {
    final rm = V2MasterRealtimeManager.instance;
    final vozaci = rm.vozaciCache.values.map((row) => V2Vozac.fromMap(row)).toList()
      ..sort((a, b) => a.ime.compareTo(b.ime));
    if (fromInitState) {
      _drivers = vozaci;
      _isLoadingDrivers = false;
    } else {
      if (mounted)
        setState(() {
          _drivers = vozaci;
          _isLoadingDrivers = false;
        });
    }
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = 'v${info.version}');
    } catch (_) {
      // Fallback - ostavi prazno
    }
  }

  /// > Inicijalizacija servisa jedan po jedan, bez agresivnih await-ova
  Future<void> _initServicesRecursively() async {
    try {
      // 1. Notifikacije
      unawaited(V2LocalNotificationService.initialize(context));

      // 2. Auto-login — tek kada je V2VozacCache spreman (izbjegava race condition)
      if (mounted) {
        _ensureNotificationPermissions();
        _checkAutoLoginWhenReady();
      }
    } catch (e) {
    }
  }

  /// Pokreće auto-login čim V2MasterRealtimeManager bude potpuno inicijalizovan.
  /// Koristi onCacheChanged stream (kancelabilan) umjesto .first.asStream() koje nije.
  void _checkAutoLoginWhenReady() {
    if (V2MasterRealtimeManager.instance.isInitialized) {
      // RM je već spreman — V2VozacCache.initialize() je sigurno pozvan
      _loadDrivers();
      _checkAutoLogin();
      return;
    }
    // RM još nije spreman — čekaj bilo koji cache event i provjeri isInitialized.
    // Koristimo StreamSubscription umjesto .first da bismo mogli cancel() u dispose().
    _cacheReadySub = V2MasterRealtimeManager.instance.onCacheChanged.listen((_) {
      if (!V2MasterRealtimeManager.instance.isInitialized) return;
      _cacheReadySub?.cancel();
      _cacheReadySub = null;
      if (mounted) {
        _loadDrivers(); // osvježi listu vozača na welcome screenu
        _checkAutoLogin();
      }
    });
  }

  Future<void> _ensureNotificationPermissions() async {
    try {
      // On Android request POST_NOTIFICATIONS runtime permission (API 33+)
      if (defaultTargetPlatform == TargetPlatform.android) {
        final status = await Permission.notification.status;
        if (!status.isGranted) {
          await Permission.notification.request();
        }
      }
    } catch (e) {
      // Silently ignore
    }
  }

  // "" AUTO-LOGIN BEZ PESME - Proveri da li je vozač ve logovan
  Future<void> _checkAutoLogin() async {
    // ZPREKINI PESMU ako se auto-login aktivira
    await _stopAudio();

    // "PRVO PROVERI REMEMBERED DEVICE
    final rememberedDevice = await V2AuthManager.getRememberedDevice();
    if (!mounted) return;
    if (rememberedDevice != null) {
      // Auto-login sa zapamenim ureajem
      final email = rememberedDevice['email']!;
      // "" FORSIRAJ ISPRAVNO MAPIRANJE: email -> vozač ime
      try {
        final driverName = V2VozacCache.getImeByEmail(email);
        // Ne dozvoli auto-login ako vozač nije prepoznat
        if (driverName == null || !V2VozacCache.isValidIme(driverName)) {
          // Ostani na welcome/login i ne auto-login
          return;
        }

        // Postavi driver session
        await V2AuthManager.setCurrentDriver(driverName);

        if (!mounted) return;

        // Ako je obavezno ažuriranje aktivno — ostani na Welcome da se prikaže dialog
        if (updateInfoNotifier.value?.isForced == true) return;

        // Direktno na Home Screen bez daily check-in
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (context) => _getScreenForDriver(driverName),
          ),
        );
        return;
      } catch (e) {
        // Nastavi dalje bez auto-login-a
      }
    }

    // Koristi V2AuthManager za session management
    final activeDriver = await V2AuthManager.getCurrentDriver();

    if (activeDriver != null && activeDriver.isNotEmpty) {
      // Vozač je ve logovan - direktno na odgovarajui ekran
      if (!mounted) return;

      // Ako je obavezno ažuriranje aktivno — ostani na Welcome da se prikaže dialog
      if (updateInfoNotifier.value?.isForced == true) return;

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

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    )..repeat();

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    // Start animations
    _fadeController.forward();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Uklanjamo observer
    updateInfoNotifier.removeListener(_onUpdateInfo);
    _cacheReadySub?.cancel();
    _fadeController.dispose();
    _pulseController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  /// Prikazuje dialog za obavezno ažuriranje
  void _onUpdateInfo() {
    final info = updateInfoNotifier.value;
    if (info == null || !mounted) return;
    if (_updateDialogShown) return;
    _updateDialogShown = true;

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
                  // Ikona
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
                  // Naslov
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
                  // Verzija badge
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
                  // Poruka
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
                  // Dugmad
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
                            V2AppSettingsService.openStore();
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
    ).whenComplete(() {
      // Reset uvijek — ako stignu 2+ update eventi, drugi ne smije biti izgubljen
      _updateDialogShown = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
        // Aplikacija ide u pozadinu - zaustavi muziku
        _stopAudio();
        break;
      case AppLifecycleState.resumed:
        // Aplikacija se vraa u foreground - ne radi ništa
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
    // ZPREKINI PESMU kada korisnik počne login
    await _stopAudio();

    // Uklonjena striktna validacija vozača - dozvoljava sve vozače

    // "PRVO PROVERI REMEMBERED DEVICE za ovog vozača
    final rememberedDevice = await V2AuthManager.getRememberedDevice();
    if (rememberedDevice != null) {
      final rememberedEmail = rememberedDevice['email']!;
      final rememberedName = rememberedDevice['driverName']!;

      // "" FORSIRAJ REFRESH: Koristi V2VozacCache mapiranje za ispravno ime
      final correctName = V2VozacCache.getImeByEmail(rememberedEmail) ?? rememberedName;

      if (correctName == driverName) {
        // '? BIOMETRIJA: Traži samo ako sesija nije aktivna (vrati se posle dužeg vremena)
        final sessionActive = await V2AuthManager.isSessionActive();

        if (!sessionActive) {
          // Sesija je istekla - proveri biometriju ako je uključena
          final biometricAvailable = await V2BiometricService.isBiometricAvailable();
          final biometricEnabled = await V2BiometricService.isBiometricEnabled();

          if (biometricAvailable && biometricEnabled) {
            final authenticated = await V2BiometricService.authenticate(
              reason: 'Potvrdi identitet za prijavu kao $correctName',
            );

            if (!authenticated) {
              // Korisnik je otkazao ili nije uspeo - idi na manual login
              if (!mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (context) => V2VozacLoginScreen(vozacIme: driverName),
                ),
              );
              return;
            }
          }
        }

        // Ovaj vozač je zapamen na ovom ureaju - DIREKTNO AUTO-LOGIN
        await V2AuthManager.setCurrentDriver(correctName);

        if (!mounted) return;

        // Direktno na Home Screen bez daily check-in
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (context) => _getScreenForDriver(correctName),
          ),
        );
        return;
      }
    }

    // AKO NIJE REMEMBERED DEVICE - IDI NA VOZA LOGIN
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => V2VozacLoginScreen(vozacIme: driverName),
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

                  // ZLOGO sa shimmer efektom
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
                        } catch (e) {
                        }
                      },
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            return ShaderMask(
                              shaderCallback: (bounds) {
                                return LinearGradient(
                                  begin: Alignment(-1.5 + 3 * _pulseController.value, 0),
                                  end: Alignment(-0.5 + 3 * _pulseController.value, 0),
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

                  // ZDOBRODOŠLI tekst - klikabilno za promenu teme
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

                  // Subtitle
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

                  // s? GLAVNO DUGME - PRIJAVA PUTNIKA
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
                              color: Colors.amber.withValues(alpha: 0.4),
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

                  // "SEKUNDARNA DUGMAD - O nama i Vozači
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
                                MaterialPageRoute(builder: (_) => const V2ONamaScreen()),
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
                                  Icon(
                                    Icons.info_outline,
                                    color: Colors.white.withValues(alpha: 0.9),
                                    size: 28,
                                  ),
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

                        // VOZAI
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _showDriverSelectionDialog(),
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
                                  Icon(
                                    Icons.local_taxi,
                                    color: Colors.white.withValues(alpha: 0.9),
                                    size: 28,
                                  ),
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

                  // "FOOTER
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
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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

  // s- Dijalog za izbor vozača
  void _showDriverSelectionDialog() {
    // Citaj vozace direktno iz cache-a — nema setState na parent widgetu
    final drivers = V2MasterRealtimeManager.instance.vozaciCache.values.map((row) => V2Vozac.fromMap(row)).toList()
      ..sort((a, b) => a.ime.compareTo(b.ime));
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
                Text(
                  'Izaberi vozača',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                if (drivers.isEmpty)
                  const CircularProgressIndicator(color: Colors.white)
                else
                  ...drivers.map((driver) {
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
                                (driver.color ?? Colors.blue).withValues(alpha: 0.8),
                                Colors.white.withValues(alpha: 0.1),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: (driver.color ?? Colors.blue).withValues(alpha: 0.6),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                V2VozacCache.getIconForDriver(driver.ime),
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
        );
      },
    );
  }

  /// "Zahtev za dozvolama ako su potrebne
  Future<void> _requestPermissionsIfNeeded() async {
    try {
      final permissionsChecked = await V2PermissionService.checkAllPermissionsGranted();
      if (!permissionsChecked && mounted) {
        await V2PermissionService.requestAllPermissionsOnFirstLaunch(context);
      }
    } catch (e) {
    }
  }

  /// "< Show battery optimization warning for Huawei/Xiaomi phones
  Future<void> _checkBatteryOptimization() async {
    try {
      final shouldShow = await V2BatteryOptimizationService.shouldShowWarning();
      if (shouldShow && mounted) {
        await V2BatteryOptimizationService.showWarningDialog(context);
      }
    } catch (_) {
      // Battery optimization check failed - silent
    }
  }
}
