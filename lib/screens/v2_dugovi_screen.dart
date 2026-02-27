import 'package:flutter/material.dart';

import '../models/v2_putnik.dart';
import '../services/v2_putnik_stream_service.dart';
import '../theme.dart';
import '../utils/v2_putnik_helpers.dart';
import '../widgets/v2_putnik_list.dart';

class DugoviScreen extends StatefulWidget {
  const DugoviScreen({super.key, required this.currentDriver});
  final String currentDriver;

  @override
  State<DugoviScreen> createState() => _DugoviScreenState();
}

class _DugoviScreenState extends State<DugoviScreen> {
  // 🔍 SEARCH & FILTERING (bez RxDart)
  final TextEditingController _searchController = TextEditingController();
  final _putnikService = V2PutnikStreamService();

  final String _selectedFilter = 'svi'; // 'svi', 'veliki_dug', 'mali_dug'
  final String _sortBy = 'vreme'; // 'iznos', 'vreme', 'ime', 'vozac' - default: najnoviji gore

  @override
  void initState() {
    super.initState();
    _setupDebouncedSearch();
  }

  @override
  void dispose() {
    // 🧹 SEARCH CLEANUP
    _searchController.dispose();
    super.dispose();
  }

  // 🔍 SEARCH SETUP (bez RxDart - jednostavan setState)
  void _setupDebouncedSearch() {
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  // 📊 SORT DUGOVE
  void _sortDugovi(List<V2Putnik> dugovi) {
    switch (_sortBy) {
      case 'iznos':
        dugovi.sort((a, b) {
          // Za dugove, koristimo cenu putovanja kao osnovu za sortiranje
          final cenaA = _calculateDugAmount(a);
          final cenaB = _calculateDugAmount(b);
          return cenaB.compareTo(cenaA); // Najveći dug prvi
        });
        break;
      case 'vreme':
        dugovi.sort((a, b) {
          final timeA = a.vremePokupljenja;
          final timeB = b.vremePokupljenja;
          if (timeA == null && timeB == null) return 0;
          if (timeA == null) return 1;
          if (timeB == null) return -1;
          return timeB.compareTo(timeA); // Najnoviji prvi
        });
        break;
      case 'ime':
        dugovi.sort((a, b) => a.ime.compareTo(b.ime));
        break;
      case 'vozac':
        dugovi.sort(
          (a, b) => (a.pokupioVozac ?? '').compareTo(b.pokupioVozac ?? ''),
        );
        break;
    }
  }

  // 💰 CALCULATE DUG AMOUNT HELPER
  double _calculateDugAmount(V2Putnik putnik) {
    // ✅ FIX: Koristi efektivnu cenu iz modela pomnoženu sa brojem mesta
    // Umesto hardkodovanih 500.0
    return putnik.effectivePrice * (putnik.brojMesta > 0 ? putnik.brojMesta : 1);
  }

  List<V2Putnik> _applyFiltersAndSort(List<V2Putnik> input) {
    var result = input;

    // Apply search filter
    final searchQuery = _searchController.text.toLowerCase();
    if (searchQuery.isNotEmpty) {
      result = result.where((duznik) {
        return duznik.ime.toLowerCase().contains(searchQuery) ||
            (duznik.pokupioVozac?.toLowerCase().contains(searchQuery) ?? false) ||
            (duznik.grad.toLowerCase().contains(searchQuery));
      }).toList();
    }

    // Apply amount filter
    if (_selectedFilter != 'svi') {
      result = result.where((duznik) {
        final iznos = _calculateDugAmount(duznik);
        switch (_selectedFilter) {
          case 'veliki_dug':
            return iznos >= 600; // Veliki dug (Dnevni je 600)
          case 'mali_dug':
            return iznos < 600;
          default:
            return true;
        }
      }).toList();
    }

    // Sort
    _sortDugovi(result);
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<V2Putnik>>(
      stream: _putnikService.streamKombinovaniPutniciFiltered(
        isoDate: PutnikHelpers.getWorkingDateIso(),
      ),
      builder: (context, snapshot) {
        final putnici = snapshot.data ?? [];
        final isLoading = snapshot.connectionState == ConnectionState.waiting && putnici.isEmpty;

        // ✅ Filter dužnike - putnici sa PLAVOM KARTICOM (nisu mesečni tip) koji nisu platili
        final duzniciRaw = putnici
            .where(
              (p) =>
                  (!p.isMesecniTip) && // ✅ FIX: Plava kartica = nije mesečni tip
                  (p.placeno != true) && // ✅ FIX: Koristi placeno flag iz voznje_log
                  (p.jePokupljen) &&
                  (p.status == null || (p.status != 'Otkazano' && p.status != 'otkazan')),
              // 🎯 IZMENA: Uklonjen filter po vozaču da bi se prikazali SVI dužnici (zahtev 26.01.2026)
            )
            .toList();

        // ✅ DEDUPLIKACIJA: Jedan V2Putnik može imati više termina, ali je jedan dužnik
        final seenIds = <dynamic>{};
        final duzniciDeduplicated = duzniciRaw.where((p) {
          final key = p.id ?? '${p.ime}_${p.dan}';
          if (seenIds.contains(key)) return false;
          seenIds.add(key);
          return true;
        }).toList();

        // Apply filters and sort
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
                  style: TextStyle(fontSize: 12, color: Colors.white70.withOpacity(0.8)),
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
                  // ...existing code...
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
                            : PutnikList(
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
