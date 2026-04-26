/// Model za tabelu v3_gorivo
library;

class V3PumpaStanje {
  final String id;

  final String naziv;

  final double kapacitetLitri;

  final double trenutnoStanje;

  final double stanjeBrojacPistolj;

  V3PumpaStanje({
    required this.id,
    this.naziv = 'Kucna Pumpa',
    this.kapacitetLitri = 0,
    required this.trenutnoStanje,
    this.stanjeBrojacPistolj = 0,
  });

  factory V3PumpaStanje.fromJson(Map<String, dynamic> json) {
    return V3PumpaStanje(
      id: json['id']?.toString() ?? '',
      naziv: json['naziv'] as String? ?? 'Kucna Pumpa',
      kapacitetLitri: (json['kapacitet_litri'] as num?)?.toDouble() ?? 0,
      trenutnoStanje: (json['trenutno_stanje_litri'] as num?)?.toDouble() ?? 0,
      stanjeBrojacPistolj: (json['brojac_pistolj_litri'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'kapacitet_litri': kapacitetLitri,
        'trenutno_stanje_litri': trenutnoStanje,
        'brojac_pistolj_litri': stanjeBrojacPistolj,
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
