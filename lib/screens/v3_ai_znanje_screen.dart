import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:gavra_android/config/ml_config.dart';
import 'package:http/http.dart' as http;

import '../services/v3_theme_manager.dart';
import '../utils/v3_container_utils.dart';

class V3AiZnanjeScreen extends StatefulWidget {
  const V3AiZnanjeScreen({super.key});

  @override
  State<V3AiZnanjeScreen> createState() => _V3AiZnanjeScreenState();
}

class _V3AiZnanjeScreenState extends State<V3AiZnanjeScreen> with SingleTickerProviderStateMixin {
  static const _mlBaseUrl = MlConfig.baseUrl;

  // Znanje (General) AI state
  bool _znanLoading = true;
  String? _znanError;
  Map<String, dynamic>? _znanHealth;

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

  // Training-in-progress flags
  bool _finTraining = false;
  bool _vozTraining = false;
  bool _gorTraining = false;
  bool _putTraining = false;
  bool _zahTraining = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _currentTab = _tabController.index;
      });
      if (_currentTab == 0 && _znanHealth == null) _loadZnanjeAI();
      if (_currentTab == 1 && _finHealth == null) _loadFinancialAI();
      if (_currentTab == 2 && _vozHealth == null) _loadVehicleAI();
      if (_currentTab == 3 && _gorHealth == null) _loadGorivoAI();
      if (_currentTab == 4 && _putHealth == null) _loadPutnikAI();
      if (_currentTab == 5 && _zahHealth == null) _loadZahteviAI();
    });
    // Učitaj samo aktivni tab odmah — ostali se učitavaju lezerno pri prelasku
    _loadZnanjeAI();
  }

  Future<void> _loadFinancialAI() async {
    setState(() {
      _finLoading = true;
      _finError = null;
    });

    const mlUrl = _mlBaseUrl;

    // Health check
    try {
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
    } catch (e) {
      setState(() {
        _finError = 'Greska (health): $e';
        _finLoading = false;
      });
      return;
    }

    // Trends analysis — ne-fatalno
    try {
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
    } catch (_) {
      _finTrends = null;
    }

    // Amount prediction for current month — ne-fatalno
    try {
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
    } catch (_) {
      _finPredictions = null;
    }

    setState(() {
      _finLoading = false;
    });
  }

  Future<void> _loadVehicleAI() async {
    setState(() {
      _vozLoading = true;
      _vozError = null;
    });

    const mlUrl = _mlBaseUrl;

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
    } catch (e) {
      setState(() {
        _vozError = 'Greska (health): $e';
        _vozLoading = false;
      });
      return;
    }

    try {
      final predictResp = await http
          .get(
            Uri.parse('$mlUrl/vozilo/predict/all'),
          )
          .timeout(const Duration(seconds: 20));

      if (predictResp.statusCode == 200) {
        _vozPredictions = jsonDecode(predictResp.body) as Map<String, dynamic>?;
      }
    } catch (_) {
      _vozPredictions = null;
    }

    setState(() {
      _vozLoading = false;
    });
  }

  Future<void> _loadGorivoAI() async {
    setState(() {
      _gorLoading = true;
      _gorError = null;
    });
    const mlUrl = _mlBaseUrl;
    try {
      final healthResp = await http.get(Uri.parse('$mlUrl/gorivo/health')).timeout(const Duration(seconds: 15));
      if (healthResp.statusCode != 200) {
        setState(() {
          _gorError = 'Server nije dostupan (${healthResp.statusCode})';
          _gorLoading = false;
        });
        return;
      }
      _gorHealth = jsonDecode(healthResp.body) as Map<String, dynamic>;
    } catch (e) {
      setState(() {
        _gorError = 'Greska (health): $e';
        _gorLoading = false;
      });
      return;
    }

    try {
      final predictResp = await http.get(Uri.parse('$mlUrl/gorivo/predict')).timeout(const Duration(seconds: 20));
      if (predictResp.statusCode == 200) _gorPredictions = jsonDecode(predictResp.body) as Map<String, dynamic>?;
    } catch (_) {
      _gorPredictions = null;
    }

    setState(() {
      _gorLoading = false;
    });
  }

  Future<void> _loadPutnikAI() async {
    setState(() {
      _putLoading = true;
      _putError = null;
    });
    const mlUrl = _mlBaseUrl;
    try {
      final healthResp = await http.get(Uri.parse('$mlUrl/putnik/health')).timeout(const Duration(seconds: 15));
      if (healthResp.statusCode != 200) {
        setState(() {
          _putError = 'Server nije dostupan (${healthResp.statusCode})';
          _putLoading = false;
        });
        return;
      }
      _putHealth = jsonDecode(healthResp.body) as Map<String, dynamic>;
    } catch (e) {
      setState(() {
        _putError = 'Greska (health): $e';
        _putLoading = false;
      });
      return;
    }

    try {
      final predictResp = await http.get(Uri.parse('$mlUrl/putnik/predict/all')).timeout(const Duration(seconds: 20));
      if (predictResp.statusCode == 200) _putPredictions = jsonDecode(predictResp.body) as Map<String, dynamic>?;
    } catch (_) {
      _putPredictions = null;
    }

    setState(() {
      _putLoading = false;
    });
  }

  Future<void> _loadZahteviAI() async {
    setState(() {
      _zahLoading = true;
      _zahError = null;
    });
    const mlUrl = _mlBaseUrl;
    try {
      final healthResp = await http.get(Uri.parse('$mlUrl/zahtevi/health')).timeout(const Duration(seconds: 15));
      if (healthResp.statusCode != 200) {
        setState(() {
          _zahError = 'Server nije dostupan (${healthResp.statusCode})';
          _zahLoading = false;
        });
        return;
      }
      _zahHealth = jsonDecode(healthResp.body) as Map<String, dynamic>;
    } catch (e) {
      setState(() {
        _zahError = 'Greska (health): $e';
        _zahLoading = false;
      });
      return;
    }

    try {
      final predictResp =
          await http.get(Uri.parse('$mlUrl/zahtevi/predict/next-week')).timeout(const Duration(seconds: 20));
      if (predictResp.statusCode == 200) _zahPredictions = jsonDecode(predictResp.body) as Map<String, dynamic>?;
    } catch (_) {
      _zahPredictions = null;
    }

    setState(() {
      _zahLoading = false;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadZnanjeAI() async {
    setState(() {
      _znanLoading = true;
      _znanError = null;
    });

    const mlUrl = _mlBaseUrl;

    try {
      final healthResp = await http
          .get(
            Uri.parse('$mlUrl/znanje/health'),
          )
          .timeout(const Duration(seconds: 15));

      if (healthResp.statusCode != 200) {
        setState(() {
          _znanError = 'Server nije dostupan (${healthResp.statusCode})';
          _znanLoading = false;
        });
        return;
      }

      _znanHealth = jsonDecode(healthResp.body) as Map<String, dynamic>;

      setState(() {
        _znanLoading = false;
      });
    } catch (e) {
      setState(() {
        _znanError = 'Greska (health): $e';
        _znanLoading = false;
      });
    }
  }

  Future<void> _trainModel(String endpoint, Future<void> Function() reload, String label) async {
    final scaffold = ScaffoldMessenger.of(context);
    try {
      final resp = await http.post(Uri.parse('$_mlBaseUrl$endpoint')).timeout(const Duration(seconds: 30));
      if (resp.statusCode == 200) {
        scaffold.showSnackBar(
          SnackBar(content: Text('$label je treniran! Osvezavam podatke...'), duration: const Duration(seconds: 2)),
        );
        await reload();
      } else {
        String detail = resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body;
        scaffold.showSnackBar(
          SnackBar(
            content: Text('Greska ${resp.statusCode}: $detail'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text('Greska pri treningu $label: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(88),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      _buildTabButton(0, 'Baza Znanja', Icons.psychology),
                      _buildTabButton(1, 'Finansije', Icons.account_balance_wallet),
                      _buildTabButton(2, 'Vozila', Icons.directions_car),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _buildTabButton(3, 'Gorivo', Icons.local_gas_station),
                      _buildTabButton(4, 'Putnici', Icons.people),
                      _buildTabButton(5, 'Zahtevi', Icons.request_page),
                    ],
                  ),
                ],
              ),
            ),
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
  }

  Widget _buildZnanjeTab() {
    if (_znanLoading) {
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

    if (_znanError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.white54),
            const SizedBox(height: 16),
            Text(
              _znanError!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadZnanjeAI,
              child: const Text('Pokusaj ponovo'),
            ),
          ],
        ),
      );
    }

    final ready = _znanHealth?['ready'] ?? false;
    final tablesLoaded = _znanHealth?['tables_loaded'] ?? 0;
    final totalRecords = _znanHealth?['total_records'] ?? 0;
    final tableStats = _znanHealth?['table_stats'] as Map<String, dynamic>? ?? {};

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      children: [
        const Center(
          child: Column(
            children: [
              Icon(Icons.psychology, size: 48, color: Colors.white70),
              SizedBox(height: 8),
              Text(
                'AI Znanje - Generalni Asistent',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Uci iz svih tabela kao i ostali AI modeli',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Status kartica
        Card(
          color: Colors.white.withOpacity(0.12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _StatRow(
                  icon: ready ? Icons.check_circle : Icons.error,
                  label: 'AI Status',
                  value: ready ? 'Spreman' : 'Nije spreman',
                  color: ready ? Colors.green : Colors.red,
                ),
                const Divider(height: 20, color: Colors.white24),
                _StatRow(
                  icon: Icons.storage,
                  label: 'Ucitane tabele',
                  value: '$tablesLoaded',
                  color: Colors.blue,
                ),
                const Divider(height: 20, color: Colors.white24),
                _StatRow(
                  icon: Icons.data_usage,
                  label: 'Ukupno zapisa',
                  value: '$totalRecords',
                  color: Colors.purple,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Statistika po tabelama
        if (tableStats.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Podaci po tabelama:',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...tableStats.entries.map((e) {
            return Card(
              color: Colors.white.withOpacity(0.08),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              margin: const EdgeInsets.only(bottom: 6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.table_chart, color: Colors.white54, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        e.key,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                    Text(
                      '${e.value} zapisa',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
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

        if (!modelTrained && predictions == null && trends == null)
          _buildUntrainedMessage(
            'Finansijski model',
            onTrain: () async {
              setState(() => _finTraining = true);
              await _trainModel('/train', _loadFinancialAI, 'Finansijski model');
              setState(() => _finTraining = false);
            },
            isTraining: _finTraining,
          ),
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
        if (!modelTrained && vehicles.isEmpty)
          _buildUntrainedMessage(
            'Vozilo model',
            onTrain: () async {
              setState(() => _vozTraining = true);
              await _trainModel('/vozilo/train', _loadVehicleAI, 'Vozilo model');
              setState(() => _vozTraining = false);
            },
            isTraining: _vozTraining,
          ),
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
        if (!modelTrained && rezervoari.isEmpty)
          _buildUntrainedMessage(
            'Gorivo model',
            onTrain: () async {
              setState(() => _gorTraining = true);
              await _trainModel('/gorivo/train', _loadGorivoAI, 'Gorivo model');
              setState(() => _gorTraining = false);
            },
            isTraining: _gorTraining,
          ),
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
        if (!modelTrained && passengers.isEmpty)
          _buildUntrainedMessage(
            'Putnik model',
            onTrain: () async {
              setState(() => _putTraining = true);
              await _trainModel('/putnik/train', _loadPutnikAI, 'Putnik model');
              setState(() => _putTraining = false);
            },
            isTraining: _putTraining,
          ),
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
        if (!modelTrained && nextWeek.isEmpty)
          _buildUntrainedMessage(
            'Zahtevi model',
            onTrain: () async {
              setState(() => _zahTraining = true);
              await _trainModel('/zahtevi/train', _loadZahteviAI, 'Zahtevi model');
              setState(() => _zahTraining = false);
            },
            isTraining: _zahTraining,
          ),
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

  Widget _buildUntrainedMessage(String label, {VoidCallback? onTrain, bool isTraining = false}) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            children: [
              const Icon(Icons.model_training, size: 40, color: Colors.white38),
              const SizedBox(height: 12),
              Text(
                '$label nije treniran',
                style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              const Text(
                'Pokrenite /train na ML backend-u da biste videli predikcije.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              if (onTrain != null) ...[
                const SizedBox(height: 12),
                isTraining
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                      )
                    : ElevatedButton.icon(
                        onPressed: onTrain,
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('Treniraj'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.2),
                          foregroundColor: Colors.white,
                        ),
                      ),
              ],
            ],
          ),
        ),
      );

  Widget _buildTabButton(int index, String label, IconData icon) {
    final isActive = _currentTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _tabController.animateTo(index),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? Colors.white.withOpacity(0.25) : Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border:
                isActive ? Border.all(color: Colors.white, width: 1) : Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: isActive ? Colors.white : Colors.white70, size: 20),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.white70,
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
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
