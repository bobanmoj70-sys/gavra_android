import 'package:flutter/foundation.dart';

import '../models/v2_putnik.dart';
import '../utils/v2_grad_adresa_validator.dart';
import '../utils/v2_putnik_helpers.dart';
import 'v2_kapacitet_service.dart';
import 'v2_putnik_stream_service.dart';

/// ?? Model za slobodna mesta po polasku
class SlobodnaMesta {
  final String grad;
  final String vreme;
  final int maxMesta;
  final int zauzetaMesta;
  final int uceniciCount;
  final bool aktivan;

  SlobodnaMesta({
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
}

class SlobodnaMestaService {
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
      // ??? AKO RADIMO UPDATE: Iskljuci putnika koga menjamo da ne bi sam sebi zauzimao mesto
      if (excludePutnikId != null && p.id?.toString() == excludePutnikId.toString()) {
        continue;
      }

      // ?? REFAKTORISANO: Koristi PutnikHelpers za konzistentnu logiku
      // Ne racuna: otkazane (jeOtkazan), odsustvo (jeOdsustvo)
      if (!PutnikHelpers.shouldCountInSeats(p)) continue;

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
    final targetDayAbbr = _isoDateToDayAbbr(isoDate);

    int count = 0;
    for (final p in putnici) {
      if (excludePutnikId != null && p.id?.toString() == excludePutnikId.toString()) {
        continue;
      }

      // Isti filteri kao za putnike (bez otkazanih, itd)
      if (!PutnikHelpers.shouldCountInSeats(p)) continue;

      // Filter: SAMO UCENICI
      if (p.tipPutnika != 'ucenik') continue;

      // Filtriraj po dan kraticama (v2_polasci nema datum kolonu)
      if (!p.dan.toLowerCase().contains(targetDayAbbr.toLowerCase())) continue;

      // Proveri vreme
      final normVreme = GradAdresaValidator.normalizeTime(p.polazak);
      if (normVreme != vreme) continue;

      // Proveri grad
      if ((normalizedGrad == 'BC' && p.grad == 'BC') || (normalizedGrad == 'VS' && p.grad == 'VS')) {
        count += p.brojMesta.toInt();
      }
    }

    return count;
  }

  /// Dohvati slobodna mesta po gradu za odredeni datum
  static Future<Map<String, List<SlobodnaMesta>>> getSlobodnaMesta({String? datum, String? excludeId}) async {
    final isoDate = datum ?? DateTime.now().toIso8601String().split('T')[0];
    final excludePutnikId = excludeId;

    final result = <String, List<SlobodnaMesta>>{
      'BC': [],
      'VS': [],
    };

    try {
      final putnici = await _putnikService.getPutniciByDayIso(isoDate);
      final kapacitet = await V2KapacitetService.getKapacitet();

      // Bela Crkva
      final bcKapaciteti = kapacitet['BC'] ?? {};
      final bcVremenaSorted = bcKapaciteti.keys.toList()..sort();

      for (final vreme in bcVremenaSorted) {
        final maxMesta = bcKapaciteti[vreme] ?? 8;
        final zauzeto = _countPutniciZaPolazak(putnici, 'BC', vreme, isoDate, excludePutnikId: excludePutnikId);
        final ucenici = _countUceniciZaPolazak(putnici, 'BC', vreme, isoDate, excludePutnikId: excludePutnikId);

        result['BC']!.add(
          SlobodnaMesta(
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
      debugPrint('❌ getSlobodnaMesta BC error: $e');
    }

    try {
      final putnici = await _putnikService.getPutniciByDayIso(isoDate);
      final kapacitet = await V2KapacitetService.getKapacitet();

      // Vrsac - Koristi SVA vremena iz kapaciteta
      final vsKapaciteti = kapacitet['VS'] ?? {};
      final vsVremenaSorted = vsKapaciteti.keys.toList()..sort();

      for (final vreme in vsVremenaSorted) {
        final maxMesta = vsKapaciteti[vreme] ?? 8;
        final zauzeto = _countPutniciZaPolazak(putnici, 'VS', vreme, isoDate, excludePutnikId: excludePutnikId);
        final ucenici = _countUceniciZaPolazak(putnici, 'VS', vreme, isoDate, excludePutnikId: excludePutnikId);

        result['VS']!.add(
          SlobodnaMesta(
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
      debugPrint('❌ getSlobodnaMesta VS error: $e');
    }

    return result;
  }

  /// Proveri da li ima slobodnih mesta za odredeni polazak
  static Future<bool> imaSlobodnihMesta(String grad, String vreme,
      {String? datum, String? tipPutnika, int brojMesta = 1, String? excludeId}) async {
    // ?? POŠILJKE: Ne zauzimaju mesto, pa uvek ima "mesta" za njih
    if (tipPutnika == 'posiljka') {
      return true;
    }

    // ?? BC LOGIKA: Ucenici u Beloj Crkvi se auto-prihvataju (bez provere kapaceta)
    if (grad.toUpperCase() == 'BC' && tipPutnika == 'ucenik') {
      return true;
    }

    // ??? NORMALIZACIJA ULAZNOG VREMENA
    final targetVreme = GradAdresaValidator.normalizeTime(vreme);

    final slobodna = await getSlobodnaMesta(datum: datum, excludeId: excludeId);
    final lista = slobodna[grad.toUpperCase()];
    if (lista == null) return false;

    for (final s in lista) {
      // ??? NORMALIZACIJA VREMENA IZ LISTE (Kapacitet table može imati "6:00" umesto "06:00")
      final currentVreme = GradAdresaValidator.normalizeTime(s.vreme);
      if (currentVreme == targetVreme) {
        return s.slobodna >= brojMesta;
      }
    }
    return false;
  }

  /// ?? Cisti realtime subscriptions
  static void dispose() {}
}
