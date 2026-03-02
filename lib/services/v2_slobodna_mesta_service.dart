import 'package:flutter/foundation.dart';

import '../models/v2_putnik.dart';
import '../utils/v2_grad_adresa_validator.dart';
import '../utils/v2_putnik_helpers.dart';
import 'v2_kapacitet_service.dart';
import 'v2_polasci_service.dart';

/// Model za slobodna mesta po polasku
class V2SlobodnaMesta {
  final String grad;
  final String vreme;
  final int maxMesta;
  final int zauzetaMesta;
  final int uceniciCount;
  final bool aktivan;

  V2SlobodnaMesta({
    required this.grad,
    required this.vreme,
    required this.maxMesta,
    required this.zauzetaMesta,
    this.uceniciCount = 0,
    this.aktivan = true,
  });

  int get slobodna => maxMesta - zauzetaMesta;
  bool get imaMesta => slobodna > 0;
  bool get jePuno => slobodna <= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is V2SlobodnaMesta &&
          grad == other.grad &&
          vreme == other.vreme &&
          maxMesta == other.maxMesta &&
          zauzetaMesta == other.zauzetaMesta &&
          uceniciCount == other.uceniciCount &&
          aktivan == other.aktivan;

  @override
  int get hashCode => Object.hash(grad, vreme, maxMesta, zauzetaMesta, uceniciCount, aktivan);
}

class V2SlobodnaMestaService {
  V2SlobodnaMestaService._();

  static final _putnikService = V2PutnikStreamService();

  /// Pretvara ISO datum u skracenicu dana ('pon', 'uto', itd.)
  static String _isoDateToDayAbbr(String isoDate) {
    final date = DateTime.tryParse(isoDate);
    if (date == null) return 'pon';
    const dani = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
    return dani[(date.weekday - 1).clamp(0, 6)];
  }

  /// Izracunaj broj zauzetih mesta za odredeni grad/vreme/datum
  static int _countPutniciZaPolazak(List<V2Putnik> putnici, String grad, String vreme, String isoDate,
      {String? excludePutnikId}) {
    final normalizedGrad = GradAdresaValidator.normalizeGrad(grad); // 'BC' ili 'VS'
    final targetVreme = GradAdresaValidator.normalizeTime(vreme);
    final targetDayAbbr = _isoDateToDayAbbr(isoDate);

    int count = 0;
    for (final p in putnici) {
      // AKO RADIMO UPDATE: Iskljuci putnika koga menjamo da ne bi sam sebi zauzimao mesto
      if (excludePutnikId != null && p.id?.toString() == excludePutnikId.toString()) {
        continue;
      }

      // Koristi V2PutnikHelpers za konzistentnu logiku
      // Ne racuna: otkazane (jeOtkazan), odsustvo (jeOdsustvo)
      if (!V2PutnikHelpers.shouldCountInSeats(p)) continue;

      // Filtriraj po dan kraticama (v2_polasci nema datum kolonu)
      if (!p.dan.toLowerCase().contains(targetDayAbbr.toLowerCase())) continue;

      // Proveri vreme - OBA MORAJU BITI NORMALIZOVANA
      final normVreme = GradAdresaValidator.normalizeTime(p.polazak);
      if (normVreme != targetVreme) continue;

      // Proveri grad
      if ((normalizedGrad == 'BC' && p.grad == 'BC') || (normalizedGrad == 'VS' && p.grad == 'VS')) {
        // Brojimo sve putnike za ovaj grad
        count += p.brojMesta.toInt();
      }
    }

    return count;
  }

  static int _countUceniciZaPolazak(List<V2Putnik> putnici, String grad, String vreme, String isoDate,
      {String? excludePutnikId}) {
    final normalizedGrad = GradAdresaValidator.normalizeGrad(grad); // 'BC' ili 'VS'
    final targetVreme = GradAdresaValidator.normalizeTime(vreme);
    final targetDayAbbr = _isoDateToDayAbbr(isoDate);

    int count = 0;
    for (final p in putnici) {
      if (excludePutnikId != null && p.id?.toString() == excludePutnikId.toString()) {
        continue;
      }

      // Isti filteri kao za putnike (bez otkazanih, itd)
      if (!V2PutnikHelpers.shouldCountInSeats(p)) continue;

      // Filter: SAMO UCENICI
      if (p.tipPutnika != 'ucenik') continue;

      // Filtriraj po dan kraticama (v2_polasci nema datum kolonu)
      if (!p.dan.toLowerCase().contains(targetDayAbbr.toLowerCase())) continue;

      // Proveri vreme
      final normVreme = GradAdresaValidator.normalizeTime(p.polazak);
      if (normVreme != targetVreme) continue;

      // Proveri grad
      if ((normalizedGrad == 'BC' && p.grad == 'BC') || (normalizedGrad == 'VS' && p.grad == 'VS')) {
        count += p.brojMesta.toInt();
      }
    }

    return count;
  }

  /// Dohvati slobodna mesta po gradu za odredeni datum
  static Future<Map<String, List<V2SlobodnaMesta>>> getSlobodnaMesta({String? datum, String? excludeId}) async {
    final isoDate = datum ?? DateTime.now().toIso8601String().split('T')[0];
    final excludePutnikId = excludeId;

    final result = <String, List<V2SlobodnaMesta>>{
      'BC': [],
      'VS': [],
    };

    List<V2Putnik> putnici;
    Map<String, dynamic> kapacitet;
    try {
      putnici = await _putnikService.getPutniciByDayIso(isoDate);
      kapacitet = V2KapacitetService.getKapacitet();
    } catch (e) {
      debugPrint('[V2SlobodnaMestaService] getSlobodnaMesta: greska pri ucitavanju podataka: $e');
      return result;
    }

    try {
      // Bela Crkva
      final bcKapaciteti = kapacitet['BC'] as Map? ?? {};
      final bcVremenaSorted = bcKapaciteti.keys.cast<String>().toList()..sort();

      for (final vreme in bcVremenaSorted) {
        final maxMesta = (bcKapaciteti[vreme] as num?)?.toInt() ?? 8;
        final zauzeto = _countPutniciZaPolazak(putnici, 'BC', vreme, isoDate, excludePutnikId: excludePutnikId);
        final ucenici = _countUceniciZaPolazak(putnici, 'BC', vreme, isoDate, excludePutnikId: excludePutnikId);

        result['BC']!.add(
          V2SlobodnaMesta(
            grad: 'BC',
            vreme: vreme,
            maxMesta: maxMesta,
            zauzetaMesta: zauzeto,
            aktivan: true,
            uceniciCount: ucenici,
          ),
        );
      }
    } catch (e) {
      debugPrint('[V2SlobodnaMestaService] getSlobodnaMesta BC error: $e');
    }

    try {
      // Vrsac
      final vsKapaciteti = kapacitet['VS'] as Map? ?? {};
      final vsVremenaSorted = vsKapaciteti.keys.cast<String>().toList()..sort();

      for (final vreme in vsVremenaSorted) {
        final maxMesta = (vsKapaciteti[vreme] as num?)?.toInt() ?? 8;
        final zauzeto = _countPutniciZaPolazak(putnici, 'VS', vreme, isoDate, excludePutnikId: excludePutnikId);
        final ucenici = _countUceniciZaPolazak(putnici, 'VS', vreme, isoDate, excludePutnikId: excludePutnikId);

        result['VS']!.add(
          V2SlobodnaMesta(
            grad: 'VS',
            vreme: vreme,
            maxMesta: maxMesta,
            zauzetaMesta: zauzeto,
            aktivan: true,
            uceniciCount: ucenici,
          ),
        );
      }
    } catch (e) {
      debugPrint('[V2SlobodnaMestaService] getSlobodnaMesta VS error: $e');
    }

    return result;
  }

  /// Proveri da li ima slobodnih mesta za odredeni polazak
  static Future<bool> imaSlobodnihMesta(String grad, String vreme,
      {String? datum, String? tipPutnika, int brojMesta = 1, String? excludeId}) async {
    // POSILJKE: Ne zauzimaju mesto, pa uvek ima "mesta" za njih
    if (tipPutnika == 'posiljka') {
      return true;
    }

    // BC LOGIKA: Ucenici u Beloj Crkvi se auto-prihvataju (bez provere kapaciteta)
    if (grad.toUpperCase() == 'BC' && tipPutnika == 'ucenik') {
      return true;
    }

    // NORMALIZACIJA ULAZNOG VREMENA
    final targetVreme = GradAdresaValidator.normalizeTime(vreme);

    final slobodna = await getSlobodnaMesta(datum: datum, excludeId: excludeId);
    final lista = slobodna[grad.toUpperCase()];
    if (lista == null) return false;

    for (final s in lista) {
      // NORMALIZACIJA VREMENA IZ LISTE (Kapacitet table moze imati "6:00" umesto "06:00")
      final currentVreme = GradAdresaValidator.normalizeTime(s.vreme);
      if (currentVreme == targetVreme) {
        return s.slobodna >= brojMesta;
      }
    }
    return false;
  }

  /// Cisti realtime subscriptions
  static void dispose() {}
}
