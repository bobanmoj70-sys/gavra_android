import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/ml_config.dart';

/// Ekran koji prikazuje stanje prave neuronske mreže (autoenkoder, ručni
/// backpropagation) koja uči od nule iz svih tabela baze, bez ijedne
/// poslovne pretpostavke. Prikazuje po tabeli: broj naučenih redova,
/// prosečnu grešku rekonstrukcije, i listu poslednjih uočenih anomalija
/// (neobičnih kombinacija vrednosti u redu), kao i ŽIVI tok "razmišljanja"
/// mreže o svakom redu koji trenutno obrađuje.
class V3NeuralMozakScreen extends StatefulWidget {
  const V3NeuralMozakScreen({super.key});

  @override
  State<V3NeuralMozakScreen> createState() => _V3NeuralMozakScreenState();
}

class _V3NeuralMozakScreenState extends State<V3NeuralMozakScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _report;

  List<Map<String, dynamic>> _thoughts = [];
  String? _thoughtsError;
  Timer? _thoughtsTimer;

  Map<String, dynamic>? _relationsReport;
  List<Map<String, dynamic>> _liveRelations = [];
  String? _relationsError;
  Timer? _relationsTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchReport();
    _fetchThoughts();
    _fetchRelations();
    _thoughtsTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchThoughts());
    _relationsTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchRelations());
  }

  @override
  void dispose() {
    _thoughtsTimer?.cancel();
    _relationsTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchReport() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await http
          .get(
            Uri.parse('${MlConfig.baseUrl}/neural'),
            headers: MlConfig.headers(),
          )
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        setState(() {
          _report = data;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Server je vratio grešku: ${resp.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Neuspešno povezivanje sa AI serverom: $e';
        _loading = false;
      });
    }
  }

  Future<void> _fetchThoughts() async {
    try {
      final resp = await http
          .get(
            Uri.parse('${MlConfig.baseUrl}/neural/thoughts'),
            headers: MlConfig.headers(),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        setState(() {
          _thoughts = (data['thoughts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          _thoughtsError = null;
        });
      } else if (mounted) {
        setState(() => _thoughtsError = 'Server je vratio grešku: ${resp.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _thoughtsError = 'Neuspešno povezivanje: $e');
      }
    }
  }

  Future<void> _fetchRelations() async {
    try {
      final reportResp = await http
          .get(Uri.parse('${MlConfig.baseUrl}/neural/relations'), headers: MlConfig.headers())
          .timeout(const Duration(seconds: 15));
      final liveResp = await http
          .get(Uri.parse('${MlConfig.baseUrl}/neural/relations/live'), headers: MlConfig.headers())
          .timeout(const Duration(seconds: 15));

      if (reportResp.statusCode == 200 && liveResp.statusCode == 200 && mounted) {
        final reportData = jsonDecode(utf8.decode(reportResp.bodyBytes)) as Map<String, dynamic>;
        final liveData = jsonDecode(utf8.decode(liveResp.bodyBytes)) as Map<String, dynamic>;
        setState(() {
          _relationsReport = reportData;
          _liveRelations = (liveData['relations'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          _relationsError = null;
        });
      } else if (mounted) {
        setState(() => _relationsError = 'Server je vratio grešku.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _relationsError = 'Neuspešno povezivanje: $e');
      }
    }
  }

  Future<void> _resetBrain() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resetuj neuronsku mrežu?'),
        content: const Text(
          'Ovo briše SVE naučene težine i statistiku. Mreža počinje ponovo od nule '
          '(nasumična inicijalizacija). Ova akcija je nepovratna.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Otkaži')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Resetuj', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final resp = await http
          .post(Uri.parse('${MlConfig.baseUrl}/neural/reset'), headers: MlConfig.headers())
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🧠 Neuronska mreža je resetovana.')),
        );
        _fetchReport();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Greška pri resetu: $e')),
        );
      }
    }
  }

  Future<void> _triggerResync() async {
    try {
      final resp = await http
          .post(Uri.parse('${MlConfig.baseUrl}/resync'), headers: MlConfig.headers())
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🔄 Ponovno učenje pokrenuto u pozadini.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Greška: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🧠 Neuronska mreža'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          isScrollable: true,
          tabs: const [
            Tab(text: '📊 Pregled'),
            Tab(text: '💭 Živa razmišljanja'),
            Tab(text: '🔗 Otkrivene veze'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Osveži',
            onPressed: () {
              _fetchReport();
              _fetchThoughts();
              _fetchRelations();
            },
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Pokreni ponovno učenje',
            onPressed: _triggerResync,
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: 'Resetuj mrežu',
            onPressed: _resetBrain,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBody(),
          _buildThoughtsTab(),
          _buildRelationsTab(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _fetchReport, child: const Text('Pokušaj ponovo')),
            ],
          ),
        ),
      );
    }

    final report = _report ?? {};
    final architecture = report['architecture'] as String? ?? '';
    final tables = (report['tables'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final anomalies = (report['recent_anomalies'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return RefreshIndicator(
      onRefresh: _fetchReport,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: Colors.deepPurple.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Arhitektura',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(architecture, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '📊 Tabele koje mreža uči (${tables.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          if (tables.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Mreža još nije naučila nijednu tabelu.'),
            )
          else
            ...tables.map(_buildTableTile),
          const SizedBox(height: 20),
          Text(
            '⚠️ Poslednje uočene anomalije (${anomalies.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          if (anomalies.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Nema uočenih anomalija.'),
            )
          else
            ...anomalies.map(_buildAnomalyTile),
        ],
      ),
    );
  }

  Widget _buildTableTile(Map<String, dynamic> table) {
    final ready = table['ready_for_anomaly_detection'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          ready ? Icons.check_circle : Icons.hourglass_bottom,
          color: ready ? Colors.green : Colors.orange,
        ),
        title: Text(
          table['table']?.toString() ?? '',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Naučeno redova: ${table['observations']}  •  '
          'Prosečna greška: ${table['avg_reconstruction_error']}\n'
          'Poslednje ažurirano: ${table['updated_at'] ?? '-'}',
        ),
        isThreeLine: true,
      ),
    );
  }

  Widget _buildAnomalyTile(Map<String, dynamic> anomaly) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${anomaly['table']}  (id: ${anomaly['source_id'] ?? '-'})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                Text(
                  'z=${(anomaly['z_score'] as num?)?.toStringAsFixed(1) ?? '-'}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(anomaly['detail']?.toString() ?? '', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              anomaly['created_at']?.toString() ?? '',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThoughtsTab() {
    if (_thoughtsError != null && _thoughts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(_thoughtsError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _fetchThoughts, child: const Text('Pokušaj ponovo')),
            ],
          ),
        ),
      );
    }

    if (_thoughts.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Mreža još nije obradila nijedan red. Čim stigne novi podatak iz baze, ovde će '
            'se prikazati šta mreža o njemu "misli" u realnom vremenu.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchThoughts,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _thoughts.length,
        itemBuilder: (ctx, i) => _buildThoughtTile(_thoughts[i]),
      ),
    );
  }

  Color _stageColor(String? stage) {
    switch (stage) {
      case 'anomalija':
        return Colors.red;
      case 'neuobicajeno':
        return Colors.orange;
      case 'normalno':
        return Colors.blue;
      case 'vrlo_poznato':
        return Colors.green;
      case 'uci':
      default:
        return Colors.grey;
    }
  }

  Widget _buildThoughtTile(Map<String, dynamic> thought) {
    final stage = thought['stage']?.toString();
    final color = _stageColor(stage);
    final z = thought['z_score'];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${thought['table']}  (id: ${thought['source_id'] ?? '-'})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                if (z != null)
                  Text(
                    'z=${(z as num).toStringAsFixed(1)}',
                    style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 12),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              thought['thought']?.toString() ?? '',
              style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(thought['detail']?.toString() ?? '', style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 4),
            Text(
              'Viđeno redova ove tabele do sad: ${thought['observations_seen'] ?? '-'}',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRelationsTab() {
    if (_relationsError != null && _relationsReport == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(_relationsError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _fetchRelations, child: const Text('Pokušaj ponovo')),
            ],
          ),
        ),
      );
    }

    final report = _relationsReport ?? {};
    final method = report['method'] as String? ?? '';
    final embedDim = report['embedding_dim'];
    final tables = (report['tables'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return RefreshIndicator(
      onRefresh: _fetchRelations,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: Colors.teal.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Metoda', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(method, style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('Dimenzija vektora: $embedDim', style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '💭 Trenutno obrađuje (${_liveRelations.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          if (_liveRelations.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Čeka se novi red...'),
            )
          else
            ..._liveRelations.map(_buildLiveRelationTile),
          const SizedBox(height: 20),
          Text(
            '📚 Naučeno po tabeli (${tables.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          if (tables.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Mreža još nije naučila nijednu vezu.'),
            )
          else
            ...tables.map(_buildRelationsTableTile),
        ],
      ),
    );
  }

  Widget _buildLiveRelationTile(Map<String, dynamic> relation) {
    final predictions = (relation['predictions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.teal.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${relation['table']}  (id: ${relation['source_id'] ?? '-'})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Prepoznato ${relation['tokens_seen']} vrednosti u redu • Ukupan rečnik tabele: ${relation['vocab_size']}',
              style: const TextStyle(fontSize: 11),
            ),
            if (predictions.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Predikcije (iz konteksta ostatka reda):',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              ...predictions.map((p) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '  ${p['column']}: predviđeno ${p['predicted']}, stvarno ${p['actual']} '
                      '(nakon ${p['confidence_samples']} primera)',
                      style: const TextStyle(fontSize: 11),
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRelationsTableTile(Map<String, dynamic> table) {
    final topTokens = (table['top_tokens'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final predictors = (table['numeric_predictors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              table['table']?.toString() ?? '',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'Rečnik: ${table['vocab_size']} različitih vrednosti • Ukupno posmatranja: ${table['total_observations']}',
              style: const TextStyle(fontSize: 11),
            ),
            if (topTokens.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Najčešće vrednosti:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: topTokens
                    .map((t) => Chip(
                          label: Text('${t['token']} (${t['count']})', style: const TextStyle(fontSize: 10)),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ))
                    .toList(),
              ),
            ],
            if (predictors.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Predviđa se: ${predictors.map((p) => '${p['column']} (${p['trained_on']}x)').join(', ')}',
                style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
