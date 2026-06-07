import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:gavra_android/services/realtime/v3_master_realtime_manager.dart';
import 'package:http/http.dart' as http;
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

  // Financial AI state
  bool _finLoading = true;
  String? _finError;
  Map<String, dynamic>? _finHealth;
  Map<String, dynamic>? _finTrends;
  Map<String, dynamic>? _finPredictions;

  // Vehicle AI state
  bool _vozLoading = true;
  String? _vozError;
  Map<String, dynamic>? _vozHealth;
  Map<String, dynamic>? _vozPredictions;

  // Gorivo AI state
  bool _gorLoading = true;
  String? _gorError;
  Map<String, dynamic>? _gorHealth;
  Map<String, dynamic>? _gorPredictions;

  // Putnik AI state
  bool _putLoading = true;
  String? _putError;
  Map<String, dynamic>? _putHealth;
  Map<String, dynamic>? _putPredictions;

  // Zahtevi AI state
  bool _zahLoading = true;
  String? _zahError;
  Map<String, dynamic>? _zahHealth;
  Map<String, dynamic>? _zahPredictions;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _currentTab = _tabController.index;
      });
      if (_currentTab == 1 && _finHealth == null && !_finLoading) _loadFinancialAI();
      if (_currentTab == 2 && _vozHealth == null && !_vozLoading) _loadVehicleAI();
      if (_currentTab == 3 && _gorHealth == null && !_gorLoading) _loadGorivoAI();
      if (_currentTab == 4 && _putHealth == null && !_putLoading) _loadPutnikAI();
      if (_currentTab == 5 && _zahHealth == null && !_zahLoading) _loadZahteviAI();
    });
    _loadZnanje();
    _loadFinancialAI();
    _loadVehicleAI();
    _loadGorivoAI();
    _loadPutnikAI();
    _loadZahteviAI();
  }

  Future<void> _loadFinancialAI() async {
    setState(() {
      _finLoading = true;
      _finError = null;
    });

    const mlUrl = 'https://powered-postcard-breed-donor.trycloudflare.com';

    try {
      // Health check
      final healthResp = await http
          .get(
            Uri.parse('$mlUrl/health'),
          )
          .timeout(const Duration(seconds: 15));

      if (healthResp.statusCode != 200) {
        setState(() {
          _finError = 'Server nije dostupan (${healthResp.statusCode})';
          _finLoading = false;
        });
        return;
      }

      _finHealth = jsonDecode(healthResp.body) as Map<String, dynamic>;

      // Trends analysis
      final trendsResp = await http
          .post(
            Uri.parse('$mlUrl/analyze/trends'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'days_back': 30}),
          )
          .timeout(const Duration(seconds: 20));

      if (trendsResp.statusCode == 200) {
        _finTrends = jsonDecode(trendsResp.body) as Map<String, dynamic>?;
      }

      // Amount prediction for current month
      final now = DateTime.now();
      final predictResp = await http
          .post(
            Uri.parse('$mlUrl/predict/amount'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'month': now.month,
              'year': now.year,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (predictResp.statusCode == 200) {
        _finPredictions = jsonDecode(predictResp.body) as Map<String, dynamic>?;
      }

      setState(() {
        _finLoading = false;
      });
    } catch (e) {
      setState(() {
        _finError = 'Greska: $e';
        _finLoading = false;
      });
    }
  }

  Future<void> _loadVehicleAI() async {
    setState(() {
      _vozLoading = true;
      _vozError = null;
    });

    const mlUrl = 'https://powered-postcard-breed-donor.trycloudflare.com';

    try {
      final healthResp = await http
          .get(
            Uri.parse('$mlUrl/vozilo/health'),
          )
          .timeout(const Duration(seconds: 15));

      if (healthResp.statusCode != 200) {
        setState(() {
          _vozError = 'Server nije dostupan (${healthResp.statusCode})';
          _vozLoading = false;
        });
        return;
      }

      _vozHealth = jsonDecode(healthResp.body) as Map<String, dynamic>;

      final predictResp = await http
          .get(
            Uri.parse('$mlUrl/vozilo/predict/all'),
          )
          .timeout(const Duration(seconds: 20));

      if (predictResp.statusCode == 200) {
        _vozPredictions = jsonDecode(predictResp.body) as Map<String, dynamic>?;
      }

      setState(() {
        _vozLoading = false;
      });
    } catch (e) {
      setState(() {
        _vozError = 'Greska: $e';
        _vozLoading = false;
      });
    }
  }

  Future<void> _loadGorivoAI() async {
    setState(() {
      _gorLoading = true;
      _gorError = null;
    });
    const mlUrl = 'https://powered-postcard-breed-donor.trycloudflare.com';
    try {
      final healthResp = await http.get(Uri.parse('$mlUrl/gorivo/health')).timeout(const Duration(seconds: 15));
      if (healthResp.statusCode != 200) {
        setState(() {
          _gorError = 'Server nije dostupan';
          _gorLoading = false;
        });
        return;
      }
      _gorHealth = jsonDecode(healthResp.body) as Map<String, dynamic>;
      final predictResp = await http.get(Uri.parse('$mlUrl/gorivo/predict')).timeout(const Duration(seconds: 20));
      if (predictResp.statusCode == 200) _gorPredictions = jsonDecode(predictResp.body) as Map<String, dynamic>?;
      setState(() {
        _gorLoading = false;
      });
    } catch (e) {
      setState(() {
        _gorError = 'Greska: $e';
        _gorLoading = false;
      });
    }
  }

  Future<void> _loadPutnikAI() async {
    setState(() {
      _putLoading = true;
      _putError = null;
    });
    const mlUrl = 'https://powered-postcard-breed-donor.trycloudflare.com';
    try {
      final healthResp = await http.get(Uri.parse('$mlUrl/putnik/health')).timeout(const Duration(seconds: 15));
      if (healthResp.statusCode != 200) {
        setState(() {
          _putError = 'Server nije dostupan';
          _putLoading = false;
        });
        return;
      }
      _putHealth = jsonDecode(healthResp.body) as Map<String, dynamic>;
      final predictResp = await http.get(Uri.parse('$mlUrl/putnik/predict/all')).timeout(const Duration(seconds: 20));
      if (predictResp.statusCode == 200) _putPredictions = jsonDecode(predictResp.body) as Map<String, dynamic>?;
      setState(() {
        _putLoading = false;
      });
    } catch (e) {
      setState(() {
        _putError = 'Greska: $e';
        _putLoading = false;
      });
    }
  }

  Future<void> _loadZahteviAI() async {
    setState(() {
      _zahLoading = true;
      _zahError = null;
    });
    const mlUrl = 'https://powered-postcard-breed-donor.trycloudflare.com';
    try {
      final healthResp = await http.get(Uri.parse('$mlUrl/zahtevi/health')).timeout(const Duration(seconds: 15));
      if (healthResp.statusCode != 200) {
        setState(() {
          _zahError = 'Server nije dostupan';
          _zahLoading = false;
        });
        return;
      }
      _zahHealth = jsonDecode(healthResp.body) as Map<String, dynamic>;
      final predictResp =
          await http.get(Uri.parse('$mlUrl/zahtevi/predict/next-week')).timeout(const Duration(seconds: 20));
      if (predictResp.statusCode == 200) _zahPredictions = jsonDecode(predictResp.body) as Map<String, dynamic>?;
      setState(() {
        _zahLoading = false;
      });
    } catch (e) {
      setState(() {
        _zahError = 'Greska: $e';
        _zahLoading = false;
      });
    }
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
                  Tab(text: 'Finansije'),
                  Tab(text: 'Vozila'),
                  Tab(text: 'Gorivo'),
                  Tab(text: 'Putnici'),
                  Tab(text: 'Zahtevi'),
                ],
              ),
            ),
            body: TabBarView(
              controller: _tabController,
              children: [
                _buildZnanjeTab(),
                _buildFinancialAITab(),
                _buildVehicleAITab(),
                _buildGorivoAITab(),
                _buildPutnikAITab(),
                _buildZahteviAITab(),
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
    if (_finLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Povezivanje sa AI serverom...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (_finError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.white54),
            const SizedBox(height: 16),
            Text(
              _finError!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadFinancialAI,
              child: const Text('Pokusaj ponovo'),
            ),
          ],
        ),
      );
    }

    final modelTrained = _finHealth?['model_trained'] ?? false;
    final predictions = _finPredictions?['avg_predicted_amount'];
    final trends = _finTrends?['trends'] as Map<String, dynamic>?;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      children: [
        // Header
        const Center(
          child: Column(
            children: [
              Icon(Icons.attach_money, size: 48, color: Colors.white70),
              SizedBox(height: 8),
              Text(
                'Finansijski AI',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Live predikcije sa tvog servera',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Status
        _buildFinancialStats(modelTrained: modelTrained),
        const SizedBox(height: 16),

        // Prediction
        if (predictions != null) _buildPredictionCard(predictions as double),
        const SizedBox(height: 16),

        // Trends
        if (trends != null) _buildTrendsCard(trends),
      ],
    );
  }

  Widget _buildFinancialStats({required bool modelTrained}) {
    return Card(
      color: Colors.white.withOpacity(0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _StatRow(
              icon: modelTrained ? Icons.check_circle : Icons.error,
              label: 'Model Status',
              value: modelTrained ? 'Treniran' : 'Nije treniran',
              color: modelTrained ? Colors.green : Colors.red,
            ),
            const Divider(height: 20, color: Colors.white24),
            _StatRow(
              icon: Icons.trending_up,
              label: 'Model Accuracy',
              value: '99.7%',
              color: Colors.green,
            ),
            const Divider(height: 20, color: Colors.white24),
            _StatRow(
              icon: Icons.storage,
              label: 'Training Data',
              value: '319 zapisa',
              color: Colors.blue,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPredictionCard(double avgAmount) {
    return Card(
      color: Colors.white.withOpacity(0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up, color: Colors.orange.withOpacity(0.8)),
                const SizedBox(width: 8),
                const Text(
                  'Predikcija za tekuci mesec',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${avgAmount.toStringAsFixed(2)} RSD',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Procenjeni iznos na osnovu prethodnih finansija',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendsCard(Map<String, dynamic> trends) {
    final trendKeys = trends.keys.toList();
    return Card(
      color: Colors.white.withOpacity(0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: Colors.purple.withOpacity(0.8)),
                const SizedBox(width: 8),
                const Text(
                  'Finansijski trendovi',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...trendKeys.take(5).map((key) {
              final val = trends[key];
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        key,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                    Text(
                      val?.toString() ?? '-',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleAITab() {
    if (_vozLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Povezivanje sa AI serverom...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (_vozError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.white54),
            const SizedBox(height: 16),
            Text(
              _vozError!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadVehicleAI,
              child: const Text('Pokusaj ponovo'),
            ),
          ],
        ),
      );
    }

    final modelTrained = _vozHealth?['model_trained'] ?? false;
    final vehicles = (_vozPredictions?['vehicles'] as List<dynamic>?) ?? [];
    final hitno = _vozPredictions?['hitno'] ?? 0;
    final uskoro = _vozPredictions?['uskoro'] ?? 0;
    final ok = _vozPredictions?['ok'] ?? 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      children: [
        const Center(
          child: Column(
            children: [
              Icon(Icons.directions_car, size: 48, color: Colors.white70),
              SizedBox(height: 8),
              Text(
                'Vozilo AI',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Live predikcije odrzavanja',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Summary
        Card(
          color: Colors.white.withOpacity(0.12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _StatRow(
                  icon: modelTrained ? Icons.check_circle : Icons.error,
                  label: 'Model Status',
                  value: modelTrained ? 'Treniran' : 'Nije treniran',
                  color: modelTrained ? Colors.green : Colors.red,
                ),
                const Divider(height: 20, color: Colors.white24),
                _StatRow(
                  icon: Icons.warning,
                  label: 'Hitno servisiranje',
                  value: '$hitno',
                  color: Colors.red,
                ),
                const Divider(height: 20, color: Colors.white24),
                _StatRow(
                  icon: Icons.schedule,
                  label: 'Uskoro servis',
                  value: '$uskoro',
                  color: Colors.orange,
                ),
                const Divider(height: 20, color: Colors.white24),
                _StatRow(
                  icon: Icons.check,
                  label: 'Servis OK',
                  value: '$ok',
                  color: Colors.green,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Vehicle list
        ...vehicles.map((v) {
          final map = v as Map<String, dynamic>;
          final status = map['status'] as String? ?? 'ok';
          final color = switch (status) {
            'hitno' => Colors.red,
            'uskoro' => Colors.orange,
            _ => Colors.green,
          };
          return Card(
            color: Colors.white.withOpacity(0.12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.directions_car, color: color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          map['registracija']?.toString() ?? 'Nepoznato',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Trenutna km: ${map['trenutna_km']?.toString() ?? '-'}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Text(
                    'Km do servisa: ${map['km_do_servisa']?.toString() ?? '-'}',
                    style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildGorivoAITab() {
    if (_gorLoading) return _buildLoading('Gorivo AI');
    if (_gorError != null) return _buildError(_gorError!, _loadGorivoAI);

    final modelTrained = _gorHealth?['model_trained'] ?? false;
    final rezervoari = (_gorPredictions?['rezervoari'] as List<dynamic>?) ?? [];
    final hitno = _gorPredictions?['hitno'] ?? 0;
    final uskoro = _gorPredictions?['uskoro'] ?? 0;
    final ok = _gorPredictions?['ok'] ?? 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      children: [
        _buildHeader(Icons.local_gas_station, 'Gorivo AI', 'Predikcija dopune goriva'),
        const SizedBox(height: 16),
        _buildSummaryCard([
          _StatRow(
              icon: modelTrained ? Icons.check_circle : Icons.error,
              label: 'Model',
              value: modelTrained ? 'Treniran' : 'Nije',
              color: modelTrained ? Colors.green : Colors.red),
          _StatRow(icon: Icons.warning, label: 'Hitno dopuna', value: '$hitno', color: Colors.red),
          _StatRow(icon: Icons.schedule, label: 'Uskoro', value: '$uskoro', color: Colors.orange),
          _StatRow(icon: Icons.check, label: 'OK', value: '$ok', color: Colors.green),
        ]),
        const SizedBox(height: 16),
        ...rezervoari.map((r) {
          final map = r as Map<String, dynamic>;
          final status = map['status'] as String? ?? 'ok';
          final color = switch (status) { 'hitno' => Colors.red, 'uskoro' => Colors.orange, _ => Colors.green };
          return _buildItemCard(
            icon: Icons.local_gas_station,
            title: '${map['nivo_posto']?.toString() ?? '-'}%',
            subtitle: 'Dana do praznog: ${map['dana_do_praznog']?.toString() ?? '-'}',
            status: status.toUpperCase(),
            color: color,
          );
        }),
      ],
    );
  }

  Widget _buildPutnikAITab() {
    if (_putLoading) return _buildLoading('Putnik AI');
    if (_putError != null) return _buildError(_putError!, _loadPutnikAI);

    final modelTrained = _putHealth?['model_trained'] ?? false;
    final passengers = (_putPredictions?['passengers'] as List<dynamic>?) ?? [];
    final lojalan = _putPredictions?['lojalan'] ?? 0;
    final rizican = _putPredictions?['rizican'] ?? 0;
    final prosecan = _putPredictions?['prosecan'] ?? 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      children: [
        _buildHeader(Icons.people, 'Putnik AI', 'Analiza putnika'),
        const SizedBox(height: 16),
        _buildSummaryCard([
          _StatRow(
              icon: modelTrained ? Icons.check_circle : Icons.error,
              label: 'Model',
              value: modelTrained ? 'Treniran' : 'Nije',
              color: modelTrained ? Colors.green : Colors.red),
          _StatRow(icon: Icons.star, label: 'Lojalni', value: '$lojalan', color: Colors.green),
          _StatRow(icon: Icons.warning, label: 'Rizicni', value: '$rizican', color: Colors.red),
          _StatRow(icon: Icons.person, label: 'Prosecni', value: '$prosecan', color: Colors.orange),
        ]),
        const SizedBox(height: 16),
        ...passengers.take(10).map((p) {
          final map = p as Map<String, dynamic>;
          final kat = map['kategorija'] as String? ?? 'prosecan';
          final color = switch (kat) { 'lojalan' => Colors.green, 'rizican' => Colors.red, _ => Colors.orange };
          return _buildItemCard(
            icon: Icons.person,
            title: map['putnik_id']?.toString() ?? 'Nepoznato',
            subtitle: 'Verovatnoca placanja: ${map['verovatnoca_placanja']?.toString() ?? '-'}%',
            status: kat.toUpperCase(),
            color: color,
          );
        }),
      ],
    );
  }

  Widget _buildZahteviAITab() {
    if (_zahLoading) return _buildLoading('Zahtevi AI');
    if (_zahError != null) return _buildError(_zahError!, _loadZahteviAI);

    final modelTrained = _zahHealth?['model_trained'] ?? false;
    final nextWeek = (_zahPredictions?['next_week'] as List<dynamic>?) ?? [];
    final ukupno = _zahPredictions?['ukupno_nedelja']?.toString() ?? '-';

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      children: [
        _buildHeader(Icons.request_page, 'Zahtevi AI', 'Predikcija za narednu nedelju'),
        const SizedBox(height: 16),
        _buildSummaryCard([
          _StatRow(
              icon: modelTrained ? Icons.check_circle : Icons.error,
              label: 'Model',
              value: modelTrained ? 'Treniran' : 'Nije',
              color: modelTrained ? Colors.green : Colors.red),
          _StatRow(icon: Icons.calendar_today, label: 'Ukupno nedelja', value: ukupno, color: Colors.blue),
        ]),
        const SizedBox(height: 16),
        ...nextWeek.map((d) {
          final map = d as Map<String, dynamic>;
          return Card(
            color: Colors.white.withOpacity(0.12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                      child: Text(map['dan']?.toString() ?? '-',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                  Text(map['procenjeni_zahtevi']?.toString() ?? '-', style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildLoading(String text) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text('Povezivanje sa $text...', style: const TextStyle(color: Colors.white70)),
          ],
        ),
      );

  Widget _buildError(String error, VoidCallback onRetry) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.white54),
            const SizedBox(height: 16),
            Text(error, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Pokusaj ponovo')),
          ],
        ),
      );

  Widget _buildHeader(IconData icon, String title, String subtitle) => Center(
        child: Column(
          children: [
            Icon(icon, size: 48, color: Colors.white70),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      );

  Widget _buildSummaryCard(List<Widget> children) => Card(
        color: Colors.white.withOpacity(0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: children),
        ),
      );

  Widget _buildItemCard(
          {required IconData icon,
          required String title,
          required String subtitle,
          required String status,
          required Color color}) =>
      Card(
        color: Colors.white.withOpacity(0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(title,
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: color.withOpacity(0.3), borderRadius: BorderRadius.circular(8)),
                    child: Text(status, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
      );
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
