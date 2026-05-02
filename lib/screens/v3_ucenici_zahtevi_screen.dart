// ignore_for_file: unused_element, unused_import

import 'package:flutter/material.dart';

import '../models/v3_zahtev.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_putnik_service.dart';
import '../theme.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dan_helper.dart';
import '../utils/v3_status_policy.dart';
import '../utils/v3_string_utils.dart';
import '../widgets/v3_zahtev_timelapse_widget.dart';

/// V3 ekran — Monitoring Učenika
/// Prikaz i upravljanje zahtevima putnika tipa 'ucenik'.
class V3UceniciZahteviScreen extends StatefulWidget {
  const V3UceniciZahteviScreen({super.key});

  @override
  State<V3UceniciZahteviScreen> createState() => _V3UceniciZahteviScreenState();
}

class _V3UceniciZahteviScreenState extends State<V3UceniciZahteviScreen> {
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
    const tip = 'ucenik';

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

  // ─── Helpers ──────────────────────────────────────────────────────────────────

  List<V3Zahtev> _getZahtevi() {
    final rm = V3MasterRealtimeManager.instance;
    final uceniciIds = rm.putniciCache.values
        .where((p) => (p['tip_putnika'] as String? ?? '').toLowerCase() == 'ucenik')
        .map((p) => p['id'] as String)
        .toSet();

    return rm.zahteviCache.values
        .where((r) {
          final putnikId = (r['created_by']?.toString() ?? '').trim();
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
    final zahtevi = _getMonitoringZahtevi();
    final brObrada =
        zahtevi.where((z) => V3StatusPolicy.isPending(z.status) || V3StatusPolicy.isOfferLike(z.status)).length;
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
                    if (brObrada > 0) _badge('🟡 $brObrada obrada', Colors.amber),
                    if (brOdobreno > 0) _badge('🟢 $brOdobreno odobreno', Colors.greenAccent),
                    if (brOdbijeno > 0) _badge('🔴 $brOdbijeno odbijeno', Colors.redAccent),
                    if (brOtkazano > 0) _badge('⛔ $brOtkazano otkazano', Colors.orange),
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
                        itemBuilder: (_, i) => _MonitoringCardUcenik(zahtev: zahtevi[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String tekst, Color color) => V3ContainerUtils.badgeContainer(
        backgroundColor: color.withValues(alpha: 0.15),
        borderColor: color.withValues(alpha: 0.5),
        borderWidth: 1,
        child: Text(tekst, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

class _MonitoringCardUcenik extends StatelessWidget {
  const _MonitoringCardUcenik({required this.zahtev});

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
                  if (zahtev.brojMesta > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '👥 ${zahtev.brojMesta} mesta',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
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

// ─── Zahtev kartica ───────────────────────────────────────────────────────────
class _ZahtevKarticaUcenik extends StatelessWidget {
  const _ZahtevKarticaUcenik({
    required this.zahtev,
  });

  final V3Zahtev zahtev;

  @override
  Widget build(BuildContext context) {
    final style = V3StatusPolicy.statusCardStyle(zahtev.status);
    final borderColor = style.borderColor;
    final statusLabel = style.label;

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
                    '${zahtev.grad} · ${zahtev.trazeniPolazakAt} · '
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
                  // ── Timelapse ──────────────────────────────────
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
