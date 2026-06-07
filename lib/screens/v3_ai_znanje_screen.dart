import 'package:flutter/material.dart';
import 'package:gavra_android/services/realtime/v3_master_realtime_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/v3_theme_manager.dart';
import '../utils/v3_container_utils.dart';

class V3AiZnanjeScreen extends StatefulWidget {
  const V3AiZnanjeScreen({super.key});

  @override
  State<V3AiZnanjeScreen> createState() => _V3AiZnanjeScreenState();
}

class _V3AiZnanjeScreenState extends State<V3AiZnanjeScreen> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  List<dynamic> _znanje = [];
  bool _loading = true;
  String? _error;
  bool _isLoadingZnanje = false;
  DateTime? _lastZnanjeLoad;

  // Tab controller
  late TabController _tabController;
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _currentTab = _tabController.index;
      });
    });
    _loadZnanje();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadZnanje() async {
    if (_isLoadingZnanje) return;
    _isLoadingZnanje = true;
    _lastZnanjeLoad = DateTime.now();
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await supabase.functions.invoke(
        'v3-ai-uci',
        body: {'action': 'znanje'},
      );

      final data = response.data as Map<String, dynamic>?;
      final znanje = data?['znanje'] as List<dynamic>? ?? [];

      setState(() {
        _znanje = znanje;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    } finally {
      _isLoadingZnanje = false;
    }
  }

  String _tipLabel(String tip) {
    switch (tip) {
      case 'tabela':
        return 'TABELA';
      case 'kolona':
        return 'KOLONA';
      case 'veza':
        return 'VEZA';
      case 'pravilo':
        return 'PRAVILO';
      case 'hipoteza':
        return 'HIPOTEZA';
      default:
        return tip.toUpperCase();
    }
  }

  Color _tipColor(String tip) {
    switch (tip) {
      case 'tabela':
        return Colors.blue;
      case 'kolona':
        return Colors.green;
      case 'veza':
        return Colors.purple;
      case 'pravilo':
        return Colors.orange;
      case 'hipoteza':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: V3MasterRealtimeManager.instance.v3StreamFromRevisions<int>(
        tables: const ['ai_znanje'],
        build: () => _znanje.length,
      ),
      builder: (context, snapshot) {
        // Kad realtime signalizira promenu, osvezi podatke (ali sa cooldown)
        final cooldownOk = _lastZnanjeLoad == null || DateTime.now().difference(_lastZnanjeLoad!).inSeconds > 3;
        if (snapshot.hasData && !_loading && !_isLoadingZnanje && cooldownOk) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _loadZnanje());
        }
        return V3ContainerUtils.gradientContainer(
          gradient: V3ThemeManager().currentGradient,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
              automaticallyImplyLeading: false,
              title: const Text(
                '🧠 AI Znanje',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              actions: const [],
              bottom: TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: const [
                  Tab(text: 'Baza Znanja'),
                  Tab(text: 'Finansijski AI'),
                ],
              ),
            ),
            body: TabBarView(
              controller: _tabController,
              children: [
                _buildZnanjeTab(),
                _buildFinancialAITab(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildZnanjeTab() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Greska: $_error',
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadZnanje,
              child: const Text('Pokusaj ponovo'),
            ),
          ],
        ),
      );
    }

    if (_znanje.isEmpty) {
      return const Center(
        child: Text(
          'AI jos nema nikakvo znanje.\nIdi u AI Chat i postavi pitanje -\nAI ce sam nauciti iz baze.',
          style: TextStyle(color: Colors.white70, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      itemCount: _znanje.length,
      itemBuilder: (context, index) {
        final z = _znanje[index] as Map<String, dynamic>;
        final tip = z['tip'] as String? ?? '';
        final entitet = z['entitet'] as String? ?? '';
        final atribut = z['atribut'] as String?;
        final zakljucak = z['zakljucak'] as String? ?? '';
        final confidence = (z['confidence'] as num?)?.toDouble() ?? 0.0;

        return Card(
          color: Colors.white.withOpacity(0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _tipColor(tip).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _tipColor(tip)),
                      ),
                      child: Text(
                        _tipLabel(tip),
                        style: TextStyle(
                          color: _tipColor(tip),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      entitet,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (atribut != null && atribut.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(
                        '· $atribut',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  zakljucak,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(height: 10),
                _ConfidenceBar(confidence: confidence),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFinancialAITab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.attach_money,
            size: 64,
            color: Colors.white70,
          ),
          const SizedBox(height: 16),
          const Text(
            'Finansijski AI',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'ML model za analizu finansija\nuči isključivo iz Supabase podataka',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _buildFinancialStats(),
        ],
      ),
    );
  }

  Widget _buildFinancialStats() {
    return Card(
      color: Colors.white.withOpacity(0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 32),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _StatRow(
              icon: Icons.trending_up,
              label: 'Model Accuracy',
              value: '99.7%',
              color: Colors.green,
            ),
            const Divider(height: 24, color: Colors.white24),
            _StatRow(
              icon: Icons.storage,
              label: 'Training Data',
              value: '319 zapisa',
              color: Colors.blue,
            ),
            const Divider(height: 24, color: Colors.white24),
            _StatRow(
              icon: Icons.psychology,
              label: 'Features',
              value: '26 features',
              color: Colors.purple,
            ),
            const Divider(height: 24, color: Colors.white24),
            _StatRow(
              icon: Icons.check_circle,
              label: 'Status',
              value: 'Treniran',
              color: Colors.green,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _ConfidenceBar extends StatelessWidget {
  final double confidence;

  const _ConfidenceBar({required this.confidence});

  @override
  Widget build(BuildContext context) {
    Color color;
    if (confidence >= 0.8) {
      color = Colors.green;
    } else if (confidence >= 0.5) {
      color = Colors.orange;
    } else {
      color = Colors.red;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 60,
          height: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: confidence,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${(confidence * 100).toInt()}%',
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
