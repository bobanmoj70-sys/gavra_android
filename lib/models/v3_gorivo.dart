/// Model za tabelu v3_pumpa_stanje
library;

class V3PumpaStanje {
  final String id;

  final String naziv;

  final double kapacitetLitri;

  final double trenutnoStanje;

  final double stanjeBrojacPistolj;

  final bool aktivno;

  final DateTime? updatedAt;

  final DateTime? createdAt;

  V3PumpaStanje({
    required this.id,
    this.naziv = 'Kucna Pumpa',
    this.kapacitetLitri = 0,
    required this.trenutnoStanje,
    this.stanjeBrojacPistolj = 0,
    this.aktivno = true,
    this.updatedAt,
    this.createdAt,
  });

  factory V3PumpaStanje.fromJson(Map<String, dynamic> json) {
    return V3PumpaStanje(
      id: json['id']?.toString() ?? '',
      naziv: json['naziv'] as String? ?? 'Kucna Pumpa',
      kapacitetLitri: (json['kapacitet_litri'] as num?)?.toDouble() ?? 0,
      trenutnoStanje: (json['trenutno_stanje'] as num?)?.toDouble() ?? 0,
      stanjeBrojacPistolj: (json['stanje_brojac_pistolj'] as num?)?.toDouble() ?? 0,
      aktivno: json['aktivno'] as bool? ?? true,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'naziv': naziv,
        'kapacitet_litri': kapacitetLitri,
        'trenutno_stanje': trenutnoStanje,
        'stanje_brojac_pistolj': stanjeBrojacPistolj,
        'aktivno': aktivno,
      };
}

/// Model za tabelu v3_pumpa_rezervoar

class V3PumpaRezervoar {
  final String id;

  final double kapacitetMax;

  final double trenutnoLitara;

  final double alarmNivo;

  final DateTime? updatedAt;

  final DateTime? createdAt;

  V3PumpaRezervoar({
    required this.id,
    this.kapacitetMax = 3000,
    required this.trenutnoLitara,
    this.alarmNivo = 500,
    this.updatedAt,
    this.createdAt,
  });

  factory V3PumpaRezervoar.fromJson(Map<String, dynamic> json) {
    return V3PumpaRezervoar(
      id: json['id']?.toString() ?? '',
      kapacitetMax: (json['kapacitet_max'] as num?)?.toDouble() ?? 3000,
      trenutnoLitara: (json['trenutno_litara'] as num?)?.toDouble() ?? 0,
      alarmNivo: (json['alarm_nivo'] as num?)?.toDouble() ?? 500,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'kapacitet_max': kapacitetMax,
        'trenutno_litara': trenutnoLitara,
        'alarm_nivo': alarmNivo,
      };

  bool get ispodAlarma => trenutnoLitara <= alarmNivo;

  double get procentPunjenosti => kapacitetMax > 0 ? (trenutnoLitara / kapacitetMax * 100).clamp(0, 100) : 0;
}

/// Backward-compat alias (stari kod može koristiti V3GorivoStanje)

@Deprecated('Koristi V3PumpaStanje umjesto V3GorivoStanje')
class V3GorivoStanje {
  final double kolicina;

  final DateTime updatedAt;

  V3GorivoStanje({required this.kolicina, required this.updatedAt});

  factory V3GorivoStanje.fromJson(Map<String, dynamic> json) {
    return V3GorivoStanje(
      kolicina: (json['trenutno_stanje'] as num?)?.toDouble() ?? (json['kolicina'] as num?)?.toDouble() ?? 0,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class V3PumpaPunjenje {
  final String id;

  final double kolicina;

  final String? dobavljac;

  final String? opis;

  final DateTime datum;

  V3PumpaPunjenje({
    required this.id,
    required this.kolicina,
    this.dobavljac,
    this.opis,
    required this.datum,
  });

  factory V3PumpaPunjenje.fromJson(Map<String, dynamic> json) {
    return V3PumpaPunjenje(
      id: json['id']?.toString() ?? '',
      kolicina: (json['kolicina'] as num).toDouble(),
      dobavljac: json['dobavljac'] as String?,
      opis: json['opis'] as String?,
      datum: DateTime.parse(json['datum'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'kolicina': kolicina,
        'dobavljac': dobavljac,
        'opis': opis,
        'datum': datum.toIso8601String(),
      };
}

class V3PumpaTocenje {
  final String id;

  final String voziloId;

  final double kolicina;

  final int? kilometraza;

  final String? vozacId;

  final DateTime datum;

  V3PumpaTocenje({
    required this.id,
    required this.voziloId,
    required this.kolicina,
    this.kilometraza,
    this.vozacId,
    required this.datum,
  });

  factory V3PumpaTocenje.fromJson(Map<String, dynamic> json) {
    return V3PumpaTocenje(
      id: json['id']?.toString() ?? '',
      voziloId: json['vozilo_id']?.toString() ?? '',
      kolicina: (json['kolicina'] as num).toDouble(),
      kilometraza: json['kilometraza'] as int?,
      vozacId: json['vozac_id']?.toString(),
      datum: DateTime.parse(json['datum'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'vozilo_id': voziloId,
        'kolicina': kolicina,
        'kilometraza': kilometraza,
        'vozac_id': vozacId,
        'datum': datum.toIso8601String(),
      };
}
