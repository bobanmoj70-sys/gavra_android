import 'package:flutter/material.dart';
import 'package:gavra_android/models/v3_gorivo.dart';
import 'package:gavra_android/services/realtime/v3_master_realtime_manager.dart';
import 'package:gavra_android/services/v3/v3_gorivo_service.dart';
import 'package:gavra_android/theme.dart';

import '../utils/v3_container_utils.dart';
import '../utils/v3_format_utils.dart';

class V3GorivoScreen extends StatefulWidget {
  const V3GorivoScreen({super.key});

  @override
  State<V3GorivoScreen> createState() => _V3GorivoScreenState();
}

class _V3GorivoScreenState extends State<V3GorivoScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  static const Color _accent = Color(0xFFFF9800);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<_GorivoData>(
      stream: V3MasterRealtimeManager.instance.v3StreamFromCache<_GorivoData>(
        tables: ['v3_pumpa_stanje', 'v3_pumpa_rezervoar'],
        build: () => _GorivoData(
          stanje: V3GorivoService.getStanjeSync(),
          rezervoar: V3GorivoService.getRezervoarSync(),
        ),
      ),
      builder: (context, snapshot) {
        final data = snapshot.data ??
            _GorivoData(
              stanje: V3GorivoService.getStanjeSync(),
              rezervoar: V3GorivoService.getRezervoarSync(),
            );
        return _buildScaffold(context, data);
      },
    );
  }

  Widget _buildScaffold(BuildContext context, _GorivoData data) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: Theme.of(context).backgroundGradient,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).glassBorder),
            ),
          ),
        ),
        title: Row(
          children: [
            V3ContainerUtils.iconContainer(
              padding: const EdgeInsets.all(7),
              backgroundColor: _accent.withValues(alpha: 0.25),
              borderRadiusGeometry: BorderRadius.circular(10),
              border: Border.all(color: _accent.withValues(alpha: 0.5)),
              child: const Icon(Icons.local_gas_station, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Text(
              'Gorivo',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _accent,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: '⛽ Pumpa'),
            Tab(text: '🛢️ Rezervoar'),
          ],
        ),
      ),
      body: V3ContainerUtils.backgroundContainer(
        gradient: Theme.of(context).backgroundGradient,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildPumpaTab(data.stanje),
            _buildRezervoarTab(data.rezervoar),
          ],
        ),
      ),
    );
  }

  Widget _buildPumpaTab(V3PumpaStanje? stanje) {
    final topPad = MediaQuery.of(context).padding.top + kToolbarHeight + 48 + 16;
    if (stanje == null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.only(top: topPad),
          child: const Text('Nema podataka o pumpi', style: TextStyle(color: Colors.white70)),
        ),
      );
    }
    final procenat = stanje.kapacitetLitri > 0 ? (stanje.trenutnoStanje / stanje.kapacitetLitri).clamp(0.0, 1.0) : 0.0;
    final ispodAlarma = stanje.kapacitetLitri > 0 && stanje.trenutnoStanje < stanje.kapacitetLitri * 0.1;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, topPad, 16, 16),
      child: Column(
        children: [
          _V3BrojcanikCard(
            label: '⛽ Pumpa — trenutno stanje',
            trenutno: stanje.trenutnoStanje,
            kapacitet: stanje.kapacitetLitri,
            procenat: procenat,
            ispodAlarma: ispodAlarma,
          ),
          const SizedBox(height: 16),
          _V3DetaljiCard(
            children: [
              _gorivoDetaljiRow('🔫 Stanje brojača pištolja',
                  '${V3FormatUtils.formatGorivo(stanje.stanjeBrojacPistolj)} L', Colors.white70),
              _gorivoDetaljiRow(
                  '📦 Kapacitet', '${V3FormatUtils.formatGorivo(stanje.kapacitetLitri)} L', Colors.white70),
              _gorivoDetaljiRow('🔖 Naziv', stanje.naziv, Colors.white70),
              _gorivoDetaljiRow(
                  '✅ Aktivno', stanje.aktivno ? 'Da' : 'Ne', stanje.aktivno ? Colors.greenAccent : Colors.redAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRezervoarTab(V3PumpaRezervoar? r) {
    final topPad = MediaQuery.of(context).padding.top + kToolbarHeight + 48 + 16;
    if (r == null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.only(top: topPad),
          child: const Text('Nema podataka o rezervoaru', style: TextStyle(color: Colors.white70)),
        ),
      );
    }
    final procenat = (r.procentPunjenosti / 100).clamp(0.0, 1.0);
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, topPad, 16, 16),
      child: Column(
        children: [
          _V3BrojcanikCard(
            label: '🛢️ Rezervoar — trenutni nivo',
            trenutno: r.trenutnoLitara,
            kapacitet: r.kapacitetMax,
            procenat: procenat,
            ispodAlarma: r.ispodAlarma,
          ),
          const SizedBox(height: 16),
          _V3DetaljiCard(
            children: [
              _gorivoDetaljiRow(
                '🔔 Alarm nivo',
                '${V3FormatUtils.formatGorivo(r.alarmNivo)} L',
                r.ispodAlarma ? Colors.redAccent : Colors.white54,
              ),
              _gorivoDetaljiRow('📦 Kapacitet', '${V3FormatUtils.formatGorivo(r.kapacitetMax)} L', Colors.white70),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── helper ─────────────────────────────────────────────────────────────────

Widget _gorivoDetaljiRow(String label, String value, Color valueColor) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: valueColor, fontSize: 13)),
      ],
    ),
  );
}

// ─── Kartice ────────────────────────────────────────────────────────────────

class _V3BrojcanikCard extends StatelessWidget {
  const _V3BrojcanikCard({
    required this.label,
    required this.trenutno,
    required this.kapacitet,
    required this.procenat,
    required this.ispodAlarma,
  });

  final String label;
  final double trenutno;
  final double kapacitet;
  final double procenat;
  final bool ispodAlarma;

  static const Color _accent = Color(0xFFFF9800);

  @override
  Widget build(BuildContext context) {
    final Color barColor = ispodAlarma
        ? Colors.red
        : procenat > 0.6
            ? Colors.green
            : Colors.orange;

    return V3ContainerUtils.styledContainer(
      backgroundColor: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: barColor.withValues(alpha: 0.5), width: 2),
      boxShadow: [
        BoxShadow(color: barColor.withValues(alpha: 0.15), blurRadius: 16, spreadRadius: 1),
      ],
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                ),
                if (ispodAlarma)
                  V3ContainerUtils.iconContainer(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    backgroundColor: Colors.red.withValues(alpha: 0.15),
                    borderRadiusGeometry: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red),
                    child: const Text(
                      '⚠️ MALO GORIVA',
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              '${V3FormatUtils.formatGorivo(trenutno)} L',
              style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: barColor),
            ),
            Text(
              'od ${V3FormatUtils.formatGorivo(kapacitet)} L kapaciteta',
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: procenat,
                minHeight: 24,
                backgroundColor: Colors.grey.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('0 L', style: TextStyle(color: Colors.white38, fontSize: 12)),
                Text(
                  '${(procenat * 100).toStringAsFixed(0)}%',
                  style: TextStyle(fontWeight: FontWeight.bold, color: barColor),
                ),
                Text(
                  '${V3FormatUtils.formatGorivo(kapacitet)} L',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _V3DetaljiCard extends StatelessWidget {
  const _V3DetaljiCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return V3ContainerUtils.styledContainer(
      backgroundColor: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Theme.of(context).glassBorder),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📊 Detalji',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

// ─── Data holder ─────────────────────────────────────────────────────────────

class _GorivoData {
  final V3PumpaStanje? stanje;
  final V3PumpaRezervoar? rezervoar;
  _GorivoData({required this.stanje, required this.rezervoar});
}
