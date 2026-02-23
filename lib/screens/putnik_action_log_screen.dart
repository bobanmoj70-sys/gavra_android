import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../globals.dart';
import '../models/voznje_log.dart';
import '../theme.dart';
import '../utils/vozac_cache.dart';

/// 👤 DNEVNIK AKCIJA PUTNIKA
/// Search bar za izbor putnika → prikazuje sve akcije po datumu
/// Namjena: admin ispravlja greške sistema (pogrešno pokupljeni, otkazani, uplate)
class PutnikActionLogScreen extends StatefulWidget {
  const PutnikActionLogScreen({super.key});

  @override
  State<PutnikActionLogScreen> createState() => _PutnikActionLogScreenState();
}

class _PutnikActionLogScreenState extends State<PutnikActionLogScreen> with SingleTickerProviderStateMixin {
  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Izabrani putnik
  String? _selectedPutnikId;
  String? _selectedPutnikIme;

  // Lista svih putnika (za search)
  List<Map<String, dynamic>> _sviPutnici = [];
  bool _loadingPutnici = false;

  // Seat requests
  List<Map<String, dynamic>> _seatRequests = [];
  bool _loadingSeatRequests = false;

  // Tabovi
  TabController? _tabController;
  static const List<String> _actionTypes = ['sve', 'voznja', 'otkazivanje', 'uplata', 'zahtevi'];
  static const Map<String, String> _actionLabels = {
    'sve': '📊 Sve',
    'voznja': '🚗 Vožnje',
    'otkazivanje': '❌ Otkazane',
    'uplata': '💰 Uplate',
    'zahtevi': '📋 Zahtjevi',
  };

  static const Color _accentColor = Color(0xFF5C6BC0); // indigo

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _actionTypes.length, vsync: this);
    _tabController!.addListener(() {
      if (!mounted) return;
      setState(() {});
      // Učitaj zahtjeve kad se klikne na "Zahtjevi" tab
      if (_tabController!.index == _actionTypes.indexOf('zahtevi') && !_tabController!.indexIsChanging) {
        _loadSeatRequests();
      }
    });
    _loadSviPutnici();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Učitaj sve aktivne putnike za search
  Future<void> _loadSviPutnici() async {
    setState(() => _loadingPutnici = true);
    try {
      final response = await supabase
          .from('registrovani_putnici')
          .select('id, putnik_ime, tip')
          .eq('obrisan', false)
          .order('putnik_ime');

      setState(() {
        _sviPutnici = List<Map<String, dynamic>>.from(response as List);
        _loadingPutnici = false;
      });
    } catch (e) {
      setState(() => _loadingPutnici = false);
      debugPrint('❌ [PutnikLog] Greška pri učitavanju putnika: $e');
    }
  }

  /// Filtrirani putnici prema search query-ju
  List<Map<String, dynamic>> get _filteredPutnici {
    if (_searchQuery.isEmpty) return _sviPutnici;
    final q = _searchQuery.toLowerCase();
    return _sviPutnici.where((p) {
      final ime = (p['putnik_ime'] as String? ?? '').toLowerCase();
      return ime.contains(q);
    }).toList();
  }

  /// Učitaj seat_requests za izabranog putnika (sve, sortirano najnovije gore)
  Future<void> _loadSeatRequests() async {
    if (_selectedPutnikId == null) return;
    setState(() => _loadingSeatRequests = true);
    try {
      final response = await supabase
          .from('seat_requests')
          .select(
              'id, grad, dan, zeljeno_vreme, dodeljeno_vreme, status, created_at, broj_mesta, priority, cancelled_by')
          .eq('putnik_id', _selectedPutnikId!)
          .order('created_at', ascending: false);
      setState(() {
        _seatRequests = List<Map<String, dynamic>>.from(response as List);
        _loadingSeatRequests = false;
      });
    } catch (e) {
      setState(() => _loadingSeatRequests = false);
      debugPrint('❌ [PutnikLog] Greška pri učitavanju zahtjeva: $e');
    }
  }

  /// Formatira tip akcije za prikaz
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

  /// Formatira vreme iz DateTime
  String _formatVreme(DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('HH:mm').format(dt.toLocal());
  }

  /// Dohvati ime vozača iz UUID-a
  String _getVozacIme(String? vozacId) {
    if (vozacId == null || vozacId.isEmpty) return '—';
    return VozacCache.getImeByUuid(vozacId) ?? vozacId.substring(0, 8);
  }

  /// Dohvati grad i vreme iz meta
  Map<String, String> _getGradVreme(VoznjeLog log) {
    final meta = log.meta;
    String grad = meta?['grad']?.toString() ?? '';
    String vreme = meta?['vreme']?.toString() ?? '';

    if (grad.toLowerCase() == 'vs' || grad.toLowerCase().contains('vrsac')) {
      grad = 'Vrsac';
    } else if (grad.toLowerCase() == 'bc' || grad.toLowerCase().contains('bela')) {
      grad = 'Bela Crkva';
    }
    return {'grad': grad, 'vreme': vreme};
  }

  /// Filter po tabu
  bool _matchesFilter(VoznjeLog log) {
    if (_tabController == null) return true;
    final selectedType = _actionTypes[_tabController!.index];
    if (selectedType == 'sve') return true;
    if (selectedType == 'voznja') return log.tip == 'voznja';
    if (selectedType == 'otkazivanje') return log.tip == 'otkazivanje';
    if (selectedType == 'uplata') {
      return log.tip == 'uplata' || log.tip == 'uplata_dnevna' || log.tip == 'uplata_mesecna';
    }
    return true;
  }

  /// Boja za tip akcije
  Color _colorForTip(String? tip) {
    switch (tip) {
      case 'voznja':
        return Colors.green;
      case 'otkazivanje':
        return Colors.redAccent;
      case 'uplata':
      case 'uplata_dnevna':
      case 'uplata_mesecna':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '👤 Dnevnik putnika',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        backgroundColor: _accentColor,
      ),
      body: Column(
        children: [
          // ── SEARCH BAR ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            decoration: BoxDecoration(
              color: Theme.of(context).glassContainer,
              border: Border(
                bottom: BorderSide(color: Theme.of(context).glassBorder, width: 1.5),
              ),
            ),
            child: TextField(
              controller: _searchController,
              autofocus: _selectedPutnikIme == null,
              style: Theme.of(context).textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Pretraži putnika po imenu...',
                prefixIcon: const Icon(Icons.search, color: _accentColor),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            // Ne briši odabranog putnika - samo zatvori dropdown
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.6),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _accentColor.withOpacity(0.4)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _accentColor.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _accentColor, width: 2),
                ),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),

          // ── DROPDOWN LISTA PUTNIKA (dok se kuca) ─────────────────
          if (_searchQuery.isNotEmpty)
            Flexible(
              flex: 2,
              child: _loadingPutnici
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(color: _accentColor),
                    )
                  : _filteredPutnici.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Nema putnika za "${_searchQuery}"',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                ),
                          ),
                        )
                      : Material(
                          elevation: 4,
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(8),
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            itemCount: _filteredPutnici.length > 8 ? 8 : _filteredPutnici.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: Theme.of(context).glassBorder,
                            ),
                            itemBuilder: (context, index) {
                              final p = _filteredPutnici[index];
                              final ime = p['putnik_ime'] as String? ?? '';
                              final tip = p['tip'] as String? ?? '';
                              final vozacIme = _getVozacIme(p['vozac_id'] as String?);

                              return ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: _accentColor.withOpacity(0.2),
                                  child: Text(
                                    ime.isNotEmpty ? ime[0].toUpperCase() : '?',
                                    style: const TextStyle(
                                      color: _accentColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  ime,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                subtitle: Text(
                                  '$tip • $vozacIme',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                      ),
                                ),
                                onTap: () {
                                  setState(() {
                                    _selectedPutnikId = p['id'] as String?;
                                    _selectedPutnikIme = ime;
                                    _searchQuery = '';
                                    _searchController.clear();
                                  });
                                  FocusScope.of(context).unfocus();
                                  _loadSeatRequests();
                                },
                              );
                            },
                          ),
                        ),
            ),

          // ── IZABRANI PUTNIK - header ──────────────────────────────
          if (_selectedPutnikIme != null && _searchQuery.isEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _accentColor.withOpacity(0.12),
                border: Border(
                  bottom: BorderSide(color: _accentColor.withOpacity(0.3), width: 1.5),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: _accentColor,
                    child: Text(
                      _selectedPutnikIme![0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedPutnikIme!,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: _accentColor,
                              ),
                        ),
                      ],
                    ),
                  ),
                  // Dugme za promjenu putnika
                  IconButton(
                    icon: Icon(Icons.swap_horiz, color: _accentColor.withOpacity(0.7)),
                    onPressed: () {
                      setState(() {
                        _selectedPutnikId = null;
                        _selectedPutnikIme = null;
                      });
                      _searchController.clear();
                      Future.delayed(
                        const Duration(milliseconds: 100),
                        () => FocusScope.of(context).requestFocus(FocusNode()),
                      );
                    },
                    tooltip: 'Promjeni putnika',
                  ),
                ],
              ),
            ),

            // ── TABOVI ─────────────────────────────────────────────
            if (_tabController != null)
              Material(
                color: Theme.of(context).glassContainer,
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  indicatorColor: _accentColor,
                  indicatorWeight: 3,
                  labelColor: _accentColor,
                  unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                  tabs: _actionTypes.map((type) => Tab(text: _actionLabels[type] ?? type)).toList(),
                  onTap: (_) => setState(() {}),
                ),
              ),

            // ── LISTA AKCIJA / ZAHTJEVI ────────────────────────────
            Expanded(
              child: (_tabController != null && _actionTypes[_tabController!.index] == 'zahtevi')
                  ? _buildZahteviList()
                  : _buildAkcijeList(),
            ),
          ],

          // ── PRAZAN STATE - nema izabranog putnika ─────────────────
          if (_selectedPutnikIme == null && _searchQuery.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.person_search,
                      size: 72,
                      color: _accentColor.withOpacity(0.25),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Pretraži putnika',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Upiši ime u search bar gore',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                          ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Gradi listu akcija za odabranog putnika (sva historija, sortirano najnovije gore)
  Widget _buildAkcijeList() {
    final putnikId = _selectedPutnikId!;

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: supabase
          .from('voznje_log')
          .stream(primaryKey: ['id'])
          .eq('putnik_id', putnikId)
          .order('created_at', ascending: false),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _accentColor));
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Greška: ${snapshot.error}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          );
        }

        final logs = snapshot.data?.map((json) => VoznjeLog.fromJson(json)).toList() ?? [];
        final filteredLogs = logs.where((log) => _matchesFilter(log)).toList();

        if (filteredLogs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.25),
                ),
                const SizedBox(height: 16),
                Text(
                  'Nema akcija za ovog putnika',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
                      ),
                ),
              ],
            ),
          );
        }

        // Grupiši po datumu
        final Map<String, List<VoznjeLog>> grouped = {};
        for (final log in filteredLogs) {
          final key = log.datum != null ? log.datum!.toIso8601String().split('T')[0] : 'Nepoznat datum';
          grouped.putIfAbsent(key, () => []).add(log);
        }
        final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a)); // najnoviji datum gore

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: sortedDates.length,
          itemBuilder: (context, i) {
            final dateKey = sortedDates[i];
            final dayLogs = grouped[dateKey]!;
            DateTime? dt = DateTime.tryParse(dateKey);
            final dateLabel = dt != null ? DateFormat('EEEE, d. MMMM yyyy.', 'sr').format(dt) : dateKey;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _accentColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _accentColor.withOpacity(0.3)),
                        ),
                        child: Text(
                          dateLabel,
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: _accentColor,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${dayLogs.length} akcija',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                            ),
                      ),
                    ],
                  ),
                ),
                ...dayLogs.map((log) => _buildLogCard(log)),
              ],
            );
          },
        );
      },
    );
  }

  /// Boja za status zahtjeva
  Color _colorForStatus(String? status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'rejected':
        return Colors.redAccent;
      case 'cancelled':
        return Colors.grey;
      case 'manual':
        return Colors.blueAccent;
      default:
        return Colors.grey;
    }
  }

  /// Ikona za status
  IconData _iconForStatus(String? status) {
    switch (status) {
      case 'approved':
        return Icons.check_circle;
      case 'pending':
        return Icons.hourglass_empty;
      case 'rejected':
        return Icons.cancel;
      case 'cancelled':
        return Icons.block;
      case 'manual':
        return Icons.edit_note;
      default:
        return Icons.help_outline;
    }
  }

  /// Label za status
  String _labelForStatus(String? status) {
    switch (status) {
      case 'approved':
        return '✅ Odobreno';
      case 'pending':
        return '⏳ Na čekanju';
      case 'rejected':
        return '❌ Odbijeno';
      case 'cancelled':
        return '🚫 Otkazano';
      case 'manual':
        return '✏️ Ručno';
      default:
        return status ?? 'Nepoznato';
    }
  }

  /// Formatiraj grad
  String _formatGrad(String? grad) {
    if (grad == null) return '—';
    if (grad.toLowerCase() == 'vs' || grad.toLowerCase().contains('vr')) return 'Vrsac';
    if (grad.toLowerCase() == 'bc' || grad.toLowerCase().contains('be')) return 'Bela Crkva';
    return grad;
  }

  /// Gradi listu zahtjeva (seat_requests)
  Widget _buildZahteviList() {
    if (_loadingSeatRequests) {
      return const Center(child: CircularProgressIndicator(color: _accentColor));
    }

    if (_seatRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_seat_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.25),
            ),
            const SizedBox(height: 16),
            Text(
              'Nema zahtjeva za izabrani datum',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
                  ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                _loadSeatRequests();
              },
              icon: const Icon(Icons.refresh, size: 16, color: _accentColor),
              label: const Text('Osvježi', style: TextStyle(color: _accentColor)),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSeatRequests,
      color: _accentColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _seatRequests.length,
        itemBuilder: (context, index) {
          return _buildSeatRequestCard(_seatRequests[index]);
        },
      ),
    );
  }

  Widget _buildSeatRequestCard(Map<String, dynamic> req) {
    final status = req['status'] as String?;
    final statusColor = _colorForStatus(status);
    final grad = _formatGrad(req['grad'] as String?);
    final zeljenoVreme = req['zeljeno_vreme'] as String? ?? '';
    final dodeljenovVreme = req['dodeljeno_vreme'] as String?;
    final brojMesta = req['broj_mesta'] as int? ?? 1;
    final priority = req['priority'] as int? ?? 0;
    final cancelledBy = req['cancelled_by'] as String?;
    final createdAt = req['created_at'] != null ? DateTime.tryParse(req['created_at'] as String)?.toLocal() : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Theme.of(context).cardColor.withOpacity(0.9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.withOpacity(0.5), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status ikona
            Column(
              children: [
                if (createdAt != null)
                  Container(
                    width: 52,
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: statusColor.withOpacity(0.5), width: 1),
                    ),
                    child: Text(
                      DateFormat('HH:mm').format(createdAt),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 4),
                Icon(
                  _iconForStatus(status),
                  size: 20,
                  color: statusColor,
                ),
              ],
            ),
            const SizedBox(width: 12),

            // Detalji
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status label
                  Text(
                    _labelForStatus(status),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                  ),
                  const SizedBox(height: 4),

                  // Grad
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 13,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        grad,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),

                  // Željeno vreme
                  if (zeljenoVreme.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 13,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Željeno: $zeljenoVreme',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                ),
                          ),
                        ],
                      ),
                    ),

                  // Dodijeljeno vreme
                  if (dodeljenovVreme != null && dodeljenovVreme.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_outline,
                            size: 13,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Dodijeljeno: $dodeljenovVreme',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),

                  // Broj mjesta + prioritet
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.event_seat,
                          size: 13,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Mjesta: $brojMesta',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              ),
                        ),
                        if (priority > 0) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.star, size: 12, color: Colors.amber),
                          const SizedBox(width: 2),
                          Text(
                            'P$priority',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.amber,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Otkazao
                  if (cancelledBy != null && cancelledBy.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Otkazao: $cancelledBy',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.redAccent.withOpacity(0.7),
                              fontStyle: FontStyle.italic,
                            ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogCard(VoznjeLog log) {
    final tipColor = _colorForTip(log.tip);
    final gradVreme = _getGradVreme(log);
    final vozacIme = _getVozacIme(log.vozacId);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Theme.of(context).cardColor.withOpacity(0.9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: tipColor.withOpacity(0.5), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Vreme + ikona
            Column(
              children: [
                Container(
                  width: 52,
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  decoration: BoxDecoration(
                    color: tipColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: tipColor.withOpacity(0.5), width: 1),
                  ),
                  child: Text(
                    _formatVreme(log.createdAt),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 4),
                Icon(
                  log.tip == 'voznja'
                      ? Icons.directions_car
                      : log.tip == 'otkazivanje'
                          ? Icons.cancel
                          : Icons.payments,
                  size: 18,
                  color: tipColor,
                ),
              ],
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
                          color: tipColor,
                        ),
                  ),
                  const SizedBox(height: 4),

                  // Vozač
                  Row(
                    children: [
                      Icon(
                        Icons.person_pin,
                        size: 13,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        vozacIme,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                      ),
                    ],
                  ),

                  // Grad i vreme polaska
                  if (gradVreme['grad']!.isNotEmpty || gradVreme['vreme']!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 13,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${gradVreme['grad']} ${gradVreme['vreme']}'.trim(),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                ),
                          ),
                        ],
                      ),
                    ),

                  // Iznos
                  if (log.iznos > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${log.iznos.toStringAsFixed(0)} RSD',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.amber,
                            ),
                      ),
                    ),

                  // Detalji (ako postoje)
                  if (log.detalji != null && log.detalji!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        log.detalji!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                              fontStyle: FontStyle.italic,
                            ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
