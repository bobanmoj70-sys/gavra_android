class V3FinansijskiUnos {
  final String id;
  final String tip; // 'prihod', 'trosak'
  final String kategorija; // 'voznja', 'gorivo', 'odrzavanje', 'ostalo'
  final String opis;
  final double iznos;
  final DateTime datum;
  final String? vozacId;
  final String? voziloId;
  final String? putnikId;
  final DateTime createdAt;

  V3FinansijskiUnos({
    required this.id,
    required this.tip,
    required this.kategorija,
    required this.opis,
    required this.iznos,
    required this.datum,
    this.vozacId,
    this.voziloId,
    this.putnikId,
    required this.createdAt,
  });

  factory V3FinansijskiUnos.fromJson(Map<String, dynamic> json) {
    return V3FinansijskiUnos(
      id: json['id'] as String? ?? '',
      tip: json['tip'] as String? ?? 'trosak',
      kategorija: json['kategorija'] as String? ?? 'ostalo',
      opis: json['opis'] as String? ?? '',
      iznos: (json['iznos'] as num?)?.toDouble() ?? 0.0,
      datum: json['datum'] != null ? DateTime.parse(json['datum'] as String) : DateTime.now(),
      vozacId: json['vozac_id'] as String?,
      voziloId: json['vozilo_id'] as String?,
      putnikId: json['putnik_id'] as String?,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tip': tip,
      'kategorija': kategorija,
      'opis': opis,
      'iznos': iznos,
      'datum': datum.toIso8601String(),
      'vozac_id': vozacId,
      'vozilo_id': voziloId,
      'putnik_id': putnikId,
    };
  }
}

class V3FinansijskiIzvestaj {
  final double prihodDanas;
  final double trosakDanas;
  final double prihodMesec;
  final double trosakMesec;
  final Map<String, double> troskoviPoKategoriji;

  V3FinansijskiIzvestaj({
    this.prihodDanas = 0,
    this.trosakDanas = 0,
    this.prihodMesec = 0,
    this.trosakMesec = 0,
    this.troskoviPoKategoriji = const {},
  });

  double get netoDanas => prihodDanas - trosakDanas;
  double get netoMesec => prihodMesec - trosakMesec;
}
