import 'package:flutter/material.dart';

import '../services/realtime/v2_master_realtime_manager.dart';
import '../theme.dart';

/// Ekran za pregled audit log zapisa.
/// Dostupan samo adminima, otvara se iz AppBar admin screena.
/// Čita iz V2MasterRealtimeManager.auditLogCache — 0 direktnih DB upita.
class V2AuditLogScreen extends StatefulWidget {
  const V2AuditLogScreen({super.key});

  @override
  State<V2AuditLogScreen> createState() => _V2AuditLogScreenState();
}

class _V2AuditLogScreenState extends State<V2AuditLogScreen> {
  late final Stream<List<Map<String, dynamic>>> _stream;

  // Filteri — primenjuju se klijentski na cache podatke
  String? _filterTip;

  @override
  void initState() {
    super.initState();
    _stream = V2MasterRealtimeManager.instance.streamAuditLog();
  }

  static List<Map<String, dynamic>> _applyFilters(
    List<Map<String, dynamic>> logs,
    String? filterTip,
  ) {
    // Uvijek samo vozači — putnici imaju svoje ekrane
    final vozacLogs = logs.where((log) => log['aktor_tip']?.toString() == 'vozac').toList();
    if (filterTip == null) return vozacLogs;
    return vozacLogs.where((log) => log['tip']?.toString() == filterTip).toList();
  }

  static Color _tipColor(String tip) {
    if (tip.contains('zahtev') || tip == 'pokupljen') return Colors.greenAccent;
    if (tip.contains('otkazan') || tip.contains('otkazano') || tip.contains('odbijen')) return Colors.redAccent;
    if (tip.contains('uplata') || tip == 'naplata') return Colors.amberAccent;
    if (tip.contains('logout') || tip.contains('sifre')) return Colors.purpleAccent;
    if (tip.contains('termin') || tip.contains('vozac')) return Colors.lightBlueAccent;
    if (tip.contains('odsustvo')) return Colors.orangeAccent;
    return Colors.white70;
  }

  static const _tipEmojiMap = {
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
    'putnik_logout': '🚪',
    'dodat_termin': '📅',
    'uklonjen_termin': '🗑️',
    'dodeljen_vozac': '👤',
    'uklonjen_vozac': '👤',
    'promena_sifre': '🔑',
  };

  static String _tipEmoji(String tip) => _tipEmojiMap[tip] ?? '📋';

  static String _formatDatum(String? iso) {
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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          title: const Text('Audit log', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _stream,
          builder: (context, snapshot) {
            final allLogs = snapshot.data ?? [];
            final logs = _applyFilters(allLogs, _filterTip);
            final isLoading = snapshot.connectionState == ConnectionState.waiting && allLogs.isEmpty;
            // Dinamički tipovi — samo od vozača
            final dostupniTipovi = allLogs
                .where((l) => l['aktor_tip']?.toString() == 'vozac')
                .map((l) => l['tip']?.toString())
                .whereType<String>()
                .toSet()
                .toList()
              ..sort();

            return Column(
              children: [
                // Filter bar
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
                    children: [
                      // Tip filter
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
                                ...dostupniTipovi.map((t) => DropdownMenuItem<String?>(value: t, child: Text(t))),
                              ],
                              onChanged: (v) => setState(() => _filterTip = v),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Clear filter dugme
                      if (_filterTip != null)
                        InkWell(
                          onTap: () => setState(() {
                            _filterTip = null;
                          }),
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
                  ),
                ),
                // Lista
                Expanded(
                  child: isLoading
                      ? const Center(child: CircularProgressIndicator(color: Colors.white))
                      : logs.isEmpty
                          ? const Center(
                              child: Text('Nema zapisa', style: TextStyle(color: Colors.white54, fontSize: 16)))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                              itemCount: logs.length,
                              itemBuilder: (context, index) {
                                final log = logs[index];
                                final tip = log['tip']?.toString() ?? '';
                                final aktorIme = log['aktor_ime']?.toString();
                                final putnikIme = log['putnik_ime']?.toString();
                                final detalji = log['detalji']?.toString();
                                final dan = log['dan']?.toString();
                                final grad = log['grad']?.toString();
                                final vreme = log['vreme']?.toString();
                                final createdAt = log['created_at']?.toString();
                                final color = _tipColor(tip);
                                // Sakrij detalji ako samo ponavlja aktorIme (npr. "Putnik pokupljen od: Bruda")
                                final prikaziDetalji =
                                    detalji != null && (aktorIme == null || !detalji.contains(aktorIme));

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
                                          Text(_tipEmoji(tip), style: const TextStyle(fontSize: 18)),
                                          const SizedBox(height: 4),
                                          Text(
                                            _formatDatum(createdAt),
                                            style: const TextStyle(color: Colors.white38, fontSize: 10),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(width: 12),
                                      // Sadržaj
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // RED 1: ime putnika + badge
                                            Row(
                                              children: [
                                                if (putnikIme != null) ...[
                                                  Flexible(
                                                    child: Text(
                                                      putnikIme,
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.bold),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
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
                                                  child: Text(
                                                    tip,
                                                    style: TextStyle(
                                                      color: color,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            // RED 2: vozač + dan · grad · vreme
                                            if (aktorIme != null || dan != null || grad != null || vreme != null) ...[
                                              const SizedBox(height: 3),
                                              Row(
                                                children: [
                                                  if (aktorIme != null) ...[
                                                    Text(
                                                      aktorIme,
                                                      style: const TextStyle(
                                                          color: Colors.white70,
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w600),
                                                    ),
                                                    if (dan != null || grad != null || vreme != null)
                                                      const SizedBox(width: 8),
                                                  ],
                                                  if (dan != null || grad != null || vreme != null)
                                                    Text(
                                                      [dan, grad, vreme].whereType<String>().join(' · '),
                                                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                                                    ),
                                                ],
                                              ),
                                            ],
                                            if (prikaziDetalji) ...[
                                              const SizedBox(height: 3),
                                              Text(
                                                detalji,
                                                style: const TextStyle(color: Colors.white38, fontSize: 11),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
