import 'package:flutter/material.dart';

import '../models/v2_polazak.dart';
import '../services/v2_polasci_service.dart';
import '../theme.dart';
import '../widgets/v2_summary_badge.dart';

class V2UceniciZahteviScreen extends StatefulWidget {
  const V2UceniciZahteviScreen({super.key});

  @override
  State<V2UceniciZahteviScreen> createState() => _V2UceniciZahteviScreenState();
}

class _V2UceniciZahteviScreenState extends State<V2UceniciZahteviScreen> {
  // obrada + odobreno + odbijeno + otkazano — kompletan lifecycle zahteva
  final Stream<List<V2Polazak>> _stream = V2PolasciService.v2StreamZahteviObrada(
    statusFilter: const ['obrada', 'odobreno', 'odbijeno', 'otkazano'],
  );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<V2Polazak>>(
      stream: _stream,
      builder: (context, snapshot) {
        final svi = snapshot.data ?? [];

        // Samo zahtevi koji su prošli kroz kronom:
        // - status='obrada' → čeka kronom
        // - odobrio='sistem' → kronom odobrio
        // - otkazao='sistem' → kronom odbio
        final zahtevi = svi.where((z) {
          if ((z.tipPutnika ?? '').toLowerCase() != 'ucenik') return false;
          return z.status == 'obrada' || z.approvedBy == 'sistem' || z.cancelledBy == 'sistem';
        }).toList();

        final brObrada = zahtevi.where((z) => z.status == 'obrada').length;
        final brOdobreno = zahtevi.where((z) => z.status == 'odobreno').length;
        final brOdbijeno = zahtevi.where((z) => z.status == 'odbijeno').length;
        final brOtkazano = zahtevi.where((z) => z.status == 'otkazano').length;

        return Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.transparent,
          appBar: PreferredSize(
            preferredSize: Size.fromHeight(80 + MediaQuery.of(context).padding.top),
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
                        'Monitoring Učenika',
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
                            Text('Nema aktivnih zahtjeva',
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
          body: Container(
            decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
            child: snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : v2ZahtjevLista(context, zahtevi, Icons.inbox_outlined, 'Nema zahteva učenika'),
          ),
        );
      },
    );
  }
}
