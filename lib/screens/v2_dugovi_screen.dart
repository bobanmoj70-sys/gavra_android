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

class _DugoviScreenState extends State<V2DugoviScreen> with WidgetsBindingObserver {
  final _putnikService = V2PutnikStreamService();

  late String _workingDateIso;
  late Stream<List<V2Putnik>> _streamDugovi;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _workingDateIso = V2PutnikHelpers.getWorkingDateIso();
    _streamDugovi = _putnikService.streamKombinovaniPutniciFiltered(
      dan: V2DanUtils.odIso(_workingDateIso),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!mounted) return;
      final newIso = V2PutnikHelpers.getWorkingDateIso();
      if (newIso != _workingDateIso) {
        setState(() {
          _workingDateIso = newIso;
          _streamDugovi = _putnikService.streamKombinovaniPutniciFiltered(
            dan: V2DanUtils.odIso(_workingDateIso),
          );
        });
      }
    }
  }

  static void _sortDugovi(List<V2Putnik> dugovi) {
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
    final result = List<V2Putnik>.of(input);
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
              (p) => p.isDnevniTip && (p.placeno != true) && (p.jePokupljen) && !p.jeOtkazan,
            )
            .toList();

        final seenIds = <String>{};
        final duzniciDeduplicated = duzniciRaw.where((p) {
          final key = p.id?.toString() ?? '${p.ime}_${p.dan}';
          return seenIds.add(key);
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
                  style: TextStyle(fontSize: 12, color: Colors.white70),
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
