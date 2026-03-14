class V3Kapacitet {
  final String id;
  final String grad;
  final String vreme;
  final int maxMesta;
  final bool aktivno;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  V3Kapacitet({
    required this.id,
    required this.grad,
    required this.vreme,
    required this.maxMesta,
    this.aktivno = true,
    this.createdAt,
    this.updatedAt,
  });

  factory V3Kapacitet.fromJson(Map<String, dynamic> json) {
    return V3Kapacitet(
      id: json['id']?.toString() ?? '',
      grad: json['grad'] ?? '',
      vreme: json['vreme'] ?? '',
      maxMesta: (json['max_mesta'] as num?)?.toInt() ?? 8,
      aktivno: json['aktivno'] ?? true,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'grad': grad,
      'vreme': vreme,
      'max_mesta': maxMesta,
      'aktivno': aktivno,
    };
  }
}
