import '../utils/v3_date_utils.dart';

/// Universal model for all types of passengers in v3_putnici table
class V3Putnik {
  final String id;
  final String imePrezime;
  final String? telefon1;
  final String? telefon2;
  final String? email;
  final String? pin;
  final String tipPutnika; // 'dnevni', 'radnik', 'ucenik', 'posiljka'
  final String? adresaBcId;
  final String? adresaVsId;
  final String? adresaBcId2;
  final String? adresaVsId2;

  // Specific fields
  final String? opisPosiljke;
  final String? skola;

  final double cenaPoDanu;
  final double cenaPoPokupljenju;

  final int? placeniMesec;
  final int? placenaGodina;

  final String? pushToken;
  final String? pushToken2;
  final bool aktivno;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;

  V3Putnik({
    required this.id,
    required this.imePrezime,
    this.telefon1,
    this.telefon2,
    this.email,
    this.pin,
    required this.tipPutnika,
    this.adresaBcId,
    this.adresaVsId,
    this.adresaBcId2,
    this.adresaVsId2,
    this.opisPosiljke,
    this.skola,
    this.cenaPoDanu = 0.0,
    this.cenaPoPokupljenju = 0.0,
    this.placeniMesec,
    this.placenaGodina,
    this.pushToken,
    this.pushToken2,
    this.aktivno = true,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
  });

  factory V3Putnik.fromJson(Map<String, dynamic> json) {
    return V3Putnik(
      id: json['id'] as String? ?? '',
      imePrezime: json['ime_prezime'] as String? ?? '',
      telefon1: json['telefon_1'] as String?,
      telefon2: json['telefon_2'] as String?,
      email: json['email'] as String?,
      pin: json['pin'] as String?,
      tipPutnika: json['tip_putnika'] as String? ?? 'dnevni',
      adresaBcId: json['adresa_bc_id'] as String?,
      adresaVsId: json['adresa_vs_id'] as String?,
      adresaBcId2: json['adresa_bc_id_2'] as String?,
      adresaVsId2: json['adresa_vs_id_2'] as String?,
      opisPosiljke: json['opis_posiljke'] as String?,
      skola: json['skola'] as String?,
      cenaPoDanu: (json['cena_po_danu'] as num?)?.toDouble() ?? 0.0,
      cenaPoPokupljenju: (json['cena_po_pokupljenju'] as num?)?.toDouble() ?? 0.0,
      placeniMesec: json['placeni_mesec'] as int?,
      placenaGodina: json['placena_godina'] as int?,
      pushToken: json['push_token'] as String?,
      pushToken2: json['push_token_2'] as String?,
      aktivno: json['aktivno'] as bool? ?? true,
      createdAt: V3DateUtils.parseTs(json['created_at'] as String?),
      updatedAt: V3DateUtils.parseTs(json['updated_at'] as String?),
      createdBy: json['created_by'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ime_prezime': imePrezime,
      'telefon_1': telefon1,
      'telefon_2': telefon2,
      'email': email,
      'pin': pin,
      'tip_putnika': tipPutnika,
      'adresa_bc_id': adresaBcId,
      'adresa_vs_id': adresaVsId,
      'adresa_bc_id_2': adresaBcId2,
      'adresa_vs_id_2': adresaVsId2,
      'opis_posiljke': opisPosiljke,
      'skola': skola,
      'cena_po_danu': cenaPoDanu,
      'cena_po_pokupljenju': cenaPoPokupljenju,
      'placeni_mesec': placeniMesec,
      'placena_godina': placenaGodina,
      'aktivno': aktivno,
      if (pushToken != null) 'push_token': pushToken,
      if (pushToken2 != null) 'push_token_2': pushToken2,
      if (createdBy != null) 'created_by': createdBy,
    };
  }

  V3Putnik copyWith({
    String? id,
    String? imePrezime,
    String? telefon1,
    String? telefon2,
    String? email,
    String? pin,
    String? tipPutnika,
    String? adresaBcId,
    String? adresaVsId,
    String? adresaBcId2,
    String? adresaVsId2,
    String? opisPosiljke,
    String? skola,
    double? cenaPoDanu,
    double? cenaPoPokupljenju,
    int? placeniMesec,
    int? placenaGodina,
    String? pushToken,
    String? pushToken2,
    bool? aktivno,
  }) {
    return V3Putnik(
      id: id ?? this.id,
      imePrezime: imePrezime ?? this.imePrezime,
      telefon1: telefon1 ?? this.telefon1,
      telefon2: telefon2 ?? this.telefon2,
      email: email ?? this.email,
      pin: pin ?? this.pin,
      tipPutnika: tipPutnika ?? this.tipPutnika,
      adresaBcId: adresaBcId ?? this.adresaBcId,
      adresaVsId: adresaVsId ?? this.adresaVsId,
      adresaBcId2: adresaBcId2 ?? this.adresaBcId2,
      adresaVsId2: adresaVsId2 ?? this.adresaVsId2,
      opisPosiljke: opisPosiljke ?? this.opisPosiljke,
      skola: skola ?? this.skola,
      cenaPoDanu: cenaPoDanu ?? this.cenaPoDanu,
      cenaPoPokupljenju: cenaPoPokupljenju ?? this.cenaPoPokupljenju,
      placeniMesec: placeniMesec ?? this.placeniMesec,
      placenaGodina: placenaGodina ?? this.placenaGodina,
      pushToken: pushToken ?? this.pushToken,
      pushToken2: pushToken2 ?? this.pushToken2,
      aktivno: aktivno ?? this.aktivno,
    );
  }

  @override
  String toString() => 'V3Putnik($imePrezime, $tipPutnika, cena: $cenaPoDanu)';
}
