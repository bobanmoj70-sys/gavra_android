/// Model za učenike (v2_ucenici tabela)
class V2Ucenik {
  static const statusAktivan = 'aktivan';
  static const statusNeaktivan = 'neaktivan';
  static const statusObrisan = 'obrisan';

  final String id;
  final String ime;
  final String status;
  final String? telefon;
  final String? telefonOca;
  final String? telefonMajke;
  final String? adresaBcId;
  final String? adresaVsId;
  final String? pin;
  final String? email;
  final double? cenaPoDanu;
  final int? brojMesta;
  final bool trebaRacun;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  V2Ucenik({
    required this.id,
    required this.ime,
    this.status = statusAktivan,
    this.telefon,
    this.telefonOca,
    this.telefonMajke,
    this.adresaBcId,
    this.adresaVsId,
    this.pin,
    this.email,
    this.cenaPoDanu,
    this.brojMesta,
    this.trebaRacun = false,
    this.createdAt,
    this.updatedAt,
  });

  factory V2Ucenik.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) throw ArgumentError('V2Ucenik.fromJson: id je null ili prazan');
    return V2Ucenik(
      id: id,
      ime: json['ime'] as String? ?? '',
      status: json['status'] as String? ?? statusAktivan,
      telefon: json['telefon'] as String?,
      telefonOca: json['telefon_oca'] as String?,
      telefonMajke: json['telefon_majke'] as String?,
      adresaBcId: json['adresa_bc_id'] as String?,
      adresaVsId: json['adresa_vs_id'] as String?,
      pin: json['pin'] as String?,
      email: json['email'] as String?,
      cenaPoDanu: (json['cena_po_danu'] as num?)?.toDouble(),
      brojMesta: (json['broj_mesta'] as num?)?.toInt(),
      trebaRacun: json['treba_racun'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '')?.toLocal(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ime': ime,
      'status': status,
      if (telefon != null) 'telefon': telefon,
      if (telefonOca != null) 'telefon_oca': telefonOca,
      if (telefonMajke != null) 'telefon_majke': telefonMajke,
      if (adresaBcId != null) 'adresa_bc_id': adresaBcId,
      if (adresaVsId != null) 'adresa_vs_id': adresaVsId,
      if (pin != null) 'pin': pin,
      if (email != null) 'email': email,
      if (cenaPoDanu != null) 'cena_po_danu': cenaPoDanu,
      if (brojMesta != null) 'broj_mesta': brojMesta,
      'treba_racun': trebaRacun,
    };
  }

  V2Ucenik copyWith({
    String? id,
    String? ime,
    String? status,
    Object? telefon = _sentinel,
    Object? telefonOca = _sentinel,
    Object? telefonMajke = _sentinel,
    Object? adresaBcId = _sentinel,
    Object? adresaVsId = _sentinel,
    Object? pin = _sentinel,
    Object? email = _sentinel,
    Object? cenaPoDanu = _sentinel,
    Object? brojMesta = _sentinel,
    bool? trebaRacun,
    Object? createdAt = _sentinel,
    Object? updatedAt = _sentinel,
  }) {
    return V2Ucenik(
      id: id ?? this.id,
      ime: ime ?? this.ime,
      status: status ?? this.status,
      telefon: telefon == _sentinel ? this.telefon : telefon as String?,
      telefonOca: telefonOca == _sentinel ? this.telefonOca : telefonOca as String?,
      telefonMajke: telefonMajke == _sentinel ? this.telefonMajke : telefonMajke as String?,
      adresaBcId: adresaBcId == _sentinel ? this.adresaBcId : adresaBcId as String?,
      adresaVsId: adresaVsId == _sentinel ? this.adresaVsId : adresaVsId as String?,
      pin: pin == _sentinel ? this.pin : pin as String?,
      email: email == _sentinel ? this.email : email as String?,
      cenaPoDanu: cenaPoDanu == _sentinel ? this.cenaPoDanu : cenaPoDanu as double?,
      brojMesta: brojMesta == _sentinel ? this.brojMesta : brojMesta as int?,
      trebaRacun: trebaRacun ?? this.trebaRacun,
      createdAt: createdAt == _sentinel ? this.createdAt : createdAt as DateTime?,
      updatedAt: updatedAt == _sentinel ? this.updatedAt : updatedAt as DateTime?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (runtimeType == other.runtimeType && other is V2Ucenik && id == other.id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'V2Ucenik(id: $id, ime: $ime, status: $status, '
      'telefon: $telefon, brojMesta: $brojMesta, cenaPoDanu: $cenaPoDanu, '
      'trebaRacun: $trebaRacun)';
}

const _sentinel = Object();
