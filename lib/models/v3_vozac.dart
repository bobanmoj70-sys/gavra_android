import '../utils/v3_date_utils.dart';

class V3Vozac {
  final String id;
  final String imePrezime;
  final String? telefon1;
  final String? telefon2;
  final String? boja;
  final String? pushToken;
  final String? pushProvider;
  final String? pushToken2;
  final String? pushProvider2;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  V3Vozac({
    required this.id,
    required this.imePrezime,
    this.telefon1,
    this.telefon2,
    this.boja,
    this.pushToken,
    this.pushProvider,
    this.pushToken2,
    this.pushProvider2,
    this.createdAt,
    this.updatedAt,
  });

  factory V3Vozac.fromJson(Map<String, dynamic> json) {
    return V3Vozac(
      id: json['id'] as String? ?? '',
      imePrezime: json['ime_prezime'] as String? ?? '',
      telefon1: json['telefon_1'] as String?,
      telefon2: json['telefon_2'] as String?,
      boja: json['boja'] as String?,
      pushToken: json['push_token'] as String?,
      pushProvider: json['push_provider'] as String?,
      pushToken2: json['push_token_2'] as String?,
      pushProvider2: json['push_provider_2'] as String?,
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
      'boja': boja,
      'push_token': pushToken,
      'push_provider': pushProvider,
      'push_token_2': pushToken2,
      'push_provider_2': pushProvider2,
    };
  }

  V3Vozac copyWith({
    String? id,
    String? imePrezime,
    String? telefon1,
    String? telefon2,
    String? boja,
    String? pushToken,
    String? pushProvider,
    String? pushToken2,
    String? pushProvider2,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return V3Vozac(
      id: id ?? this.id,
      imePrezime: imePrezime ?? this.imePrezime,
      telefon1: telefon1 ?? this.telefon1,
      telefon2: telefon2 ?? this.telefon2,
      boja: boja ?? this.boja,
      pushToken: pushToken ?? this.pushToken,
      pushProvider: pushProvider ?? this.pushProvider,
      pushToken2: pushToken2 ?? this.pushToken2,
      pushProvider2: pushProvider2 ?? this.pushProvider2,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
