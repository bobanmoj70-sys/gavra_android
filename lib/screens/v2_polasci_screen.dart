import 'package:flutter/material.dart';

import '../models/v2_polazak.dart';
import '../services/v2_auth_manager.dart';
import '../services/v2_polasci_service.dart';
import '../theme.dart';
import '../utils/v2_app_snack_bar.dart';

class V2PolasciScreen extends StatefulWidget {
  const V2PolasciScreen({super.key});

  @override
  State<V2PolasciScreen> createState() => _V2PolasciScreenState();
}

class _V2PolasciScreenState extends State<V2PolasciScreen> {
  final Set<String> _loadingIds = {};
  String? _currentDriver;

  final Stream<List<V2Polazak>> _streamDnevni = V2PolasciService.v2StreamZahteviObrada();

  @override
  void initState() {
    super.initState();
    V2AuthManager.getCurrentDriver().then((d) {
      if (mounted) setState(() => _currentDriver = d);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
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
            child: const Center(
              child: Text(
                'Zahtevi Rezervacija',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [
                    Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
        child: StreamBuilder<List<V2Polazak>>(
          stream: _streamDnevni,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator(color: Colors.white));
            }
            final zahtevi =
                (snapshot.data ?? []).where((z) => (z.tipPutnika ?? 'dnevni').toLowerCase() == 'dnevni').toList();
            return _polasciDnevniLista(
              zahtevi: zahtevi,
              loadingIds: _loadingIds,
              glassContainer: Theme.of(context).glassContainer,
              glassBorder: Theme.of(context).glassBorder,
              onApprove: (id, z) => _approveZahtev(id, z),
              onReject: (id) => _rejectZahtev(id),
            );
          },
        ),
      ),
    );
  }

  // ─── Akcije ───────────────────────────────────────────────────────────────

  Future<void> _approveZahtev(String id, V2Polazak zahtev) async {
    setState(() => _loadingIds.add(id));
    try {
      final success = await V2PolasciService.v2OdobriZahtev(id, approvedBy: _currentDriver);
      if (!mounted) return;
      if (success) {
        V2AppSnackBar.success(context, '✅ Zahtev uspešno odobren');
      } else {
        V2AppSnackBar.error(context, '❌ Greška pri odobravanju, pokušaj ponovo');
      }
    } finally {
      if (mounted) setState(() => _loadingIds.remove(id));
    }
  }

  Future<void> _rejectZahtev(String id) async {
    setState(() => _loadingIds.add(id));
    try {
      final success = await V2PolasciService.v2OdbijZahtev(id, rejectedBy: _currentDriver);
      if (!mounted) return;
      if (success) {
        V2AppSnackBar.warning(context, '🚫 Zahtev odbijen');
      } else {
        V2AppSnackBar.error(context, '❌ Greška pri odbijanju, pokušaj ponovo');
      }
    } finally {
      if (mounted) setState(() => _loadingIds.remove(id));
    }
  }
}

// ─── Top-level: lista i kartica ─────────────────────────────────────────────

Widget _polasciDnevniLista({
  required List<V2Polazak> zahtevi,
  required Set<String> loadingIds,
  required Color glassContainer,
  required Color glassBorder,
  required void Function(String, V2Polazak) onApprove,
  required void Function(String) onReject,
}) {
  if (zahtevi.isEmpty) return _polasciBuildPrazno('Nema dnevnih zahteva na čekanju');
  return ListView.builder(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
    itemCount: zahtevi.length,
    itemBuilder: (_, index) => _polasciDnevniKartica(
      zahtev: zahtevi[index],
      loadingIds: loadingIds,
      glassContainer: glassContainer,
      glassBorder: glassBorder,
      onApprove: onApprove,
      onReject: onReject,
    ),
  );
}

Widget _polasciDnevniKartica({
  required V2Polazak zahtev,
  required Set<String> loadingIds,
  required Color glassContainer,
  required Color glassBorder,
  required void Function(String, V2Polazak) onApprove,
  required void Function(String) onReject,
}) {
  final ime = zahtev.putnikIme ?? 'Nepoznat';
  final telefon = zahtev.brojTelefona ?? '';
  final grad = zahtev.grad ?? 'BC';
  final dan = zahtev.dan ?? '';
  final vreme = zahtev.zeljenoVreme ?? '';
  final id = zahtev.id;
  final brojMesta = zahtev.brojMesta;
  final isLoading = loadingIds.contains(id);

  return Container(
    margin: const EdgeInsets.only(bottom: 20),
    decoration: BoxDecoration(
      color: glassContainer.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: glassBorder, width: 1.5),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 15, offset: const Offset(0, 8))],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ime, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        children: [
                          _polasciTipBadge('🎟️ DNEVNI', Colors.blue),
                          if (brojMesta > 1) _polasciInfoBadge('👥 $brojMesta mesta', Colors.purple),
                        ],
                      ),
                    ],
                  ),
                ),
                _polasciGradBadge(grad),
              ],
            ),
            if (telefon.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(children: [
                Icon(Icons.phone, size: 16, color: Colors.white.withValues(alpha: 0.7)),
                const SizedBox(width: 8),
                Text(telefon, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 15)),
              ]),
            ],
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(color: Colors.white24, height: 1),
            ),
            Row(children: [
              const Icon(Icons.calendar_month, size: 20, color: Colors.amber),
              const SizedBox(width: 10),
              Text('$dan  ($vreme)',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
            ]),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isLoading ? null : () => onApprove(id, zahtev),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('ODOBRI', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.withValues(alpha: 0.9),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isLoading ? null : () => onReject(id),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('ODBIJ', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.withValues(alpha: 0.8),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    ),
  );
}

// ─── Top-level helpers ────────────────────────────────────────────────────────

Widget _polasciTipBadge(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10)),
    );

Widget _polasciGradBadge(String grad) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Text(grad, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
    );

Widget _polasciInfoBadge(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child:
          Text(label, style: TextStyle(color: color.withValues(alpha: 0.9), fontWeight: FontWeight.bold, fontSize: 10)),
    );

Widget _polasciBuildPrazno(String poruka) => Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 72, color: Colors.white.withValues(alpha: 0.4)),
          const SizedBox(height: 14),
          Text(poruka,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 17, fontWeight: FontWeight.w500)),
        ],
      ),
    );
