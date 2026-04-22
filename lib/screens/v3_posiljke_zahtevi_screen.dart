import 'package:flutter/material.dart';

import '../models/v3_zahtev.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_putnik_service.dart';
import '../theme.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_status_policy.dart';
import '../widgets/v3_zahtev_timelapse_widget.dart';

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
          final putnikId = (r['created_by']?.toString() ?? '').trim();
          if (putnikId.isEmpty) return false;
          if (!posiljkaPutnici.contains(putnikId)) return false;
          // Samo zahtevi koje je pošiljatelj sam poslao
          final createdBy = (r['created_by']?.toString() ?? '').trim();
          return createdBy == putnikId;
        })
        .map((r) => V3Zahtev.fromJson(r))
        .toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));

    return zahtevi;
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<int>(
      stream: V3MasterRealtimeManager.instance.tablesRevisionStream(const ['v3_zahtevi', 'v3_auth']),
      builder: (context, _) {
        final zahtevi = _getPosiljkeZahtevi();

        final brObrada = zahtevi.where((z) => V3StatusPolicy.isPending(z.status)).length;
        final brOdobreno = zahtevi.where((z) => V3StatusPolicy.isApproved(z.status)).length;
        final brOdbijeno = zahtevi.where((z) => V3StatusPolicy.isRejected(z.status)).length;
        final brOtkazano = zahtevi.where((z) => V3StatusPolicy.isCanceled(z.status)).length;

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
                  V3ContainerUtils.iconContainer(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    backgroundColor: Colors.orangeAccent.withValues(alpha: 0.3),
                    borderRadiusGeometry: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.6)),
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
                              return _ZahtevKartica(
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

  Widget _badge(String tekst, Color color) => V3ContainerUtils.styledContainer(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        backgroundColor: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
        child: Text(tekst, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

// ─── Zahtev kartica ───────────────────────────────────────────────────────────
class _ZahtevKartica extends StatelessWidget {
  const _ZahtevKartica({
    required this.zahtev,
  });

  final V3Zahtev zahtev;

  @override
  Widget build(BuildContext context) {
    final style = V3StatusPolicy.statusCardStyle(zahtev.status);
    final borderColor = style.borderColor;
    final statusLabel = style.label;

    return V3ContainerUtils.styledContainer(
      margin: const EdgeInsets.only(bottom: 8),
      backgroundColor: borderColor.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: borderColor.withValues(alpha: 0.45), width: 1.5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            V3ContainerUtils.iconContainer(
              padding: const EdgeInsets.all(8),
              backgroundColor: borderColor.withValues(alpha: 0.15),
              borderRadiusGeometry: BorderRadius.circular(10),
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
                    '${zahtev.grad} · ${zahtev.trazeniPolazakAt} · '
                    '${zahtev.datum.day}.${zahtev.datum.month}.${zahtev.datum.year}.',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  V3ZahtevTimelapseWidget(zahtev: zahtev),
                  if (zahtev.polazakAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: V3ContainerUtils.iconContainer(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        backgroundColor: Colors.purpleAccent.withValues(alpha: 0.15),
                        borderRadiusGeometry: BorderRadius.circular(8),
                        border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4)),
                        child: Text(
                          '🕐 Vreme: ${zahtev.polazakAt}',
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
