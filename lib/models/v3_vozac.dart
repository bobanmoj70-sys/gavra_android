import '../utils/v3_date_utils.dart';

class V3Vozac {
  final String id;
  final String imePrezime;
  final String? telefon1;
  final String? telefon2;
  final String? email;
  final String? sifra;
  final String? boja;
  final String? pushToken;
  final bool aktivno;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  V3Vozac({
    required this.id,
    required this.imePrezime,
    this.telefon1,
    this.telefon2,
    this.email,
    this.sifra,
    this.boja,
    this.pushToken,
    this.aktivno = true,
    this.createdAt,
    this.updatedAt,
  });

  factory V3Vozac.fromJson(Map<String, dynamic> json) {
    return V3Vozac(
      id: json['id'] as String? ?? '',
      imePrezime: json['ime_prezime'] as String? ?? '',
      telefon1: json['telefon_1'] as String?,
      telefon2: json['telefon_2'] as String?,
      email: json['email'] as String?,
      sifra: json['sifra'] as String?,
      boja: json['boja'] as String?,
      pushToken: json['push_token'] as String?,
      aktivno: json['aktivno'] as bool? ?? true,
      createdAt: V3DateUtils.parseTs(json['created_at'] as String?),
      updatedAt: V3DateUtils.parseTs(json['updated_at'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ime_prezime': imePrezime,
      'telefon_1': telefon1,
      'telefon_2': telefon2,
      'email': email,
      'sifra': sifra,
      'boja': boja,
      'push_token': pushToken,
      'aktivno': aktivno,
    };
  }
}
