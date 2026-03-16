import 'package:flutter/material.dart';

import '../globals.dart';
import '../models/v3_putnik.dart';
import '../models/v3_zahtev.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_putnik_service.dart';
import '../services/v3/v3_zahtev_service.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';

class V3ZahteviDnevniScreen extends StatefulWidget {
  const V3ZahteviDnevniScreen({super.key});

  @override
  State<V3ZahteviDnevniScreen> createState() => _V3ZahteviDnevniScreenState();
}

class _V3ZahteviDnevniScreenState extends State<V3ZahteviDnevniScreen> {
  // ─── data helpers ────────────────────────────────────────────────

  List<V3Zahtev> _getZahtevi(String status) {
    final rm = V3MasterRealtimeManager.instance;
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final windowEnd = todayOnly.add(const Duration(days: 14));
    return rm.zahteviCache.values.map((v) => V3Zahtev.fromJson(v)).where((z) {
      if (!z.aktivno || z.status != status) return false;
      final d = DateTime(z.datum.year, z.datum.month, z.datum.day);
      if (d.isBefore(todayOnly) || d.isAfter(windowEnd)) return false;
      final p = rm.putniciCache[z.putnikId];
      final tip = (p?['tip_putnika'] as String? ?? '').toLowerCase();
      if (tip != 'dnevni') return false;
      // Samo zahtevi koje je putnik sam poslao (izvor_id == putnik_id)
      if (z.izvorId != z.putnikId) return false;
      return true;
    }).toList()
      ..sort((a, b) {
        final danOrd = a.datum.compareTo(b.datum);
        if (danOrd != 0) return danOrd;
        return a.zeljenoVreme.compareTo(b.zeljenoVreme);
      });
  }

  // ─── actions ─────────────────────────────────────────────────────

  Future<void> _updateStatus(String id, String status) async {
    try {
      await V3ZahtevService.updateStatus(id, status);
      if (mounted) {
        final label = status == 'odobreno' ? '✅ Odobreno' : '❌ Odbijeno';
        V3AppSnackBar.success(context, label);
      }
    } catch (e) {
      if (mounted) V3AppSnackBar.error(context, '❌ Greška: $e');
    }
  }

  // ─── build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: StreamBuilder<void>(
          stream: V3MasterRealtimeManager.instance.onChange,
          builder: (context, __) {
            final obrada = _getZahtevi('obrada');
            final odobreno = _getZahtevi('odobreno');
            final odbijeno = _getZahtevi('odbijeno');
            final otkazano = _getZahtevi('otkazano');

            return CustomScrollView(
              slivers: [
                // ── AppBar ────────────────────────────────────────
                SliverAppBar(
                  backgroundColor: Colors.transparent,
                  expandedHeight: 110,
                  floating: true,
                  snap: true,
                  automaticallyImplyLeading: false,
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(24),
                          bottomRight: Radius.circular(24),
                        ),
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.white.withValues(alpha: 0.13),
                            width: 1.5,
                          ),
                        ),
                      ),
                      child: SafeArea(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Zahtevi dnevnih putnika',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 6,
                              children: [
                                if (obrada.isNotEmpty) _StatusBadge('⏳ ${obrada.length} obrada', Colors.amber),
                                if (odobreno.isNotEmpty) _StatusBadge('✅ ${odobreno.length} odobreno', Colors.green),
                                if (odbijeno.isNotEmpty) _StatusBadge('❌ ${odbijeno.length} odbijeno', Colors.red),
                                if (otkazano.isNotEmpty) _StatusBadge('🚫 ${otkazano.length} otkazano', Colors.orange),
                                if (obrada.isEmpty && odobreno.isEmpty && odbijeno.isEmpty && otkazano.isEmpty)
                                  Text(
                                    'Nema zahteva',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.5),
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Sekcija: NA ČEKANJU ───────────────────────────
                if (obrada.isNotEmpty) ...[
                  _sectionHeader('⏳ Na čekanju', Colors.amber, obrada.length),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _ZahtevCard(
                        zahtev: obrada[i],
                        putnik: V3PutnikService.getPutnikById(obrada[i].putnikId),
                        onOdobri: () => _updateStatus(obrada[i].id, 'odobreno'),
                        onOdbij: () => _updateStatus(obrada[i].id, 'odbijeno'),
                      ),
                      childCount: obrada.length,
                    ),
                  ),
                ],

                // ── Sekcija: ODOBRENO ─────────────────────────────
                if (odobreno.isNotEmpty) ...[
                  _sectionHeader('✅ Odobreno', Colors.green, odobreno.length),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _ZahtevCard(
                        zahtev: odobreno[i],
                        putnik: V3PutnikService.getPutnikById(odobreno[i].putnikId),
                        onOdobri: null,
                        onOdbij: () => _updateStatus(odobreno[i].id, 'odbijeno'),
                      ),
                      childCount: odobreno.length,
                    ),
                  ),
                ],

                // ── Sekcija: ODBIJENO / OTKAZANO ─────────────────
                if (odbijeno.isNotEmpty || otkazano.isNotEmpty) ...[
                  _sectionHeader(
                    '❌ Odbijeno / Otkazano',
                    Colors.red,
                    odbijeno.length + otkazano.length,
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final all = [...odbijeno, ...otkazano];
                        return _ZahtevCard(
                          zahtev: all[i],
                          putnik: V3PutnikService.getPutnikById(all[i].putnikId),
                          onOdobri: () => _updateStatus(all[i].id, 'odobreno'),
                          onOdbij: null,
                        );
                      },
                      childCount: odbijeno.length + otkazano.length,
                    ),
                  ),
                ],

                // ── Prazan state ──────────────────────────────────
                if (obrada.isEmpty && odobreno.isEmpty && odbijeno.isEmpty && otkazano.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inbox_outlined,
                            color: Colors.white.withValues(alpha: 0.3),
                            size: 64,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Nema zahteva',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            );
          },
        ),
      ),
    );
  }

  SliverToBoxAdapter _sectionHeader(String title, Color color, int count) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Widgets
// ─────────────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _ZahtevCard extends StatelessWidget {
  final V3Zahtev zahtev;
  final V3Putnik? putnik;
  final VoidCallback? onOdobri;
  final VoidCallback? onOdbij;

  const _ZahtevCard({
    required this.zahtev,
    required this.putnik,
    required this.onOdobri,
    required this.onOdbij,
  });

  @override
  Widget build(BuildContext context) {
    final tip = putnik?.tipPutnika ?? '';
    final tipColor = _tipColor(tip);
    final statusColor = _statusColor(zahtev.status);
    final danLabel = V3DanHelper.label(zahtev.datum);
    final vreme = zahtev.zeljenoVreme.length >= 5 ? zahtev.zeljenoVreme.substring(0, 5) : zahtev.zeljenoVreme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tipColor.withValues(alpha: 0.25),
                border: Border.all(color: tipColor.withValues(alpha: 0.5)),
              ),
              child: Center(
                child: Text(
                  _initials(putnik?.imePrezime ?? zahtev.imePrezime ?? '?'),
                  style: TextStyle(
                    color: tipColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
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
                          putnik?.imePrezime ?? zahtev.imePrezime ?? 'Nepoznat',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      // Status chip
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          zahtev.status.toUpperCase(),
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _InfoChip(
                        icon: zahtev.grad == 'BC' ? Icons.home : Icons.work,
                        label: zahtev.grad,
                        color: zahtev.grad == 'BC' ? Colors.cyan : Colors.tealAccent,
                      ),
                      const SizedBox(width: 6),
                      _InfoChip(icon: Icons.access_time, label: vreme, color: Colors.amber),
                      if (danLabel.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _InfoChip(icon: Icons.calendar_today, label: danLabel, color: Colors.white54),
                      ],
                      if (zahtev.brojMesta > 1) ...[
                        const SizedBox(width: 6),
                        _InfoChip(
                          icon: Icons.event_seat,
                          label: '×${zahtev.brojMesta}',
                          color: Colors.purple.shade200,
                        ),
                      ],
                    ],
                  ),
                  if (zahtev.napomena != null && zahtev.napomena!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '💬 ${zahtev.napomena}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // Akcije
            if (onOdobri != null || onOdbij != null) ...[
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onOdobri != null)
                    _ActionBtn(
                      icon: Icons.check_circle_outline,
                      color: Colors.green,
                      onTap: onOdobri!,
                    ),
                  if (onOdobri != null && onOdbij != null) const SizedBox(height: 6),
                  if (onOdbij != null)
                    _ActionBtn(
                      icon: Icons.cancel_outlined,
                      color: Colors.red,
                      onTap: onOdbij!,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : '?';
    return '${parts[0][0]}${parts.last[0]}'.toUpperCase();
  }

  Color _tipColor(String tip) {
    switch (tip.toLowerCase()) {
      case 'ucenik':
        return Colors.blue;
      case 'dnevni':
        return Colors.green;
      case 'posiljka':
        return Colors.purple;
      default:
        return Colors.orange;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'odobreno':
        return Colors.green;
      case 'odbijeno':
        return Colors.red;
      case 'otkazano':
        return Colors.orange;
      default:
        return Colors.amber;
    }
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.15),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}
