class V3Vozilo {
  final String id;
  final String registracija;
  final String? marka;
  final String? model;
  final int? godiste;
  final int brojSedista;
  final double trenutnaKm;
  final DateTime? registracijaIstice;
  final int? maliServisKm;
  final int? velikiServisKm;
  final DateTime? servisKlimeDatum;
  final String? gumeZimske;
  final String? gumeLetnje;
  final bool aktivno;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  V3Vozilo({
    required this.id,
    required this.registracija,
    this.marka,
    this.model,
    this.godiste,
    this.brojSedista = 1,
    this.trenutnaKm = 0.0,
    this.registracijaIstice,
    this.maliServisKm,
    this.velikiServisKm,
    this.servisKlimeDatum,
    this.gumeZimske,
    this.gumeLetnje,
    this.aktivno = true,
    this.createdAt,
    this.updatedAt,
  });

  String get naziv => marka != null ? '$marka $model' : (model ?? registracija);

  factory V3Vozilo.fromJson(Map<String, dynamic> json) {
    return V3Vozilo(
      id: json['id'] as String? ?? '',
      registracija: json['registracija'] as String? ?? '',
      marka: json['marka'] as String?,
      model: json['model'] as String?,
      godiste: json['godiste'] as int?,
      brojSedista: json['broj_sedista'] as int? ?? 1,
      trenutnaKm: (json['trenutna_km'] as num?)?.toDouble() ?? 0.0,
      registracijaIstice:
          json['registracija_istice'] != null ? DateTime.tryParse(json['registracija_istice'] as String) : null,
      maliServisKm: json['mali_servis_km'] as int?,
      velikiServisKm: json['veliki_servis_km'] as int?,
      servisKlimeDatum:
          json['servis_klime_datum'] != null ? DateTime.tryParse(json['servis_klime_datum'] as String) : null,
      gumeZimske: json['gume_zimske'] as String?,
      gumeLetnje: json['gume_letnje'] as String?,
      aktivno: json['aktivno'] as bool? ?? true,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'registracija': registracija,
      'marka': marka,
      'model': model,
      'godiste': godiste,
      'broj_sedista': brojSedista,
      'trenutna_km': trenutnaKm,
      'registracija_istice': registracijaIstice?.toIso8601String().split('T')[0],
      'mali_servis_km': maliServisKm,
      'veliki_servis_km': velikiServisKm,
      'servis_klime_datum': servisKlimeDatum?.toIso8601String().split('T')[0],
      'gume_zimske': gumeZimske,
      'gume_letnje': gumeLetnje,
      'aktivno': aktivno,
    };
  }
}
