import '../services/v2_adresa_supabase_service.dart';

class RegistrovaniPutnik {
  RegistrovaniPutnik({
    required this.id,
    required this.ime,
    required this.v2Tabela,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.telefon,
    this.telefon2,
    this.telefonOca,
    this.telefonMajke,
    this.adresaBcId,
    this.adresaVsId,
    this.pin,
    this.email,
    this.cena,
    this.trebaRacun = false,
    this.brojMesta = 1,
    this.adresa,
    this.grad,
  });

  final String id;
  final String ime;

  /// v2_radnici | v2_ucenici | v2_dnevni | v2_posiljke
  final String v2Tabela;

  /// aktivan | neaktivan | godisnji | bolovanje
  final String status;

  bool get aktivan => status == 'aktivan';

  final String? telefon;
  final String? telefon2;
  final String? telefonOca;
  final String? telefonMajke;
  final String? adresaBcId;
  final String? adresaVsId;
  final String? pin;
  final String? email;
  final double? cena;
  final bool trebaRacun;
  final int brojMesta;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Iz JOIN-a — ne ide u bazu
  final String? adresa;
  final String? grad;

  factory RegistrovaniPutnik.fromMap(Map<String, dynamic> map) {
    final v2Tabela = map['_tabela'] as String;
    final bool dnevniIliPosiljka = v2Tabela == 'v2_dnevni' || v2Tabela == 'v2_posiljke';
    return RegistrovaniPutnik(
      id: map['id'] as String,
      ime: map['ime'] as String,
      v2Tabela: v2Tabela,
      status: map['status'] as String,
      telefon: map['telefon'] as String?,
      telefon2: map['telefon_2'] as String?,
      telefonOca: map['telefon_oca'] as String?,
      telefonMajke: map['telefon_majke'] as String?,
      adresaBcId: map['adresa_bc_id'] as String?,
      adresaVsId: map['adresa_vs_id'] as String?,
      pin: map['pin'] as String?,
      email: map['email'] as String?,
      cena: dnevniIliPosiljka ? _parseNum(map['cena'])?.toDouble() : _parseNum(map['cena_po_danu'])?.toDouble(),
      trebaRacun: (map['treba_racun'] as bool?) ?? false,
      brojMesta: v2Tabela == 'v2_posiljke' ? 0 : (_parseNum(map['broj_mesta'])?.toInt() ?? 1),
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at'] as String).toLocal() : DateTime.now(),
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at'] as String).toLocal() : DateTime.now(),
      adresa: (map['adresa_bc'] is Map ? (map['adresa_bc'] as Map)['naziv'] as String? : null) ??
          (map['adresa_vs'] is Map ? (map['adresa_vs'] as Map)['naziv'] as String? : null),
      grad: map['adresa_bc'] is Map ? 'BC' : (map['adresa_vs'] is Map ? 'VS' : null),
    );
  }

  Map<String, dynamic> toMap() {
    final bool dnevniIliPosiljka = v2Tabela == 'v2_dnevni' || v2Tabela == 'v2_posiljke';
    final result = <String, dynamic>{
      'id': id,
      'ime': ime,
      'status': status,
      'telefon': telefon,
      'adresa_bc_id': adresaBcId,
      'adresa_vs_id': adresaVsId,
      'pin': pin,
      'email': email,
      'treba_racun': trebaRacun,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };

    if (v2Tabela != 'v2_posiljke') result['telefon_2'] = telefon2;
    if (v2Tabela == 'v2_ucenici') {
      result['telefon_oca'] = telefonOca;
      result['telefon_majke'] = telefonMajke;
    }
    if (dnevniIliPosiljka) {
      result['cena'] = cena;
      if (v2Tabela == 'v2_dnevni') result['broj_mesta'] = brojMesta;
    } else {
      result['cena_po_danu'] = cena;
      result['broj_mesta'] = brojMesta;
    }

    return result;
  }

  RegistrovaniPutnik copyWith({
    String? id,
    String? ime,
    String? v2Tabela,
    String? status,
    String? telefon,
    String? telefon2,
    String? telefonOca,
    String? telefonMajke,
    String? adresaBcId,
    String? adresaVsId,
    String? pin,
    String? email,
    double? cena,
    bool? trebaRacun,
    int? brojMesta,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? adresa,
    String? grad,
  }) {
    return RegistrovaniPutnik(
      id: id ?? this.id,
      ime: ime ?? this.ime,
      v2Tabela: v2Tabela ?? this.v2Tabela,
      status: status ?? this.status,
      telefon: telefon ?? this.telefon,
      telefon2: telefon2 ?? this.telefon2,
      telefonOca: telefonOca ?? this.telefonOca,
      telefonMajke: telefonMajke ?? this.telefonMajke,
      adresaBcId: adresaBcId ?? this.adresaBcId,
      adresaVsId: adresaVsId ?? this.adresaVsId,
      pin: pin ?? this.pin,
      email: email ?? this.email,
      cena: cena ?? this.cena,
      trebaRacun: trebaRacun ?? this.trebaRacun,
      brojMesta: brojMesta ?? this.brojMesta,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      adresa: adresa ?? this.adresa,
      grad: grad ?? this.grad,
    );
  }

  @override
  String toString() => 'RegistrovaniPutnik(id: $id, ime: $ime, v2Tabela: $v2Tabela, status: $status)';

  @override
  bool operator ==(Object other) => identical(this, other) || (other is RegistrovaniPutnik && other.id == id);

  @override
  int get hashCode => id.hashCode;

  String? getAdresaBelaCrkvaNaziv() {
    if (adresaBcId == null) return null;
    return V2AdresaSupabaseService.getNazivAdreseByUuid(adresaBcId);
  }

  String? getAdresaVrsacNaziv() {
    if (adresaVsId == null) return null;
    return V2AdresaSupabaseService.getNazivAdreseByUuid(adresaVsId);
  }

  String getAdresaZaSelektovaniGrad(String? selektovaniGrad) {
    final bcNaziv = getAdresaBelaCrkvaNaziv();
    final vsNaziv = getAdresaVrsacNaziv();
    if (selektovaniGrad?.toLowerCase().contains('bela') == true) {
      if (bcNaziv != null) return bcNaziv;
      if (vsNaziv != null) return vsNaziv;
    } else {
      if (vsNaziv != null) return vsNaziv;
      if (bcNaziv != null) return bcNaziv;
    }
    return 'Nema adresa';
  }

  static num? _parseNum(dynamic value) {
    if (value == null) return null;
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }
}
