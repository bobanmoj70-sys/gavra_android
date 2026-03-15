import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/v3_zahtev.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_zahtev_service.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';

/// V3 ekran za prikaz i upravljanje zahtevima tipa "pošiljka".
/// Admin odobrava / odbija / otkazuje pošiljke.
class V3PosiljkeZahteviScreen extends StatefulWidget {
  const V3PosiljkeZahteviScreen({super.key});

  @override
  State<V3PosiljkeZahteviScreen> createState() => _V3PosiljkeZahteviScreenState();
}

class _V3PosiljkeZahteviScreenState extends State<V3PosiljkeZahteviScreen> {
  String _filterStatus = 'svi'; // 'svi' | 'obrada' | 'odobreno' | 'odbijeno' | 'otkazano'

  // ─── Helpers ─────────────────────────────────────────────────────────────

  /// Svi zahtevi čiji putnik ima tip == 'posiljka'
  List<V3Zahtev> _getPosiljkeZahtevi() {
    final rm = V3MasterRealtimeManager.instance;
    final posiljkaPutnici = rm.putniciCache.values
        .where((p) => (p['tip_putnika'] as String? ?? '').toLowerCase() == 'posiljka')
        .map((p) => p['id'] as String)
        .toSet();

    final zahtevi = rm.zahteviCache.values
        .where((r) => posiljkaPutnici.contains(r['putnik_id']))
        .map((r) => V3Zahtev.fromJson(r))
        .where((z) => _filterStatus == 'svi' || z.status == _filterStatus)
        .toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));

    return zahtevi;
  }

  String? _opisPosiljke(String putnikId) {
    final data = V3MasterRealtimeManager.instance.putniciCache[putnikId];
    return data?['opis_posiljke'] as String?;
  }

  String? _telefonPutnika(String putnikId) {
    final data = V3MasterRealtimeManager.instance.putniciCache[putnikId];
    return (data?['telefon1'] ?? data?['telefon']) as String?;
  }

  // ─── Akcije ───────────────────────────────────────────────────────────────

  Future<void> _updateStatus(V3Zahtev z, String noviStatus) async {
    final label = switch (noviStatus) {
      'odobreno' => 'odobreno',
      'odbijeno' => 'odbijeno',
      'otkazano' => 'otkazano',
      _ => noviStatus,
    };
    try {
      await V3ZahtevService.updateStatus(z.id, noviStatus);
      if (mounted) V3AppSnackBar.success(context, '✅ ${z.imePrezime ?? 'Pošiljka'} — $label');
    } catch (e) {
      if (mounted) V3AppSnackBar.error(context, '❌ Greška: $e');
    }
  }

  Future<void> _showVremeDialog(V3Zahtev z) async {
    final ctrl = TextEditingController(
      text: z.dodeljenoVreme ?? '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('🕐 Dodeljeno vreme', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.datetime,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Vreme (npr. 07:30)',
            labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            hintText: 'HH:MM',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.purpleAccent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Otkaži', style: TextStyle(color: Colors.white54)),
          ),
          if (z.dodeljenoVreme != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, '__clear__'),
              child: const Text('Ukloni', style: TextStyle(color: Colors.redAccent)),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Sačuvaj'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || !mounted) return;
    try {
      final vreme = result == '__clear__' ? null : (result.isEmpty ? null : result);
      await V3ZahtevService.updatedodeljenoVreme(z.id, vreme);
      if (mounted) V3AppSnackBar.success(context, vreme != null ? '✅ Vreme postavljeno: $vreme' : '✅ Vreme uklonjeno');
    } catch (e) {
      if (mounted) V3AppSnackBar.error(context, '❌ Greška: $e');
    }
  }

  Future<void> _showAkcijeSheet(V3Zahtev z) async {
    final opis = _opisPosiljke(z.putnikId);
    final tel = _telefonPutnika(z.putnikId);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          gradient: Theme.of(context).backgroundGradient,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '📦 ${(z.imePrezime ?? 'Pošiljka').toUpperCase()}',
              style: const TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1.2),
            ),
            Text(
              '${z.grad} · ${z.zeljenoVreme} · ${z.datum.day}.${z.datum.month}.${z.datum.year}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
            ),
            if (opis?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text('📝 $opis', style: const TextStyle(color: Colors.white60, fontSize: 13)),
            ],
            const SizedBox(height: 6),
            const SizedBox(height: 8),
            // Dodeljeno vreme
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.purpleAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    z.dodeljenoVreme != null ? '🕐 Vreme: ${z.dodeljenoVreme}' : '🕐 Vreme: nije postavljeno',
                    style: const TextStyle(color: Colors.purpleAccent, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _showVremeDialog(z);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: const Text('✏️ Postavi', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white24),
            const SizedBox(height: 8),

            // Odobri
            if (z.status != 'odobreno')
              _akcijaBtn(
                ctx: ctx,
                icon: Icons.check_circle_outline,
                label: 'Odobri pošiljku',
                color: Colors.greenAccent,
                onTap: () async {
                  Navigator.pop(ctx);
                  await _updateStatus(z, 'odobreno');
                },
              ),

            // Odbij
            if (z.status != 'odbijeno')
              _akcijaBtn(
                ctx: ctx,
                icon: Icons.cancel_outlined,
                label: 'Odbij pošiljku',
                color: Colors.redAccent,
                onTap: () async {
                  Navigator.pop(ctx);
                  await _updateStatus(z, 'odbijeno');
                },
              ),

            // Otkaži
            if (z.status != 'otkazano')
              _akcijaBtn(
                ctx: ctx,
                icon: Icons.block,
                label: 'Otkaži pošiljku',
                color: Colors.orangeAccent,
                onTap: () async {
                  Navigator.pop(ctx);
                  await _updateStatus(z, 'otkazano');
                },
              ),

            // Vrati na obradu
            if (z.status != 'obrada')
              _akcijaBtn(
                ctx: ctx,
                icon: Icons.replay,
                label: 'Vrati na obradu',
                color: Colors.white54,
                onTap: () async {
                  Navigator.pop(ctx);
                  await _updateStatus(z, 'obrada');
                },
              ),

            // Pozovi
            if (tel?.isNotEmpty == true)
              _akcijaBtn(
                ctx: ctx,
                icon: Icons.phone,
                label: 'Pozovi: $tel',
                color: Colors.cyanAccent,
                onTap: () async {
                  Navigator.pop(ctx);
                  final uri = Uri(scheme: 'tel', path: tel);
                  if (await canLaunchUrl(uri)) await launchUrl(uri);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _akcijaBtn({
    required BuildContext ctx,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 14),
            Text(label, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
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
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '📦 Pošiljke',
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
          body: Container(
            decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
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

                  // ── Filter chips ───────────────────────────────────
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(
                      children: [
                        for (final s in ['svi', 'obrada', 'odobreno', 'odbijeno', 'otkazano'])
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _filterChip(s),
                          ),
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
                                onTap: () => _showAkcijeSheet(z),
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

  Widget _filterChip(String status) {
    final isSelected = _filterStatus == status;
    final (label, color) = switch (status) {
      'obrada' => ('🟡 Obrada', Colors.amber),
      'odobreno' => ('🟢 Odobreno', Colors.greenAccent),
      'odbijeno' => ('🔴 Odbijeno', Colors.redAccent),
      'otkazano' => ('⛔ Otkazano', Colors.orange),
      _ => ('Svi', Colors.white70),
    };
    return GestureDetector(
      onTap: () => setState(() => _filterStatus = status),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : Colors.white.withValues(alpha: 0.2),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? color : Colors.white54,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ─── Zahtev kartica ───────────────────────────────────────────────────────────
class _ZahtevKartica extends StatelessWidget {
  const _ZahtevKartica({
    required this.zahtev,
    this.opisPosiljke,
    required this.onTap,
  });

  final V3Zahtev zahtev;
  final String? opisPosiljke;
  final VoidCallback onTap;

  Widget _buildTimelapse(V3Zahtev z) {
    final created = z.createdAt;
    final updated = z.updatedAt;
    if (created == null) return const SizedBox.shrink();

    String fmt(DateTime dt) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }

    String odgovorInfo;
    if (updated != null && updated.isAfter(created.add(const Duration(seconds: 5)))) {
      final diff = updated.difference(created);
      final mins = diff.inMinutes;
      final secs = diff.inSeconds % 60;
      final diffStr = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';

      String odgovorLabel;
      if (z.status == 'odbijeno' && (z.altVremePre != null || z.altVremePosle != null)) {
        final alts = [
          if (z.altVremePre != null) z.altVremePre.toString().substring(0, 5),
          if (z.altVremePosle != null) z.altVremePosle.toString().substring(0, 5),
        ].join(' / ');
        odgovorLabel = '⚠️ alt: $alts';
      } else {
        odgovorLabel = switch (z.status) {
          'odobreno' => '✅',
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
      'odbijeno' => (Colors.redAccent, '🔴 odbijeno'),
      'otkazano' => (Colors.orange, '⛔ otkazano'),
      _ => (Colors.white24, zahtev.status),
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
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
                            zahtev.imePrezime ?? 'Pošiljka',
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
                            style:
                                const TextStyle(color: Colors.purpleAccent, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Tap indikator
              const SizedBox(width: 6),
              Icon(Icons.more_vert, color: Colors.white24, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
