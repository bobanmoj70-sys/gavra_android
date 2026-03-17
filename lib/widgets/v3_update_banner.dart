import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../globals.dart';

/// Banner koji se prikazuje kada postoji update (opcioni ili obavezni).
/// Koristi se na V3HomeScreen i V3PutnikProfilScreen.
class V3UpdateBanner extends StatelessWidget {
  const V3UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<V2UpdateInfo?>(
      valueListenable: updateInfoNotifier,
      builder: (context, info, _) {
        if (info == null) return const SizedBox.shrink();
        return _UpdateBannerContent(info: info);
      },
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
