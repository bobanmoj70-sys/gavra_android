/// Model za punjenja gorivne pumpe (v2_pumpa_punjenja tabela)
class V2PumpaPunjenje {
  final String id;
  final DateTime datum;
  final double litri;
  final double? cenaPoPLitru;
  final double? ukupnoCena;
  final String? napomena;
  final DateTime createdAt;

  V2PumpaPunjenje({
    required this.id,
    required this.datum,
    required this.litri,
    this.cenaPoPLitru,
    this.ukupnoCena,
    this.napomena,
    required this.createdAt,
  });

  factory V2PumpaPunjenje.fromJson(Map<String, dynamic> j) => V2PumpaPunjenje(
        id: j['id'] as String,
        datum: DateTime.parse(j['datum'] as String),
        litri: (j['litri'] as num).toDouble(),
        cenaPoPLitru: (j['cena_po_litru'] as num?)?.toDouble(),
        ukupnoCena: (j['ukupno_cena'] as num?)?.toDouble(),
        napomena: j['napomena'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      );

  @override
  bool operator ==(Object other) => identical(this, other) || other is V2PumpaPunjenje && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
