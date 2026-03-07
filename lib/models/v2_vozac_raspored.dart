/// Model za raspored vožnji vozača (v2_vozac_raspored tabela)
class V2VozacRaspored {
  final String id;
  final String vozacId;
  final String dan;
  final String grad;
  final String vreme;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  V2VozacRaspored({
    required this.id,
    required this.vozacId,
    required this.dan,
    required this.grad,
    required this.vreme,
    this.createdAt,
    this.updatedAt,
  });

  factory V2VozacRaspored.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) throw ArgumentError('V2VozacRaspored.fromJson: id je null ili prazan');
    final vozacId = json['vozac_id'] as String?;
    if (vozacId == null || vozacId.isEmpty)
      throw ArgumentError('V2VozacRaspored.fromJson: vozac_id je null ili prazan');
    return V2VozacRaspored(
      id: id,
      vozacId: vozacId,
      dan: json['dan'] as String? ?? '',
      grad: json['grad'] as String? ?? '',
      vreme: json['vreme'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '')?.toLocal(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'vozac_id': vozacId,
      'dan': dan,
      'grad': grad,
      'vreme': vreme,
    };
  }

  V2VozacRaspored copyWith({
    String? id,
    String? vozacId,
    String? dan,
    String? grad,
    String? vreme,
    Object? createdAt = _sentinel,
    Object? updatedAt = _sentinel,
  }) {
    return V2VozacRaspored(
      id: id ?? this.id,
      vozacId: vozacId ?? this.vozacId,
      dan: dan ?? this.dan,
      grad: grad ?? this.grad,
      vreme: vreme ?? this.vreme,
      createdAt: createdAt == _sentinel ? this.createdAt : createdAt as DateTime?,
      updatedAt: updatedAt == _sentinel ? this.updatedAt : updatedAt as DateTime?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (runtimeType == other.runtimeType &&
          other is V2VozacRaspored &&
          id == other.id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'V2VozacRaspored(id: $id, vozacId: $vozacId, '
      'dan: $dan, grad: $grad, vreme: $vreme)';
}

const _sentinel = Object();
