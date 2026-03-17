import 'package:flutter/material.dart';

import '../globals.dart';
import '../theme.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

String _formatVreme(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  // Može biti "07:30:00" ili "2026-03-16T07:30:00"
  try {
    if (iso.contains('T')) {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return iso.length >= 5 ? iso.substring(0, 5) : iso;
  } catch (_) {
    return iso;
  }
}

String _formatDatumKratko(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  try {
    final dt = DateTime.parse(iso);
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.';
  } catch (_) {
    return iso;
  }
}

String _formatCreatedAt(String? iso) {
  if (iso == null || iso.isEmpty) return '';
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

Color _statusBoja(String tip) {
  if (tip == 'dispecer_odobrio') return Colors.greenAccent;
  if (tip == 'dispecer_odbio') return Colors.redAccent;
  return Colors.white70;
}

String _statusEmoji(String tip) {
  if (tip == 'dispecer_odobrio') return '✅';
  if (tip == 'dispecer_odbio') return '❌';
  return '🤖';
}

// ─── Log card ─────────────────────────────────────────────────────────────────

class _LogCard extends StatelessWidget {
  final Map<String, dynamic> log;
  const _LogCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final tip = log['tip']?.toString() ?? '';
    final putnikIme = log['putnik_ime']?.toString() ?? '—';
    final grad = log['grad']?.toString() ?? '';
    final vreme = _formatVreme(log['vreme']?.toString());
    final datum = _formatDatumKratko(log['datum']?.toString());
    final detalji = log['detalji']?.toString() ?? '';
    final createdAt = _formatCreatedAt(log['created_at']?.toString());
    final boja = _statusBoja(tip);
    final emoji = _statusEmoji(tip);

    // Alt termini iz detalji stringa
    String altInfo = '';
    if (tip == 'dispecer_odbio') {
      final alt1Match = RegExp(r'alt1=(\S+)').firstMatch(detalji);
      final alt2Match = RegExp(r'alt2=(\S+)').firstMatch(detalji);
      final a1 = alt1Match?.group(1);
      final a2 = alt2Match?.group(1);
      if (a1 != null || a2 != null) {
        altInfo = 'Alt: ${[a1, a2].whereType<String>().join(' / ')}';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: boja.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Emoji + vreme obrade
          SizedBox(
            width: 48,
            child: Column(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(height: 2),
                Text(
                  createdAt,
                  style: const TextStyle(color: Colors.white38, fontSize: 9),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Putnik + termin
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  putnikIme,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      grad,
                      style: TextStyle(color: boja, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      vreme,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      datum,
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
                if (altInfo.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    altInfo,
                    style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          // Status chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: boja.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: boja.withValues(alpha: 0.5)),
            ),
            child: Text(
              tip == 'dispecer_odobrio' ? 'Odobrio' : 'Odbio',
              style: TextStyle(color: boja, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Ekran ─────────────────────────────────────────────────────────────────────

class V3DispecerLogScreen extends StatefulWidget {
  const V3DispecerLogScreen({super.key});

  @override
  State<V3DispecerLogScreen> createState() => _V3DispecerLogScreenState();
}

class _V3DispecerLogScreenState extends State<V3DispecerLogScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _logs = [];

  // Filteri
  String _filterGrad = 'SVI'; // 'SVI' / 'BC' / 'VS'
  String _filterTip = 'SVI'; // 'SVI' / 'dispecer_odobrio' / 'dispecer_odbio'
  DateTime _filterDatum = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final datumStr =
          '${_filterDatum.year}-${_filterDatum.month.toString().padLeft(2, '0')}-${_filterDatum.day.toString().padLeft(2, '0')}';

      var query = supabase
          .from('v3_audit_log')
          .select()
          .inFilter('tip', ['dispecer_odobrio', 'dispecer_odbio'])
          .eq('datum', datumStr)
          .order('created_at', ascending: false)
          .limit(200);

      final raw = await query;
      List<Map<String, dynamic>> logs = List<Map<String, dynamic>>.from(raw as List);

      if (_filterGrad != 'SVI') {
        logs = logs.where((r) => (r['grad']?.toString() ?? '') == _filterGrad).toList();
      }
      if (_filterTip != 'SVI') {
        logs = logs.where((r) => (r['tip']?.toString() ?? '') == _filterTip).toList();
      }

      setState(() {
        _logs = logs;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _odaberiDatum() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDatum,
      firstDate: DateTime(2025),
      lastDate: DateTime.now().add(const Duration(days: 7)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(primary: Colors.teal),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _filterDatum = picked);
      await _load();
    }
  }

  String get _naslovDatuma {
    final danas = DateTime.now();
    if (_filterDatum.year == danas.year && _filterDatum.month == danas.month && _filterDatum.day == danas.day) {
      return 'Danas';
    }
    return '${_filterDatum.day.toString().padLeft(2, '0')}.${_filterDatum.month.toString().padLeft(2, '0')}.${_filterDatum.year}';
  }

  @override
  Widget build(BuildContext context) {
    final odobreno = _logs.where((r) => r['tip'] == 'dispecer_odobrio').length;
    final odbijeno = _logs.where((r) => r['tip'] == 'dispecer_odbio').length;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              // ─── Header ───────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(
                      child: Text(
                        '🤖 Dispečer log',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // Datum picker
                    GestureDetector(
                      onTap: _odaberiDatum,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white30),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.calendar_today, color: Colors.white70, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              _naslovDatuma,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ─── Stat chips ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    _StatChip(label: 'Ukupno', value: _logs.length, color: Colors.white70),
                    const SizedBox(width: 8),
                    _StatChip(label: 'Odobreno', value: odobreno, color: Colors.greenAccent),
                    const SizedBox(width: 8),
                    _StatChip(label: 'Odbijeno', value: odbijeno, color: Colors.redAccent),
                  ],
                ),
              ),

              // ─── Filter row ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    // Grad filter
                    _FilterChip(
                      label: 'Svi gradovi',
                      selected: _filterGrad == 'SVI',
                      onTap: () {
                        setState(() => _filterGrad = 'SVI');
                        _load();
                      },
                    ),
                    const SizedBox(width: 6),
                    _FilterChip(
                      label: 'BC',
                      selected: _filterGrad == 'BC',
                      onTap: () {
                        setState(() => _filterGrad = 'BC');
                        _load();
                      },
                    ),
                    const SizedBox(width: 6),
                    _FilterChip(
                      label: 'VS',
                      selected: _filterGrad == 'VS',
                      onTap: () {
                        setState(() => _filterGrad = 'VS');
                        _load();
                      },
                    ),
                    const Spacer(),
                    // Tip filter
                    _FilterChip(
                      label: '✅',
                      selected: _filterTip == 'dispecer_odobrio',
                      color: Colors.greenAccent,
                      onTap: () {
                        setState(() => _filterTip = _filterTip == 'dispecer_odobrio' ? 'SVI' : 'dispecer_odobrio');
                        _load();
                      },
                    ),
                    const SizedBox(width: 6),
                    _FilterChip(
                      label: '❌',
                      selected: _filterTip == 'dispecer_odbio',
                      color: Colors.redAccent,
                      onTap: () {
                        setState(() => _filterTip = _filterTip == 'dispecer_odbio' ? 'SVI' : 'dispecer_odbio');
                        _load();
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // ─── Lista ─────────────────────────────────────────────────────
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: Colors.teal))
                    : _error != null
                        ? Center(
                            child: Text(
                              'Greška: $_error',
                              style: const TextStyle(color: Colors.redAccent),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : _logs.isEmpty
                            ? const Center(
                                child: Text(
                                  '🤖 Nema zapisa dispečera\nza odabrani datum.',
                                  style: TextStyle(color: Colors.white54, fontSize: 15),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : RefreshIndicator(
                                color: Colors.teal,
                                onRefresh: _load,
                                child: ListView.builder(
                                  padding: EdgeInsets.fromLTRB(12, 0, 12, 16 + MediaQuery.of(context).padding.bottom),
                                  itemCount: _logs.length,
                                  itemBuilder: (_, i) => _LogCard(log: _logs[i]),
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

// ─── Helper widgets ────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$value ',
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            TextSpan(
              text: label,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;
  const _FilterChip({required this.label, required this.selected, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.teal;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? c.withValues(alpha: 0.8) : Colors.white24,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? c : Colors.white60,
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
