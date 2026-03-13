class V3Zahtev {
  final String id;
  final String putnikId;
  final DateTime datum;
  final String? danUSedmici;
  final String grad;
  final String zeljenoVreme;
  final int brojMesta;
  final String status; // 'obrada', 'odobreno', 'odbijeno', 'otkazano'
  final String? napomena;
  final bool aktivno;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  V3Zahtev({
    required this.id,
    required this.putnikId,
    required this.datum,
    this.danUSedmici,
    required this.grad,
    required this.zeljenoVreme,
    this.brojMesta = 1,
    this.status = 'obrada',
    this.napomena,
    this.aktivno = true,
    this.createdAt,
    this.updatedAt,
  });

  factory V3Zahtev.fromJson(Map<String, dynamic> json) {
    return V3Zahtev(
      id: json['id'] as String? ?? '',
      putnikId: json['putnik_id'] as String? ?? '',
      datum: json['datum'] != null ? DateTime.parse(json['datum'] as String) : DateTime.now(),
      danUSedmici: json['dan_u_sedmici'] as String?,
      grad: json['grad'] as String? ?? '',
      zeljenoVreme: json['zeljeno_vreme'] as String? ?? '',
      brojMesta: json['broj_mesta'] as int? ?? 1,
      status: json['status'] as String? ?? 'obrada',
      napomena: json['napomena'] as String?,
      aktivno: json['aktivno'] as bool? ?? true,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'putnik_id': putnikId,
      'datum': datum.toIso8601String().split('T')[0],
      'dan_u_sedmici': danUSedmici,
      'grad': grad,
      'zeljeno_vreme': zeljenoVreme,
      'broj_mesta': brojMesta,
      'status': status,
      'napomena': napomena,
      'aktivno': aktivno,
    };
  }
}
