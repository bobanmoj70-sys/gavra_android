/// Model za radnike (v2_radnici tabela)
class V2Radnik {
  static const statusAktivan = 'aktivan';
  static const statusNeaktivan = 'neaktivan';
  static const statusObrisan = 'obrisan';

  final String id;
  final String ime;
  final String status;
  final String? telefon;
  final String? telefon2;
  final String? adresaBcId;
  final String? adresaVsId;
  final String? pin;
  final String? email;
  final double? cenaPoDanu;
  final int? brojMesta;
  final bool trebaRacun;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  V2Radnik({
    required this.id,
    required this.ime,
    this.status = statusAktivan,
    this.telefon,
    this.telefon2,
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

  factory V2Radnik.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) throw ArgumentError('V2Radnik.fromJson: id je null ili prazan');
    return V2Radnik(
      id: id,
      ime: json['ime'] as String? ?? '',
      status: json['status'] as String? ?? statusAktivan,
      telefon: json['telefon'] as String?,
      telefon2: json['telefon_2'] as String?,
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
      if (telefon2 != null) 'telefon_2': telefon2,
      if (adresaBcId != null) 'adresa_bc_id': adresaBcId,
      if (adresaVsId != null) 'adresa_vs_id': adresaVsId,
      if (pin != null) 'pin': pin,
      if (email != null) 'email': email,
      if (cenaPoDanu != null) 'cena_po_danu': cenaPoDanu,
      if (brojMesta != null) 'broj_mesta': brojMesta,
      'treba_racun': trebaRacun,
    };
  }

  V2Radnik copyWith({
    String? id,
    String? ime,
    String? status,
    Object? telefon = _sentinel,
    Object? telefon2 = _sentinel,
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
    return V2Radnik(
      id: id ?? this.id,
      ime: ime ?? this.ime,
      status: status ?? this.status,
      telefon: telefon == _sentinel ? this.telefon : telefon as String?,
      telefon2: telefon2 == _sentinel ? this.telefon2 : telefon2 as String?,
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
      identical(this, other) ||
      (runtimeType == other.runtimeType &&
          other is V2Radnik &&
          id == other.id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'V2Radnik(id: $id, ime: $ime, status: $status, '
      'telefon: $telefon, brojMesta: $brojMesta, cenaPoDanu: $cenaPoDanu, '
      'trebaRacun: $trebaRacun)';
}

const _sentinel = Object();
