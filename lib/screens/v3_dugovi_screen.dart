import 'package:flutter/material.dart';
import 'package:gavra_android/models/v3_dug.dart';
import 'package:gavra_android/services/v3/v3_finansije_service.dart';
import 'package:gavra_android/utils/v3_string_utils.dart';
import 'package:intl/intl.dart';

import '../helpers/v3_placanje_dialog_helper.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_safe_text.dart';
import '../utils/v3_state_utils.dart';

class V3DugoviScreen extends StatefulWidget {
  const V3DugoviScreen({super.key});

  @override
  State<V3DugoviScreen> createState() => _V3DugoviScreenState();
}

class _V3DugoviScreenState extends State<V3DugoviScreen> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<V3Dug>>(
      stream: V3FinansijeService.streamDugovi(),
      builder: (context, snapshot) {
        final isLoading = !snapshot.hasData && snapshot.connectionState == ConnectionState.waiting;
        final allDugovi = snapshot.data ?? [];
        final dugovi = allDugovi.where((d) => V3StringUtils.containsSearch(d.imePrezime, _filter)).toList();
        final ukupanIznos = allDugovi.fold(0.0, (s, d) => s + d.iznos);

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '💳 Dugovanja',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                ),
                Text(
                  'Neplaćeni putnici · ${allDugovi.length} dugova',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
          body: Container(
            decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
            child: SafeArea(
              child: Column(
                children: [
                  // ─── Stats kartica ───
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Row(
                      children: [
                        _StatCard(
                          label: 'Ukupno dugova',
                          value: '${allDugovi.length}',
                          icon: '💳',
                          color: Colors.redAccent,
                        ),
                        const SizedBox(width: 8),
                        _StatCard(
                          label: 'Ukupan iznos',
                          value: '${ukupanIznos.toStringAsFixed(0)} RSD',
                          icon: '💰',
                          color: Colors.orange,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ─── Search box ───
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                      ),
                      child: TextField(
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: '🔍  Pretraži putnike...',
                          hintStyle: TextStyle(color: Colors.white54),
                          prefixIcon: Icon(Icons.search, color: Colors.white54),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onChanged: (v) => V3StateUtils.safeSetState(this, () => _filter = v),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ─── Lista dugova ───
                  Expanded(
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator(color: Colors.white))
                        : dugovi.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('✅', style: TextStyle(fontSize: 48)),
                                    const SizedBox(height: 12),
                                    Text(
                                      _filter.isEmpty ? 'Nema evidentiranih dugovanja' : 'Nema rezultata za "$_filter"',
                                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                                itemCount: dugovi.length,
                                itemBuilder: (context, i) => _DugCard(
                                  dug: dugovi[i],
                                  onNaplati: () async {
                                    final dug = dugovi[i];
                                    final rezultat = await V3PlacanjeDialogHelper.naplati(
                                      context: context,
                                      putnikId: dug.putnikId,
                                      imePrezime: dug.imePrezime,
                                      defaultCena: dug.iznos,
                                      operativnaId: dug.id,
                                    );
                                    if (rezultat == null) return;

                                    if (context.mounted) {
                                      V3AppSnackBar.success(
                                        context,
                                        '✅ Naplaćeno ${rezultat.iznos.toStringAsFixed(0)} RSD za ${dug.imePrezime}',
                                      );
                                    }
                                  },
                                ),
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
}

// ─────────────────────────────────────────────
// Stats kartica
// ─────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
                  Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Kartica jednog duga
// ─────────────────────────────────────────────
class _DugCard extends StatelessWidget {
  const _DugCard({required this.dug, required this.onNaplati});

  final V3Dug dug;
  final VoidCallback onNaplati;

  @override
  Widget build(BuildContext context) {
    final initial = dug.imePrezime.isNotEmpty ? dug.imePrezime[0].toUpperCase() : '?';
    final datumStr = DateFormat('dd.MM.yyyy  HH:mm').format(dug.datum);
    final pickupStr = dug.pokupljenAt != null ? DateFormat('dd.MM.yyyy  HH:mm').format(dug.pokupljenAt!) : 'Nepoznato';
    final vozacStr = dug.vozacIme.isNotEmpty ? dug.vozacIme : 'Nepoznato';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              backgroundColor: Colors.redAccent.withValues(alpha: 0.8),
              radius: 22,
              child:
                  Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  V3SafeText.userName(dug.imePrezime,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Text('💰 ', style: TextStyle(fontSize: 13)),
                      Text(
                        '${dug.iznos.toStringAsFixed(0)} RSD',
                        style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(datumStr, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  const SizedBox(height: 1),
                  Text('Vozač: $vozacStr', style: const TextStyle(color: Colors.white60, fontSize: 11)),
                  const SizedBox(height: 1),
                  Text('Pokupljen: $pickupStr', style: const TextStyle(color: Colors.white60, fontSize: 11)),
                ],
              ),
            ),
            // Naplati dugme
            GestureDetector(
              onTap: onNaplati,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'NAPLATI',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
