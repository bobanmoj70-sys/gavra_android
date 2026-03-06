import 'package:flutter/material.dart';

import '../models/v2_putnik.dart';
import '../services/v2_polasci_service.dart';
import '../theme.dart';
import '../utils/v2_dan_utils.dart';
import '../utils/v2_putnik_helpers.dart';
import '../widgets/v2_putnik_list.dart';

class V2DugoviScreen extends StatefulWidget {
  const V2DugoviScreen({super.key, required this.currentDriver});
  final String currentDriver;

  @override
  State<V2DugoviScreen> createState() => _DugoviScreenState();
}

class _DugoviScreenState extends State<V2DugoviScreen> {
  final TextEditingController _searchController = TextEditingController();
  final _putnikService = V2PutnikStreamService();

  late final Stream<List<V2Putnik>> _streamDugovi;

  @override
  void initState() {
    super.initState();
    _streamDugovi = _putnikService.streamKombinovaniPutniciFiltered(
      dan: V2DanUtils.odIso(V2PutnikHelpers.getWorkingDateIso()),
    );
    _setupSearchListener();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setupSearchListener() {
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  void _sortDugovi(List<V2Putnik> dugovi) {
    dugovi.sort((a, b) {
      final timeA = a.vremePokupljenja;
      final timeB = b.vremePokupljenja;
      if (timeA == null && timeB == null) return 0;
      if (timeA == null) return 1;
      if (timeB == null) return -1;
      return timeB.compareTo(timeA);
    });
  }

  List<V2Putnik> _applyFiltersAndSort(List<V2Putnik> input) {
    var result = input;

    final searchQuery = _searchController.text.toLowerCase();
    if (searchQuery.isNotEmpty) {
      result = result.where((duznik) {
        return duznik.ime.toLowerCase().contains(searchQuery) ||
            (duznik.pokupioVozac?.toLowerCase().contains(searchQuery) ?? false) ||
            (duznik.grad.toLowerCase().contains(searchQuery));
      }).toList();
    }

    _sortDugovi(result);
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<V2Putnik>>(
      stream: _streamDugovi,
      builder: (context, snapshot) {
        final putnici = snapshot.data ?? [];
        final isLoading = snapshot.connectionState == ConnectionState.waiting && putnici.isEmpty;

        final duzniciRaw = putnici
            .where(
              (p) => (p.isDnevni || p.isPosiljka) && (p.placeno != true) && (p.jePokupljen) && !p.jeOtkazan,
            )
            .toList();

        final seenIds = <dynamic>{};
        final duzniciDeduplicated = duzniciRaw.where((p) {
          final key = p.id ?? '${p.ime}_${p.dan}';
          if (seenIds.contains(key)) return false;
          seenIds.add(key);
          return true;
        }).toList();

        final filteredDugovi = _applyFiltersAndSort(duzniciDeduplicated);

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dugovanja',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                ),
                Text(
                  'Svi neplaćeni putnici (Plava kartica)',
                  style: TextStyle(fontSize: 12, color: Colors.white70.withValues(alpha: 0.8)),
                ),
              ],
            ),
            automaticallyImplyLeading: false,
          ),
          body: Container(
            decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
            child: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator(color: Colors.white))
                        : filteredDugovi.isEmpty
                            ? const Center(
                                child: Text(
                                  'Nema evidentiranih dugovanja.',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              )
                            : V2PutnikList(
                                putnici: filteredDugovi,
                                currentDriver: widget.currentDriver,
                                isDugovanjaMode: true,
                              ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
