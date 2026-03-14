import 'package:flutter/material.dart';

import '../models/v3_putnik.dart';
import '../models/v3_zahtev.dart';
import 'v3_putnik_card.dart';

/// Widget koji prikazuje listu putnika koristeći V3PutnikCard za svaki element.
/// Sortiranje po grupama: Aktivni (beli) → Pokupljeni (plavi) → Plaćeni (zeleni) → Otkazani (crveni)
class V3PutnikList extends StatefulWidget {
  const V3PutnikList({
    super.key,
    this.putnici,
    this.putniciStream,
    this.zahteviMap,
  });

  final List<V3Putnik>? putnici;
  final Stream<List<V3Putnik>>? putniciStream;

  /// Mapa putnikId → V3Zahtev za tekući dan
  final Map<String, V3Zahtev>? zahteviMap;

  @override
  State<V3PutnikList> createState() => _V3PutnikListState();
}

class _V3PutnikListState extends State<V3PutnikList> {
  // Sortira putnike po grupama kao V2:
  // 1 = Aktivni (obrada/odobreno) — beli
  // 2 = Pokupljeni neplaćeni — plavi
  // 3 = Pokupljeni plaćeni — zeleni
  // 4 = Otkazani — crveni
  int _sortKey(V3Putnik putnik, Map<String, V3Zahtev>? zahteviMap) {
    final zahtev = zahteviMap?[putnik.id];
    final status = zahtev?.status ?? '';
    if (status == 'otkazano') return 4;
    if (status == 'pokupljen') {
      return 2; // plavi — pokupljeni
    }
    return 1;
  }

  List<V3Putnik> _sortiraj(List<V3Putnik> lista, Map<String, V3Zahtev>? zahteviMap) {
    final sorted = List<V3Putnik>.from(lista);
    sorted.sort((a, b) {
      final cmp = _sortKey(a, zahteviMap).compareTo(_sortKey(b, zahteviMap));
      if (cmp != 0) return cmp;
      return a.imePrezime.compareTo(b.imePrezime);
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<V3Putnik>>(
      stream: widget.putniciStream,
      initialData: widget.putnici,
      builder: (context, snapshot) {
        final raw = snapshot.data ?? [];
        if (raw.isEmpty) {
          return const Center(
            child: Text(
              'Nema putnika',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          );
        }

        final lista = _sortiraj(raw, widget.zahteviMap);

        // Redni broj — samo aktivni (ne otkazani)
        int redniBroj = 0;
        return ListView.builder(
          itemCount: lista.length,
          itemBuilder: (context, index) {
            final putnik = lista[index];
            final zahtev = widget.zahteviMap?[putnik.id];
            final bool isOtkazan = zahtev?.status == 'otkazano';
            if (!isOtkazan) redniBroj++;
            return V3PutnikCard(
              putnik: putnik,
              zahtev: zahtev,
              redniBroj: isOtkazan ? null : redniBroj,
              onChanged: () => setState(() {}),
            );
          },
        );
      },
    );
  }
}
