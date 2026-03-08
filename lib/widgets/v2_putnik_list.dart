import 'package:flutter/material.dart';

import '../models/v2_putnik.dart';
import '../utils/v2_putnik_helpers.dart';
import 'v2_putnik_card.dart';

/// Widget koji prikazuje listu putnika koristeći V2PutnikCard za svaki element.

class V2PutnikList extends StatelessWidget {
  const V2PutnikList({
    super.key,
    this.putnici,
    this.putniciStream,
    this.showActions = true,
    required this.currentDriver,
    this.bcVremena,
    this.vsVremena,
    this.useProvidedOrder = false,
    this.onPutnikStatusChanged,
    this.onPokupljen,
    this.selectedGrad,
    this.selectedVreme,
    this.selectedDay,
    this.isDugovanjaMode = false,
  });
  final bool showActions;
  final String currentDriver;
  // Rezervisano za buducu upotrebu - trenutno se ne koristi u logici prikaza
  final bool isDugovanjaMode;
  final Stream<List<V2Putnik>>? putniciStream;
  final List<V2Putnik>? putnici;
  final List<String>? bcVremena;
  final List<String>? vsVremena;
  final bool useProvidedOrder;
  final VoidCallback? onPutnikStatusChanged;
  final VoidCallback? onPokupljen;
  final String? selectedGrad;
  final String? selectedVreme;
  final String? selectedDay;

  // Helper metoda za sortiranje putnika po grupama
  // Prati V2CardColorHelper prioritet boja:
  // Beli (moji→nedodeljeni) → Sivi (tuđi) → Plavi → Zeleni → Crveni → Žuti
  int _putnikSortKey(V2Putnik p, String currentDriver, {bool imaSivih = false}) {
    // ŽUTE - Odsustvo
    if (p.jeOdsustvo) {
      return 7; // žute na dno liste
    }

    // CRVENE - Otkazane
    if (p.jeOtkazan) {
      return 6; // crvene pre žutih
    }

    // Pokupljeni putnici — SVI tipovi jednako
    if (p.jePokupljen) {
      // ZELENE - Plaćeni (svi tipovi)
      if (p.placeno == true) {
        return 5; // zelene
      }
      // PLAVE - Pokupljeni neplaćeni (svi tipovi)
      return 4;
    }

    // SIVI - Tuđi putnici (dodeljen DRUGOM vozaču)
    final bool isTudji = p.dodeljenVozac != null &&
        p.dodeljenVozac!.isNotEmpty &&
        p.dodeljenVozac != 'Nedodeljen' &&
        p.dodeljenVozac != currentDriver;
    if (isTudji) {
      return 3; // sivi - između belih i plavih
    }

    // BELI - Moji ili Nedodeljeni (na vrhu)
    if (imaSivih) {
      final bool isMoj = p.dodeljenVozac == currentDriver;
      if (isMoj) {
        return 1; // moji na vrh
      }
      return 2; // nedodeljeni
    }

    // Nema sivih - svi beli zajedno
    return 1;
  }

  // Helper za proveru da li ima sivih kartica u listi
  bool _imaSivihKartica(List<V2Putnik> putnici, String currentDriver) {
    return putnici.any((p) =>
        !p.jeOdsustvo &&
        !p.jeOtkazan &&
        p.dodeljenVozac != null &&
        p.dodeljenVozac!.isNotEmpty &&
        p.dodeljenVozac != 'Nedodeljen' &&
        p.dodeljenVozac != currentDriver);
  }

  // Helper za deduplikaciju po id + grad + polazak (za slucaj vise polazaka istog putnika)
  List<V2Putnik> _deduplicatePutnici(List<V2Putnik> putnici) {
    final seen = <String, bool>{};
    return putnici.where((p) {
      final key = '${p.id}_${p.grad}_${p.polazak}';
      if (seen.containsKey(key)) return false;
      seen[key] = true;
      return true;
    }).toList(growable: false);
  }

  // Vraća početni redni broj za putnika (prvi broj od njegovih mesta)
  // O(n) akumulacijom umesto O(n²) iteracijom od pocetka
  int _pocetniRedniBroj(List<V2Putnik> putnici, int currentIndex) {
    int redniBroj = 1;
    for (int i = 0; i < currentIndex; i++) {
      if (V2PutnikHelpers.shouldHaveOrdinalNumber(putnici[i])) {
        redniBroj += putnici[i].brojMesta;
      }
    }
    return redniBroj;
  }

  @override
  Widget build(BuildContext context) {
    if (putniciStream != null) {
      return StreamBuilder<List<V2Putnik>>(
        stream: putniciStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Nema putnika za prikaz.'));
          }
          var filteredPutnici = _deduplicatePutnici(snapshot.data!);

          final imaSivih = _imaSivihKartica(filteredPutnici, currentDriver);

          // SORTIRANJE: Ako ima sivih: Moji → Nedodeljeni → Sivi → ostali
          // Ako nema sivih: Svi beli alfabetski → ostali
          filteredPutnici.sort((a, b) {
            final aSortKey = _putnikSortKey(a, currentDriver, imaSivih: imaSivih);
            final bSortKey = _putnikSortKey(b, currentDriver, imaSivih: imaSivih);

            final cmp = aSortKey.compareTo(bSortKey);
            if (cmp != 0) return cmp;

            // Ako su u istoj grupi, sortiraj alfabetski po imenu
            return a.ime.compareTo(b.ime);
          });

          final prikaz = filteredPutnici;
          if (prikaz.isEmpty) {
            return const Center(child: Text('Nema putnika za prikaz.'));
          }
          return ListView.builder(
            itemCount: prikaz.length,
            itemBuilder: (context, index) {
              final v2Putnik = prikaz[index];
              // Redni broj: računa sa brojem mesta svakog putnika
              int? redniBroj;
              if (V2PutnikHelpers.shouldHaveOrdinalNumber(v2Putnik)) {
                redniBroj = _pocetniRedniBroj(prikaz, index);
              }

              return V2PutnikCard(
                putnik: v2Putnik,
                showActions: showActions,
                currentDriver: currentDriver,
                redniBroj: redniBroj,
                bcVremena: bcVremena,
                vsVremena: vsVremena,
                selectedGrad: selectedGrad,
                selectedVreme: selectedVreme,
                selectedDay: selectedDay,
                onChanged: onPutnikStatusChanged,
                onPokupljen: onPokupljen,
              );
            },
          );
        },
      );
    } else if (putnici != null) {
      if (putnici!.isEmpty) {
        return const Center(child: Text('Nema putnika za prikaz.'));
      }
      var filteredPutnici = _deduplicatePutnici(putnici!);
      // VIZUELNI REDOSLED U LISTI:
      // 1) BELE - Nepokupljeni (na vrhu)
      // 2) PLAVE - Pokupljeni neplaćeni (svi tipovi)
      // 3) ZELENE - Pokupljeni plaćeni (svi tipovi)
      // 4) CRVENE - Otkazani
      // 5) ŽUTE - Odsustvo (godišnji/bolovanje) (na dnu)

      // HIBRIDNO SORTIRANJE ZA OPTIMIZOVANU RUTU:
      // Bele kartice (nepokupljeni) → zadržavaju geografski redosled
      // Plave/Zelene/Crvene/Žute → sortiraju se po grupama ispod belih
      if (useProvidedOrder) {
        // Razdvoji putnike po grupama
        final moji = <V2Putnik>[]; // moji putnici (dodeljen = ja)
        final nedodeljeni = <V2Putnik>[]; // nedodeljeni (vozac_id = null)
        final sivi = <V2Putnik>[]; // tuđi putnici (dodeljen drugom vozaču)
        final plavi = <V2Putnik>[]; // pokupljeni neplaćeni
        final zeleni = <V2Putnik>[]; // pokupljeni plaćeni (svi tipovi)
        final crveni = <V2Putnik>[]; // otkazani
        final zuti = <V2Putnik>[]; // odsustvo

        for (final p in filteredPutnici) {
          final sortKey = _putnikSortKey(p, currentDriver);
          switch (sortKey) {
            case 1:
              moji.add(p); // moji zadržavaju originalni geografski redosled
              break;
            case 2:
              nedodeljeni.add(p);
              break;
            case 3:
              sivi.add(p); // tuđi putnici
              break;
            case 4:
              plavi.add(p);
              break;
            case 5:
              zeleni.add(p);
              break;
            case 6:
              crveni.add(p);
              break;
            case 7:
              zuti.add(p);
              break;
          }
        }

        // Spoji sve grupe: MOJI → NEDODELJENI → SIVI (tuđi) → PLAVI → ZELENI → CRVENI → ŽUTI
        final prikaz = [...moji, ...nedodeljeni, ...sivi, ...plavi, ...zeleni, ...crveni, ...zuti];

        if (prikaz.isEmpty) {
          return const Center(child: Text('Nema putnika za prikaz.'));
        }
        return ListView.builder(
          itemCount: prikaz.length,
          itemBuilder: (context, index) {
            final v2Putnik = prikaz[index];
            // Redni broj: računa sa brojem mesta svakog putnika
            int? redniBroj;
            if (V2PutnikHelpers.shouldHaveOrdinalNumber(v2Putnik)) {
              redniBroj = _pocetniRedniBroj(prikaz, index);
            }
            return V2PutnikCard(
              putnik: v2Putnik,
              showActions: showActions,
              currentDriver: currentDriver,
              redniBroj: redniBroj,
              bcVremena: bcVremena,
              vsVremena: vsVremena,
              selectedGrad: selectedGrad,
              selectedVreme: selectedVreme,
              selectedDay: selectedDay,
              onChanged: onPutnikStatusChanged,
              onPokupljen: onPokupljen,
            );
          },
        );
      }

      final imaSivih = _imaSivihKartica(filteredPutnici, currentDriver);

      // SORTIRAJ: Ako ima sivih: Moji → Nedodeljeni → Sivi → ostali
      // Ako nema sivih: Svi beli alfabetski → ostali
      filteredPutnici.sort((a, b) {
        final aSortKey = _putnikSortKey(a, currentDriver, imaSivih: imaSivih);
        final bSortKey = _putnikSortKey(b, currentDriver, imaSivih: imaSivih);
        final cmp = aSortKey.compareTo(bSortKey);
        if (cmp != 0) return cmp;
        return a.ime.compareTo(b.ime);
      });

      if (filteredPutnici.isEmpty) {
        return const Center(child: Text('Nema putnika za prikaz.'));
      }
      return ListView.builder(
        itemCount: filteredPutnici.length,
        itemBuilder: (context, index) {
          final v2Putnik = filteredPutnici[index];
          // Redni broj: računa sa brojem mesta svakog putnika
          int? redniBroj;
          if (V2PutnikHelpers.shouldHaveOrdinalNumber(v2Putnik)) {
            redniBroj = _pocetniRedniBroj(filteredPutnici, index);
          }
          return V2PutnikCard(
            putnik: v2Putnik,
            showActions: showActions,
            currentDriver: currentDriver,
            redniBroj: redniBroj,
            bcVremena: bcVremena,
            vsVremena: vsVremena,
            selectedGrad: selectedGrad,
            selectedVreme: selectedVreme,
            onChanged: onPutnikStatusChanged,
            onPokupljen: onPokupljen,
          );
        },
      );
    } else {
      return const Center(child: Text('Nema podataka.'));
    }
  }
}
