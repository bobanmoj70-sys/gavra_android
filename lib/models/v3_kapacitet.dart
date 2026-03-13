class V3Kapacitet {
  final String id;
  final String grad;
  final String vreme;
  final int maxMesta;
  final bool aktivno;

  V3Kapacitet({
    required this.id,
    required this.grad,
    required this.vreme,
    required this.maxMesta,
    this.aktivno = true,
  });

  factory V3Kapacitet.fromJson(Map<String, dynamic> json) {
    return V3Kapacitet(
      id: json['id']?.toString() ?? '',
      grad: json['grad'] ?? '',
      vreme: json['vreme'] ?? '',
      maxMesta: json['max_mesta'] ?? 8,
      aktivno: json['aktivno'] ?? true,
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
