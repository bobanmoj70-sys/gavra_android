import '../utils/v3_dan_helper.dart';
import '../utils/v3_date_utils.dart';

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
  });

  factory V3DnevnaPredaja.fromJson(Map<String, dynamic> json) {
    return V3DnevnaPredaja(
      id: json['id'] as String,
      vozacId: json['naplaceno_by'] as String?,
      vozacImePrezime: (json['vozac_ime'] as String?) ?? (json['vozac_ime_prezime'] as String?),
      datum: json['datum'] != null ? DateTime.parse(json['datum'] as String) : DateTime.now(),
      predaoIznos: (json['predao_iznos'] as num?)?.toDouble() ?? 0,
      ukupnoNaplaceno: (json['ukupno_naplaceno'] as num?)?.toDouble() ?? 0,
      razlika: (json['razlika'] as num?)?.toDouble() ?? 0,
      napomena: json['napomena'] as String?,
      createdAt: V3DateUtils.parseTs(json['created_at'] as String?),
      updatedAt: V3DateUtils.parseTs(json['updated_at'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'naplaceno_by': vozacId,
        'vozac_ime': vozacImePrezime,
        'datum': V3DanHelper.toIsoDate(datum),
        'predao_iznos': predaoIznos,
        'ukupno_naplaceno': ukupnoNaplaceno,
        'razlika': razlika,
        'napomena': napomena,
      };
}
