import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/v2_theme_manager.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_error_utils.dart';
import '../utils/v3_state_utils.dart';

class V3ONamaScreen extends StatefulWidget {
  const V3ONamaScreen({super.key});

  @override
  State<V3ONamaScreen> createState() => _V3ONamaScreenState();
}

class _V3ONamaScreenState extends State<V3ONamaScreen> {
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      V3StateUtils.safeSetState(this, () => _appVersion = 'v${info.version} (${info.buildNumber})');
    } catch (_) {
      if (!mounted) return;
      V3StateUtils.safeSetState(this, () => _appVersion = 'v1.0.0');
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final status = await Permission.phone.status;
    if (!status.isGranted) {
      final result = await Permission.phone.request();
      if (!result.isGranted) {
        V3ErrorUtils.validationError(this, context, 'Dozvola za pozive je potrebna');
        return;
      }
    }
    final uri = Uri(scheme: 'tel', path: phoneNumber);
    if (!mounted) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      V3AppSnackBar.error(context, 'Ne mogu da otvorim aplikaciju za pozive');
    }
  }

  Future<void> _sendEmail(String email) async {
    final uri = Uri(scheme: 'mailto', path: email);
    if (!mounted) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      V3AppSnackBar.error(context, 'Ne mogu da otvorim email aplikaciju');
    }
  }

  Future<void> _openMaps() async {
    final uri = Uri.parse(
      'https://share.here.com/r/44.8983,21.4152,Mihajla+Pupina+74+Bela+Crkva',
    );
    if (!mounted) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      V3AppSnackBar.error(context, 'Ne mogu da otvorim aplikaciju za mape');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: V2ThemeManager().currentGradient,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            '📖 O nama',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              _buildGlassCard(
                icon: Icons.history,
                title: 'Naša priča',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Limo servis "Gavra 013" osnovan je 25. aprila 2003. godine u Beloj Crkvi.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Firmu je osnovao Branislav Gavrilović, a danas je vodi njegov sin Bojan Gavrilović, nastavljajući porodičnu tradiciju kvalitetnog prevoza putnika.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Više od 20 godina pružamo pouzdanu uslugu prevoza putnika.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildGlassCard(
                icon: Icons.contact_phone,
                title: 'Kontakt',
                child: Column(
                  children: [
                    _buildContactRow(
                      icon: Icons.location_on,
                      label: 'Adresa',
                      value: 'Mihajla Pupina 74, 26340 Bela Crkva',
                      onTap: _openMaps,
                    ),
                    const Divider(color: Colors.white24, height: 20),
                    _buildContactRow(
                      icon: Icons.phone_android,
                      label: 'Mobilni',
                      value: '064/116-2560',
                      onTap: () => _makePhoneCall('0641162560'),
                    ),
                    const Divider(color: Colors.white24, height: 20),
                    _buildContactRow(
                      icon: Icons.email,
                      label: 'Email',
                      value: 'gavriconi19@gmail.com',
                      onTap: () => _sendEmail('gavriconi19@gmail.com'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildGlassCard(
                icon: Icons.business,
                title: 'Podaci o firmi',
                child: Column(
                  children: [
                    _buildInfoRow('Pun naziv', 'PR LIMO SERVIS GAVRA 013'),
                    const Divider(color: Colors.white24, height: 16),
                    _buildInfoRow('Delatnost', '4932 - Limo servis + Taksi prevoz'),
                    const Divider(color: Colors.white24, height: 16),
                    _buildInfoRow('PIB', '102853497'),
                    const Divider(color: Colors.white24, height: 16),
                    _buildInfoRow('Matični broj', '55572178'),
                    const Divider(color: Colors.white24, height: 16),
                    _buildInfoRow('Datum osnivanja', '25.04.2003.'),
                    const Divider(color: Colors.white24, height: 16),
                    _buildInfoRow('Žiro račun', '340-11436537-92'),
                    const Divider(color: Colors.white24, height: 16),
                    _buildInfoRow('Vlasnik', 'Bojan Gavrilović'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildGlassCard(
                icon: Icons.phone_android,
                title: 'Aplikacija',
                child: Column(
                  children: [
                    _buildInfoRow('Verzija', _appVersion),
                    const Divider(color: Colors.white24, height: 16),
                    _buildInfoRow('Platforma', 'Android'),
                    const SizedBox(height: 12),
                    Text(
                      '© 2024-2026 Gavra 013. Sva prava zadržana.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Column(
                  children: [
                    const Text('🕯️', style: TextStyle(fontSize: 32)),
                    const SizedBox(height: 8),
                    Text(
                      'U sećanje na Branislava Gavrilovića',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      'Osnivač Gavra 013',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.3),
                Colors.white.withValues(alpha: 0.1),
              ],
            ),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/logo_transparent.png',
              width: 90,
              height: 90,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Gavra 013',
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            shadows: [Shadow(offset: Offset(0, 2), blurRadius: 4, color: Colors.black38)],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Limo servis',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 16,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Iznajmljivanje putničkih vozila sa vozačem',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 16,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: Colors.greenAccent, size: 16),
              SizedBox(width: 6),
              Text(
                'Od 2003. godine',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _buildGlassCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.15),
            Colors.white.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white70, size: 22),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  static Widget _buildContactRow({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, color: Colors.white60, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                  ),
                  Text(
                    value,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            if (onTap != null) Icon(Icons.arrow_forward_ios, color: Colors.white.withValues(alpha: 0.4), size: 16),
          ],
        ),
      ),
    );
  }

  static Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
