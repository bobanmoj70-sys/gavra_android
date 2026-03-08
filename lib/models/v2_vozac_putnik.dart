/// Model za vezu vozač-putnik (v2_vozac_putnik tabela)
class V2VozacPutnik {
  final String id;
  final String vozacId;
  final String putnikId;
  final String putnikTabela;
  final String dan;
  final String grad;
  final String vreme;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  V2VozacPutnik({
    required this.id,
    required this.vozacId,
    required this.putnikId,
    required this.putnikTabela,
    required this.dan,
    required this.grad,
    required this.vreme,
    this.createdAt,
    this.updatedAt,
  });

  factory V2VozacPutnik.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) throw ArgumentError('V2VozacPutnik.fromJson: id je null ili prazan');
    final vozacId = json['vozac_id'] as String?;
    if (vozacId == null || vozacId.isEmpty) throw ArgumentError('V2VozacPutnik.fromJson: vozac_id je null ili prazan');
    final putnikId = json['putnik_id'] as String?;
    if (putnikId == null || putnikId.isEmpty)
      throw ArgumentError('V2VozacPutnik.fromJson: putnik_id je null ili prazan');
    return V2VozacPutnik(
      id: id,
      vozacId: vozacId,
      putnikId: putnikId,
      putnikTabela: json['putnik_tabela'] as String? ?? '',
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
      'putnik_id': putnikId,
      'putnik_tabela': putnikTabela,
      'dan': dan,
      'grad': grad,
      'vreme': vreme,
    };
  }

  V2VozacPutnik copyWith({
    String? id,
    String? vozacId,
    String? putnikId,
    String? putnikTabela,
    String? dan,
    String? grad,
    String? vreme,
    Object? createdAt = _sentinel,
    Object? updatedAt = _sentinel,
  }) {
    return V2VozacPutnik(
      id: id ?? this.id,
      vozacId: vozacId ?? this.vozacId,
      putnikId: putnikId ?? this.putnikId,
      putnikTabela: putnikTabela ?? this.putnikTabela,
      dan: dan ?? this.dan,
      grad: grad ?? this.grad,
      vreme: vreme ?? this.vreme,
      createdAt: createdAt == _sentinel ? this.createdAt : createdAt as DateTime?,
      updatedAt: updatedAt == _sentinel ? this.updatedAt : updatedAt as DateTime?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (runtimeType == other.runtimeType && other is V2VozacPutnik && id == other.id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'V2VozacPutnik(id: $id, vozacId: $vozacId, putnikId: $putnikId, '
      'putnikTabela: $putnikTabela, dan: $dan, grad: $grad, vreme: $vreme)';
}

const _sentinel = Object();
