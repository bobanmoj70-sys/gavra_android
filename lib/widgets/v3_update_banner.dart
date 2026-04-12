import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../globals.dart';
import '../utils/v3_animation_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_style_helper.dart';

/// Forced-update gate za aplikaciju.
/// Koristi se na V3HomeScreen, V3PutnikProfilScreen i V3VozacScreen.
/// Kada je update obavezan (`isForced=true`), prikazuje fullscreen blokadu preko cele aplikacije.
class V3UpdateBanner extends StatefulWidget {
  const V3UpdateBanner({super.key});

  @override
  State<V3UpdateBanner> createState() => _V3UpdateBannerState();
}

class _V3UpdateBannerState extends State<V3UpdateBanner> {
  static bool _forceDialogOpen = false;
  static String? _dialogSignature;

  @override
  void initState() {
    super.initState();
    updateInfoNotifier.addListener(_handleUpdateInfoChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handleUpdateInfoChange();
    });
  }

  @override
  void dispose() {
    updateInfoNotifier.removeListener(_handleUpdateInfoChange);
    super.dispose();
  }

  void _handleUpdateInfoChange() {
    final info = updateInfoNotifier.value;
    if (!mounted) return;

    if (info == null || !info.isForced) {
      if (_forceDialogOpen) {
        final nav = Navigator.of(context, rootNavigator: true);
        if (nav.canPop()) {
          nav.pop();
        }
        _forceDialogOpen = false;
        _dialogSignature = null;
      }
      return;
    }

    final signature = [
      info.isMaintenance,
      info.latestVersion,
      info.maintenanceTitle,
      info.maintenanceMessage,
    ].join('|');

    if (_forceDialogOpen && _dialogSignature == signature) return;
    if (_forceDialogOpen) return;

    _forceDialogOpen = true;
    _dialogSignature = signature;

    showGeneralDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierLabel: 'force_update',
      barrierColor: Colors.black.withValues(alpha: 0.72),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, __) =>
          info.isMaintenance ? _MaintenanceDialog(info: info) : _ForceUpdateDialog(info: info),
      transitionBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    ).whenComplete(() {
      _forceDialogOpen = false;
      _dialogSignature = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _MaintenanceDialog extends StatefulWidget {
  final V2UpdateInfo info;
  const _MaintenanceDialog({required this.info});

  @override
  State<_MaintenanceDialog> createState() => _MaintenanceDialogState();
}

class _MaintenanceDialogState extends State<_MaintenanceDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
      debugLabel: 'Maintenance Pulse Animation',
    )..repeat(reverse: true);
    _pulseAnim = V3AnimationUtils.createTween(
      controller: _pulseCtrl,
      begin: 0.92,
      end: 1.08,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: AbsorbPointer(
                absorbing: true,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xF2141619), Color(0xF2212428)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: V3ContainerUtils.styledContainer(
                  backgroundColor: const Color(0xFF161A1E),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFFFD54F), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.44),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  padding: const EdgeInsets.fromLTRB(22, 28, 22, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ScaleTransition(
                        scale: _pulseAnim,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.construction_rounded, color: Color(0xFFFFD54F), size: 34),
                            SizedBox(width: 8),
                            Icon(Icons.engineering_rounded, color: Color(0xFFFFD54F), size: 34),
                            SizedBox(width: 8),
                            Icon(Icons.warning_amber_rounded, color: Color(0xFFFFD54F), size: 34),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.info.maintenanceTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0x26FFD54F),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0x66FFD54F)),
                        ),
                        child: const Text(
                          '⛔ Radovi u toku — ne diraj kablove 😄',
                          style: TextStyle(
                            color: Color(0xFFFFD54F),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.info.maintenanceMessage,
                        style: TextStyle(
                          color: V3StyleHelper.whiteAlpha75,
                          fontSize: 13,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fullscreen modal koji blokira celu aplikaciju pri obaveznom updatu.
class _ForceUpdateDialog extends StatefulWidget {
  final V2UpdateInfo info;
  const _ForceUpdateDialog({required this.info});

  @override
  State<_ForceUpdateDialog> createState() => _ForceUpdateDialogState();
}

class _ForceUpdateDialogState extends State<_ForceUpdateDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;
  String _installedVersion = '';

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
      debugLabel: 'Force Update Pulse Animation',
    )..repeat(reverse: true);
    _pulseAnim = V3AnimationUtils.createTween(
      controller: _pulseCtrl,
      begin: 0.9,
      end: 1.1,
      curve: Curves.easeInOut,
    );
    _loadInstalledVersion();
  }

  Future<void> _loadInstalledVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _installedVersion = info.version.trim());
    } catch (_) {
      return;
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _openStore() async {
    final url = Uri.tryParse(widget.info.storeUrl);
    if (url != null && await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: AbsorbPointer(
                absorbing: true,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xF20D0D0D), Color(0xF2260B12)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: V3ContainerUtils.styledContainer(
                  backgroundColor: const Color(0xFF171C2C),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.32), width: 1.4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.42),
                      blurRadius: 30,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: Colors.redAccent.withValues(alpha: 0.18),
                      blurRadius: 38,
                      spreadRadius: 2,
                    ),
                  ],
                  padding: const EdgeInsets.fromLTRB(26, 32, 26, 26),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ScaleTransition(
                        scale: _pulseAnim,
                        child: Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const RadialGradient(
                              colors: [Color(0xFFFF5A6A), Color(0xFFB1002D)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.redAccent.withValues(alpha: 0.45),
                                blurRadius: 20,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.system_update_rounded, color: Colors.white, size: 40),
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Potrebno ažuriranje',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      V3ContainerUtils.styledContainer(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        backgroundColor: Colors.redAccent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.38)),
                        child: Text(
                          'verzija ${_installedVersion.isNotEmpty ? _installedVersion : widget.info.latestVersion}',
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Ova verzija aplikacije više nije podržana. Ažurirajte aplikaciju da biste nastavili rad.',
                        style: TextStyle(
                          color: V3StyleHelper.whiteAlpha75,
                          fontSize: 13,
                          height: 1.55,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _openStore,
                          icon: const Icon(Icons.download_rounded, size: 20),
                          label: const Text(
                            'Ažuriraj aplikaciju',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            elevation: 8,
                            shadowColor: Colors.redAccent.withValues(alpha: 0.45),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
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
    );
  }
}
