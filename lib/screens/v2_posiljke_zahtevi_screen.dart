import 'package:flutter/material.dart';

import '../models/v2_polazak.dart';
import '../services/v2_polasci_service.dart';
import '../theme.dart';
import '../utils/v2_vozac_cache.dart';
import '../widgets/v2_summary_badge.dart';

class V2PosiljkeZahteviScreen extends StatefulWidget {
  const V2PosiljkeZahteviScreen({super.key});

  @override
  State<V2PosiljkeZahteviScreen> createState() => _V2PosiljkeZahteviScreenState();
}

class _V2PosiljkeZahteviScreenState extends State<V2PosiljkeZahteviScreen> {
  late final Stream<List<V2Polazak>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = V2PolasciService.v2StreamZahteviObrada(
      statusFilter: const ['obrada', 'odobreno', 'odbijeno', 'otkazano'],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<V2Polazak>>(
      stream: _stream,
      builder: (context, snapshot) {
        final svi = snapshot.data ?? [];

        final zahtevi = svi.where((z) {
          if ((z.tipPutnika ?? '').toLowerCase() != 'posiljka') return false;
          return z.status == 'obrada' || z.approvedBy == 'sistem' || z.cancelledBy == 'sistem';
        }).toList();

        final brObrada = zahtevi.where((z) => z.status == 'obrada').length;
        final brOdobreno = zahtevi.where((z) => z.status == 'odobreno').length;
        final brOdbijeno = zahtevi.where((z) => z.status == 'odbijeno').length;
        final brOtkazano = zahtevi.where((z) => z.status == 'otkazano').length;

        return Container(
          decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(80),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).glassContainer,
                  border: Border(
                    bottom: BorderSide(color: Theme.of(context).glassBorder, width: 1.5),
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(25),
                    bottomRight: Radius.circular(25),
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Pošiljke Zahtevi',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          children: [
                            if (brObrada > 0) v2SummaryBadge('🟡 $brObrada obrada', Colors.amber),
                            if (brOdobreno > 0) v2SummaryBadge('🟢 $brOdobreno odobreno', Colors.green),
                            if (brOdbijeno > 0) v2SummaryBadge('🔴 $brOdbijeno odbijeno', Colors.red),
                            if (brOtkazano > 0) v2SummaryBadge('⛔ $brOtkazano otkazano', Colors.orange),
                            if (zahtevi.isEmpty)
                              Text('Nema zahteva',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            body: snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : _buildLista(zahtevi),
          ),
        );
      },
    );
  }

  Widget _buildLista(List<V2Polazak> zahtevi) {
    if (zahtevi.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_shipping_outlined, size: 72, color: Colors.white.withValues(alpha: 0.4)),
            const SizedBox(height: 14),
            Text(
              'Nema zahteva pošiljki',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 17, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      itemCount: zahtevi.length,
      itemBuilder: (_, index) => _buildKartica(zahtevi[index]),
    );
  }

  Widget _buildKartica(V2Polazak z) {
    final ime = z.putnikIme ?? 'Nepoznat';
    final grad = z.grad ?? 'BC';
    final dan = z.dan ?? '';
    final zeljeno = z.zeljenoVreme ?? '—';
    final dodeljeno = z.dodeljenoVreme;
    final alt1 = z.alternativeVreme1;
    final alt2 = z.alternativeVreme2;
    final status = z.status;

    final (statusColor, statusLabel) = switch (status) {
      'obrada' => (Colors.amber, 'OBRADA'),
      'odobreno' => (Colors.green, 'ODOBRENO'),
      'odbijeno' => (Colors.red, 'ODBIJENO'),
      'otkazano' => (Colors.orange, 'OTKAZANO'),
      _ => (Colors.grey, status.toUpperCase()),
    };

    final poslatStr = z.createdAt != null
        ? '${z.createdAt!.toLocal().day.toString().padLeft(2, '0')}.${z.createdAt!.toLocal().month.toString().padLeft(2, '0')}. ${z.createdAt!.toLocal().hour.toString().padLeft(2, '0')}:${z.createdAt!.toLocal().minute.toString().padLeft(2, '0')}'
        : null;
    final obradjenoStr = z.processedAt != null
        ? '${z.processedAt!.toLocal().day.toString().padLeft(2, '0')}.${z.processedAt!.toLocal().month.toString().padLeft(2, '0')}. ${z.processedAt!.toLocal().hour.toString().padLeft(2, '0')}:${z.processedAt!.toLocal().minute.toString().padLeft(2, '0')}'
        : null;
    final koObradio = z.approvedBy ?? z.cancelledBy;
    final koObradioColor = V2VozacCache.getColor(koObradio);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).glassContainer.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(ime,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.calendar_today, size: 12, color: Colors.amber.withValues(alpha: 0.8)),
                      const SizedBox(width: 3),
                      Text(dan, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
                    ],
                  ),
                ),
                v2GradBadge(grad),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10)),
                ),
              ],
            ),
            const SizedBox(height: 5),
            // RED 3: željeno → odobreno (+ alt1/alt2 ako postoje)
            Wrap(
              spacing: 14,
              runSpacing: 2,
              children: [
                v2VremeChip('Željeno', zeljeno, Colors.white70),
                if (dodeljeno != null && dodeljeno.isNotEmpty) v2VremeChip('', '→ $dodeljeno', Colors.green),
                if (alt1 != null && alt1.isNotEmpty) v2VremeChip('Alt 1', alt1, Colors.lightBlue),
                if (alt2 != null && alt2.isNotEmpty) v2VremeChip('Alt 2', alt2, Colors.lightBlue),
              ],
            ),
            const SizedBox(height: 4),
            // RED 4: timeline — kada poslato / kada obrađeno / ko obradio
            Wrap(
              spacing: 12,
              runSpacing: 2,
              children: [
                if (poslatStr != null) v2TimelineChip('📨 poslato', poslatStr, Colors.white54),
                if (obradjenoStr != null) v2TimelineChip('⚙️ obrađeno', obradjenoStr, Colors.lightBlueAccent),
                if (obradjenoStr == null && status == 'obrada')
                  v2TimelineChip('⏳', 'čeka kronom', Colors.amber.shade200),
                if (koObradio != null) v2TimelineChip('👤', koObradio, koObradioColor),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
