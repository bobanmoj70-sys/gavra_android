import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/seat_request.dart';
import '../services/theme_manager.dart';
import '../services/v2_polasci_service.dart';
import '../theme.dart';

/// 📋 Audit/log ekran za SVE seat_requests — admin pregled celog toka zahteva
class V2PolasciLogScreen extends StatefulWidget {
  const V2PolasciLogScreen({super.key});

  @override
  State<V2PolasciLogScreen> createState() => _V2PolasciLogScreenState();
}

class _V2PolasciLogScreenState extends State<V2PolasciLogScreen> {
  // Filteri
  String _gradFilter = 'BC'; // 'BC' ili 'VS'
  final Set<String> _statusFilter = {}; // prazno = svi statusi

  static const _sviStatusi = [
    'pending',
    'approved',
    'confirmed',
    'rejected',
  ];

  static const _danLabels = {
    'pon': 'Pon',
    'uto': 'Uto',
    'sre': 'Sre',
    'cet': 'Čet',
    'pet': 'Pet',
    'sub': 'Sub',
    'ned': 'Ned',
  };

  Color _statusBoja(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.purple;
      case 'confirmed':
        return Colors.deepOrange;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _statusIkona(String status) {
    switch (status) {
      case 'pending':
        return Icons.hourglass_top;
      case 'approved':
        return Icons.settings_suggest;
      case 'confirmed':
        return Icons.drive_eta;
      case 'rejected':
        return Icons.cancel_outlined;
      default:
        return Icons.help_outline;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'ČEKA';
      case 'approved':
        return 'DISPECER';
      case 'confirmed':
        return 'VOZAČ';
      case 'rejected':
        return 'ODBIJEN';
      default:
        return status.toUpperCase();
    }
  }

  String _formatVreme(String? vreme) {
    if (vreme == null || vreme.isEmpty) return '—';
    // "08:00:00" → "08:00"
    return vreme.length >= 5 ? vreme.substring(0, 5) : vreme;
  }

  String _formatDatumVreme(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    return DateFormat('dd.MM. HH:mm').format(local);
  }

  Stream<List<SeatRequest>> _buildStream() {
    return V2PolasciService.streamSviZahtevi(
      statusFilter: _statusFilter.isEmpty ? null : _statusFilter.toList(),
      gradFilter: _gradFilter,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: ThemeManager().currentGradient),
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
                        'Log Zahteva',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            _buildFilteri(),
            Expanded(
              child: StreamBuilder<List<SeatRequest>>(
                stream: _buildStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator(color: Colors.white));
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('Greška: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
                    );
                  }
                  final lista = snapshot.data ?? [];
                  if (lista.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox, size: 64, color: Colors.white.withOpacity(0.4)),
                          const SizedBox(height: 12),
                          Text(
                            'Nema zahteva za izabrane filtere',
                            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 16),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                    itemCount: lista.length,
                    itemBuilder: (context, i) => _buildKartica(lista[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilteri() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grad filter - tabovi
          Row(
            children: [
              _gradTab('BC'),
              const SizedBox(width: 1),
              _gradTab('VS'),
            ],
          ),
          const SizedBox(height: 6),
          // Status filter
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              const Text('Status:', style: TextStyle(color: Colors.white70, fontSize: 13)),
              ..._sviStatusi.map((s) => _statusChip(s)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _gradTab(String grad) {
    final sel = _gradFilter == grad;
    return GestureDetector(
      onTap: () => setState(() => _gradFilter = grad),
      child: Container(
        width: 64,
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: sel ? Colors.white.withOpacity(0.2) : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: sel ? Colors.white : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Text(
          grad,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: sel ? Colors.white : Colors.white38,
            fontWeight: sel ? FontWeight.bold : FontWeight.normal,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final sel = _statusFilter.contains(status);
    final boja = _statusBoja(status);
    return GestureDetector(
      onTap: () => setState(() {
        if (sel) {
          _statusFilter.remove(status);
        } else {
          _statusFilter.add(status);
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: sel ? boja.withOpacity(0.25) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: sel ? boja.withOpacity(0.8) : Colors.white24),
        ),
        child: Text(
          _statusLabel(status),
          style: TextStyle(
            color: sel ? boja : Colors.white54,
            fontWeight: sel ? FontWeight.bold : FontWeight.normal,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildKartica(SeatRequest z) {
    final boja = _statusBoja(z.status);
    final dan = _danLabels[z.dan] ?? z.dan ?? '?';
    final grad = z.grad ?? '?';
    final zelja = _formatVreme(z.zeljenoVreme);
    final dodelja = _formatVreme(z.dodeljenoVreme);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).glassContainer.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: boja.withOpacity(0.4), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Zaglavlje: ime + status badge ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    z.putnikIme ?? '(nepoznat)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: boja.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: boja.withOpacity(0.6)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_statusIkona(z.status), color: boja, size: 13),
                      const SizedBox(width: 4),
                      Text(_statusLabel(z.status),
                          style: TextStyle(color: boja, fontWeight: FontWeight.bold, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // ── Dan / Grad / Vreme ──
            Row(
              children: [
                Icon(Icons.calendar_today, size: 14, color: Colors.white54),
                const SizedBox(width: 6),
                Text('$dan  •  $grad  •  $zelja',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                if (dodelja != zelja && dodelja != '—') ...[
                  const SizedBox(width: 6),
                  Icon(Icons.arrow_forward, size: 12, color: Colors.green.shade300),
                  const SizedBox(width: 4),
                  Text(dodelja,
                      style: TextStyle(color: Colors.green.shade300, fontSize: 13, fontWeight: FontWeight.w500)),
                ],
                if (z.brojMesta > 1) ...[
                  const SizedBox(width: 10),
                  Icon(Icons.group, size: 14, color: Colors.purple.shade200),
                  const SizedBox(width: 3),
                  Text('${z.brojMesta}', style: TextStyle(color: Colors.purple.shade200, fontSize: 13)),
                ],
              ],
            ),
            const SizedBox(height: 8),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 8),
            // ── Timeline podataka ──
            _infoRed(
              ikona: Icons.drive_eta,
              boja: Colors.deepOrange.shade200,
              label: 'Vozač',
              vrednost: (z.approvedBy != null && z.approvedBy!.isNotEmpty)
                  ? '${z.approvedBy}  (${_formatDatumVreme(z.createdAt)})'
                  : _formatDatumVreme(z.createdAt),
            ),
            if (z.processedAt != null)
              _infoRed(
                ikona: Icons.settings,
                boja: Colors.lightBlue.shade200,
                label: 'Obrađen',
                vrednost: _formatDatumVreme(z.processedAt),
              ),
            if (z.cancelledBy != null && z.cancelledBy!.isNotEmpty)
              _infoRed(
                ikona: Icons.person_off_outlined,
                boja: Colors.red.shade300,
                label: 'Otkazao',
                vrednost: z.cancelledBy!,
              ),
            // Alternative vremena
            if ((z.alternativeVreme1 != null && z.alternativeVreme1!.isNotEmpty) ||
                (z.alternativeVreme2 != null && z.alternativeVreme2!.isNotEmpty)) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.alt_route, size: 14, color: Colors.cyan.shade200),
                  const SizedBox(width: 6),
                  Text(
                    'Alternative: ${[
                      z.alternativeVreme1,
                      z.alternativeVreme2
                    ].where((v) => v != null && v.isNotEmpty).join(", ")}',
                    style: TextStyle(color: Colors.cyan.shade200, fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRed({
    required IconData ikona,
    required Color boja,
    required String label,
    required String vrednost,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(ikona, size: 13, color: boja),
          const SizedBox(width: 6),
          Text('$label: ', style: TextStyle(color: boja, fontSize: 12, fontWeight: FontWeight.w500)),
          Expanded(
            child: Text(vrednost, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
