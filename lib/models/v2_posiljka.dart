/// Model za pošiljke (v2_posiljke tabela)
class V2Posiljka {
  static const String statusAktivan = 'aktivan';
  static const String statusNeaktivan = 'neaktivan';
  static const String statusObrisan = 'obrisan';

  final String id;
  final String ime;
  final String status;
  final String? telefon;
  final String? adresaBcId;
  final String? adresaVsId;
  final double? cena;
  final bool trebaRacun;
  final String? pin;
  final String? email;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  V2Posiljka({
    required this.id,
    required this.ime,
    this.status = statusAktivan,
    this.telefon,
    this.adresaBcId,
    this.adresaVsId,
    this.cena,
    this.trebaRacun = false,
    this.pin,
    this.email,
    this.createdAt,
    this.updatedAt,
  });

  factory V2Posiljka.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final ime = json['ime'] as String?;
    if (id == null || id.isEmpty) throw ArgumentError('V2Posiljka.fromJson: id je null/prazan');
    if (ime == null || ime.isEmpty) throw ArgumentError('V2Posiljka.fromJson: ime je null/prazno');
    return V2Posiljka(
      id: id,
      ime: ime,
      status: json['status'] as String? ?? statusAktivan,
      telefon: json['telefon'] as String?,
      adresaBcId: json['adresa_bc_id'] as String?,
      adresaVsId: json['adresa_vs_id'] as String?,
      cena: (json['cena'] as num?)?.toDouble(),
      trebaRacun: json['treba_racun'] as bool? ?? false,
      pin: json['pin'] as String?,
      email: json['email'] as String?,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String)?.toLocal() : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String)?.toLocal() : null,
    );
  }

  /// Samo polja koja se šalju pri insertu — id i timestamps generiše baza.
  Map<String, dynamic> toJson() {
    return {
      'ime': ime,
      'status': status,
      'treba_racun': trebaRacun,
      if (telefon != null) 'telefon': telefon,
      if (adresaBcId != null) 'adresa_bc_id': adresaBcId,
      if (adresaVsId != null) 'adresa_vs_id': adresaVsId,
      if (cena != null) 'cena': cena,
      if (pin != null) 'pin': pin,
      if (email != null) 'email': email,
    };
  }

  V2Posiljka copyWith({
    String? id,
    String? ime,
    String? status,
    String? telefon,
    String? adresaBcId,
    String? adresaVsId,
    double? cena,
    bool? trebaRacun,
    String? pin,
    String? email,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return V2Posiljka(
      id: id ?? this.id,
      ime: ime ?? this.ime,
      status: status ?? this.status,
      telefon: telefon ?? this.telefon,
      adresaBcId: adresaBcId ?? this.adresaBcId,
      adresaVsId: adresaVsId ?? this.adresaVsId,
      cena: cena ?? this.cena,
      trebaRacun: trebaRacun ?? this.trebaRacun,
      pin: pin ?? this.pin,
      email: email ?? this.email,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is V2Posiljka && runtimeType == other.runtimeType && id == other.id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'V2Posiljka(id: $id, ime: $ime, status: $status)';
}
