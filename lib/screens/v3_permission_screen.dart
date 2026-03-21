import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';

import '../utils/v3_state_utils.dart';

/// Prikazuje se samo jednom — pri prvom pokretanju aplikacije.
/// Traži GPS, Pozive i Notifikacije.
class V3PermissionScreen extends StatefulWidget {
  final VoidCallback onDone;

  const V3PermissionScreen({super.key, required this.onDone});

  static const _storage = FlutterSecureStorage();
  static const _shownKey = 'v3_permission_screen_shown';

  /// Provjeri da li je screen već prikazan — poziva se iz welcome screena.
  static Future<bool> shouldShow() async {
    final val = await _storage.read(key: _shownKey);
    return val != 'true';
  }

  @override
  State<V3PermissionScreen> createState() => _V3PermissionScreenState();
}

class _V3PermissionScreenState extends State<V3PermissionScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut),
    );
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _onOdobri() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      // 1. GPS (Request and wait)
      final locStatus = await Permission.location.request();
      debugPrint('Location permission: $locStatus');

      // 2. Pozivi (Request and wait)
      final phoneStatus = await Permission.phone.request();
      debugPrint('Phone permission: $phoneStatus');

      // 3. Notifikacije
      if (Platform.isAndroid) {
        final notifStatus = await Permission.notification.request();
        debugPrint('Notification permission: $notifStatus');
      } else if (Platform.isIOS) {
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      }
    } catch (e) {
      debugPrint('Greška pri proveri: $e');
    } finally {
      V3StateUtils.safeSetState(this, () => setState(() => _loading = false));
    }

    // Tek nakon što su svi dijalozi prošli, pišemo da je prikazano i gasimo screen
    await V3PermissionScreen._storage.write(key: V3PermissionScreen._shownKey, value: 'true');
    if (mounted) widget.onDone();
  }

  Future<void> _onPreskoci() async {
    await V3PermissionScreen._storage.write(key: V3PermissionScreen._shownKey, value: 'true');
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D1B2A), Color(0xFF1A2E44)],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 24),

                    // Ikona
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.blueAccent.withValues(alpha: 0.12),
                        border: Border.all(
                          color: Colors.blueAccent.withValues(alpha: 0.4),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.shield_rounded,
                        color: Colors.blueAccent,
                        size: 44,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Naslov
                    const Text(
                      'Podešavanje aplikacije',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 10),

                    Text(
                      'Za potpunu funkcionalnost\naplikacije potrebne su sledeće dozvole:',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 14,
                        height: 1.6,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 24),

                    // Permission stavke
                    _PermissionItem(
                      icon: Icons.location_on_rounded,
                      color: const Color(0xFF34C759),
                      title: 'GPS lokacija',
                      subtitle: 'za navigaciju do putnika',
                    ),
                    const SizedBox(height: 12),
                    _PermissionItem(
                      icon: Icons.phone_rounded,
                      color: const Color(0xFF007AFF),
                      title: 'Pozivi',
                      subtitle: 'za kontaktiranje putnika',
                    ),
                    const SizedBox(height: 12),
                    _PermissionItem(
                      icon: Icons.notifications_rounded,
                      color: const Color(0xFFAF52DE),
                      title: 'Notifikacije',
                      subtitle: 'za nova putovanja',
                    ),

                    const SizedBox(height: 24),

                    // Napomena
                    Text(
                      'Dozvole se zahtevaju samo jednom. Možete ih\nkasnije promeniti u podešavanjima telefona.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 12,
                        height: 1.6,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 20),

                    // Dugmad
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: _loading ? null : _onPreskoci,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                              ),
                            ),
                            child: Text(
                              'PRESKOČI',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: _loading ? null : _onOdobri,
                            icon: _loading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_circle_rounded, size: 20),
                            label: const Text(
                              'ODOBRI',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF34C759),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _PermissionItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
