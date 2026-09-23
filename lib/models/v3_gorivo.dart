/// Model za tabelu v3_gorivo
library;

class V3PumpaStanje {
  final String id;
  final double kapacitetLitri;
  final double trenutnoStanje;
  final double alarmNivoLitri;
  final double stanjeBrojacPistolj;
  final double cenaPoLitru;
  final double dugIznos;

  V3PumpaStanje({
    required this.id,
    this.kapacitetLitri = 0,
    required this.trenutnoStanje,
    this.alarmNivoLitri = 500,
    this.stanjeBrojacPistolj = 0,
    this.cenaPoLitru = 0,
    this.dugIznos = 0,
  });

  factory V3PumpaStanje.fromJson(Map<String, dynamic> json) {
    return V3PumpaStanje(
      id: json['id']?.toString() ?? '',
      kapacitetLitri: (json['kapacitet_litri'] as num?)?.toDouble() ?? 0,
      trenutnoStanje: (json['trenutno_stanje_litri'] as num?)?.toDouble() ?? 0,
      alarmNivoLitri: (json['alarm_nivo_litri'] as num?)?.toDouble() ?? 500,
      stanjeBrojacPistolj: (json['brojac_pistolj_litri'] as num?)?.toDouble() ?? 0,
      cenaPoLitru: (json['cena_po_litru'] as num?)?.toDouble() ?? 0,
      dugIznos: (json['dug_iznos'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'kapacitet_litri': kapacitetLitri,
        'trenutno_stanje_litri': trenutnoStanje,
        'alarm_nivo_litri': alarmNivoLitri,
        'brojac_pistolj_litri': stanjeBrojacPistolj,
        'cena_po_litru': cenaPoLitru,
        'dug_iznos': dugIznos,
      };
}

/// Model za tabelu v3_gorivo (rezervoar pogled)

class V3PumpaRezervoar {
  final String id;

  final double kapacitetMax;

  final double trenutnoLitara;

  final double alarmNivo;

  V3PumpaRezervoar({
    required this.id,
    this.kapacitetMax = 3000,
    required this.trenutnoLitara,
    this.alarmNivo = 500,
  });

  factory V3PumpaRezervoar.fromJson(Map<String, dynamic> json) {
    return V3PumpaRezervoar(
      id: json['id']?.toString() ?? '',
      kapacitetMax: (json['kapacitet_litri'] as num?)?.toDouble() ?? 3000,
      trenutnoLitara: (json['trenutno_stanje_litri'] as num?)?.toDouble() ?? 0,
      alarmNivo: (json['alarm_nivo_litri'] as num?)?.toDouble() ?? 500,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'kapacitet_litri': kapacitetMax,
        'trenutno_stanje_litri': trenutnoLitara,
        'alarm_nivo_litri': alarmNivo,
      };

  bool get ispodAlarma => trenutnoLitara <= alarmNivo;

  double get procentPunjenosti => kapacitetMax > 0 ? (trenutnoLitara / kapacitetMax * 100).clamp(0, 100) : 0;
}

class V3GorivoIstorijaEntry {
  final String id;
  final String vrsta;
  final double litri;
  final DateTime createdAt;

  const V3GorivoIstorijaEntry({
    required this.id,
    required this.vrsta,
    required this.litri,
    required this.createdAt,
  });

  factory V3GorivoIstorijaEntry.fromJson(Map<String, dynamic> json, DateTime createdAt) {
    return V3GorivoIstorijaEntry(
      id: json['id']?.toString() ?? '',
      vrsta: (json['vrsta']?.toString() ?? '').toLowerCase(),
      litri: (json['litri'] as num?)?.toDouble() ?? 0,
      createdAt: createdAt,
    );
  }
}

class V3GorivoPotrosnjaPregled {
  final double danasLitri;
  final double nedeljaLitri;
  final double mesecLitri;
  final double godinaLitri;
  final String danasPeriod;
  final String nedeljaPeriod;

  const V3GorivoPotrosnjaPregled({
    required this.danasLitri,
    required this.nedeljaLitri,
    required this.mesecLitri,
    required this.godinaLitri,
    required this.danasPeriod,
    required this.nedeljaPeriod,
  });
}
