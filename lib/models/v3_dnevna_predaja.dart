/// Model za dnevne predaje vozača u V3 migraciji.
class V3DnevnaPredaja {
  final String id;
  final String? vozacId;
  final String? vozacImePrezime;
  final DateTime datum;
  final double predaoIznos;
  final double ukupnoNaplaceno;
  final double razlika;
  final String? napomena;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool aktivno;

  V3DnevnaPredaja({
    required this.id,
    this.vozacId,
    this.vozacImePrezime,
    required this.datum,
    this.predaoIznos = 0,
    this.ukupnoNaplaceno = 0,
    this.razlika = 0,
    this.napomena,
    this.createdAt,
    this.updatedAt,
    this.aktivno = true,
  });

  factory V3DnevnaPredaja.fromJson(Map<String, dynamic> json) {
    return V3DnevnaPredaja(
      id: json['id'] as String,
      vozacId: json['vozac_id'] as String?,
      vozacImePrezime: json['vozac_ime_prezime'] as String?,
      datum: json['datum'] != null ? DateTime.parse(json['datum'] as String) : DateTime.now(),
      predaoIznos: (json['predao_iznos'] as num?)?.toDouble() ?? 0,
      ukupnoNaplaceno: (json['ukupno_naplaceno'] as num?)?.toDouble() ?? 0,
      razlika: (json['razlika'] as num?)?.toDouble() ?? 0,
      napomena: json['napomena'] as String?,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String) : null,
      aktivno: json['aktivno'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'vozac_id': vozacId,
        'vozac_ime_prezime': vozacImePrezime,
        'datum': "${datum.year}-${datum.month.toString().padLeft(2, '0')}-${datum.day.toString().padLeft(2, '0')}",
        'predao_iznos': predaoIznos,
        'ukupno_naplaceno': ukupnoNaplaceno,
        'razlika': razlika,
        'napomena': napomena,
        'aktivno': aktivno,
      };

  V3DnevnaPredaja copyWith({
    String? id,
    String? vozacId,
    String? vozacImePrezime,
    DateTime? datum,
    double? predaoIznos,
    double? ukupnoNaplaceno,
    double? razlika,
    String? napomena,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? aktivno,
  }) {
    return V3DnevnaPredaja(
      id: id ?? this.id,
      vozacId: vozacId ?? this.vozacId,
      vozacImePrezime: vozacImePrezime ?? this.vozacImePrezime,
      datum: datum ?? this.datum,
      predaoIznos: predaoIznos ?? this.predaoIznos,
      ukupnoNaplaceno: ukupnoNaplaceno ?? this.ukupnoNaplaceno,
      razlika: razlika ?? this.razlika,
      napomena: napomena ?? this.napomena,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      aktivno: aktivno ?? this.aktivno,
    );
  }
}
