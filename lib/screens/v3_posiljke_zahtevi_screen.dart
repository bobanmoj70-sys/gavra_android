import 'package:flutter/material.dart';

import '../models/v3_zahtev.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_putnik_service.dart';
import '../theme.dart';
import '../utils/v3_dan_helper.dart';
import '../utils/v3_string_utils.dart';

/// V3 ekran za prikaz i upravljanje zahtevima tipa "pošiljka".
/// Admin odobrava / odbija / otkazuje pošiljke.
class V3PosiljkeZahteviScreen extends StatefulWidget {
  const V3PosiljkeZahteviScreen({super.key});

  @override
  State<V3PosiljkeZahteviScreen> createState() => _V3PosiljkeZahteviScreenState();
}

class _V3PosiljkeZahteviScreenState extends State<V3PosiljkeZahteviScreen> {
  // ─── Helpers ─────────────────────────────────────────────────────────────

  /// Svi zahtevi čiji putnik ima tip == 'posiljka' i koje je sam poslao
  List<V3Zahtev> _getPosiljkeZahtevi() {
    final rm = V3MasterRealtimeManager.instance;
    final posiljkaPutnici = rm.putniciCache.values
        .where((p) => (p['tip_putnika'] as String? ?? '').toLowerCase() == 'posiljka')
        .map((p) => p['id'] as String)
        .toSet();

    final zahtevi = rm.zahteviCache.values
        .where((r) {
          if (!posiljkaPutnici.contains(r['putnik_id'])) return false;
          // Samo zahtevi koje je pošiljatelj sam poslao (created_by počinje sa 'putnik:')
          final createdBy = r['created_by'] as String? ?? '';
          return createdBy.startsWith('putnik:');
        })
        .map((r) => V3Zahtev.fromJson(r))
        .toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));

    return zahtevi;
  }

  String? _opisPosiljke(String putnikId) {
    final data = V3MasterRealtimeManager.instance.putniciCache[putnikId];
    return data?['opis_posiljke'] as String?;
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: V3MasterRealtimeManager.instance.onChange,
      builder: (context, _) {
        final zahtevi = _getPosiljkeZahtevi();

        final brObrada = zahtevi.where((z) => z.status == 'obrada').length;
        final brOdobreno = zahtevi.where((z) => z.status == 'odobreno').length;
        final brOdbijeno = zahtevi.where((z) => z.status == 'odbijeno').length;
        final brOtkazano = zahtevi.where((z) => z.status == 'otkazano').length;

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            foregroundColor: Colors.white,
            automaticallyImplyLeading: false,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Pošiljke',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
                if (brObrada > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.6)),
                    ),
                    child: Text(
                      '$brObrada',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ],
            ),
          ),
          body: V3ContainerUtils.backgroundContainer(
            gradient: Theme.of(context).backgroundGradient,
            child: SafeArea(
              child: Column(
                children: [
                  // ── Summary badges ─────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: [
                        if (brObrada > 0) _badge('🟡 $brObrada obrada', Colors.amber),
                        if (brOdobreno > 0) _badge('🟢 $brOdobreno odobreno', Colors.greenAccent),
                        if (brOdbijeno > 0) _badge('🔴 $brOdbijeno odbijeno', Colors.redAccent),
                        if (brOtkazano > 0) _badge('⛔ $brOtkazano otkazano', Colors.orange),
                      ],
                    ),
                  ),

                  // ── Lista ──────────────────────────────────────────
                  Expanded(
                    child: zahtevi.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.local_shipping_outlined,
                                    size: 56, color: Colors.white.withValues(alpha: 0.25)),
                                const SizedBox(height: 14),
                                Text(
                                  'Nema pošiljki',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                            physics: const BouncingScrollPhysics(),
                            itemCount: zahtevi.length,
                            itemBuilder: (_, i) {
                              final z = zahtevi[i];
                              final opis = _opisPosiljke(z.putnikId);
                              return _ZahtevKartica(
                                zahtev: z,
                                opisPosiljke: opis,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _badge(String tekst, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
        ),
        child: Text(tekst, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

// ─── Zahtev kartica ───────────────────────────────────────────────────────────
class _ZahtevKartica extends StatelessWidget {
  const _ZahtevKartica({
    required this.zahtev,
    this.opisPosiljke,
  });

  final V3Zahtev zahtev;
  final String? opisPosiljke;

  Widget _buildTimelapse(V3Zahtev z) {
    final created = z.createdAt;
    final updated = z.updatedAt;
    if (created == null) return const SizedBox.shrink();

    String fmt(DateTime dt) {
      return V3DanHelper.formatVreme(dt.hour, dt.minute);
    }

    String odgovorInfo;
    if (updated != null && updated.isAfter(created.add(const Duration(seconds: 5)))) {
      final diff = updated.difference(created);
      final mins = diff.inMinutes;
      final secs = diff.inSeconds % 60;
      final diffStr = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';

      String odgovorLabel;
      if ((z.status == 'alternativa' || z.status == 'ponuda') && (z.altVremePre != null || z.altVremePosle != null)) {
        final alts = [
          if (z.altVremePre != null) V3StringUtils.formatAlternativeTime(z.altVremePre),
          if (z.altVremePosle != null) V3StringUtils.formatAlternativeTime(z.altVremePosle),
        ].join(' / ');
        odgovorLabel = '⚠️ alt: $alts';
      } else {
        odgovorLabel = switch (z.status) {
          'odobreno' => '✅',
          'alternativa' || 'ponuda' => '⚠️',
          'odbijeno' => '❌',
          'otkazano' => '⛔',
          _ => '🕒',
        };
      }

      odgovorInfo = '${fmt(created)} → ${fmt(updated)} ($diffStr) $odgovorLabel';
    } else {
      odgovorInfo = '${fmt(created)} · čeka kron...';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '⏱ $odgovorInfo',
        style: const TextStyle(color: Colors.white24, fontSize: 11),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (borderColor, statusLabel) = switch (zahtev.status) {
      'obrada' => (Colors.amber, '🟡 obrada'),
      'odobreno' => (Colors.greenAccent, '🟢 odobreno'),
      'alternativa' || 'ponuda' => (Colors.orange, '🕒 alternativa'),
      'odbijeno' => (Colors.redAccent, '🔴 odbijeno'),
      'otkazano' => (Colors.orange, '⛔ otkazano'),
      _ => (Colors.white24, zahtev.status),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: borderColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: borderColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.local_shipping_outlined, color: borderColor, size: 22),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          V3PutnikService.getPutnikById(zahtev.putnikId)?.imePrezime ?? 'Pošiljka',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Text(
                        statusLabel,
                        style: TextStyle(color: borderColor, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${zahtev.grad} · ${zahtev.zeljenoVreme} · '
                    '${zahtev.datum.day}.${zahtev.datum.month}.${zahtev.datum.year}.',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  if (opisPosiljke?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '📝 $opisPosiljke',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (zahtev.napomena?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '💬 ${zahtev.napomena}',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  _buildTimelapse(zahtev),
                  if (zahtev.dodeljenoVreme != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.purpleAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          '🕐 Vreme: ${zahtev.dodeljenoVreme}',
                          style: const TextStyle(color: Colors.purpleAccent, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Tap indikator
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}
