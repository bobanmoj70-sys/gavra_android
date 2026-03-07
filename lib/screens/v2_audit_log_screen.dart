import 'package:flutter/material.dart';

import '../globals.dart';
import '../services/v2_theme_manager.dart';

/// Ekran za pregled audit log zapisa.
/// Dostupan samo adminima, otvara se iz AppBar admin screena.
class V2AuditLogScreen extends StatefulWidget {
  const V2AuditLogScreen({super.key});

  @override
  State<V2AuditLogScreen> createState() => _V2AuditLogScreenState();
}

class _V2AuditLogScreenState extends State<V2AuditLogScreen> {
  static const _pageSize = 50;

  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  bool _hasMore = true;
  int _offset = 0;

  // Filteri
  String? _filterTip;
  String? _filterAktorTip; // vozac / putnik / admin
  String? _filterPutnikIme;

  final _scrollController = ScrollController();

  // Sve dostupne vrijednosti za tip dropdown
  static const _tipoviList = [
    'odobren_zahtev',
    'odbijen_zahtev',
    'zahtev_poslan',
    'zahtev_otkazan',
    'pokupljen',
    'otkazano_vozac',
    'naplata',
    'uplata_dodana',
    'bez_polaska_globalni',
    'odsustvo_postavljeno',
    'odsustvo_uklonjeno',
    'putnik_logout',
    'dodat_termin',
    'uklonjen_termin',
    'dodeljen_vozac',
    'uklonjen_vozac',
    'promena_sifre',
  ];

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_loading && _hasMore) _loadMore();
    }
  }

  Future<void> _loadLogs({bool reset = false}) async {
    if (reset) {
      setState(() {
        _logs = [];
        _offset = 0;
        _hasMore = true;
        _loading = true;
      });
    } else {
      setState(() => _loading = true);
    }

    try {
      var q = supabase.from('v2_audit_log').select();

      if (_filterTip != null) q = q.eq('tip', _filterTip!);
      if (_filterAktorTip != null) q = q.eq('aktor_tip', _filterAktorTip!);
      if (_filterPutnikIme != null && _filterPutnikIme!.isNotEmpty) {
        q = q.ilike('putnik_ime', '%$_filterPutnikIme%');
      }

      final res = await q.order('created_at', ascending: false).range(_offset, _offset + _pageSize - 1);
      final items = List<Map<String, dynamic>>.from(res);

      setState(() {
        if (reset || _offset == 0) {
          _logs = items;
        } else {
          _logs.addAll(items);
        }
        _offset += items.length;
        _hasMore = items.length == _pageSize;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    await _loadLogs();
  }

  Color _tipColor(String tip) {
    if (tip.contains('zahtev') || tip == 'pokupljen') return Colors.greenAccent;
    if (tip.contains('otkazan') || tip.contains('otkazano') || tip.contains('odbijen')) return Colors.redAccent;
    if (tip.contains('uplata') || tip == 'naplata') return Colors.amberAccent;
    if (tip.contains('logout') || tip.contains('sifre')) return Colors.purpleAccent;
    if (tip.contains('termin') || tip.contains('vozac')) return Colors.lightBlueAccent;
    if (tip.contains('odsustvo')) return Colors.orangeAccent;
    if (tip.contains('bez_polaska')) return Colors.orange;
    return Colors.white70;
  }

  String _tipEmoji(String tip) {
    const map = {
      'odobren_zahtev': '✅',
      'odbijen_zahtev': '❌',
      'zahtev_poslan': '📤',
      'zahtev_otkazan': '🚫',
      'pokupljen': '🚗',
      'otkazano_vozac': '❌',
      'naplata': '💳',
      'uplata_dodana': '💰',
      'bez_polaska_globalni': '⚠️',
      'odsustvo_postavljeno': '🏥',
      'odsustvo_uklonjeno': '✅',
      'putnik_logout': '🚪',
      'dodat_termin': '📅',
      'uklonjen_termin': '🗑️',
      'dodeljen_vozac': '👤',
      'uklonjen_vozac': '👤',
      'promena_sifre': '🔑',
    };
    return map[tip] ?? '📋';
  }

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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: V2ThemeManager().currentGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          title: const Text('Audit log', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: 'Osveži',
              onPressed: () => _loadLogs(reset: true),
            ),
          ],
        ),
        body: Column(
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
                        child: DropdownButton<String>(
                          value: _filterTip,
                          hint: const Text('Tip', style: TextStyle(color: Colors.white54, fontSize: 13)),
                          dropdownColor: const Color(0xFF1A1A2E),
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white54, size: 18),
                          items: [
                            const DropdownMenuItem<String>(value: null, child: Text('Svi tipovi')),
                            ..._tipoviList.map((t) => DropdownMenuItem(value: t, child: Text(t))),
                          ],
                          onChanged: (v) {
                            setState(() => _filterTip = v);
                            _loadLogs(reset: true);
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Aktor tip filter
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
                        child: DropdownButton<String>(
                          value: _filterAktorTip,
                          hint: const Text('Ko', style: TextStyle(color: Colors.white54, fontSize: 13)),
                          dropdownColor: const Color(0xFF1A1A2E),
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white54, size: 18),
                          items: const [
                            DropdownMenuItem<String>(value: null, child: Text('Svi')),
                            DropdownMenuItem(value: 'vozac', child: Text('Vozač')),
                            DropdownMenuItem(value: 'putnik', child: Text('Putnik')),
                            DropdownMenuItem(value: 'admin', child: Text('Admin')),
                          ],
                          onChanged: (v) {
                            setState(() => _filterAktorTip = v);
                            _loadLogs(reset: true);
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Clear filter dugme
                  if (_filterTip != null || _filterAktorTip != null)
                    InkWell(
                      onTap: () {
                        setState(() {
                          _filterTip = null;
                          _filterAktorTip = null;
                        });
                        _loadLogs(reset: true);
                      },
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
              child: _logs.isEmpty && _loading
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : _logs.isEmpty
                      ? const Center(child: Text('Nema zapisa', style: TextStyle(color: Colors.white54, fontSize: 16)))
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                          itemCount: _logs.length + (_hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _logs.length) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2)),
                              );
                            }
                            final log = _logs[index];
                            final tip = log['tip']?.toString() ?? '';
                            final aktorIme = log['aktor_ime']?.toString();
                            final putnikIme = log['putnik_ime']?.toString();
                            final detalji = log['detalji']?.toString();
                            final dan = log['dan']?.toString();
                            final grad = log['grad']?.toString();
                            final vreme = log['vreme']?.toString();
                            final createdAt = log['created_at']?.toString();

                            final color = _tipColor(tip);

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
                                        Row(
                                          children: [
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
                                            if (aktorIme != null) ...[
                                              const SizedBox(width: 8),
                                              Text(
                                                aktorIme,
                                                style: const TextStyle(
                                                    color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                                              ),
                                            ],
                                          ],
                                        ),
                                        if (putnikIme != null) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            '👤 $putnikIme',
                                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                                          ),
                                        ],
                                        if (detalji != null) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            detalji,
                                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                                          ),
                                        ],
                                        if (dan != null || grad != null || vreme != null) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            [dan, grad, vreme].where((e) => e != null).join(' · '),
                                            style: const TextStyle(color: Colors.white24, fontSize: 10),
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
        ),
      ),
    );
  }
}
