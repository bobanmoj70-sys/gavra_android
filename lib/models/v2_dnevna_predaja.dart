/// Model za dnevnu predaju novca vozača (v2_dnevna_predaja tabela)
class V2DnevnaPredaja {
  final String id;
  final String vozacIme;
  final DateTime datum;
  final double predaoIznos;
  final double? ukupnoNaplaceno;
  final double? razlika;
  final String? napomena;
  final DateTime updatedAt;

  V2DnevnaPredaja({
    required this.id,
    required this.vozacIme,
    required this.datum,
    required this.predaoIznos,
    this.ukupnoNaplaceno,
    this.razlika,
    this.napomena,
    required this.updatedAt,
  });

  factory V2DnevnaPredaja.fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    if (id == null || id.isEmpty) throw ArgumentError('V2DnevnaPredaja.fromJson: id je null ili prazan');
    final datumRaw = j['datum'] as String?;
    if (datumRaw == null || datumRaw.isEmpty) throw ArgumentError('V2DnevnaPredaja.fromJson: datum je null ili prazan');
    final datum = DateTime.tryParse(datumRaw)?.toLocal();
    if (datum == null) throw ArgumentError('V2DnevnaPredaja.fromJson: datum format neispravan: $datumRaw');
    return V2DnevnaPredaja(
      id: id,
      vozacIme: j['vozac_ime'] as String? ?? '',
      datum: datum,
      predaoIznos: (j['predao_iznos'] as num?)?.toDouble() ??
          (throw ArgumentError('V2DnevnaPredaja.fromJson: predao_iznos je null')),
      ukupnoNaplaceno: (j['ukupno_naplaceno'] as num?)?.toDouble(),
      razlika: (j['razlika'] as num?)?.toDouble(),
      napomena: j['napomena'] as String?,
      updatedAt: j['updated_at'] != null
          ? (DateTime.tryParse(j['updated_at'] as String)?.toLocal() ?? DateTime.now())
          : DateTime.now(),
    );
  }

  /// Formatira DateTime u 'YYYY-MM-DD' string za DB.
  static String datumStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  V2DnevnaPredaja copyWith({
    String? id,
    String? vozacIme,
    DateTime? datum,
    double? predaoIznos,
    double? ukupnoNaplaceno,
    double? razlika,
    String? napomena,
    DateTime? updatedAt,
  }) {
    return V2DnevnaPredaja(
      id: id ?? this.id,
      vozacIme: vozacIme ?? this.vozacIme,
      datum: datum ?? this.datum,
      predaoIznos: predaoIznos ?? this.predaoIznos,
      ukupnoNaplaceno: ukupnoNaplaceno ?? this.ukupnoNaplaceno,
      razlika: razlika ?? this.razlika,
      napomena: napomena ?? this.napomena,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toUpsertJson() => {
        'vozac_ime': vozacIme,
        'datum': datumStr(datum),
        'predao_iznos': predaoIznos,
        if (ukupnoNaplaceno != null) 'ukupno_naplaceno': ukupnoNaplaceno,
        if (razlika != null) 'razlika': razlika,
        if (napomena != null) 'napomena': napomena,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is V2DnevnaPredaja && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
