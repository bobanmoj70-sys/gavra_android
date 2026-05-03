// ignore_for_file: unused_element, unused_import

import 'package:flutter/material.dart';

import '../globals.dart';
import '../models/v3_putnik.dart';
import '../models/v3_zahtev.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_putnik_service.dart';
import '../services/v3/v3_zahtev_service.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dan_helper.dart';
import '../utils/v3_error_utils.dart';
import '../utils/v3_safe_text.dart';
import '../utils/v3_status_policy.dart';
import '../utils/v3_string_utils.dart';
import '../utils/v3_tip_putnika_utils.dart';
import '../widgets/v3_zahtev_timelapse_widget.dart';

class V3ZahteviDnevniScreen extends StatefulWidget {
  const V3ZahteviDnevniScreen({super.key});

  @override
  State<V3ZahteviDnevniScreen> createState() => _V3ZahteviDnevniScreenState();
}

class _V3ZahteviDnevniScreenState extends State<V3ZahteviDnevniScreen> {
  static const String _sistemAkterId = '4feffa3a-8b4d-4e28-9b8b-c0af3c48ea4e';

  bool _isSistemAkter(String? akterId, Map<String, Map<String, dynamic>> authCache) {
    final id = (akterId ?? '').trim();
    if (id.isEmpty) return false;
    if (id == _sistemAkterId) return true;
    final tip = (authCache[id]?['tip']?.toString() ?? '').trim().toLowerCase();
    return tip == 'sistem';
  }

  List<V3Zahtev> _getMonitoringZahtevi() {
    final rm = V3MasterRealtimeManager.instance;
    const tip = 'dnevni';

    final putniciIds = rm.putniciCache.values
        .where((p) => (p['tip_putnika'] as String? ?? '').toLowerCase() == tip)
        .map((p) => p['id'] as String)
        .toSet();

    return rm.zahteviCache.values
        .where((r) {
          final putnikId = (r['created_by']?.toString() ?? '').trim();
          if (putnikId.isEmpty) return false;
          if (!putniciIds.contains(putnikId)) return false;

          final createdBy = (r['created_by']?.toString() ?? '').trim();
          if (createdBy != putnikId) return false;

          final datumRaw = r['datum']?.toString();
          final datum = datumRaw != null ? DateTime.tryParse(datumRaw) : null;
          if (datum == null) return false;
          if (!V3DanHelper.isInSchedulingWeek(datum)) return false;

          final status = (r['status']?.toString() ?? '').trim().toLowerCase();
          if (V3StatusPolicy.isCanceled(status)) {
            final updatedBy = (r['updated_by']?.toString() ?? '').trim();
            if (updatedBy.isEmpty) return false;
            if (updatedBy != putnikId && !_isSistemAkter(updatedBy, rm.authCache)) {
              return false;
            }
          }

          return true;
        })
        .map((r) => V3Zahtev.fromJson(r))
        .toList()
      ..sort((a, b) {
        final aCreated = a.createdAt ?? DateTime(2000);
        final bCreated = b.createdAt ?? DateTime(2000);
        final createdCmp = bCreated.compareTo(aCreated);
        if (createdCmp != 0) return createdCmp;
        return b.datum.compareTo(a.datum);
      });
  }
  // ─── data helpers ────────────────────────────────────────────────

  List<V3Zahtev> _getZahtevi(String status) {
    final rm = V3MasterRealtimeManager.instance;
    final today = DateTime.now();
    final todayOnly = V3DanHelper.dateOnlyFrom(today.year, today.month, today.day);
    final windowEnd = todayOnly.add(const Duration(days: 14));
    return rm.zahteviCache.values.map((v) => V3Zahtev.fromJson(v)).where((z) {
      // Ako tražimo 'obrada', prikaži i one koji su u statusu 'alternativa' (jer ih dispečer i dalje vidi kao nešto na čemu radi)
      if (V3StatusPolicy.isPending(status)) {
        if (!V3StatusPolicy.isPending(z.status) && !V3StatusPolicy.isOfferLike(z.status)) return false;
      } else {
        if (z.status != status) return false;
      }

      final d = V3DanHelper.dateOnlyFrom(z.datum.year, z.datum.month, z.datum.day);
      if (d.isBefore(todayOnly) || d.isAfter(windowEnd)) return false;
      final p = rm.putniciCache[z.putnikId];
      final tip = (p?['tip_putnika'] as String? ?? '').toLowerCase();
      if (tip != 'dnevni') return false;
      // Samo zahtevi koje je putnik sam poslao
      final createdBy = (z.createdBy ?? '').trim();
      if (createdBy != z.putnikId) return false;
      return true;
    }).toList()
      ..sort((a, b) {
        final aCreated = a.createdAt;
        final bCreated = b.createdAt;

        if (aCreated != null || bCreated != null) {
          if (aCreated == null) return 1;
          if (bCreated == null) return -1;
          final createdOrd = bCreated.compareTo(aCreated);
          if (createdOrd != 0) return createdOrd;
        }

        final danOrd = b.datum.compareTo(a.datum);
        if (danOrd != 0) return danOrd;
        return b.trazeniPolazakAt.compareTo(a.trazeniPolazakAt);
      });
  }

  // ─── actions ─────────────────────────────────────────────────────

  Future<void> _updateStatus(String id, String status) async {
    try {
      await V3ZahtevService.updateStatus(id, status);
      if (mounted) {
        String label = '✅ Uspeh';
        if (V3StatusPolicy.isApproved(status))
          label = '✅ Odobreno';
        else if (V3StatusPolicy.isCanceled(status))
          label = '🚫 Otkazano';
        else if (V3StatusPolicy.isRejected(status)) label = '❌ Odbijeno';

        V3AppSnackBar.success(context, label);
      }
    } catch (e) {
      V3ErrorUtils.asyncError(this, context, e);
    }
  }

  // ─── build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final zahtevi = _getMonitoringZahtevi();
    final obrada =
        zahtevi.where((z) => V3StatusPolicy.isPending(z.status) || V3StatusPolicy.isOfferLike(z.status)).toList();
    final odobreno = zahtevi.where((z) => V3StatusPolicy.isApproved(z.status)).toList();
    final odbijeno = zahtevi.where((z) => V3StatusPolicy.isRejected(z.status)).toList();
    final otkazano = zahtevi.where((z) => V3StatusPolicy.isCanceled(z.status)).toList();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: const Text(
          'Monitoring zahteva',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: V3ContainerUtils.backgroundContainer(
        gradient: Theme.of(context).backgroundGradient,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    if (obrada.isNotEmpty) _StatusBadge('🟡 ${obrada.length} obrada', Colors.amber),
                    if (odobreno.isNotEmpty) _StatusBadge('🟢 ${odobreno.length} odobreno', Colors.greenAccent),
                    if (odbijeno.isNotEmpty) _StatusBadge('🔴 ${odbijeno.length} odbijeno', Colors.redAccent),
                    if (otkazano.isNotEmpty) _StatusBadge('⛔ ${otkazano.length} otkazano', Colors.orange),
                    if (zahtevi.isEmpty)
                      Text(
                        'Nema zahteva',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: zahtevi.isEmpty
                    ? Center(
                        child: Text(
                          'Nema zahteva',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                        physics: const BouncingScrollPhysics(),
                        itemCount: zahtevi.length,
                        itemBuilder: (_, i) => _MonitoringCardDaily(zahtev: zahtevi[i]),
                      ),
              ),
            ],
          ),
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
            V3ContainerUtils.styledContainer(
              width: 4,
              height: V3ContainerUtils.responsiveHeight(context, 18),
              backgroundColor: color,
              borderRadius: BorderRadius.circular(2),
              child: const SizedBox(),
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
            V3ContainerUtils.badgeContainer(
              backgroundColor: color.withValues(alpha: 0.2),
              borderRadius: 10,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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

class _MonitoringCardDaily extends StatelessWidget {
  const _MonitoringCardDaily({required this.zahtev});

  final V3Zahtev zahtev;

  @override
  Widget build(BuildContext context) {
    final style = V3StatusPolicy.statusCardStyle(zahtev.status);
    final borderColor = style.borderColor;
    final statusLabel = style.label;
    final putnik = V3PutnikService.getPutnikById(zahtev.putnikId);

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
              icon: Icon(Icons.monitor_heart_outlined, color: borderColor, size: 22),
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
                          putnik?.imePrezime ?? 'Putnik',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      Text(statusLabel, style: TextStyle(color: borderColor, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${zahtev.grad} · ${V3StringUtils.trimTimeToHhMm(zahtev.trazeniPolazakAt)} · ${zahtev.datum.day}.${zahtev.datum.month}.${zahtev.datum.year}.',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  V3ZahtevTimelapseWidget(zahtev: zahtev),
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

// ─────────────────────────────────────────────────────────────────────
// Widgets
// ─────────────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return V3ContainerUtils.badgeContainer(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      backgroundColor: color.withValues(alpha: 0.22),
      borderRadiusGeometry: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.5)),
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
    final tipColor = V3TipPutnikaUtils.color(tip);
    final statusColor = V3StatusPolicy.statusColor(zahtev.status);
    final danLabel = V3DanHelper.label(zahtev.datum);
    final vreme = V3StringUtils.trimTimeToHhMm(zahtev.trazeniPolazakAt);

    return V3ContainerUtils.iconContainer(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      backgroundColor: Colors.white.withValues(alpha: 0.07),
      borderRadiusGeometry: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Avatar
            V3ContainerUtils.iconContainer(
              width: 44,
              height: V3ContainerUtils.responsiveHeight(context, 44),
              backgroundColor: tipColor.withValues(alpha: 0.25),
              border: Border.all(color: tipColor.withValues(alpha: 0.5)),
              borderRadiusGeometry: BorderRadius.circular(22),
              alignment: Alignment.center,
              child: Text(
                _initials(putnik?.imePrezime ?? '?'),
                style: TextStyle(
                  color: tipColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
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
                        child: V3SafeText.userName(
                          putnik?.imePrezime ?? 'Nepoznat',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      // Status chip
                      V3ContainerUtils.badgeContainer(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        backgroundColor: statusColor.withValues(alpha: 0.2),
                        borderRadiusGeometry: BorderRadius.circular(8),
                        border: Border.all(color: statusColor.withValues(alpha: 0.5)),
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
                    ],
                  ),
                  V3ZahtevTimelapseWidget(zahtev: zahtev, cekaTekst: 'čeka odgovor...'),
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
                  if (onOdbij != null) ...[
                    const SizedBox(height: 6),
                    _ActionBtn(
                      icon: Icons.cancel_outlined,
                      color: Colors.red,
                      onTap: onOdbij!,
                    ),
                  ],
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
      child: V3ContainerUtils.iconContainer(
        width: 36,
        height: V3ContainerUtils.responsiveHeight(context, 36),
        backgroundColor: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadiusGeometry: BorderRadius.circular(18),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}
