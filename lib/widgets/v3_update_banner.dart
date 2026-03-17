import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../globals.dart';

/// Banner koji se prikazuje kada postoji update (opcioni ili obavezni).
/// Koristi se na V3HomeScreen i V3PutnikProfilScreen.
/// Ako je obavezni update (isForced), prikazuje fullscreen blokadu.
class V3UpdateBanner extends StatelessWidget {
  const V3UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<V2UpdateInfo?>(
      valueListenable: updateInfoNotifier,
      builder: (context, info, _) {
        if (info == null) return const SizedBox.shrink();
        if (info.isForced) return _ForceUpdateOverlay(info: info);
        return _UpdateBannerContent(info: info);
      },
    );
  }
}

/// Fullscreen overlay koji blokira cijelu aplikaciju pri obaveznom updatu.
class _ForceUpdateOverlay extends StatelessWidget {
  final V2UpdateInfo info;
  const _ForceUpdateOverlay({required this.info});

  Future<void> _openStore() async {
    final url = Uri.tryParse(info.storeUrl);
    if (url != null && await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Stack(
        children: [
          // Zamračuje cijeli ekran ispod
          Positioned.fill(
            child: AbsorbPointer(
              absorbing: true,
              child: Container(color: Colors.black.withValues(alpha: 0.85)),
            ),
          ),
          // Kartice u centru
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.system_update, color: Colors.redAccent, size: 64),
                  const SizedBox(height: 20),
                  const Text(
                    'Obavezno ažuriranje',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Ova verzija aplikacije više nije podržana.\nMolimo ažurirajte na verziju ${info.latestVersion} kako biste nastavili s korišćenjem.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 14,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _openStore,
                      icon: const Icon(Icons.download_rounded),
                      label: const Text(
                        'Ažuriraj aplikaciju',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
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
        ],
      ),
    );
  }
}

class _UpdateBannerContent extends StatelessWidget {
  final V2UpdateInfo info;
  const _UpdateBannerContent({required this.info});

  Future<void> _openStore() async {
    final url = Uri.tryParse(info.storeUrl);
    if (url != null && await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isForced = info.isForced;
    final bgColor = isForced ? const Color(0xFFB71C1C) : const Color(0xFFE65100);
    final icon = isForced ? Icons.system_update : Icons.new_releases_rounded;
    final label =
        isForced ? 'Obavezno ažuriranje — v${info.latestVersion}' : 'Nova verzija v${info.latestVersion} dostupna';

    return GestureDetector(
      onTap: _openStore,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: bgColor.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 14),
          ],
        ),
      ),
    );
  }
}
