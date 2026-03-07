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
  final DateTime? createdAt;

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
    this.createdAt,
  });

  factory V2PumpaTocenje.fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    if (id == null || id.isEmpty) throw ArgumentError('V2PumpaTocenje.fromJson: id je null/prazan');
    final datumStr = j['datum'] as String?;
    if (datumStr == null) throw ArgumentError('V2PumpaTocenje.fromJson: datum je null');
    final datum = DateTime.tryParse(datumStr);
    if (datum == null) throw ArgumentError('V2PumpaTocenje.fromJson: datum nije validan: $datumStr');
    final litri = (j['litri'] as num?)?.toDouble();
    if (litri == null) throw ArgumentError('V2PumpaTocenje.fromJson: litri je null');
    final vozilo = j['v2_vozila'] as Map<String, dynamic>?;
    return V2PumpaTocenje(
      id: id,
      datum: datum,
      voziloId: j['vozilo_id'] as String?,
      registarskiBroj: vozilo?['registarski_broj'] as String?,
      marka: vozilo?['marka'] as String?,
      model: vozilo?['model'] as String?,
      litri: litri,
      kmVozila: (j['km_vozila'] as num?)?.toInt(),
      napomena: j['napomena'] as String?,
      createdAt: j['created_at'] != null ? DateTime.tryParse(j['created_at'] as String)?.toLocal() : null,
    );
  }

  String get voziloNaziv {
    if (registarskiBroj != null) {
      return '$registarskiBroj${marka != null ? ' ($marka)' : ''}';
    }
    return 'Nepoznato vozilo';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is V2PumpaTocenje && runtimeType == other.runtimeType && id == other.id);

  @override
  int get hashCode => id.hashCode;

  V2PumpaTocenje copyWith({
    String? id,
    DateTime? datum,
    String? voziloId,
    String? registarskiBroj,
    String? marka,
    String? model,
    double? litri,
    int? kmVozila,
    String? napomena,
    DateTime? createdAt,
  }) {
    return V2PumpaTocenje(
      id: id ?? this.id,
      datum: datum ?? this.datum,
      voziloId: voziloId ?? this.voziloId,
      registarskiBroj: registarskiBroj ?? this.registarskiBroj,
      marka: marka ?? this.marka,
      model: model ?? this.model,
      litri: litri ?? this.litri,
      kmVozila: kmVozila ?? this.kmVozila,
      napomena: napomena ?? this.napomena,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'datum': datum.toIso8601String().split('T')[0],
      'litri': litri,
      if (voziloId != null) 'vozilo_id': voziloId,
      if (kmVozila != null) 'km_vozila': kmVozila,
      if (napomena != null) 'napomena': napomena,
    };
  }

  @override
  String toString() =>
      'V2PumpaTocenje(id: $id, datum: ${datum.toIso8601String().split("T")[0]}, litri: $litri, vozilo: $voziloNaziv)';
}
