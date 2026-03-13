class V3PinZahtev {
  static const String statusCeka = 'ceka';
  static const String statusOdobren = 'odobren';
  static const String statusOdbijen = 'odbijen';

  final String id;
  final String putnikId;
  final String? email;
  final String? telefon;
  final String status;
  final DateTime? createdAt;

  V3PinZahtev({
    required this.id,
    required this.putnikId,
    this.email,
    this.telefon,
    this.status = statusCeka,
    this.createdAt,
  });

  factory V3PinZahtev.fromJson(Map<String, dynamic> json) {
    return V3PinZahtev(
      id: json['id']?.toString() ?? '',
      putnikId: json['putnik_id']?.toString() ?? '',
      email: json['email'] as String?,
      telefon: json['telefon'] as String?,
      status: json['status'] as String? ?? statusCeka,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String)?.toLocal() : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'putnik_id': putnikId,
      if (email != null) 'email': email,
      if (telefon != null) 'telefon': telefon,
      'status': status,
    };
  }
}
