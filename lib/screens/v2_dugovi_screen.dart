import 'package:flutter/material.dart';

import '../models/v2_putnik.dart';
import '../services/realtime/v2_master_realtime_manager.dart';
import '../services/v2_polasci_service.dart';
import '../theme.dart';
import '../utils/v2_dan_utils.dart';
import '../utils/v2_putnik_helpers.dart';
import '../widgets/v2_putnik_list.dart';

class V2DugoviScreen extends StatelessWidget {
  const V2DugoviScreen({super.key, required this.currentDriver});
  final String currentDriver;

  static Stream<List<V2Putnik>> _buildStream() {
    final dan = V2DanUtils.odIso(V2PutnikHelpers.getWorkingDateIso());
    return V2MasterRealtimeManager.instance.v2StreamFromCache<List<V2Putnik>>(
      tables: const [
        'v2_polasci',
        'v2_dnevni',
        'v2_radnici',
        'v2_ucenici',
        'v2_posiljke',
        'v2_vozac_raspored',
        'v2_vozac_putnik',
      ],
      build: () => V2PolasciService.fetchPutniciSyncStatic(dan: dan),
    );
  }

  static final Stream<List<V2Putnik>> _stream = _buildStream();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<V2Putnik>>(
      stream: _stream,
      builder: (context, snapshot) {
        final putnici = snapshot.data ?? [];
        final isLoading = snapshot.connectionState == ConnectionState.waiting && putnici.isEmpty;
        final dugovi = _dugoviFilterAndSort(putnici);

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Dugovanja', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                const Text('Svi neplaćeni putnici (Plava kartica)',
                    style: TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            ),
            automaticallyImplyLeading: false,
          ),
          body: Container(
            decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
            child: SafeArea(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : dugovi.isEmpty
                      ? const Center(
                          child: Text('Nema evidentiranih dugovanja.', style: TextStyle(color: Colors.white70)))
                      : V2PutnikList(
                          putnici: dugovi,
                          currentDriver: currentDriver,
                          isDugovanjaMode: true,
                        ),
            ),
          ),
        );
      },
    );
  }
}

// ─── top-level helperi (bez state pristupa) ───────────────────────────────────

/// Filter (dnevni tip, neplaćen, pokupljen, nije otkazan) + dedup + sort po vremenu pokupljenja DESC
List<V2Putnik> _dugoviFilterAndSort(List<V2Putnik> putnici) {
  final seenIds = <String>{};
  final result = putnici.where((p) {
    if (!p.isDnevniTip || p.placeno == true || !p.jePokupljen || p.jeOtkazan) return false;
    final key = p.id?.toString() ?? '${p.ime}_${p.dan}';
    return seenIds.add(key);
  }).toList();

  result.sort((a, b) {
    final timeA = a.vremePokupljenja;
    final timeB = b.vremePokupljenja;
    if (timeA == null && timeB == null) return 0;
    if (timeA == null) return 1;
    if (timeB == null) return -1;
    return timeB.compareTo(timeA);
  });
  return result;
}
