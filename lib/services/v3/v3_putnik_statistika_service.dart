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

class V3MesecniObracun {
  final int godina;
  final int mesec;
  final int brojVoznji;
  final double cena;
  final double obaveza;
  final double uplaceno;
  final double dug;

  const V3MesecniObracun({
    required this.godina,
    required this.mesec,
    required this.brojVoznji,
    required this.cena,
    required this.obaveza,
    required this.uplaceno,
    required this.dug,
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
  final double cena;
  final double ukupnaObaveza;

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
    this.cena = 0,
    this.ukupnaObaveza = 0,
  });
}

class V3PutnikMesecnoPoravnanje {
  final int godina;
  final int mesec;
  final String mesecNaziv;
  final int brojVoznji;
  final double cena;
  final double obaveza;
  final double uplata;
  final double saldoPocetak;
  final double saldoKraj;

  const V3PutnikMesecnoPoravnanje({
    required this.godina,
    required this.mesec,
    required this.mesecNaziv,
    required this.brojVoznji,
    required this.cena,
    required this.obaveza,
    required this.uplata,
    required this.saldoPocetak,
    required this.saldoKraj,
  });

  bool get uskladjenoPoslePrenosa => saldoKraj.abs() <= 0.009;
}

class V3PutnikGodisnjiPoravnanje {
  final int godina;
  final List<V3PutnikMesecnoPoravnanje> meseci;
  final double saldoNaPocetkuGodine;
  final double saldoNaKrajuGodine;
  final int ukupnoVoznji;
  final double ukupnaObaveza;
  final double ukupnoUplaceno;

  const V3PutnikGodisnjiPoravnanje({
    required this.godina,
    required this.meseci,
    required this.saldoNaPocetkuGodine,
    required this.saldoNaKrajuGodine,
    required this.ukupnoVoznji,
    required this.ukupnaObaveza,
    required this.ukupnoUplaceno,
  });

  bool get uskladjenoGodisnje => saldoNaKrajuGodine.abs() <= 0.009;
}

class V3PutnikStatistikaService {
  V3PutnikStatistikaService._();

  static bool _isPoDanuTip(String tip) {
    final normalized = tip.trim().toLowerCase();
    return normalized == 'radnik' || normalized == 'ucenik' || normalized == 'vozac';
  }

  static double _cenaZaTip({
    required String tip,
    required double cenaPoDanu,
    required double cenaPoPokupljenju,
  }) {
    return _isPoDanuTip(tip) ? cenaPoDanu : cenaPoPokupljenju;
  }

  static ({String tip, double cena}) _tipICena(String putnikId) {
    final rm = V3MasterRealtimeManager.instance;
    final putnikData = rm.putniciCache[putnikId] ?? const <String, dynamic>{};
    final tip = (putnikData['tip_putnika'] as String? ?? 'dnevni').toLowerCase();
    final cenaPoDanu = (putnikData['cena_po_danu'] as num?)?.toDouble() ?? 0;
    final cenaPoPokupljenju = (putnikData['cena_po_pokupljenju'] as num?)?.toDouble() ?? 0;
    final cena = _cenaZaTip(
      tip: tip,
      cenaPoDanu: cenaPoDanu,
      cenaPoPokupljenju: cenaPoPokupljenju,
    );
    return (tip: tip, cena: cena);
  }

  static V3MesecniObracun getMesecniObracun({
    required String putnikId,
    required int godina,
    required int mesec,
  }) {
    final safePutnikId = putnikId.trim();
    if (safePutnikId.isEmpty) {
      return V3MesecniObracun(
        godina: godina,
        mesec: mesec,
        brojVoznji: 0,
        cena: 0,
        obaveza: 0,
        uplaceno: 0,
        dug: 0,
      );
    }

    final tipICena = _tipICena(safePutnikId);
    final summary = V3FinansijeService.getNaplataSummaryForPutnik(
      putnikId: safePutnikId,
      godina: godina,
      mesec: mesec,
    );

    final brojVoznji = summary.brojVoznji;
    final cena = tipICena.cena;
    final obaveza = brojVoznji * cena;
    final uplaceno = summary.ukupanIznos;
    final dug = obaveza > uplaceno ? (obaveza - uplaceno) : 0.0;

    return V3MesecniObracun(
      godina: godina,
      mesec: mesec,
      brojVoznji: brojVoznji,
      cena: cena,
      obaveza: obaveza,
      uplaceno: uplaceno,
      dug: dug,
    );
  }

  static double _saldoDoGodine({
    required String putnikId,
    required int preGodine,
    required double cena,
  }) {
    var saldo = 0.0;
    final meseciSaPodacima = _getMeseciSaPodacima(putnikId);
    if (meseciSaPodacima.isEmpty) return 0.0;

    var startGodina = preGodine;
    for (final (godina, _) in meseciSaPodacima) {
      if (godina < startGodina) startGodina = godina;
    }

    for (var godina = startGodina; godina < preGodine; godina++) {
      for (var mesec = 1; mesec <= 12; mesec++) {
        final obracun = getMesecniObracun(
          putnikId: putnikId,
          godina: godina,
          mesec: mesec,
        );
        final obaveza = obracun.obaveza;
        final uplata = obracun.uplaceno;
        saldo += uplata - obaveza;
      }
    }

    return saldo;
  }

  static V3PutnikGodisnjiPoravnanje getGodisnjePoravnanje({
    required String putnikId,
    required int godina,
  }) {
    final safePutnikId = putnikId.trim();
    if (safePutnikId.isEmpty) {
      return V3PutnikGodisnjiPoravnanje(
        godina: godina,
        meseci: const <V3PutnikMesecnoPoravnanje>[],
        saldoNaPocetkuGodine: 0,
        saldoNaKrajuGodine: 0,
        ukupnoVoznji: 0,
        ukupnaObaveza: 0,
        ukupnoUplaceno: 0,
      );
    }

    final tipICena = _tipICena(safePutnikId);
    final cena = tipICena.cena;
    if (cena <= 0) {
      return V3PutnikGodisnjiPoravnanje(
        godina: godina,
        meseci: const <V3PutnikMesecnoPoravnanje>[],
        saldoNaPocetkuGodine: 0,
        saldoNaKrajuGodine: 0,
        ukupnoVoznji: 0,
        ukupnaObaveza: 0,
        ukupnoUplaceno: 0,
      );
    }
    var saldo = _saldoDoGodine(
      putnikId: safePutnikId,
      preGodine: godina,
      cena: cena,
    );
    final saldoNaPocetkuGodine = saldo;

    final stavke = <V3PutnikMesecnoPoravnanje>[];
    var ukupnoVoznji = 0;
    var ukupnaObaveza = 0.0;
    var ukupnoUplaceno = 0.0;

    for (var mesec = 1; mesec <= 12; mesec++) {
      final obracun = getMesecniObracun(
        putnikId: safePutnikId,
        godina: godina,
        mesec: mesec,
      );
      final brojVoznji = obracun.brojVoznji;
      final obaveza = obracun.obaveza;
      final uplata = obracun.uplaceno;
      final saldoPocetak = saldo;
      saldo = saldo + uplata - obaveza;

      stavke.add(
        V3PutnikMesecnoPoravnanje(
          godina: godina,
          mesec: mesec,
          mesecNaziv: V3DateUtils.mesecNaziv(mesec),
          brojVoznji: brojVoznji,
          cena: cena,
          obaveza: obaveza,
          uplata: uplata,
          saldoPocetak: saldoPocetak,
          saldoKraj: saldo,
        ),
      );

      ukupnoVoznji += brojVoznji;
      ukupnaObaveza += obaveza;
      ukupnoUplaceno += uplata;
    }

    return V3PutnikGodisnjiPoravnanje(
      godina: godina,
      meseci: stavke,
      saldoNaPocetkuGodine: saldoNaPocetkuGodine,
      saldoNaKrajuGodine: saldo,
      ukupnoVoznji: ukupnoVoznji,
      ukupnaObaveza: ukupnaObaveza,
      ukupnoUplaceno: ukupnoUplaceno,
    );
  }

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

    int ukupnoVoznji = 0;
    double ukupnaObaveza = 0;
    double ukupnoUplaceno = 0;
    int labelGodina = ref.year;
    int labelMesec = ref.month;

    if (period == V3ObracunPeriod.tekuciMesec) {
      final obracun = getMesecniObracun(
        putnikId: safePutnikId,
        godina: ref.year,
        mesec: ref.month,
      );
      ukupnoVoznji = obracun.brojVoznji;
      ukupnaObaveza = obracun.obaveza;
      ukupnoUplaceno = obracun.uplaceno;
      labelGodina = ref.year;
      labelMesec = ref.month;
    } else if (period == V3ObracunPeriod.izabraniMesec) {
      final selectedGodina = godina ?? ref.year;
      final selectedMesec = mesec ?? ref.month;
      final obracun = getMesecniObracun(
        putnikId: safePutnikId,
        godina: selectedGodina,
        mesec: selectedMesec,
      );
      ukupnoVoznji = obracun.brojVoznji;
      ukupnaObaveza = obracun.obaveza;
      ukupnoUplaceno = obracun.uplaceno;
      labelGodina = selectedGodina;
      labelMesec = selectedMesec;
    } else {
      final meseci = _getMeseciSaPodacima(safePutnikId)..add((ref.year, ref.month));
      for (final (g, m) in meseci) {
        final mObracun = getMesecniObracun(
          putnikId: safePutnikId,
          godina: g,
          mesec: m,
        );
        ukupnoVoznji += mObracun.brojVoznji;
        ukupnaObaveza += mObracun.obaveza;
        ukupnoUplaceno += mObracun.uplaceno;
      }
    }

    return V3PutnikObracunSummary(
      period: period,
      periodLabel: _periodLabel(period: period, godina: labelGodina, mesec: labelMesec),
      ukupnoVoznji: ukupnoVoznji,
      cena: ukupnoVoznji > 0 ? (ukupnaObaveza / ukupnoVoznji) : 0,
      ukupanIznos: ukupnaObaveza,
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
    final poravnanje = getGodisnjePoravnanje(
      putnikId: putnikId,
      godina: godina,
    );

    return poravnanje.meseci
        .map(
          (stavka) => V3PutnikMesecnaStatistika(
            godina: stavka.godina,
            mesec: stavka.mesec,
            mesecNaziv: stavka.mesecNaziv,
            ukupnoVoznji: stavka.brojVoznji,
            pokupljeno: stavka.brojVoznji,
            placeno: stavka.cena > 0 ? (stavka.uplata / stavka.cena).floor() : stavka.brojVoznji,
            otkazano: 0,
            neplaceno: stavka.cena > 0
                ? (stavka.brojVoznji - (stavka.uplata / stavka.cena).floor()).clamp(0, stavka.brojVoznji).toInt()
                : 0,
            naplacenoIznos: stavka.uplata,
            dugIznos: stavka.saldoKraj < 0 ? -stavka.saldoKraj : 0,
            cena: stavka.cena,
            ukupnaObaveza: stavka.obaveza,
          ),
        )
        .toList(growable: false);
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

    final obracun = getMesecniObracun(
      putnikId: putnikId,
      godina: godina,
      mesec: mesec,
    );

    if (obracun.brojVoznji <= 0 && obracun.uplaceno <= 0) {
      return V3PutnikMesecnaStatistika(godina: godina, mesec: mesec, mesecNaziv: mesecNaziv);
    }

    int placeno;
    if (obracun.cena > 0) {
      placeno = (obracun.uplaceno / obracun.cena).floor();
      if (placeno > obracun.brojVoznji) placeno = obracun.brojVoznji;
      if (placeno < 0) placeno = 0;
    } else {
      placeno = obracun.brojVoznji;
    }

    final neplaceno = (obracun.brojVoznji - placeno).clamp(0, obracun.brojVoznji);

    return V3PutnikMesecnaStatistika(
      godina: godina,
      mesec: mesec,
      mesecNaziv: mesecNaziv,
      ukupnoVoznji: obracun.brojVoznji,
      pokupljeno: obracun.brojVoznji,
      placeno: placeno,
      otkazano: 0,
      neplaceno: neplaceno,
      naplacenoIznos: obracun.uplaceno,
      dugIznos: obracun.dug,
      cena: obracun.cena,
      ukupnaObaveza: obracun.obaveza,
    );
  }

  static Set<(int, int)> _getMeseciSaPodacima(String putnikId) {
    return V3FinansijeService.getNaplataMeseciForPutnik(putnikId);
  }
}
