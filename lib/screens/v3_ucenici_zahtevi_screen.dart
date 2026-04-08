import 'package:flutter/material.dart';

import '../models/v3_zahtev.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_putnik_service.dart';
import '../theme.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dan_helper.dart';
import '../utils/v3_string_utils.dart';

/// V3 ekran — Monitoring Učenika
/// Prikaz i upravljanje zahtevima putnika tipa 'ucenik'.
class V3UceniciZahteviScreen extends StatefulWidget {
  const V3UceniciZahteviScreen({super.key});

  @override
  State<V3UceniciZahteviScreen> createState() => _V3UceniciZahteviScreenState();
}

class _V3UceniciZahteviScreenState extends State<V3UceniciZahteviScreen> {
  // ─── Helpers ──────────────────────────────────────────────────────────────────

  List<V3Zahtev> _getZahtevi() {
    final rm = V3MasterRealtimeManager.instance;
    final uceniciIds = rm.putniciCache.values
        .where((p) => (p['tip_putnika'] as String? ?? '').toLowerCase() == 'ucenik')
        .map((p) => p['id'] as String)
        .toSet();

    return rm.zahteviCache.values
        .where((r) {
          final putnikId = (r['putnik_id']?.toString() ?? '').trim();
          if (putnikId.isEmpty) return false;
          if (!uceniciIds.contains(putnikId)) return false;
          // Samo zahtevi koje je učenik sam poslao
          final createdBy = (r['created_by']?.toString() ?? '').trim();
          return createdBy == putnikId;
        })
        .map((r) => V3Zahtev.fromJson(r))
        .toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: V3MasterRealtimeManager.instance.tablesRevisionStream(const ['v3_zahtevi', 'v3_auth']),
      builder: (context, _) {
        final zahtevi = _getZahtevi();

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
                  'Monitoring Učenika',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
                if (brObrada > 0) ...[
                  const SizedBox(width: 8),
                  V3ContainerUtils.badgeContainer(
                    backgroundColor: Colors.lightBlueAccent.withValues(alpha: 0.3),
                    borderColor: Colors.lightBlueAccent.withValues(alpha: 0.6),
                    borderWidth: 1,
                    borderRadius: 10,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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

                  // ── Lista ──────────────────────────────────────────────────
                  Expanded(
                    child: zahtevi.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.school_outlined, size: 56, color: Colors.white.withValues(alpha: 0.25)),
                                const SizedBox(height: 14),
                                Text(
                                  'Nema zahteva učenika',
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
                              return _ZahtevKarticaUcenik(
                                zahtev: z,
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

  Widget _badge(String tekst, Color color) => V3ContainerUtils.badgeContainer(
        backgroundColor: color.withValues(alpha: 0.15),
        borderColor: color.withValues(alpha: 0.5),
        borderWidth: 1,
        child: Text(tekst, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

// ─── Zahtev kartica ───────────────────────────────────────────────────────────
class _ZahtevKarticaUcenik extends StatelessWidget {
  const _ZahtevKarticaUcenik({
    required this.zahtev,
  });

  final V3Zahtev zahtev;

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
      if (z.status == 'alternativa' && (z.altVremePre != null || z.altVremePosle != null)) {
        final alts = [
          if (z.altVremePre != null) V3StringUtils.formatAlternativeTime(z.altVremePre),
          if (z.altVremePosle != null) V3StringUtils.formatAlternativeTime(z.altVremePosle),
        ].join(' / ');
        odgovorLabel = '⚠️ alt: $alts';
      } else {
        odgovorLabel = switch (z.status) {
          'odobreno' => '✅',
          'alternativa' => '⚠️',
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
      'alternativa' => (Colors.orange, '🕒 alternativa'),
      'odbijeno' => (Colors.redAccent, '🔴 odbijeno'),
      'otkazano' => (Colors.orange, '⛔ otkazano'),
      _ => (Colors.white24, zahtev.status),
    };

    return V3ContainerUtils.iconContainer(
      margin: const EdgeInsets.only(bottom: 8),
      backgroundColor: borderColor.withValues(alpha: 0.06),
      borderRadiusGeometry: BorderRadius.circular(14),
      border: Border.all(color: borderColor.withValues(alpha: 0.45), width: 1.5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            V3ContainerUtils.iconContainer(
              backgroundColor: borderColor.withValues(alpha: 0.15),
              borderRadius: 10,
              icon: Icon(Icons.school_outlined, color: borderColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          V3PutnikService.getPutnikById(zahtev.putnikId)?.imePrezime ?? 'Učenik',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Text(statusLabel, style: TextStyle(color: borderColor, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${zahtev.grad} · ${zahtev.zeljenoVreme} · '
                    '${zahtev.datum.day}.${zahtev.datum.month}.${zahtev.datum.year}.',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  if (zahtev.brojMesta > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '👥 ${zahtev.brojMesta} mesta',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
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
                  // ── Timelapse ──────────────────────────────────
                  _buildTimelapse(zahtev),
                ],
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}
