import '../../utils/v3_date_utils.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'v3_finansije_service.dart';

enum V3ObracunPeriod {
  tekuciMesec,
  izabraniMesec,
  ukupno,
}

class V3PutnikObracunSummary {
  final V3ObracunPeriod period;
  final String periodLabel;
  final int ukupnoVoznji;
  final double cena;
  final double ukupanIznos;
  final int? godina;
  final int? mesec;

  const V3PutnikObracunSummary({
    required this.period,
    required this.periodLabel,
    this.ukupnoVoznji = 0,
    this.cena = 0,
    this.ukupanIznos = 0,
    this.godina,
    this.mesec,
  });
}

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

  static V3PutnikObracunSummary getObracunSummary({
    required String putnikId,
    required V3ObracunPeriod period,
    int? godina,
    int? mesec,
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final safePutnikId = putnikId.trim();

    if (safePutnikId.isEmpty) {
      return V3PutnikObracunSummary(
          period: period, periodLabel: _periodLabel(period: period, godina: godina, mesec: mesec));
    }

    final rm = V3MasterRealtimeManager.instance;
    final putnikData = rm.putniciCache[safePutnikId] ?? const <String, dynamic>{};
    final tip = (putnikData['tip_putnika'] as String? ?? 'dnevni').toLowerCase();
    final cenaPoDanu = (putnikData['cena_po_danu'] as num?)?.toDouble() ?? 0;
    final cenaPoPokupljenju = (putnikData['cena_po_pokupljenju'] as num?)?.toDouble() ?? 0;
    final koristiCenuPoDanu = tip == 'radnik' || tip == 'ucenik';
    final cena = koristiCenuPoDanu ? cenaPoDanu : cenaPoPokupljenju;

    ({int brojVoznji, double ukupanIznos}) finansijeSummary;
    int labelGodina = ref.year;
    int labelMesec = ref.month;

    if (period == V3ObracunPeriod.tekuciMesec) {
      finansijeSummary = V3FinansijeService.getNaplataSummaryForPutnik(
        putnikId: safePutnikId,
        godina: ref.year,
        mesec: ref.month,
      );
      labelGodina = ref.year;
      labelMesec = ref.month;
    } else if (period == V3ObracunPeriod.izabraniMesec) {
      final selectedGodina = godina ?? ref.year;
      final selectedMesec = mesec ?? ref.month;
      finansijeSummary = V3FinansijeService.getNaplataSummaryForPutnik(
        putnikId: safePutnikId,
        godina: selectedGodina,
        mesec: selectedMesec,
      );
      labelGodina = selectedGodina;
      labelMesec = selectedMesec;
    } else {
      finansijeSummary = V3FinansijeService.getNaplataSummaryForPutnik(
        putnikId: safePutnikId,
      );
    }

    final ukupanIznos =
        finansijeSummary.ukupanIznos > 0 ? finansijeSummary.ukupanIznos : finansijeSummary.brojVoznji * cena;
    return V3PutnikObracunSummary(
      period: period,
      periodLabel: _periodLabel(period: period, godina: labelGodina, mesec: labelMesec),
      ukupnoVoznji: finansijeSummary.brojVoznji,
      cena: cena,
      ukupanIznos: ukupanIznos,
      godina: period == V3ObracunPeriod.ukupno ? null : labelGodina,
      mesec: period == V3ObracunPeriod.ukupno ? null : labelMesec,
    );
  }

  static String _periodLabel({
    required V3ObracunPeriod period,
    int? godina,
    int? mesec,
  }) {
    switch (period) {
      case V3ObracunPeriod.tekuciMesec:
        return 'Tekući mesec';
      case V3ObracunPeriod.izabraniMesec:
        final safeMesec = mesec ?? DateTime.now().month;
        final safeGodina = godina ?? DateTime.now().year;
        return '${V3DateUtils.mesecNaziv(safeMesec)} $safeGodina';
      case V3ObracunPeriod.ukupno:
        return 'Ukupno';
    }
  }

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

    return _computeFromFinansije(
      putnikId: putnikId,
      godina: godina,
      mesec: mesec,
      mesecNaziv: mesecNaziv,
      tip: tip,
      cenaPoDanu: cenaPoDanu,
      cenaPoPokupljenju: cenaPoPokupljenju,
    );
  }

  static V3PutnikMesecnaStatistika _computeFromFinansije({
    required String putnikId,
    required int godina,
    required int mesec,
    required String mesecNaziv,
    required String tip,
    required double cenaPoDanu,
    required double cenaPoPokupljenju,
  }) {
    final summary = V3FinansijeService.getNaplataSummaryForPutnik(
      putnikId: putnikId,
      godina: godina,
      mesec: mesec,
    );

    final brojVoznji = summary.brojVoznji;
    final ukupnoUplaceno = summary.ukupanIznos;

    if (brojVoznji <= 0 && ukupnoUplaceno <= 0) {
      return V3PutnikMesecnaStatistika(godina: godina, mesec: mesec, mesecNaziv: mesecNaziv);
    }

    final isPoDanu = tip == 'radnik' || tip == 'ucenik' || tip == 'vozac';
    final cena = isPoDanu ? cenaPoDanu : cenaPoPokupljenju;
    final ukupnaObaveza = brojVoznji * cena;

    int placeno;
    if (cena > 0) {
      placeno = (ukupnoUplaceno / cena).floor();
      if (placeno > brojVoznji) placeno = brojVoznji;
      if (placeno < 0) placeno = 0;
    } else {
      placeno = brojVoznji;
    }

    final neplaceno = (brojVoznji - placeno).clamp(0, brojVoznji);
    final dugIznos = ukupnaObaveza > ukupnoUplaceno ? (ukupnaObaveza - ukupnoUplaceno) : 0.0;
    final naplacenoIznos = ukupnoUplaceno;

    return V3PutnikMesecnaStatistika(
      godina: godina,
      mesec: mesec,
      mesecNaziv: mesecNaziv,
      ukupnoVoznji: brojVoznji,
      pokupljeno: brojVoznji,
      placeno: placeno,
      otkazano: 0,
      neplaceno: neplaceno,
      naplacenoIznos: naplacenoIznos,
      dugIznos: dugIznos,
    );
  }

  static Set<(int, int)> _getMeseciSaPodacima(String putnikId) {
    return V3FinansijeService.getNaplataMeseciForPutnik(putnikId);
  }
}
