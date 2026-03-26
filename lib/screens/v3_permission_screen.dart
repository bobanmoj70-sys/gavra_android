import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';

import '../utils/v3_animation_utils.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_state_utils.dart';

/// Prikazuje se samo jednom — pri prvom pokretanju aplikacije.
/// U ovom koraku traži samo Notifikacije.
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
  bool _locationDisclosureAccepted = false;

  @override
  void initState() {
    super.initState();
    _animCtrl = V3AnimationUtils.createPermissionController(vsync: this);
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut),
    );
    _animCtrl.forward();
  }

  @override
  void dispose() {
    V3AnimationUtils.disposeController('permission');
    super.dispose();
  }

  Future<void> _onOdobri() async {
    if (_loading) return;
    if (!_locationDisclosureAccepted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Potvrdite obaveštenje o korišćenju lokacije da biste nastavili.'),
        ),
      );
      return;
    }
    V3StateUtils.safeSetState(this, () => _loading = true);

    try {
      // Notifikacije (vozači + putnici)
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
      V3StateUtils.safeSetState(this, () => _loading = false);
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
      body: V3ContainerUtils.gradientContainer(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D1B2A), Color(0xFF1A2E44)],
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
                    V3ContainerUtils.iconContainer(
                      width: V3ContainerUtils.responsiveHeight(context, 88),
                      height: V3ContainerUtils.responsiveHeight(context, 88),
                      backgroundColor: Colors.blueAccent.withValues(alpha: 0.12),
                      borderRadiusGeometry: BorderRadius.circular(44), // Circle effect
                      border: Border.all(
                        color: Colors.blueAccent.withValues(alpha: 0.4),
                        width: 2,
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
                      'Pre nastavka pročitajte obaveštenje o korišćenju podataka.\nU ovom koraku odobravate notifikacije.',
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
                      icon: Icons.notifications_rounded,
                      color: const Color(0xFFAF52DE),
                      title: 'Notifikacije',
                      subtitle: 'za vozače i putnike (nova putovanja, statusi, izmene)',
                    ),

                    const SizedBox(height: 16),

                    V3ContainerUtils.styledContainer(
                      padding: const EdgeInsets.all(14),
                      backgroundColor: const Color(0xFFFFA726).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFA726).withValues(alpha: 0.7), width: 1.4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'UOČLJIVO OBAVEŠTENJE O LOKACIJI',
                            style: TextStyle(
                              color: Color(0xFFFFCC80),
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Aplikacija prikuplja lokaciju isključivo za vozače tokom aktivne vožnje radi praćenja rute, ETA i operativne koordinacije. Lokacija se ne koristi za oglase i ne prikuplja se za putnike van vozačkog toka.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: 12.8,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: const Color(0xFF34C759),
                      value: _locationDisclosureAccepted,
                      onChanged: _loading
                          ? null
                          : (value) {
                              V3StateUtils.safeSetState(
                                this,
                                () => _locationDisclosureAccepted = value ?? false,
                              );
                            },
                      title: Text(
                        'Razumem obaveštenje o korišćenju lokacije i saglasan/saglasna sam sa ovom namenom.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 12.6,
                          height: 1.35,
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Napomena
                    Text(
                      'Dozvole možete kasnije promeniti u podešavanjima telefona.',
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
                          child: V3ButtonUtils.elevatedButton(
                            onPressed: _loading ? null : _onOdobri,
                            text: 'ODOBRI',
                            icon: Icons.check_circle_rounded,
                            backgroundColor: const Color(0xFF34C759),
                            foregroundColor: Colors.white,
                            isLoading: _loading,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            borderRadius: BorderRadius.circular(14),
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
          V3ContainerUtils.iconContainer(
            width: V3ContainerUtils.responsiveHeight(context, 42),
            height: V3ContainerUtils.responsiveHeight(context, 42),
            backgroundColor: color.withValues(alpha: 0.15),
            borderRadiusGeometry: BorderRadius.circular(10),
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
