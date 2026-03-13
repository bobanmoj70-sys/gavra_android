import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:gavra_android/models/v3_gorivo.dart';
import 'package:gavra_android/services/v3/v3_gorivo_service.dart';
import 'package:gavra_android/services/realtime/v3_master_realtime_manager.dart';
import 'package:gavra_android/utils/v2_app_snack_bar.dart';

class V2GorivoScreen extends StatefulWidget {
  const V2GorivoScreen({super.key});

  @override
  State<V2GorivoScreen> createState() => _V2GorivoScreenState();
}

class _V2GorivoScreenState extends State<V2GorivoScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _fmt = NumberFormat('#,##0.0', 'sr');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⛽ V3 Gorivo'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'STANJE', icon: Icon(Icons.storage)),
            Tab(text: 'PUNJENJA', icon: Icon(Icons.local_shipping)),
            Tab(text: 'TOČENJA', icon: Icon(Icons.ev_station)),
          ],
        ),
      ),
      body: StreamBuilder(
        stream: V3MasterRealtimeManager.instance.v3StreamFromCache(
          tables: ['v3_gorivo_stanje', 'v3_gorivo_punjenja', 'v3_gorivo_tocenja'],
          build: () => _GorivoData(
            stanje: V3GorivoService.getStanjeSync(),
            punjenja: V3GorivoService.getPunjenjaSync(),
            tocenja: V3GorivoService.getTocenjaSync(),
          ),
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;

          return TabBarView(
            controller: _tabController,
            children: [
              _buildStanjeTab(data.stanje),
              _buildPunjenjaTab(data.punjenja),
              _buildTocenjaTab(data.tocenja),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => _tabController.index == 1 ? _addPunjenje() : _addTocenje(),
      ),
    );
  }

  Widget _buildStanjeTab(V3GorivoStanje stanje) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.local_gas_station, size: 80, color: Colors.blue),
          const SizedBox(height: 16),
          Text('${_fmt.format(stanje.kolicina)} L', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
          const Text('Trenutno stanje na pumpi', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildPunjenjaTab(List<V3PumpaPunjenje> punjenja) {
    return ListView.builder(
      itemCount: punjenja.length,
      itemBuilder: (context, i) {
        final p = punjenja[i];
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.add)),
          title: Text('${_fmt.format(p.kolicina)} L - ${p.dobavljac ?? "Nepoznato"}'),
          subtitle: Text(DateFormat('dd.MM.yyyy HH:mm').format(p.datum)),
        );
      },
    );
  }

  Widget _buildTocenjaTab(List<V3PumpaTocenje> tocenja) {
    return ListView.builder(
      itemCount: tocenja.length,
      itemBuilder: (context, i) {
        final t = tocenja[i];
        return ListTile(
          leading: const CircleAvatar(backgroundColor: Colors.orange, child: Icon(Icons.car_crash, color: Colors.white)),
          title: Text('${_fmt.format(t.kolicina)} L'),
          subtitle: Text('ID Vozila: ${t.voziloId} \n${DateFormat('dd.MM.yyyy HH:mm').format(t.datum)}'),
        );
      },
    );
  }

  Future<void> _addPunjenje() async {
    // Implementacija dijaloga za dodavanje punjenja (skraćeno za demo)
    try {
      await V3GorivoService.addPunjenje(100.0, 'Petrol', 'Dopuna rezervoara');
      if (mounted) V2AppSnackBar.success(context, '✅ Punjenje dodato');
    } catch (e) {
      if (mounted) V2AppSnackBar.error(context, '❌ Greška: $e');
    }
  }

  Future<void> _addTocenje() async {
     // Implementacija dijaloga za tocenje
  }
}

class _GorivoData {
  final V3GorivoStanje stanje;
  final List<V3PumpaPunjenje> punjenja;
  final List<V3PumpaTocenje> tocenja;
  _GorivoData({required this.stanje, required this.punjenja, required this.tocenja});
}
