import 'package:flutter/material.dart';

import '../globals.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

Color _tipColor(String tip) {
  if (tip.contains('zahtev') || tip == 'pokupljen') return Colors.greenAccent;
  if (tip.contains('otkazan') || tip.contains('otkazano') || tip.contains('odbijen')) return Colors.redAccent;
  if (tip.contains('uplata') || tip == 'naplata') return Colors.amberAccent;
  if (tip.contains('logout') || tip.contains('sifre') || tip.contains('promena')) return Colors.purpleAccent;
  if (tip.contains('termin') || tip.contains('vozac') || tip.contains('dodeljen')) return Colors.lightBlueAccent;
  if (tip.contains('odsustvo')) return Colors.orangeAccent;
  return Colors.white70;
}

const _emojiMap = {
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

String _emoji(String tip) => _emojiMap[tip] ?? '📋';

String _formatDatum(String? iso) {
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

// ─── Log card ─────────────────────────────────────────────────────────────────

class _LogCard extends StatelessWidget {
  final Map<String, dynamic> log;
  const _LogCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final tip = log['tip']?.toString() ?? '';
    final aktorIme = log['aktor_ime']?.toString();
    final putnikIme = log['putnik_ime']?.toString();
    final detalji = log['detalji']?.toString();
    final dan = log['dan']?.toString();
    final grad = log['grad']?.toString();
    final vreme = log['vreme']?.toString();
    final color = _tipColor(tip);
    final prikaziDetalji = detalji != null && detalji.isNotEmpty && (aktorIme == null || !detalji.contains(aktorIme));
    final meta = [dan, grad, vreme].whereType<String>().join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Emoji + datum
          SizedBox(
            width: 52,
            child: Column(
              children: [
                Text(_emoji(tip), style: const TextStyle(fontSize: 18)),
                const SizedBox(height: 4),
                Text(
                  _formatDatum(log['created_at']?.toString()),
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Sadržaj
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (putnikIme != null) ...[
                      Flexible(
                        child: Text(
                          putnikIme,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
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
                if (aktorIme != null || meta.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (aktorIme != null) ...[
                        Text(
                          aktorIme,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (meta.isNotEmpty) const SizedBox(width: 8),
                      ],
                      if (meta.isNotEmpty)
                        Text(
                          meta,
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
  }
}

// ─── Glavni screen ────────────────────────────────────────────────────────────

class V3AuditLogScreen extends StatefulWidget {
  const V3AuditLogScreen({super.key});

  @override
  State<V3AuditLogScreen> createState() => _V3AuditLogScreenState();
}

class _V3AuditLogScreenState extends State<V3AuditLogScreen> {
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;
  String? _filterTip;
  List<String> _tipovi = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final data = await supabase.from('v2_audit_log').select().order('created_at', ascending: false).limit(300);
      final logs = (data as List).cast<Map<String, dynamic>>();
      final tipoviSet = <String>{};
      for (final l in logs) {
        final tip = l['tip']?.toString();
        if (tip != null) tipoviSet.add(tip);
      }
      if (mounted) {
        setState(() {
          _logs = logs;
          _tipovi = tipoviSet.toList()..sort();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        V3AppSnackBar.error(context, '❌ Greška: $e');
      }
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filterTip == null) return _logs;
    return _logs.where((l) => l['tip']?.toString() == _filterTip).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Container(
      decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              // ── Header ────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                  border: Border(
                    bottom: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(
                      child: Text(
                        '📋 Audit log',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // Refresh
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white70),
                      onPressed: _isLoading ? null : _load,
                    ),
                  ],
                ),
              ),

              // ── Filter ────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
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
                            hint: const Text(
                              'Svi tipovi',
                              style: TextStyle(color: Colors.white54, fontSize: 13),
                            ),
                            dropdownColor: const Color(0xFF1A1A2E),
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            isExpanded: true,
                            icon: const Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.white54,
                              size: 18,
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Svi tipovi'),
                              ),
                              ..._tipovi.map(
                                (t) => DropdownMenuItem<String?>(value: t, child: Text(t)),
                              ),
                            ],
                            onChanged: (v) => setState(() => _filterTip = v),
                          ),
                        ),
                      ),
                    ),
                    if (_filterTip != null) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() => _filterTip = null),
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
                    const SizedBox(width: 8),
                    Text(
                      '${filtered.length}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),

              // ── Lista ─────────────────────────────────────────────
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : filtered.isEmpty
                        ? Center(
                            child: Text(
                              'Nema zapisa',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 16,
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            color: Colors.white,
                            backgroundColor: Colors.black54,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) => _LogCard(log: filtered[i]),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
