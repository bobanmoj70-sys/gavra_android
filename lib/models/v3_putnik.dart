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
  final String? adresaBcNaziv;
  final String? adresaVsNaziv;
  final String? adresaBcNaziv2;
  final String? adresaVsNaziv2;

  // Specific fields
  final String? opisPosiljke;
  final String? skola;

  final double cenaPoDanu;
  final double cenaPoPokupljenju;

  final int? placeniMesec;
  final int? placenaGodina;

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
    this.adresaBcNaziv,
    this.adresaVsNaziv,
    this.adresaBcNaziv2,
    this.adresaVsNaziv2,
    this.opisPosiljke,
    this.skola,
    this.cenaPoDanu = 0.0,
    this.cenaPoPokupljenju = 0.0,
    this.placeniMesec,
    this.placenaGodina,
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
      adresaBcNaziv: json['adresa_bc_naziv'] as String?,
      adresaVsNaziv: json['adresa_vs_naziv'] as String?,
      adresaBcNaziv2: json['adresa_bc_naziv_2'] as String?,
      adresaVsNaziv2: json['adresa_vs_naziv_2'] as String?,
      opisPosiljke: json['opis_posiljke'] as String?,
      skola: json['skola'] as String?,
      cenaPoDanu: (json['cena_po_danu'] as num?)?.toDouble() ?? 0.0,
      cenaPoPokupljenju: (json['cena_po_pokupljenju'] as num?)?.toDouble() ?? 0.0,
      placeniMesec: json['placeni_mesec'] as int?,
      placenaGodina: json['placena_godina'] as int?,
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
      'adresa_bc_naziv': adresaBcNaziv,
      'adresa_vs_naziv': adresaVsNaziv,
      'adresa_bc_naziv_2': adresaBcNaziv2,
      'adresa_vs_naziv_2': adresaVsNaziv2,
      'opis_posiljke': opisPosiljke,
      'skola': skola,
      'cena_po_danu': cenaPoDanu,
      'cena_po_pokupljenju': cenaPoPokupljenju,
      'placeni_mesec': placeniMesec,
      'placena_godina': placenaGodina,
      'aktivno': aktivno,
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
    String? adresaBcNaziv,
    String? adresaVsNaziv,
    String? adresaBcNaziv2,
    String? adresaVsNaziv2,
    String? opisPosiljke,
    String? skola,
    double? cenaPoDanu,
    double? cenaPoPokupljenju,
    int? placeniMesec,
    int? placenaGodina,
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
      adresaBcNaziv: adresaBcNaziv ?? this.adresaBcNaziv,
      adresaVsNaziv: adresaVsNaziv ?? this.adresaVsNaziv,
      adresaBcNaziv2: adresaBcNaziv2 ?? this.adresaBcNaziv2,
      adresaVsNaziv2: adresaVsNaziv2 ?? this.adresaVsNaziv2,
      opisPosiljke: opisPosiljke ?? this.opisPosiljke,
      skola: skola ?? this.skola,
      cenaPoDanu: cenaPoDanu ?? this.cenaPoDanu,
      cenaPoPokupljenju: cenaPoPokupljenju ?? this.cenaPoPokupljenju,
      placeniMesec: placeniMesec ?? this.placeniMesec,
      placenaGodina: placenaGodina ?? this.placenaGodina,
      aktivno: aktivno ?? this.aktivno,
    );
  }

  @override
  String toString() => 'V3Putnik($imePrezime, $tipPutnika, cena: $cenaPoDanu)';
}
