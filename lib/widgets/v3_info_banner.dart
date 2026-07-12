import 'package:flutter/material.dart';

import '../globals.dart';
import '../services/v3/v3_putnik_service.dart';
import '../services/v3/v3_vozac_service.dart';
import 'v3_shimmer_banner.dart';

/// Inline baner koji prikazuje jednu admin-kontrolisanu info poruku.
/// Koristi [infoBannerNotifier] i vraća SizedBox.shrink ako nije uključen,
/// nema sadržaja ili trenutni korisnik ne pripada odabranoj publici.
class V3InfoBanner extends StatelessWidget {
  const V3InfoBanner({super.key, this.margin});

  final EdgeInsetsGeometry? margin;

  static const Map<String, Color> _colorMap = {
    'amber': Color(0xFFEF6C00),
    'blue': Color(0xFF1565C0),
    'red': Color(0xFFC62828),
    'green': Color(0xFF2E7D32),
  };

  static const Map<String, Color> _borderColorMap = {
    'amber': Color(0xFFFFB74D),
    'blue': Color(0xFF64B5F6),
    'red': Color(0xFFEF5350),
    'green': Color(0xFF66BB6A),
  };

  Color _resolveColor(String color, Map<String, Color> map) {
    return map[color.toLowerCase()] ?? map['amber']!;
  }

  /// Vraća trenutnu ulogu korisnika: 'vozac' ili vrednost `tip_putnika`.
  static String? _currentUserRole() {
    if (V3VozacService.currentVozac != null) return 'vozac';
    final putnik = V3PutnikService.currentPutnik;
    if (putnik != null) {
      final tip = (putnik['tip_putnika'] ?? '').toString().trim().toLowerCase();
      return tip.isEmpty ? 'dnevni' : tip;
    }
    return null;
  }

  static bool _audienceMatches(List<String> audience, String? role) {
    if (audience.contains('svi')) return true;
    if (role == null) return false;

    if (role == 'vozac') return audience.contains('vozaci');

    // Putnici
    if (audience.contains('putnici')) return true;
    if (role == 'radnik') return audience.contains('radnici');
    if (role == 'ucenik') return audience.contains('ucenici');

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<V3InfoBannerData>(
      valueListenable: infoBannerNotifier,
      builder: (context, data, _) {
        if (!data.isVisible) return const SizedBox.shrink();
        if (!_audienceMatches(data.audience, _currentUserRole())) {
          return const SizedBox.shrink();
        }

        return V3ShimmerBanner(
          margin: margin ?? EdgeInsets.zero,
          borderRadius: 12,
          backgroundColor: _resolveColor(data.color, _colorMap).withValues(alpha: 0.22),
          borderColor: _resolveColor(data.color, _borderColorMap),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '📢 ${data.title}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  data.message,
                  style: const TextStyle(color: Colors.white, fontSize: 12.5),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
