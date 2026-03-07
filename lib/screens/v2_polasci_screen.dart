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

  late final Stream<List<V2Polazak>> _streamDnevni;

  @override
  void initState() {
    super.initState();
    _streamDnevni = V2PolasciService.v2StreamZahteviObrada();
    V2AuthManager.getCurrentDriver().then((d) {
      if (mounted) setState(() => _currentDriver = d);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<V2Polazak>>(
      stream: _streamDnevni,
      builder: (context, snapshot) {
        final svi = snapshot.data ?? [];
        final zahtevi = svi.where((z) {
          final t = (z.tipPutnika ?? 'dnevni').toLowerCase();
          return t == 'dnevni';
        }).toList();

        return Container(
          decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
          child: Scaffold(
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
            body: snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : _buildDnevniLista(zahtevi),
          ),
        );
      },
    );
  }

  // ─── DNEVNI: admin odobrava/odbija ────────────────────────────────────

  Widget _buildDnevniLista(List<V2Polazak> zahtevi) {
    if (zahtevi.isEmpty) {
      return _buildPrazno('Nema dnevnih zahteva na čekanju');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      itemCount: zahtevi.length,
      itemBuilder: (context, index) => _buildDnevniKartica(zahtevi[index]),
    );
  }

  Widget _buildDnevniKartica(V2Polazak zahtev) {
    final ime = zahtev.putnikIme ?? 'Nepoznat';
    final telefon = zahtev.brojTelefona ?? '';
    final grad = zahtev.grad ?? 'BC';
    final dan = zahtev.dan ?? '';
    final vreme = zahtev.zeljenoVreme ?? '';
    final id = zahtev.id;
    final brojMesta = zahtev.brojMesta;
    final glassContainer = Theme.of(context).glassContainer;
    final glassBorder = Theme.of(context).glassBorder;

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
                        Text(ime,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          children: [
                            _tipBadge('🎟️ DNEVNI', Colors.blue),
                            if (brojMesta > 1) _infoBadge('👥 $brojMesta mesta', Colors.purple),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _gradBadge(grad),
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
                    onPressed: _loadingIds.contains(id) ? null : () => _approveZahtev(id, zahtev),
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
                    onPressed: _loadingIds.contains(id) ? null : () => _rejectZahtev(id),
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

  // ─── Helpers ──────────────────────────────────────────────────────────────

  static Widget _tipBadge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10)),
      );

  static Widget _gradBadge(String grad) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: Text(grad, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
      );

  static Widget _infoBadge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(label,
            style: TextStyle(color: color.withValues(alpha: 0.9), fontWeight: FontWeight.bold, fontSize: 10)),
      );

  static Widget _buildPrazno(String poruka) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 72, color: Colors.white.withValues(alpha: 0.4)),
            const SizedBox(height: 14),
            Text(poruka,
                style:
                    TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 17, fontWeight: FontWeight.w500)),
          ],
        ),
      );

  // ─── Akcije (samo dnevni tab) ─────────────────────────────────────────────

  Future<void> _approveZahtev(String id, V2Polazak zahtev) async {
    setState(() => _loadingIds.add(id));
    try {
      final success = await V2PolasciService.v2OdobriZahtev(id, approvedBy: _currentDriver);
      if (!mounted) return;
      if (success) {
        V2AppSnackBar.success(context, '✅ Zahtev uspešno odobren');
      } else {
        V2AppSnackBar.error(context, '⚠️ Greška pri odobravanju, pokušaj ponovo');
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
        V2AppSnackBar.warning(context, 'Zahtev odbijen');
      } else {
        V2AppSnackBar.error(context, '⚠️ Greška pri odbijanju, pokušaj ponovo');
      }
    } finally {
      if (mounted) setState(() => _loadingIds.remove(id));
    }
  }
}
