/// Model za dnevne putnike (v2_dnevni tabela)
class V2Dnevni {
  final String id;
  final String ime;
  final String status;
  final String? telefon;
  final String? telefon2;
  final String? adresaBcId;
  final String? adresaVsId;
  final double? cena;
  final bool trebaRacun;
  final String? pin;
  final String? email;
  final int? brojMesta;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  V2Dnevni({
    required this.id,
    required this.ime,
    this.status = 'aktivan',
    this.telefon,
    this.telefon2,
    this.adresaBcId,
    this.adresaVsId,
    this.cena,
    this.trebaRacun = false,
    this.pin,
    this.email,
    this.brojMesta,
    this.createdAt,
    this.updatedAt,
  });

  factory V2Dnevni.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) throw ArgumentError('V2Dnevni.fromJson: id je null ili prazan');
    final ime = json['ime'] as String?;
    if (ime == null) throw ArgumentError('V2Dnevni.fromJson: ime je null');
    return V2Dnevni(
      id: id,
      ime: ime,
      status: json['status'] as String? ?? 'aktivan',
      telefon: json['telefon'] as String?,
      telefon2: json['telefon_2'] as String?,
      adresaBcId: json['adresa_bc_id'] as String?,
      adresaVsId: json['adresa_vs_id'] as String?,
      cena: (json['cena'] as num?)?.toDouble(),
      trebaRacun: json['treba_racun'] as bool? ?? false,
      pin: json['pin'] as String?,
      email: json['email'] as String?,
      brojMesta: (json['broj_mesta'] as num?)?.toInt(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)?.toLocal()
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)?.toLocal()
          : null,
    );
  }

  V2Dnevni copyWith({
    String? id,
    String? ime,
    String? status,
    String? telefon,
    String? telefon2,
    String? adresaBcId,
    String? adresaVsId,
    double? cena,
    bool? trebaRacun,
    String? pin,
    String? email,
    int? brojMesta,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return V2Dnevni(
      id: id ?? this.id,
      ime: ime ?? this.ime,
      status: status ?? this.status,
      telefon: telefon ?? this.telefon,
      telefon2: telefon2 ?? this.telefon2,
      adresaBcId: adresaBcId ?? this.adresaBcId,
      adresaVsId: adresaVsId ?? this.adresaVsId,
      cena: cena ?? this.cena,
      trebaRacun: trebaRacun ?? this.trebaRacun,
      pin: pin ?? this.pin,
      email: email ?? this.email,
      brojMesta: brojMesta ?? this.brojMesta,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is V2Dnevni && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
