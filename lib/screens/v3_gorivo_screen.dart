import 'package:flutter/material.dart';
import 'package:gavra_android/models/v3_gorivo.dart';
import 'package:gavra_android/services/realtime/v3_master_realtime_manager.dart';
import 'package:gavra_android/services/v3/v3_gorivo_service.dart';
import 'package:intl/intl.dart';

class V3GorivoScreen extends StatefulWidget {
  const V3GorivoScreen({super.key});

  @override
  State<V3GorivoScreen> createState() => _V3GorivoScreenState();
}

class _V3GorivoScreenState extends State<V3GorivoScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _fmt = NumberFormat('#,##0.0', 'sr');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⛽ V3 Gorivo'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'PUMPA', icon: Icon(Icons.storage)),
            Tab(text: 'REZERVOAR', icon: Icon(Icons.water)),
          ],
        ),
      ),
      body: StreamBuilder(
        stream: V3MasterRealtimeManager.instance.v3StreamFromCache(
          tables: ['v3_pumpa_stanje', 'v3_pumpa_rezervoar'],
          build: () => _GorivoData(
            stanje: V3GorivoService.getStanjeSync(),
            rezervoar: V3GorivoService.getRezervoarSync(),
          ),
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;

          return TabBarView(
            controller: _tabController,
            children: [
              _buildStanjeTab(data.stanje),
              _buildRezervoarTab(data.rezervoar),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStanjeTab(V3PumpaStanje? stanje) {
    if (stanje == null) {
      return const Center(child: Text('Nema podataka o pumpi'));
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.local_gas_station, size: 80, color: Colors.blue),
          const SizedBox(height: 16),
          Text('${_fmt.format(stanje.trenutnoStanje)} L',
              style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
          const Text('Trenutno stanje pumpe', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          Text('Kapacitet: ${_fmt.format(stanje.kapacitetLitri)} L', style: const TextStyle(color: Colors.grey)),
          Text('Brojač pištolja: ${_fmt.format(stanje.stanjeBrojacPistolj)} L',
              style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildRezervoarTab(V3PumpaRezervoar? r) {
    if (r == null) {
      return const Center(child: Text('Nema podataka o rezervoaru'));
    }
    final boja = r.ispodAlarma ? Colors.red : Colors.green;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.water_drop, size: 80, color: boja),
          const SizedBox(height: 16),
          Text('${_fmt.format(r.trenutnoLitara)} L',
              style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: boja)),
          Text('od ${_fmt.format(r.kapacitetMax)} L kapaciteta', style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          Text('${r.procentPunjenosti.toStringAsFixed(1)}% pune', style: const TextStyle(fontSize: 18)),
          if (r.ispodAlarma)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('⚠️ ISPOD ALARMA!', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }
}

class _GorivoData {
  final V3PumpaStanje? stanje;
  final V3PumpaRezervoar? rezervoar;
  _GorivoData({required this.stanje, required this.rezervoar});
}
