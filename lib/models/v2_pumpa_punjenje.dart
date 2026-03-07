/// Model za punjenja gorivne pumpe (v2_pumpa_punjenja tabela)
class V2PumpaPunjenje {
  final String id;
  final DateTime datum;
  final double litri;
  final double? cenaPoPLitru;
  final double? ukupnoCena;
  final String? napomena;
  final DateTime? createdAt;

  V2PumpaPunjenje({
    required this.id,
    required this.datum,
    required this.litri,
    this.cenaPoPLitru,
    this.ukupnoCena,
    this.napomena,
    this.createdAt,
  });

  factory V2PumpaPunjenje.fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    if (id == null || id.isEmpty) throw ArgumentError('V2PumpaPunjenje.fromJson: id je null/prazan');
    final datumStr = j['datum'] as String?;
    if (datumStr == null) throw ArgumentError('V2PumpaPunjenje.fromJson: datum je null');
    final datum = DateTime.tryParse(datumStr);
    if (datum == null) throw ArgumentError('V2PumpaPunjenje.fromJson: datum nije validan: $datumStr');
    final litri = (j['litri'] as num?)?.toDouble();
    if (litri == null) throw ArgumentError('V2PumpaPunjenje.fromJson: litri je null');
    return V2PumpaPunjenje(
      id: id,
      datum: datum,
      litri: litri,
      cenaPoPLitru: (j['cena_po_litru'] as num?)?.toDouble(),
      ukupnoCena: (j['ukupno_cena'] as num?)?.toDouble(),
      napomena: j['napomena'] as String?,
      createdAt: j['created_at'] != null ? DateTime.tryParse(j['created_at'] as String)?.toLocal() : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is V2PumpaPunjenje && runtimeType == other.runtimeType && id == other.id);

  @override
  int get hashCode => id.hashCode;

  V2PumpaPunjenje copyWith({
    String? id,
    DateTime? datum,
    double? litri,
    double? cenaPoPLitru,
    double? ukupnoCena,
    String? napomena,
    DateTime? createdAt,
  }) {
    return V2PumpaPunjenje(
      id: id ?? this.id,
      datum: datum ?? this.datum,
      litri: litri ?? this.litri,
      cenaPoPLitru: cenaPoPLitru ?? this.cenaPoPLitru,
      ukupnoCena: ukupnoCena ?? this.ukupnoCena,
      napomena: napomena ?? this.napomena,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'datum': datum.toIso8601String().split('T')[0],
      'litri': litri,
      if (cenaPoPLitru != null) 'cena_po_litru': cenaPoPLitru,
      if (ukupnoCena != null) 'ukupno_cena': ukupnoCena,
      if (napomena != null) 'napomena': napomena,
    };
  }

  @override
  String toString() => 'V2PumpaPunjenje(id: $id, datum: ${datum.toIso8601String().split("T")[0]}, litri: $litri)';
}
