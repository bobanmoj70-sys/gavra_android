class V3GorivoStanje {
  final double kolicina;
  final DateTime updatedAt;

  V3GorivoStanje({
    required this.kolicina,
    required this.updatedAt,
  });

  factory V3GorivoStanje.fromJson(Map<String, dynamic> json) {
    return V3GorivoStanje(
      kolicina: (json['kolicina'] as num).toDouble(),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'kolicina': kolicina,
        'updated_at': updatedAt.toIso8601String(),
      };
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
      id: json['id'],
      kolicina: (json['kolicina'] as num).toDouble(),
      dobavljac: json['dobavljac'],
      opis: json['opis'],
      datum: DateTime.parse(json['datum']),
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
      id: json['id'],
      voziloId: json['vozilo_id'],
      kolicina: (json['kolicina'] as num).toDouble(),
      kilometraza: json['kilometraza'],
      vozacId: json['vozac_id'],
      datum: DateTime.parse(json['datum']),
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
