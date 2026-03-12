import 'package:flutter/material.dart';

import '../services/realtime/v2_master_realtime_manager.dart';
import '../theme.dart';

// ─── Top-level pure helperi (bez state pristupa) ──────────────────────────────

Color _auditTipColor(String tip) {
  if (tip.contains('zahtev') || tip == 'pokupljen') return Colors.greenAccent;
  if (tip.contains('otkazan') || tip.contains('otkazano') || tip.contains('odbijen')) return Colors.redAccent;
  if (tip.contains('uplata') || tip == 'naplata') return Colors.amberAccent;
  if (tip.contains('logout') || tip.contains('sifre')) return Colors.purpleAccent;
  if (tip.contains('termin') || tip.contains('vozac')) return Colors.lightBlueAccent;
  if (tip.contains('odsustvo')) return Colors.orangeAccent;
  return Colors.white70;
}

const _auditTipEmojiMap = {
  'odobren_zahtev': '✅',
  'odbijen_zahtev': '❌',
  'zahtev_poslan': '📤',
  'zahtev_otkazan': '🚫',
  'pokupljen': '🚗',
  'otkazano_vozac': '❌',
  'naplata': '💳',
  'uplata_dodana': '💰',
  'odsustvo_postavljeno': '🏥',
  'odsustvo_uklonjeno': '✅',
  'putnik_logout': '🚺',
  'dodat_termin': '📅',
  'uklonjen_termin': '🗑️',
  'dodeljen_vozac': '👤',
  'uklonjen_vozac': '👤',
  'promena_sifre': '🔑',
};

String _auditTipEmoji(String tip) => _auditTipEmojiMap[tip] ?? '📋';

String _auditFormatDatum(String? iso) {
  if (iso == null) return '—';
  try {
    final dt = DateTime.parse(iso).toLocal();
    final d = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$d.$mo. $h:$mi';
  } catch (_) {
    return iso;
  }
}

// ─── Log card — StatelessWidget umjesto 150 linija u itemBuilder ──────────────

class _AuditLogCard extends StatelessWidget {
  const _AuditLogCard({required this.log});

  final Map<String, dynamic> log;

  @override
  Widget build(BuildContext context) {
    final tip = log['tip']?.toString() ?? '';
    final aktorIme = log['aktor_ime']?.toString();
    final putnikIme = log['putnik_ime']?.toString();
    final detalji = log['detalji']?.toString();
    final dan = log['dan']?.toString();
    final grad = log['grad']?.toString();
    final vreme = log['vreme']?.toString();
    final color = _auditTipColor(tip);
    // Sakrij detalji ako samo ponavlja aktorIme
    final prikaziDetalji = detalji != null && (aktorIme == null || !detalji.contains(aktorIme));
    final metaSegmenti = [dan, grad, vreme].whereType<String>().join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Emoji + datum
          Column(
            children: [
              Text(_auditTipEmoji(tip), style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 4),
              Text(_auditFormatDatum(log['created_at']?.toString()),
                  style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ],
          ),
          const SizedBox(width: 12),
          // Sadržaj
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // RED 1: ime putnika + tip badge
                Row(
                  children: [
                    if (putnikIme != null) ...[
                      Flexible(
                        child: Text(putnikIme,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: color.withValues(alpha: 0.4)),
                      ),
                      child: Text(tip, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                // RED 2: vozač + dan · grad · vreme
                if (aktorIme != null || metaSegmenti.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (aktorIme != null) ...[
                        Text(aktorIme,
                            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                        if (metaSegmenti.isNotEmpty) const SizedBox(width: 8),
                      ],
                      if (metaSegmenti.isNotEmpty)
                        Text(metaSegmenti, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                ],
                if (prikaziDetalji) ...[
                  const SizedBox(height: 3),
                  Text(detalji, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Izolirani filter panel — setState ovdje ne trigguje StreamBuilder ────────

class _AuditFilterPanel extends StatefulWidget {
  const _AuditFilterPanel({required this.allLogs, required this.isLoading});

  final List<Map<String, dynamic>> allLogs;
  final bool isLoading;

  @override
  State<_AuditFilterPanel> createState() => _AuditFilterPanelState();
}

class _AuditFilterPanelState extends State<_AuditFilterPanel> {
  String? _filterTip;

  // Jedan prolaz: filtrira vozac logove + skuplja dostupne tipove
  ({List<Map<String, dynamic>> logs, List<String> tipovi}) _compute() {
    final logs = <Map<String, dynamic>>[];
    final tipoviSet = <String>{};
    for (final l in widget.allLogs) {
      if (l['aktor_tip']?.toString() != 'vozac') continue;
      final tip = l['tip']?.toString();
      if (tip != null) tipoviSet.add(tip);
      if (_filterTip == null || tip == _filterTip) logs.add(l);
    }
    final tipovi = tipoviSet.toList()..sort();
    return (logs: logs, tipovi: tipovi);
  }

  @override
  Widget build(BuildContext context) {
    final (:logs, :tipovi) = _compute();

    return Column(
      children: [
        // Filter bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _filterTip,
                      hint: const Text('Tip', style: TextStyle(color: Colors.white54, fontSize: 13)),
                      dropdownColor: const Color(0xFF1A1A2E),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white54, size: 18),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Svi tipovi')),
                        ...tipovi.map((t) => DropdownMenuItem<String?>(value: t, child: Text(t))),
                      ],
                      onChanged: (v) => setState(() => _filterTip = v),
                    ),
                  ),
                ),
              ),
              if (_filterTip != null) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => setState(() => _filterTip = null),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    height: 36,
                    width: 36,
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                    ),
                    child: const Icon(Icons.close, color: Colors.redAccent, size: 18),
                  ),
                ),
              ],
            ],
          ),
        ),
        // Lista
        Expanded(
          child: widget.isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : logs.isEmpty
                  ? const Center(child: Text('Nema zapisa', style: TextStyle(color: Colors.white54, fontSize: 16)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      itemCount: logs.length,
                      itemBuilder: (_, index) => _AuditLogCard(log: logs[index]),
                    ),
        ),
      ],
    );
  }
}

// ─── Glavni screen ────────────────────────────────────────────────────────────

/// Ekran za pregled audit log zapisa.
/// Dostupan samo adminima, otvara se iz AppBar admin screena.
/// Čita iz V2MasterRealtimeManager.auditLogCache — 0 direktnih DB upita.
class V2AuditLogScreen extends StatelessWidget {
  const V2AuditLogScreen({super.key});

  static final Stream<List<Map<String, dynamic>>> _stream = V2MasterRealtimeManager.instance.streamAuditLog();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Audit log', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
        child: SafeArea(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _stream,
            builder: (context, snapshot) {
              final allLogs = snapshot.data ?? [];
              final isLoading = snapshot.connectionState == ConnectionState.waiting && allLogs.isEmpty;
              return _AuditFilterPanel(allLogs: allLogs, isLoading: isLoading);
            },
          ),
        ),
      ),
    );
  }
}
