import 'package:flutter/material.dart';

import '../models/v3_putnik.dart';
import '../models/v3_zahtev.dart';
import 'v3_putnik_card.dart';

/// Widget koji prikazuje listu putnika koristeći V3PutnikCard za svaki element.
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
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<V3Putnik>>(
      stream: widget.putniciStream,
      initialData: widget.putnici,
      builder: (context, snapshot) {
        final lista = snapshot.data ?? [];
        if (lista.isEmpty) {
          return const Center(
            child: Text(
              'Nema putnika',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          );
        }

        // Redni broj — preskočiti otkazane
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
