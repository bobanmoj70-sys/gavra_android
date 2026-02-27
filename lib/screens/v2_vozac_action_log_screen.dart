import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../globals.dart';
import '../models/voznje_log.dart';
import '../services/realtime/v2_master_realtime_manager.dart';
import '../theme.dart';
import '../utils/grad_adresa_validator.dart';
import '../utils/vozac_cache.dart';

/// 📋 DNEVNIK AKCIJA VOZAČA
/// Prikazuje sve akcije vozača za određeni dan
class VozacActionLogScreen extends StatefulWidget {
  final String vozacIme;
  final DateTime datum;

  const VozacActionLogScreen({
    super.key,
    required this.vozacIme,
    required this.datum,
  });

  @override
  State<VozacActionLogScreen> createState() => _VozacActionLogScreenState();
}

class _VozacActionLogScreenState extends State<VozacActionLogScreen> with SingleTickerProviderStateMixin {
  DateTime _selectedDate;
  TabController? _tabController;
  StreamSubscription? _realtimeSubscription;
  final StreamController<List<Map<String, dynamic>>> _logsController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  // Tipovi akcija za tabove
  static const List<String> _actionTypes = [
    'sve',
    'voznja',
    'otkazivanje',
    'uplata',
  ];

  static const Map<String, String> _actionLabels = {
    'sve': '📊 Sve',
    'voznja': '🚗 Voznje',
    'otkazivanje': '❌ Otkazane',
    'uplata': '💰 Uplate',
  };

  _VozacActionLogScreenState() : _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.datum;
    _tabController = TabController(length: _actionTypes.length, vsync: this);
    _startRealtimeListener();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _realtimeSubscription?.cancel();
    _logsController.close();
    V2MasterRealtimeManager.instance.unsubscribe('v2_statistika_istorija');
    super.dispose();
  }

  void _startRealtimeListener() {
    _realtimeSubscription = V2MasterRealtimeManager.instance.subscribe('v2_statistika_istorija').listen((_) {
      _fetchLogs();
    });
    _fetchLogs();
  }

  Future<void> _fetchLogs() async {
    final vozacUuid = VozacCache.getUuidByIme(widget.vozacIme);
    if (vozacUuid == null) return;

    final datumStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    try {
      final data = await supabase
          .from('v2_statistika_istorija')
          .select()
          .eq('vozac_id', vozacUuid)
          .eq('datum', datumStr)
          .order('created_at', ascending: false);

      if (!_logsController.isClosed) {
        _logsController.add(List<Map<String, dynamic>>.from(data));
      }
    } catch (e) {
      if (!_logsController.isClosed) {
        _logsController.addError(e);
      }
    }
  }

  /// Otvori date picker
  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 7)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: VozacCache.getColor(widget.vozacIme),
                  surface: Theme.of(context).scaffoldBackgroundColor,
                ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _fetchLogs(); // Refresh logs sa novim datumom
    }
  }

  /// Formatira tip akcije
  String _formatTip(String? tip) {
    switch (tip) {
      case 'voznja':
        return '🚗 Pokupljen';
      case 'otkazivanje':
        return '❌ Otkazano';
      case 'uplata_dnevna':
        return '💰 Dnevna uplata';
      case 'uplata_mesecna':
        return '💰 Mesečna uplata';
      case 'uplata':
        return '💰 Uplata';
      default:
        return tip ?? 'Nepoznato';
    }
  }

  /// Formatira vreme
  String _formatVreme(DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('HH:mm').format(dt.toLocal());
  }

  /// Dohvati ime putnika
  Future<String> _getPutnikIme(String? putnikId) async {
    if (putnikId == null || putnikId.isEmpty) return '—';

    // Prvo pokusaj iz cache-a
    final cached = V2MasterRealtimeManager.instance.getPutnikById(putnikId);
    if (cached != null) return cached['ime'] as String? ?? '—';

    // Fallback: skraceni ID
    return putnikId.length > 8 ? putnikId.substring(0, 8) : putnikId;
  }

  /// Dohvati grad i vreme iz log zapisa (direktne kolone, fallback na meta)
  Map<String, String> _getGradVreme(VoznjeLog log) {
    String grad = log.grad ?? log.meta?['grad']?.toString() ?? '';
    String vreme = log.vremePolaska ?? log.meta?['vreme']?.toString() ?? '';

    grad = GradAdresaValidator.normalizeGrad(grad);

    return {'grad': grad, 'vreme': vreme};
  }

  /// Filtriraj akcije prema tipu
  bool _matchesFilter(VoznjeLog log) {
    if (_tabController == null) return true;

    final selectedType = _actionTypes[_tabController!.index];
    if (selectedType == 'sve') {
      return true;
    }

    if (selectedType == 'voznja') {
      return log.tip == 'voznja';
    } else if (selectedType == 'otkazivanje') {
      return log.tip == 'otkazivanje';
    } else if (selectedType == 'uplata') {
      return log.tip == 'uplata' || log.tip == 'uplata_dnevna' || log.tip == 'uplata_mesecna';
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    final vozacColor = VozacCache.getColor(widget.vozacIme);
    final datumStr = _selectedDate.toIso8601String().split('T')[0];
    final vozacUuid = VozacCache.getUuidByIme(widget.vozacIme);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '📋 Dnevnik - ${widget.vozacIme}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        backgroundColor: vozacColor,
        actions: [
          // Datum picker
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _selectDate,
            tooltip: 'Izaberi datum',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).scaffoldBackgroundColor,
              Theme.of(context).scaffoldBackgroundColor.withOpacity(0.8),
              vozacColor.withOpacity(0.05),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: Column(
          children: [
            // Header sa datumom
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).glassContainer,
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).glassBorder,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      DateFormat('EEEE, d. MMMM yyyy.', 'sr').format(_selectedDate),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                        shadows: [
                          Shadow(
                            color: vozacColor,
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.today, color: vozacColor),
                    onPressed: () {
                      setState(() {
                        _selectedDate = DateTime.now();
                      });
                    },
                    tooltip: 'Danas',
                  ),
                ],
              ),
            ),

            // TABBAR - Filteri za akcije
            if (_tabController != null)
              Material(
                color: Theme.of(context).glassContainer,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    indicatorColor: vozacColor,
                    indicatorWeight: 3,
                    labelColor: vozacColor,
                    unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                    tabs: _actionTypes.map((type) {
                      return Tab(text: _actionLabels[type] ?? type);
                    }).toList(),
                    onTap: (_) {
                      setState(() {});
                    },
                  ),
                ),
              ),

            // Lista akcija
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _logsController.stream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: CircularProgressIndicator(color: vozacColor),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.error),
                          const SizedBox(height: 16),
                          Text(
                            'Greška pri učitavanju\n${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                ),
                          ),
                        ],
                      ),
                    );
                  }

                  final logs = snapshot.data?.map((json) => VoznjeLog.fromJson(json)).toList() ?? [];

                  // Filtriraj logs prema trenutnom tab-u
                  final filteredLogs = logs.where((log) => _matchesFilter(log)).toList();

                  if (filteredLogs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox_outlined,
                              size: 64, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3)),
                          const SizedBox(height: 16),
                          Text(
                            'Nema akcija za izabrani datum',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: filteredLogs.length,
                    itemBuilder: (context, index) {
                      final log = filteredLogs[index];
                      final gradVreme = _getGradVreme(log);

                      return FutureBuilder<String>(
                        future: _getPutnikIme(log.putnikId),
                        builder: (context, putnikSnapshot) {
                          final putnikIme = putnikSnapshot.data ?? '...';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: Theme.of(context).cardColor.withOpacity(0.9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: vozacColor.withOpacity(0.5),
                                width: 2,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Vreme
                                  Container(
                                    width: 50,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                      horizontal: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: vozacColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: vozacColor.withOpacity(0.6),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      _formatVreme(log.createdAt),
                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.onSurface,
                                        shadows: [
                                          Shadow(
                                            color: vozacColor,
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Detalji
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Tip akcije
                                        Text(
                                          _formatTip(log.tip),
                                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context).colorScheme.onSurface,
                                            shadows: [
                                              Shadow(
                                                color: vozacColor,
                                                blurRadius: 8,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 4),

                                        // Putnik
                                        Text(
                                          putnikIme,
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: Theme.of(context).colorScheme.onSurface,
                                              ),
                                        ),

                                        // Grad i vreme
                                        if (gradVreme['grad']!.isNotEmpty || gradVreme['vreme']!.isNotEmpty)
                                          Text(
                                            '${gradVreme['grad']} ${gradVreme['vreme']}',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                                ),
                                          ),

                                        // Iznos (ako postoji)
                                        if (log.iznos > 0)
                                          Text(
                                            '${log.iznos.toStringAsFixed(0)} RSD',
                                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: Theme.of(context).colorScheme.successPrimary,
                                                ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
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
