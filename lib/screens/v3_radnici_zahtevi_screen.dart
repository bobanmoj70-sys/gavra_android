import 'package:flutter/material.dart';

import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_putnik_service.dart';
import '../theme.dart';
import '../utils/v3_container_utils.dart';

/// V3 ekran — Monitoring Radnika
/// Izvor istine: v3_operativna_nedelja.polazak_at (finalno postavljeno od crona).
class V3RadniciZahteviScreen extends StatefulWidget {
  const V3RadniciZahteviScreen({super.key});

  @override
  State<V3RadniciZahteviScreen> createState() => _V3RadniciZahteviScreenState();
}

// ─── Model ────────────────────────────────────────────────────────────────────
enum _OpStatus { aktivno, pokupljeno, otkazano }

class _OpRed {
  _OpRed({
    required this.putnikId,
    required this.datum,
    required this.grad,
    required this.polazakAt,
    required this.brojMesta,
    required this.status,
    required this.updatedAt,
  });

  final String putnikId;
  final DateTime datum;
  final String grad;
  final String polazakAt;
  final int brojMesta;
  final _OpStatus status;
  final DateTime updatedAt;

  factory _OpRed.fromJson(Map<String, dynamic> r) {
    final otkazano = r['otkazano_at'] != null;
    final pokupljeno = !otkazano && r['pokupljen_at'] != null;
    final status = otkazano
        ? _OpStatus.otkazano
        : pokupljeno
            ? _OpStatus.pokupljeno
            : _OpStatus.aktivno;

    final datum = DateTime.tryParse(r['datum']?.toString() ?? '') ?? DateTime(2000);
    final updatedAt = DateTime.tryParse(r['updated_at']?.toString() ?? '') ??
        DateTime.tryParse(r['created_at']?.toString() ?? '') ??
        DateTime(2000);

    return _OpRed(
      putnikId: r['created_by']?.toString() ?? '',
      datum: datum,
      grad: (r['grad']?.toString() ?? '').toUpperCase(),
      polazakAt: r['polazak_at']?.toString() ?? '',
      brojMesta: (r['broj_mesta'] as num?)?.toInt() ?? 1,
      status: status,
      updatedAt: updatedAt,
    );
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────
class _V3RadniciZahteviScreenState extends State<V3RadniciZahteviScreen> {
  List<_OpRed> _getRedovi() {
    final rm = V3MasterRealtimeManager.instance;
    final radniciIds = rm.putniciCache.values
        .where((p) => (p['tip_putnika'] as String? ?? '').toLowerCase() == 'radnik')
        .map((p) => p['id'] as String)
        .toSet();

    return rm.operativnaNedeljaCache.values
        .where((r) {
          final putnikId = (r['created_by']?.toString() ?? '').trim();
          return putnikId.isNotEmpty && radniciIds.contains(putnikId);
        })
        .map(_OpRed.fromJson)
        .toList()
      ..sort((a, b) {
        final datumCmp = b.datum.compareTo(a.datum);
        if (datumCmp != 0) return datumCmp;
        return b.updatedAt.compareTo(a.updatedAt);
      });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: V3MasterRealtimeManager.instance.tablesRevisionStream(const ['v3_operativna_nedelja', 'v3_auth']),
      builder: (context, _) {
        final redovi = _getRedovi();

        final brAktivno = redovi.where((r) => r.status == _OpStatus.aktivno).length;
        final brPokupljeno = redovi.where((r) => r.status == _OpStatus.pokupljeno).length;
        final brOtkazano = redovi.where((r) => r.status == _OpStatus.otkazano).length;

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
                  'Monitoring Radnika',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
                if (brAktivno > 0) ...[
                  const SizedBox(width: 8),
                  V3ContainerUtils.badgeContainer(
                    backgroundColor: Colors.greenAccent.withValues(alpha: 0.25),
                    borderColor: Colors.greenAccent.withValues(alpha: 0.6),
                    borderWidth: 1,
                    borderRadius: 10,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Text(
                      '$brAktivno',
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
                  // ── Summary badges ──────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: [
                        if (brAktivno > 0) _badge('🟢 $brAktivno aktivno', Colors.greenAccent),
                        if (brPokupljeno > 0) _badge('🚗 $brPokupljeno pokupljeno', Colors.lightBlueAccent),
                        if (brOtkazano > 0) _badge('⛔ $brOtkazano otkazano', Colors.orange),
                      ],
                    ),
                  ),

                  // ── Lista ───────────────────────────────────────────
                  Expanded(
                    child: redovi.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.engineering_outlined, size: 56, color: Colors.white.withValues(alpha: 0.25)),
                                const SizedBox(height: 14),
                                Text(
                                  'Nema raspoređenih radnika',
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
                            itemCount: redovi.length,
                            itemBuilder: (_, i) => _OpKartica(red: redovi[i]),
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

// ─── Kartica ─────────────────────────────────────────────────────────────────
class _OpKartica extends StatelessWidget {
  const _OpKartica({required this.red});
  final _OpRed red;

  @override
  Widget build(BuildContext context) {
    final (borderColor, statusLabel, icon) = switch (red.status) {
      _OpStatus.aktivno => (Colors.greenAccent, 'aktivno', Icons.schedule),
      _OpStatus.pokupljeno => (Colors.lightBlueAccent, 'pokupljeno', Icons.directions_car),
      _OpStatus.otkazano => (Colors.orange, 'otkazano', Icons.cancel_outlined),
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
              icon: Icon(icon, color: borderColor, size: 22),
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
                          V3PutnikService.getPutnikById(red.putnikId)?.imePrezime ?? 'Radnik',
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
                    '${red.grad} · ${red.polazakAt} · '
                    '${red.datum.day}.${red.datum.month}.${red.datum.year}.',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  if (red.brojMesta > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '👥 ${red.brojMesta} mesta',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ),
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
