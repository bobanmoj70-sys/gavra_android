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
        child: SafeArea(
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
                onAlternative: (id, z) => _posaljiAlternative(id, z),
                onReject: (id) => _rejectZahtev(id),
              );
            },
          ),
        ),
      ),
    );
  }

  // ─── Akcije ───────────────────────────────────────────────────────────────

  Future<void> _approveZahtev(String id, V2Polazak zahtev) async {
    final TextEditingController timeController = TextEditingController(text: zahtev.zeljenoVreme);

    final String? odabranoVreme = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E), // Podudara se sa temom
        title: const Text('Odobravanje zahteva', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Potvrdi ili promeni vreme polaska za: \n${zahtev.putnikIme ?? "Putnika"}',
                style: const TextStyle(color: Colors.white70)),
            if (zahtev.adresaNaziv != null && zahtev.adresaNaziv!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.location_on, size: 14, color: Colors.amber),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    zahtev.adresaNaziv!,
                    style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ]),
            ],
            const SizedBox(height: 20),
            TextField(
              controller: timeController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                labelText: 'Vreme polaska (HH:mm)',
                labelStyle: TextStyle(color: Colors.amber),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.amber)),
              ),
              keyboardType: TextInputType.datetime,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OTKAŽI', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, timeController.text),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('ODOBRI', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (odabranoVreme == null) return;

    setState(() => _loadingIds.add(id));
    try {
      final success = await V2PolasciService.v2OdobriZahtev(
        id,
        approvedBy: _currentDriver,
        dodeljenoVreme: odabranoVreme,
      );
      if (!mounted) return;
      if (success) {
        V2AppSnackBar.success(context, '✅ Zahtev uspešno odobren ($odabranoVreme)');
      } else {
        V2AppSnackBar.error(context, '❌ Greška pri odobravanju, pokušaj ponovo');
      }
    } finally {
      if (mounted) setState(() => _loadingIds.remove(id));
      timeController.dispose();
    }
  }

  Future<void> _posaljiAlternative(String id, V2Polazak zahtev) async {
    final TextEditingController alt1 = TextEditingController(text: zahtev.zeljenoVreme);
    final TextEditingController alt2 = TextEditingController();

    final bool? potvrda = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Ponudi Alternative', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Putnik: ${zahtev.putnikIme ?? "Nepoznato"}', style: const TextStyle(color: Colors.white)),
            if (zahtev.adresaNaziv != null) ...[
              const SizedBox(height: 4),
              Text('Lokacija: ${zahtev.adresaNaziv}', style: const TextStyle(color: Colors.amber, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            const Text('Prvo alternativno vreme:', style: TextStyle(color: Colors.white70, fontSize: 12)),
            TextField(
              controller: alt1,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Prva alternativa (obavezno)',
                labelStyle: TextStyle(color: Colors.amber),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              ),
            ),
            const SizedBox(height: 10),
            const Text('Drugo alternativno vreme (opciono):', style: TextStyle(color: Colors.white70, fontSize: 12)),
            TextField(
              controller: alt2,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Druga alternativa (opciono)',
                labelStyle: TextStyle(color: Colors.amber),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OTKAŽI', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade700),
            child: const Text('POŠALJI PREDLOGE', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (potvrda != true || alt1.text.isEmpty) return;

    setState(() => _loadingIds.add(id));
    try {
      final success = await V2PolasciService.v2PosaljiAlternative(
        id,
        alt1: alt1.text,
        alt2: alt2.text.isEmpty ? null : alt2.text,
        approvedBy: _currentDriver,
      );
      if (!mounted) return;
      if (success) {
        V2AppSnackBar.info(context, '🕒 Alternative su poslate putniku');
      } else {
        V2AppSnackBar.error(context, '❌ Greška pri slanju alternativa');
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
  required void Function(String, V2Polazak) onAlternative,
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
      onAlternative: onAlternative,
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
  required void Function(String, V2Polazak) onAlternative,
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
  final adresa = zahtev.adresaNaziv ?? '';

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
            if (adresa.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.location_on, size: 16, color: Colors.white.withValues(alpha: 0.7)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    adresa,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: isLoading ? null : () => onAlternative(id, zahtev),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.shade700,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('ALTERN.', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
                ),
              ),
              const SizedBox(width: 8),
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
