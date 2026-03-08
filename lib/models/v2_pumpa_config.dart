/// Model za konfiguraciju gorivne pumpe (v2_pumpa_config tabela)
class V2PumpaConfig {
  final String id;
  final double kapacitetLitri;
  final double alarmNivo;
  final double pocetnoStanje;
  final DateTime? updatedAt;

  V2PumpaConfig({
    required this.id,
    required this.kapacitetLitri,
    required this.alarmNivo,
    required this.pocetnoStanje,
    this.updatedAt,
  });

  factory V2PumpaConfig.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) throw ArgumentError('V2PumpaConfig.fromJson: id je null/prazan');
    return V2PumpaConfig(
      id: id,
      kapacitetLitri: (json['kapacitet_litri'] as num?)?.toDouble() ?? 0.0,
      alarmNivo: (json['alarm_nivo'] as num?)?.toDouble() ?? 0.0,
      pocetnoStanje: (json['pocetno_stanje'] as num?)?.toDouble() ?? 0.0,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String)?.toLocal() : null,
    );
  }

  /// Samo polja koja se šalju pri update-u — id i updated_at servis dodaje sam.
  Map<String, dynamic> toJson() {
    return {
      'kapacitet_litri': kapacitetLitri,
      'alarm_nivo': alarmNivo,
      'pocetno_stanje': pocetnoStanje,
    };
  }

  V2PumpaConfig copyWith({
    String? id,
    double? kapacitetLitri,
    double? alarmNivo,
    double? pocetnoStanje,
    DateTime? updatedAt,
  }) {
    return V2PumpaConfig(
      id: id ?? this.id,
      kapacitetLitri: kapacitetLitri ?? this.kapacitetLitri,
      alarmNivo: alarmNivo ?? this.alarmNivo,
      pocetnoStanje: pocetnoStanje ?? this.pocetnoStanje,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is V2PumpaConfig && runtimeType == other.runtimeType && id == other.id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'V2PumpaConfig(id: $id, kapacitet: $kapacitetLitri L, alarm: $alarmNivo L, pocetno: $pocetnoStanje L)';
}
