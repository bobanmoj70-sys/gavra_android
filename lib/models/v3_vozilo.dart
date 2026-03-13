class V3Vozilo {
  final String id;
  final String registracija;
  final String? marka;
  final String? model;
  final double trenutnaKm;
  final bool aktivno;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  V3Vozilo({
    required this.id,
    required this.registracija,
    this.marka,
    this.model,
    this.trenutnaKm = 0.0,
    this.aktivno = true,
    this.createdAt,
    this.updatedAt,
  });

  factory V3Vozilo.fromJson(Map<String, dynamic> json) {
    return V3Vozilo(
      id: json['id'] as String? ?? '',
      registracija: json['registracija'] as String? ?? '',
      marka: json['marka'] as String?,
      model: json['model'] as String?,
      trenutnaKm: (json['trenutna_km'] as num?)?.toDouble() ?? 0.0,
      aktivno: json['aktivno'] as bool? ?? true,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'registracija': registracija,
      'marka': marka,
      'model': model,
      'trenutna_km': trenutnaKm,
      'aktivno': aktivno,
    };
  }
}
