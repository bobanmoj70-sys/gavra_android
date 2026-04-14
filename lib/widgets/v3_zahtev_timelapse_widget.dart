import 'package:flutter/material.dart';

import '../models/v3_zahtev.dart';
import '../utils/v3_dan_helper.dart';
import '../utils/v3_status_filters.dart';
import '../utils/v3_string_utils.dart';

/// Zajednički widget za prikaz timelapse info reda na zahtev karticama.
/// Koristi se u: posiljke, radnici, ucenici, zahtevi_dnevni screenima.
class V3ZahtevTimelapseWidget extends StatelessWidget {
  final V3Zahtev zahtev;

  /// Tekst koji se prikazuje dok zahtev čeka odgovor.
  /// Npr. 'čeka odgovor...' ili 'čeka kron...'
  final String cekaTekst;

  const V3ZahtevTimelapseWidget({
    super.key,
    required this.zahtev,
    this.cekaTekst = 'čeka kron...',
  });

  @override
  Widget build(BuildContext context) {
    final created = zahtev.createdAt;
    final updated = zahtev.updatedAt;
    if (created == null) return const SizedBox.shrink();

    String fmt(DateTime dt) => V3DanHelper.formatVreme(dt.hour, dt.minute);

    String odgovorInfo;
    if (updated != null && updated.isAfter(created.add(const Duration(seconds: 5)))) {
      final diff = updated.difference(created);
      final mins = diff.inMinutes;
      final secs = diff.inSeconds % 60;
      final diffStr = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';

      String odgovorLabel;
      if (V3StatusFilters.isOfferLike(zahtev.status) && (zahtev.altVremePre != null || zahtev.altVremePosle != null)) {
        final alts = [
          if (zahtev.altVremePre != null) V3StringUtils.formatAlternativeTime(zahtev.altVremePre),
          if (zahtev.altVremePosle != null) V3StringUtils.formatAlternativeTime(zahtev.altVremePosle),
        ].join(' / ');
        odgovorLabel = '⚠️ alt: $alts';
      } else {
        odgovorLabel = switch (V3StatusFilters.normalizeStatus(zahtev.status)) {
          'odobreno' => '✅',
          'alternativa' => '⚠️',
          'odbijeno' => '❌',
          'otkazano' => '⛔',
          _ => '🕒',
        };
      }

      odgovorInfo = '${fmt(created)} → ${fmt(updated)} ($diffStr) $odgovorLabel';
    } else {
      odgovorInfo = '${fmt(created)} · $cekaTekst';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '⏱ $odgovorInfo',
        style: const TextStyle(color: Colors.white24, fontSize: 11),
      ),
    );
  }
}
