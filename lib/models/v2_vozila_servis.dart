/// Model za servisne zapise vozila (v2_vozila_servis tabela)
class V2VozilaServis {
  final String id;
  final String voziloId;
  final String tip;
  final DateTime datum;
  final int? km;
  final String? opis;
  final double? cena;
  final String? pozicija;
  final DateTime? createdAt;

  V2VozilaServis({
    required this.id,
    required this.voziloId,
    required this.tip,
    required this.datum,
    this.km,
    this.opis,
    this.cena,
    this.pozicija,
    this.createdAt,
  });

  factory V2VozilaServis.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) throw ArgumentError('V2VozilaServis.fromJson: id je null ili prazan');
    final voziloId = json['vozilo_id'] as String?;
    if (voziloId == null || voziloId.isEmpty)
      throw ArgumentError('V2VozilaServis.fromJson: vozilo_id je null ili prazan');
    return V2VozilaServis(
      id: id,
      voziloId: voziloId,
      tip: json['tip'] as String? ?? '',
      datum: DateTime.tryParse(json['datum'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      km: (json['km'] as num?)?.toInt(),
      opis: json['opis'] as String?,
      cena: (json['cena'] as num?)?.toDouble(),
      pozicija: json['pozicija'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'vozilo_id': voziloId,
      'tip': tip,
      'datum': datum.toIso8601String().split('T')[0],
      if (km != null) 'km': km,
      if (opis != null) 'opis': opis,
      if (cena != null) 'cena': cena,
      if (pozicija != null) 'pozicija': pozicija,
    };
  }

  V2VozilaServis copyWith({
    String? id,
    String? voziloId,
    String? tip,
    DateTime? datum,
    Object? km = _sentinel,
    Object? opis = _sentinel,
    Object? cena = _sentinel,
    Object? pozicija = _sentinel,
    Object? createdAt = _sentinel,
  }) {
    return V2VozilaServis(
      id: id ?? this.id,
      voziloId: voziloId ?? this.voziloId,
      tip: tip ?? this.tip,
      datum: datum ?? this.datum,
      km: km == _sentinel ? this.km : km as int?,
      opis: opis == _sentinel ? this.opis : opis as String?,
      cena: cena == _sentinel ? this.cena : cena as double?,
      pozicija: pozicija == _sentinel ? this.pozicija : pozicija as String?,
      createdAt: createdAt == _sentinel ? this.createdAt : createdAt as DateTime?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (runtimeType == other.runtimeType && other is V2VozilaServis && id == other.id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'V2VozilaServis(id: $id, voziloId: $voziloId, tip: $tip, '
      'datum: ${datum.toIso8601String().split("T")[0]}, km: $km, cena: $cena)';
}

const _sentinel = Object();
