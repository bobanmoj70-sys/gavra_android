import '../models/v2_putnik.dart';

/// V2Putnik HELPERS - Centralizovane funkcije za proveru statusa putnika
///
/// Ove funkcije koriste V2Putnik getters za potpunu proveru, uključujući:
/// - jeOtkazan (proverava obrisan, otkazanZaPolazak, status)
/// - jeOdsustvo (proverava bolovanje, godišnji)
///
/// ## Razlike od V2TextUtils.isStatusActive:
/// - V2TextUtils.isStatusActive proverava SAMO string status
/// - V2PutnikHelpers.shouldCountInSeats koristi V2Putnik getters za potpunu proveru
class V2PutnikHelpers {
  V2PutnikHelpers._();

  /// Da li V2Putnik treba da se RAČUNA u broju zauzetih mesta
  ///
  /// Ne računa:
  /// - Otkazane (jeOtkazan: obrisan, otkazanZaPolazak, status='otkazano')
  /// - Odsustvo (jeOdsustvo: bolovanje, godišnji)
  ///
  /// Koristi za: brojčanike na tabovima, slobodna mesta, optimizaciju rute
  static bool shouldCountInSeats(V2Putnik p) {
    // Ne računaj ako je otkazan (uključuje obrisan flag i otkazanZaPolazak)
    // Takođe ne računaj ako je uklonjen polazak (bez_polaska)
    if (p.jeOtkazan || p.jeBezPolaska) return false;

    // Ne računaj ako je na čekanju (obrada) - zauzima mesto tek kad je odobreno
    if (p.status?.toLowerCase() == 'obrada') return false;

    // Ne računaj ako je na odsustvu (bolovanje/godišnji)
    if (p.jeOdsustvo) return false;

    // POŠILJKE NE ZAUZIMAJU MESTA
    if (p.tipPutnika == 'posiljka') return false;

    return true;
  }

  /// Da li V2Putnik treba da ima REDNI BROJ u listi
  ///
  /// Isto kao shouldCountInSeats - putnici koji se ne broje u mesta
  /// ne treba da imaju redni broj
  static bool shouldHaveOrdinalNumber(V2Putnik p) {
    return shouldCountInSeats(p);
  }

  /// Vraća radni ISO datum (yyyy-MM-dd)
  static String getWorkingDateIso() {
    final now = DateTime.now();
    // Vikend (sub=6, ned=7) → naredni ponedeljak
    if (now.weekday == DateTime.saturday) {
      return now.add(const Duration(days: 2)).toIso8601String().split('T')[0];
    } else if (now.weekday == DateTime.sunday) {
      return now.add(const Duration(days: 1)).toIso8601String().split('T')[0];
    }
    return now.toIso8601String().split('T')[0];
  }
}
