import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gavra_android/services/realtime/v3_master_realtime_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/v3_theme_manager.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_container_utils.dart';

class V3AiZnanjeScreen extends StatefulWidget {
  const V3AiZnanjeScreen({super.key});

  @override
  State<V3AiZnanjeScreen> createState() => _V3AiZnanjeScreenState();
}

class _V3AiZnanjeScreenState extends State<V3AiZnanjeScreen> {
  final supabase = Supabase.instance.client;
  List<dynamic> _znanje = [];
  bool _loading = true;
  String? _error;
  Timer? _autoUciTimer;
  bool _autoUcenjeEnabled = false;
  bool _isLoadingZnanje = false;
  DateTime? _lastZnanjeLoad;

  @override
  void initState() {
    super.initState();
    _loadZnanje();
  }

  @override
  void dispose() {
    _autoUciTimer?.cancel();
    super.dispose();
  }

  void _toggleAutoUcenje() {
    setState(() {
      _autoUcenjeEnabled = !_autoUcenjeEnabled;
    });
    if (_autoUcenjeEnabled) {
      _startAutoUcenje();
      V3AppSnackBar.success(context, 'Auto-učenje uključeno (svakih 5 min)');
    } else {
      _stopAutoUcenje();
      V3AppSnackBar.info(context, 'Auto-učenje isključeno');
    }
  }

  void _startAutoUcenje() {
    _autoUciTimer?.cancel();
    _autoUciTimer = Timer.periodic(const Duration(minutes: 5), (_) => _uci());
  }

  void _stopAutoUcenje() {
    _autoUciTimer?.cancel();
    _autoUciTimer = null;
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

  Future<void> _uci() async {
    setState(() => _loading = true);
    try {
      final response = await supabase.functions.invoke(
        'v3-ai-uci',
        body: {'action': 'ucisve'},
      );

      final data = response.data as Map<String, dynamic>?;
      final msg = data?['message'] as String? ?? 'Ucenje zavrseno';
      V3AppSnackBar.success(context, msg);
      await _loadZnanje();
    } catch (e) {
      V3AppSnackBar.error(context, 'Greska pri ucenju: $e');
      setState(() => _loading = false);
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
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: _loadZnanje,
                  tooltip: 'Osvezi',
                ),
                IconButton(
                  icon: Icon(
                    _autoUcenjeEnabled ? Icons.auto_mode : Icons.auto_mode_outlined,
                    color: _autoUcenjeEnabled ? Colors.greenAccent : Colors.white,
                  ),
                  onPressed: _toggleAutoUcenje,
                  tooltip: _autoUcenjeEnabled ? 'Auto-učenje aktivno' : 'Uključi auto-učenje',
                ),
                IconButton(
                  icon: const Icon(Icons.psychology, color: Colors.white),
                  onPressed: _uci,
                  tooltip: 'Nauci sve',
                ),
              ],
            ),
            body: _buildBody(),
          ),
        );
      },
    );
  }

  Widget _buildBody() {
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'AI jos nema nikakvo znanje.',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _uci,
              icon: const Icon(Icons.psychology),
              label: const Text('Nauci iz baze'),
            ),
          ],
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
