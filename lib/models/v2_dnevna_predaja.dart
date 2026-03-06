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

  factory V2DnevnaPredaja.fromJson(Map<String, dynamic> j) => V2DnevnaPredaja(
        id: j['id'] as String,
        vozacIme: j['vozac_ime'] as String,
        datum: DateTime.parse(j['datum'] as String),
        predaoIznos: (j['predao_iznos'] as num).toDouble(),
        ukupnoNaplaceno: (j['ukupno_naplaceno'] as num?)?.toDouble(),
        razlika: (j['razlika'] as num?)?.toDouble(),
        napomena: j['napomena'] as String?,
        updatedAt: DateTime.parse(j['updated_at'] as String).toLocal(),
      );

  Map<String, dynamic> toUpsertJson() => {
        'vozac_ime': vozacIme,
        'datum': '${datum.year}-${datum.month.toString().padLeft(2, '0')}-${datum.day.toString().padLeft(2, '0')}',
        'predao_iznos': predaoIznos,
        if (ukupnoNaplaceno != null) 'ukupno_naplaceno': ukupnoNaplaceno,
        if (razlika != null) 'razlika': razlika,
        if (napomena != null) 'napomena': napomena,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  @override
  bool operator ==(Object other) => identical(this, other) || other is V2DnevnaPredaja && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
