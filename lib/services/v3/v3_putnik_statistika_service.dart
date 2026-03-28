import '../../utils/v3_dan_helper.dart';
import '../realtime/v3_master_realtime_manager.dart';

class V3PutnikMesecnaStatistika {
  final int godina;
  final int mesec;
  final String mesecNaziv;
  final int ukupnoVoznji;
  final int pokupljeno;
  final int placeno;
  final int otkazano;
  final int neplaceno;
  final double naplacenoIznos;
  final double dugIznos;

  const V3PutnikMesecnaStatistika({
    required this.godina,
    required this.mesec,
    required this.mesecNaziv,
    this.ukupnoVoznji = 0,
    this.pokupljeno = 0,
    this.placeno = 0,
    this.otkazano = 0,
    this.neplaceno = 0,
    this.naplacenoIznos = 0,
    this.dugIznos = 0,
  });
}

class V3PutnikStatistikaService {
  V3PutnikStatistikaService._();

  static List<V3PutnikMesecnaStatistika> getZaGodinu(
    String putnikId, {
    required int godina,
  }) {
    return List.generate(
      12,
      (index) => getZaMesec(
        putnikId: putnikId,
        godina: godina,
        mesec: index + 1,
      ),
    );
  }

  static List<V3PutnikMesecnaStatistika> getPoslednjihMeseci(
    String putnikId, {
    int brojMeseci = 12,
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final rezultat = <V3PutnikMesecnaStatistika>[];

    for (int i = 0; i < brojMeseci; i++) {
      final target = DateTime(ref.year, ref.month - i, 1);
      rezultat.add(
        getZaMesec(
          putnikId: putnikId,
          godina: target.year,
          mesec: target.month,
        ),
      );
    }

    return rezultat;
  }

  static V3PutnikMesecnaStatistika getTekuciMesec(
    String putnikId, {
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    return getZaMesec(
      putnikId: putnikId,
      godina: ref.year,
      mesec: ref.month,
    );
  }

  static V3PutnikMesecnaStatistika getZaMesec({
    required String putnikId,
    required int godina,
    required int mesec,
  }) {
    final mesecNaziv = _mesecNaziv(mesec);
    if (putnikId.isEmpty) {
      return V3PutnikMesecnaStatistika(godina: godina, mesec: mesec, mesecNaziv: mesecNaziv);
    }

    final rm = V3MasterRealtimeManager.instance;
    final putnikData = rm.putniciCache[putnikId] ?? const <String, dynamic>{};
    final tip = (putnikData['tip_putnika'] as String? ?? 'dnevni').toLowerCase();
    final cenaPoDanu = (putnikData['cena_po_danu'] as num?)?.toDouble() ?? 0;
    final cenaPoPokupljenju = (putnikData['cena_po_pokupljenju'] as num?)?.toDouble() ?? 0;

    final rows = <Map<String, dynamic>>[];
    for (final row in rm.operativnaNedeljaCache.values) {
      if (row['putnik_id']?.toString() != putnikId) continue;
      if (row['aktivno'] == false) continue;
      final datum = _extractDatum(row);
      if (datum == null) continue;
      if (datum.year != godina || datum.month != mesec) continue;
      rows.add(row);
    }

    final isPoDanu = tip == 'radnik' || tip == 'ucenik';
    if (isPoDanu) {
      return _computePoDanu(
        rows: rows,
        godina: godina,
        mesec: mesec,
        mesecNaziv: mesecNaziv,
        cenaPoDanu: cenaPoDanu,
      );
    }

    return _computePoPokupljenju(
      rows: rows,
      godina: godina,
      mesec: mesec,
      mesecNaziv: mesecNaziv,
      cenaPoPokupljenju: cenaPoPokupljenju,
    );
  }

  static V3PutnikMesecnaStatistika _computePoDanu({
    required List<Map<String, dynamic>> rows,
    required int godina,
    required int mesec,
    required String mesecNaziv,
    required double cenaPoDanu,
  }) {
    final byDate = <String, List<Map<String, dynamic>>>{};
    final otkazanoDatumi = <String>{};

    for (final row in rows) {
      final datum = _extractDatum(row);
      if (datum == null) continue;
      final dateKey = V3DanHelper.toIsoDate(datum);
      if (_isOtkazano(row)) {
        otkazanoDatumi.add(dateKey);
        continue;
      }
      byDate.putIfAbsent(dateKey, () => <Map<String, dynamic>>[]).add(row);
    }

    int pokupljeno = 0;
    int voznji = 0;
    int placeno = 0;
    int neplaceno = 0;
    double naplacenoIznos = 0;

    for (final dayRows in byDate.values) {
      final hasPokupljen = dayRows.any(_isPokupljen);
      final paidRows = dayRows.where(_isPlaceno).toList();
      final hasPlaceno = paidRows.isNotEmpty;

      if (hasPokupljen) {
        voznji++;
        pokupljeno++;
        if (hasPlaceno) {
          placeno++;
          final dayPaid = paidRows
              .map((r) => _placeniIznosIliFallback(r, cenaPoDanu))
              .fold<double>(0, (maxSoFar, amount) => amount > maxSoFar ? amount : maxSoFar);
          naplacenoIznos += dayPaid;
        } else {
          neplaceno++;
        }
      }
    }

    return V3PutnikMesecnaStatistika(
      godina: godina,
      mesec: mesec,
      mesecNaziv: mesecNaziv,
      ukupnoVoznji: voznji,
      pokupljeno: pokupljeno,
      placeno: placeno,
      otkazano: otkazanoDatumi.length,
      neplaceno: neplaceno,
      naplacenoIznos: naplacenoIznos,
      dugIznos: neplaceno * cenaPoDanu,
    );
  }

  static V3PutnikMesecnaStatistika _computePoPokupljenju({
    required List<Map<String, dynamic>> rows,
    required int godina,
    required int mesec,
    required String mesecNaziv,
    required double cenaPoPokupljenju,
  }) {
    final aktivne = rows.where((r) => !_isOtkazano(r)).toList();
    final placeniRows = aktivne.where(_isPlaceno).toList();
    final pokupljeniRows = aktivne.where(_isPokupljen).toList();
    final dugRows = pokupljeniRows.where((r) => !_isPlaceno(r)).toList();

    final naplacenoIznos =
        placeniRows.fold<double>(0, (sum, r) => sum + _placeniIznosIliFallback(r, cenaPoPokupljenju));

    return V3PutnikMesecnaStatistika(
      godina: godina,
      mesec: mesec,
      mesecNaziv: mesecNaziv,
      ukupnoVoznji: pokupljeniRows.length,
      pokupljeno: pokupljeniRows.length,
      placeno: placeniRows.length,
      otkazano: rows.where(_isOtkazano).length,
      neplaceno: dugRows.length,
      naplacenoIznos: naplacenoIznos,
      dugIznos: dugRows.length * cenaPoPokupljenju,
    );
  }

  static bool _isPokupljen(Map<String, dynamic> row) => row['pokupljen'] == true;

  static bool _isPlaceno(Map<String, dynamic> row) =>
      (row['naplata_status']?.toString().toLowerCase() ?? 'nije_placeno') == 'placeno';

  static bool _isOtkazano(Map<String, dynamic> row) {
    final status = (row['status_final']?.toString() ?? row['status']?.toString() ?? '').toLowerCase();
    return status == 'otkazano';
  }

  static double _placeniIznosIliFallback(Map<String, dynamic> row, double fallback) {
    final iznos = (row['iznos_naplacen'] as num?)?.toDouble() ?? 0;
    return iznos > 0 ? iznos : fallback;
  }

  static DateTime? _extractDatum(Map<String, dynamic> row) {
    final raw = row['datum']?.toString();
    if (raw == null || raw.isEmpty) return null;
    final part = V3DanHelper.parseIsoDatePart(raw);
    return DateTime.tryParse(part);
  }

  static String _mesecNaziv(int m) {
    const names = [
      '',
      'Januar',
      'Februar',
      'Mart',
      'April',
      'Maj',
      'Jun',
      'Jul',
      'Avgust',
      'Septembar',
      'Oktobar',
      'Novembar',
      'Decembar',
    ];
    return (m >= 1 && m <= 12) ? names[m] : 'Mesec';
  }
}
