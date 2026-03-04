/// Model za točenja goriva iz pumpe (v2_pumpa_tocenja tabela)
class V2PumpaTocenje {
  final String id;
  final DateTime datum;
  final String? voziloId;
  final String? registarskiBroj;
  final String? marka;
  final String? model;
  final double litri;
  final int? kmVozila;
  final String? napomena;
  final DateTime createdAt;

  V2PumpaTocenje({
    required this.id,
    required this.datum,
    this.voziloId,
    this.registarskiBroj,
    this.marka,
    this.model,
    required this.litri,
    this.kmVozila,
    this.napomena,
    required this.createdAt,
  });

  factory V2PumpaTocenje.fromJson(Map<String, dynamic> j) {
    final vozilo = j['v2_vozila'] as Map<String, dynamic>?;
    return V2PumpaTocenje(
      id: j['id'] as String,
      datum: DateTime.parse(j['datum'] as String),
      voziloId: j['vozilo_id'] as String?,
      registarskiBroj: vozilo?['registarski_broj'] as String?,
      marka: vozilo?['marka'] as String?,
      model: vozilo?['model'] as String?,
      litri: (j['litri'] as num).toDouble(),
      kmVozila: j['km_vozila'] as int?,
      napomena: j['napomena'] as String?,
      createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
    );
  }

  String get voziloNaziv {
    if (registarskiBroj != null) {
      return '$registarskiBroj${marka != null ? ' ($marka)' : ''}';
    }
    return 'Nepoznato vozilo';
  }

  @override
  bool operator ==(Object other) => identical(this, other) || other is V2PumpaTocenje && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
