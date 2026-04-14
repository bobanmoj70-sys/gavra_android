import '../utils/v3_date_utils.dart';

/// Universal model for all passenger types from logical `v3_putnici` cache (`v3_auth` source)
class V3Putnik {
  final String id;
  final String imePrezime;
  final String? telefon1;
  final String? telefon2;
  final String tipPutnika; // 'dnevni', 'radnik', 'ucenik', 'posiljka'
  final String? adresaBcId;
  final String? adresaVsId;
  final String? adresaBcId2;
  final String? adresaVsId2;

  // Specific fields
  final String? sifra;

  final double cenaPoDanu;
  final double cenaPoPokupljenju;

  final String? pushToken;
  final String? pushToken2;
  final String? pushDeviceId;
  final String? pushDeviceId2;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  V3Putnik({
    required this.id,
    required this.imePrezime,
    this.telefon1,
    this.telefon2,
    required this.tipPutnika,
    this.adresaBcId,
    this.adresaVsId,
    this.adresaBcId2,
    this.adresaVsId2,
    this.sifra,
    this.cenaPoDanu = 0.0,
    this.cenaPoPokupljenju = 0.0,
    this.pushToken,
    this.pushToken2,
    this.pushDeviceId,
    this.pushDeviceId2,
    this.createdAt,
    this.updatedAt,
  });

  factory V3Putnik.fromJson(Map<String, dynamic> json) {
    return V3Putnik(
      id: json['id'] as String? ?? '',
      imePrezime: json['ime_prezime'] as String? ?? '',
      telefon1: json['telefon_1'] as String?,
      telefon2: json['telefon_2'] as String?,
      tipPutnika: json['tip_putnika'] as String? ?? 'dnevni',
      adresaBcId: json['adresa_bc_id'] as String?,
      adresaVsId: json['adresa_vs_id'] as String?,
      adresaBcId2: json['adresa_bc_id_2'] as String?,
      adresaVsId2: json['adresa_vs_id_2'] as String?,
      sifra: json['sifra'] as String?,
      cenaPoDanu: (json['cena_po_danu'] as num?)?.toDouble() ?? 0.0,
      cenaPoPokupljenju: (json['cena_po_pokupljenju'] as num?)?.toDouble() ?? 0.0,
      pushToken: json['push_token'] as String?,
      pushToken2: json['push_token_2'] as String?,
      pushDeviceId: json['push_device_id'] as String?,
      pushDeviceId2: json['push_device_id_2'] as String?,
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
      'tip_putnika': tipPutnika,
      'adresa_bc_id': adresaBcId,
      'adresa_vs_id': adresaVsId,
      'adresa_bc_id_2': adresaBcId2,
      'adresa_vs_id_2': adresaVsId2,
      'sifra': sifra,
      'cena_po_danu': cenaPoDanu,
      'cena_po_pokupljenju': cenaPoPokupljenju,
      if (pushToken != null) 'push_token': pushToken,
      if (pushToken2 != null) 'push_token_2': pushToken2,
      if (pushDeviceId != null) 'push_device_id': pushDeviceId,
      if (pushDeviceId2 != null) 'push_device_id_2': pushDeviceId2,
    };
  }

  V3Putnik copyWith({
    String? id,
    String? imePrezime,
    String? telefon1,
    String? telefon2,
    String? tipPutnika,
    String? adresaBcId,
    String? adresaVsId,
    String? adresaBcId2,
    String? adresaVsId2,
    String? sifra,
    double? cenaPoDanu,
    double? cenaPoPokupljenju,
    String? pushToken,
    String? pushToken2,
    String? pushDeviceId,
    String? pushDeviceId2,
  }) {
    return V3Putnik(
      id: id ?? this.id,
      imePrezime: imePrezime ?? this.imePrezime,
      telefon1: telefon1 ?? this.telefon1,
      telefon2: telefon2 ?? this.telefon2,
      tipPutnika: tipPutnika ?? this.tipPutnika,
      adresaBcId: adresaBcId ?? this.adresaBcId,
      adresaVsId: adresaVsId ?? this.adresaVsId,
      adresaBcId2: adresaBcId2 ?? this.adresaBcId2,
      adresaVsId2: adresaVsId2 ?? this.adresaVsId2,
      sifra: sifra ?? this.sifra,
      cenaPoDanu: cenaPoDanu ?? this.cenaPoDanu,
      cenaPoPokupljenju: cenaPoPokupljenju ?? this.cenaPoPokupljenju,
      pushToken: pushToken ?? this.pushToken,
      pushToken2: pushToken2 ?? this.pushToken2,
      pushDeviceId: pushDeviceId ?? this.pushDeviceId,
      pushDeviceId2: pushDeviceId2 ?? this.pushDeviceId2,
    );
  }

  @override
  String toString() => 'V3Putnik($imePrezime, $tipPutnika, cena: $cenaPoDanu)';
}
