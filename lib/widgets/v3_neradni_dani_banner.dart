import 'package:flutter/material.dart';

import '../globals.dart';
import '../l10n/app_translations.dart';
import '../services/v3_locale_manager.dart';
import '../utils/v3_belgrade_time.dart';
import 'v3_shimmer_banner.dart';

String _neradniDaniTr(String key) {
  final code = V3LocaleManager().currentLocale.languageCode;
  final t = AppTranslations.ns('neradniDaniBanner');
  return t[key]?[code] ?? t[key]?['sr'] ?? key;
}

/// Inline baner koji prikazuje neradne dane iz operativne nedelje.
/// Koristi [neradniDaniNotifier] i filtrira dane iz operativne sedmice.
/// Ako nema neradnih dana, ne prikazuje ništa (SizedBox.shrink).
class V3NeradniDaniBanner extends StatelessWidget {
  const V3NeradniDaniBanner({super.key, this.margin});

  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Map<String, String>>>(
      valueListenable: neradniDaniNotifier,
      builder: (context, rules, _) {
        final weekRange = V3DanHelper.schedulingWeekRange();
        final start = weekRange.start;
        final end = weekRange.end;
        final today = V3DanHelper.dateOnly(DateTime.now());

        final lines = <String>[];
        for (final rule in rules) {
          final dateIso = V3BelgradeTime.parseIsoDatePart(rule['date'] ?? '');
          final date = DateTime.tryParse(dateIso);
          if (date == null) continue;

          final onlyDate = V3DanHelper.dateOnly(date);
          if (onlyDate.isBefore(start) || onlyDate.isAfter(end)) continue;
          if (onlyDate.isBefore(today)) continue;

          final dayName = V3DanHelper.fullName(onlyDate);
          final scope = (rule['scope'] ?? 'all').toLowerCase();
          final scopeLabel = scope == 'bc'
              ? 'BC'
              : scope == 'vs'
                  ? 'VS'
                  : '';
          final reason = (rule['reason'] ?? '').trim();
          final reasonText = reason.isEmpty ? _neradniDaniTr('neradanDan') : reason;
          final scopeText = scopeLabel.isEmpty ? '' : ' [$scopeLabel]';
          lines.add('• $dayName ($dateIso)$scopeText — $reasonText');
        }

        if (lines.isEmpty) return const SizedBox.shrink();

        return V3ShimmerBanner(
          margin: margin ?? EdgeInsets.zero,
          borderRadius: 12,
          backgroundColor: const Color(0xFFEF6C00),
          borderColor: const Color(0xFFFFB74D),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _neradniDaniTr('naslov'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  lines.join('\n'),
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
