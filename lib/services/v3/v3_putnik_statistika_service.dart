import '../../utils/v3_dan_helper.dart';
import '../../utils/v3_status_filters.dart';
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
    final ukupnoUplaceno = _sumUplateZaMesec(
      putnikId: putnikId,
      godina: godina,
      mesec: mesec,
      isPoDanu: true,
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
    final naplataByOperativna = _latestNaplataByOperativna(
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

  static bool _isPokupljen(Map<String, dynamic> row) => V3StatusFilters.isPokupljenAt(row['pokupljen_at']);

  static bool _isPlaceno(Map<String, dynamic> row, Map<String, Map<String, dynamic>> naplataByOperativna) {
    final operativnaId = row['id']?.toString() ?? '';
    if (operativnaId.isNotEmpty && naplataByOperativna.containsKey(operativnaId)) {
      return true;
    }
    return V3StatusFilters.isNaplacenAt(row['naplacen_at']);
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
    final iznos = (row['naplacen_iznos'] as num?)?.toDouble() ?? 0;
    return iznos > 0 ? iznos : fallback;
  }

  static Map<String, Map<String, dynamic>> _latestNaplataByOperativna({
    required String putnikId,
    required int godina,
    required int mesec,
  }) {
    final rows = V3MasterRealtimeManager.instance.getCache('v3_finansije').values;
    final result = <String, Map<String, dynamic>>{};

    for (final row in rows) {
      if (row['tip']?.toString() != 'prihod') continue;
      if ((row['kategorija']?.toString().toLowerCase() ?? '') != 'operativna_naplata') continue;
      if (row['putnik_v3_auth_id']?.toString() != putnikId) continue;

      final rowGodina = (row['godina'] as num?)?.toInt();
      final rowMesec = (row['mesec'] as num?)?.toInt();
      if (rowGodina != godina || rowMesec != mesec) continue;

      final operativnaId = row['operativna_id']?.toString() ?? '';
      if (operativnaId.isEmpty) continue;

      final existing = result[operativnaId];
      if (existing == null) {
        result[operativnaId] = row;
        continue;
      }

      final existingTs = DateTime.tryParse(existing['created_at']?.toString() ?? '') ?? DateTime(2000);
      final currentTs = DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime(2000);
      if (currentTs.isAfter(existingTs)) {
        result[operativnaId] = row;
      }
    }

    return result;
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

  static double _sumUplateZaMesec({
    required String putnikId,
    required int godina,
    required int mesec,
    required bool isPoDanu,
  }) {
    final arhiva = V3MasterRealtimeManager.instance.getCache('v3_finansije').values;

    return arhiva.where((row) {
      if (row['tip'] != 'prihod') return false;
      if (row['putnik_v3_auth_id']?.toString() != putnikId) return false;
      if ((row['godina'] as int?) != godina) return false;
      if ((row['mesec'] as int?) != mesec) return false;
      final kategorija = (row['kategorija']?.toString() ?? '').toLowerCase();
      if (isPoDanu) {
        return kategorija == 'operativna_naplata';
      }
      return kategorija == 'operativna_naplata';
    }).fold<double>(0, (sum, row) => sum + ((row['iznos'] as num?)?.toDouble() ?? 0));
  }
}
