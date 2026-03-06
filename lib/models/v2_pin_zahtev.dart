/// Model za zahteve za PIN pristup (v2_pin_zahtevi tabela)
class V2PinZahtev {
  final String id;
  final String putnikId;
  final String putnikTabela;
  final String? email;
  final String? telefon;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  V2PinZahtev({
    required this.id,
    required this.putnikId,
    required this.putnikTabela,
    this.email,
    this.telefon,
    this.status = 'ceka',
    this.createdAt,
    this.updatedAt,
  });

  factory V2PinZahtev.fromJson(Map<String, dynamic> json) {
    return V2PinZahtev(
      id: json['id'] as String? ?? '',
      putnikId: json['putnik_id'] as String? ?? '',
      putnikTabela: json['putnik_tabela'] as String? ?? '',
      email: json['email'] as String?,
      telefon: json['telefon'] as String?,
      status: json['status'] as String? ?? 'ceka',
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'putnik_id': putnikId,
      'putnik_tabela': putnikTabela,
      'email': email,
      'telefon': telefon,
      'status': status,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}
