import 'package:flutter/material.dart';

import '../models/v2_polazak.dart';
import '../services/v2_auth_manager.dart';
import '../services/v2_polasci_service.dart';
import '../services/v2_theme_manager.dart';
import '../theme.dart';
import '../utils/v2_app_snack_bar.dart';

class V2PolasciScreen extends StatefulWidget {
  const V2PolasciScreen({super.key});

  @override
  State<V2PolasciScreen> createState() => _V2PolasciScreenState();
}

class _V2PolasciScreenState extends State<V2PolasciScreen> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: ThemeManager().currentGradient, // 🎨 Tema gradijent pozadina
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(80),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).glassContainer,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).glassBorder,
                  width: 1.5,
                ),
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(25),
                bottomRight: Radius.circular(25),
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(
                      child: Text(
                        'Zahtevi Rezervacija',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              offset: Offset(1, 1),
                              blurRadius: 3,
                              color: Colors.black54,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: StreamBuilder<List<V2Polazak>>(
          stream: V2PolasciService.v2StreamZahteviObrada(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator(color: Colors.white));
            }

            final zahtevi = snapshot.data ?? [];

            if (zahtevi.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline, size: 80, color: Colors.white.withOpacity(0.5)),
                    const SizedBox(height: 16),
                    Text(
                      'Nema novih zahteva na čekanju',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              itemCount: zahtevi.length,
              itemBuilder: (context, index) {
                final zahtev = zahtevi[index];
                final ime = zahtev.putnikIme ?? 'Nepoznat V2Putnik';
                final telefon = zahtev.brojTelefona ?? 'Nema telefona';
                final tip = zahtev.tipPutnika ?? 'dnevni';
                final grad = zahtev.grad ?? 'BC';
                final dan = zahtev.dan ?? '';
                final vreme = zahtev.zeljenoVreme ?? '';
                final id = zahtev.id;

                // Određivanje boje i teksta za etiketu tipa putnika
                Color tipColor;
                String tipLabel;
                if (tip.toString().toLowerCase() == 'posiljka') {
                  tipColor = Colors.orange;
                  tipLabel = '📦 POŠILJKA';
                } else if (tip.toString().toLowerCase() == 'manual' || tip.toString().toLowerCase() == 'dnevni') {
                  tipColor = Colors.blue;
                  tipLabel = '🎟️ DNEVNI';
                } else {
                  tipColor = Colors.grey;
                  tipLabel = tip.toString().toUpperCase();
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).glassContainer.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Theme.of(context).glassBorder,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
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
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            ime,
                                            style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: tipColor.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: tipColor.withOpacity(0.5)),
                                          ),
                                          child: Text(
                                            tipLabel,
                                            style: TextStyle(
                                              color: tipColor,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ),
                                        if (zahtev.brojMesta > 1) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.purple.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: Colors.purple.withOpacity(0.5)),
                                            ),
                                            child: Text(
                                              '👥 ${zahtev.brojMesta} MESTA',
                                              style: const TextStyle(
                                                color: Colors.purpleAccent,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                                ),
                                child: Text(
                                  grad,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.phone, size: 16, color: Colors.white.withOpacity(0.7)),
                              const SizedBox(width: 10),
                              Text(
                                telefon,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          if ((zahtev.alternativeVreme1 != null && zahtev.alternativeVreme1!.isNotEmpty) ||
                              (zahtev.alternativeVreme2 != null && zahtev.alternativeVreme2!.isNotEmpty)) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.alt_route, size: 16, color: Colors.cyan.withOpacity(0.7)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Alternative: ${[
                                      zahtev.alternativeVreme1,
                                      zahtev.alternativeVreme2
                                    ].where((v) => v != null && v.isNotEmpty).join(", ")}',
                                    style: TextStyle(
                                      color: Colors.cyan.shade200,
                                      fontSize: 14,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Divider(color: Colors.white24, height: 1),
                          ),
                          Row(
                            children: [
                              const Icon(Icons.calendar_month, size: 20, color: Colors.amber),
                              const SizedBox(width: 12),
                              Text(
                                '$dan ($vreme)',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _isLoading ? null : () => _approveZahtev(id, zahtev),
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text('ODOBRI',
                                      style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green.withOpacity(0.9),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _isLoading ? null : () => _rejectZahtev(id),
                                  icon: const Icon(Icons.cancel_outlined),
                                  label: const Text('ODBIJ',
                                      style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red.withOpacity(0.8),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _approveZahtev(String id, V2Polazak zahtev) async {
    setState(() => _isLoading = true);
    try {
      final currentDriver = await AuthManager.getCurrentDriver();
      final success = await V2PolasciService.v2OdobriZahtev(id, approvedBy: currentDriver);
      if (success && mounted) {
        AppSnackBar.success(context, '✅ Zahtev uspešno odobren');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _rejectZahtev(String id) async {
    setState(() => _isLoading = true);
    try {
      final currentDriver = await AuthManager.getCurrentDriver();
      final success = await V2PolasciService.v2OdbijZahtev(id, rejectedBy: currentDriver);
      if (success && mounted) {
        AppSnackBar.error(context, '❌ Zahtev je odbijen');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
