import '../../utils/v3_dan_helper.dart';
import '../../utils/v3_date_utils.dart';
import '../../utils/v3_status_policy.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'v3_finansije_service.dart';

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

  static double getUkupanDugZaSveMesece(
    String putnikId, {
    DateTime? now,
  }) {
    if (putnikId.isEmpty) return 0;

    final ref = now ?? DateTime.now();
    final meseci = _getMeseciSaPodacima(putnikId)..add((ref.year, ref.month));

    double ukupno = 0;
    for (final (godina, mesec) in meseci) {
      final stat = getZaMesec(putnikId: putnikId, godina: godina, mesec: mesec);
      ukupno += stat.dugIznos;
    }

    return ukupno;
  }

  static V3PutnikMesecnaStatistika getZaMesec({
    required String putnikId,
    required int godina,
    required int mesec,
  }) {
    final mesecNaziv = V3DateUtils.mesecNaziv(mesec);
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
      final rowPutnikId = row['created_by']?.toString();
      if (rowPutnikId != putnikId) continue;
      final datum = _extractDatum(row);
      if (datum == null) continue;
      if (datum.year != godina || datum.month != mesec) continue;
      rows.add(row);
    }

    final isPoDanu = tip == 'radnik' || tip == 'ucenik' || tip == 'vozac';
    if (isPoDanu) {
      return _computePoDanu(
        putnikId: putnikId,
        rows: rows,
        godina: godina,
        mesec: mesec,
        mesecNaziv: mesecNaziv,
        cenaPoDanu: cenaPoDanu,
      );
    }

    return _computePoPokupljenju(
      rows: rows,
      putnikId: putnikId,
      godina: godina,
      mesec: mesec,
      mesecNaziv: mesecNaziv,
      cenaPoPokupljenju: cenaPoPokupljenju,
    );
  }

  static V3PutnikMesecnaStatistika _computePoDanu({
    required String putnikId,
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
    final ukupnoUplaceno = V3FinansijeService.sumOperativnaUplateZaPutnikMesec(
      putnikId: putnikId,
      godina: godina,
      mesec: mesec,
    );

    for (final dayRows in byDate.values) {
      final hasPokupljen = dayRows.any(_isPokupljen);

      if (hasPokupljen) {
        voznji++;
        pokupljeno++;
      }
    }

    final ukupnaObaveza = voznji * cenaPoDanu;
    final kredit = ukupnoUplaceno - ukupnaObaveza;
    final naplacenoIznos = kredit > 0 ? kredit : 0.0;
    final dugIznos = kredit < 0 ? -kredit : 0.0;

    int placeno = 0;
    if (cenaPoDanu > 0) {
      placeno = (ukupnoUplaceno / cenaPoDanu).floor();
      if (placeno > voznji) placeno = voznji;
    } else {
      placeno = voznji;
    }
    final neplaceno = (voznji - placeno).clamp(0, voznji);

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
      dugIznos: dugIznos,
    );
  }

  static V3PutnikMesecnaStatistika _computePoPokupljenju({
    required List<Map<String, dynamic>> rows,
    required String putnikId,
    required int godina,
    required int mesec,
    required String mesecNaziv,
    required double cenaPoPokupljenju,
  }) {
    final naplataByOperativna = V3FinansijeService.getLatestNaplataByOperativnaForPutnikMesec(
      putnikId: putnikId,
      godina: godina,
      mesec: mesec,
    );
    final aktivne = rows.where((r) => !_isOtkazano(r)).toList();
    final placeniRows = aktivne.where((r) => _isPlaceno(r, naplataByOperativna)).toList();
    final pokupljeniRows = aktivne.where(_isPokupljen).toList();
    final dugRows = pokupljeniRows.where((r) => !_isPlaceno(r, naplataByOperativna)).toList();

    final naplacenoIznos = placeniRows.fold<double>(
      0,
      (sum, r) => sum + _placeniIznosIliFallback(r, cenaPoPokupljenju, naplataByOperativna),
    );

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

  static bool _isPokupljen(Map<String, dynamic> row) => V3StatusPolicy.isTimestampSet(row['pokupljen_at']);

  static bool _isPlaceno(Map<String, dynamic> row, Map<String, Map<String, dynamic>> naplataByOperativna) {
    final operativnaId = row['id']?.toString() ?? '';
    return operativnaId.isNotEmpty && naplataByOperativna.containsKey(operativnaId);
  }

  static bool _isOtkazano(Map<String, dynamic> row) {
    return row['otkazano_at'] != null;
  }

  static double _placeniIznosIliFallback(
    Map<String, dynamic> row,
    double fallback,
    Map<String, Map<String, dynamic>> naplataByOperativna,
  ) {
    final operativnaId = row['id']?.toString() ?? '';
    if (operativnaId.isNotEmpty) {
      final naplata = naplataByOperativna[operativnaId];
      if (naplata != null) {
        final iznosFin = (naplata['iznos'] as num?)?.toDouble() ?? 0;
        return iznosFin > 0 ? iznosFin : fallback;
      }
    }
    return fallback;
  }

  static DateTime? _extractDatum(Map<String, dynamic> row) {
    final raw = row['datum']?.toString();
    if (raw == null || raw.isEmpty) return null;
    final part = V3DateUtils.parseIsoDatePart(raw);
    return DateTime.tryParse(part);
  }

  static Set<(int, int)> _getMeseciSaPodacima(String putnikId) {
    final meseci = <(int, int)>{};
    final rows = V3MasterRealtimeManager.instance.operativnaNedeljaCache.values;

    for (final row in rows) {
      final rowPutnikId = row['created_by']?.toString();
      if (rowPutnikId != putnikId) continue;
      final datum = _extractDatum(row);
      if (datum == null) continue;
      meseci.add((datum.year, datum.month));
    }

    return meseci;
  }
}
