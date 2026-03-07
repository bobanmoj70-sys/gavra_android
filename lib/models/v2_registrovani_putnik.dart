import '../services/v2_adresa_supabase_service.dart';

class V2RegistrovaniPutnik {
  static const statusAktivan = 'aktivan';
  static const statusNeaktivan = 'neaktivan';
  static const statusGodisnji = 'godisnji';
  static const statusBolovanje = 'bolovanje';

  V2RegistrovaniPutnik({
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

  bool get aktivan => status == statusAktivan;

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

  factory V2RegistrovaniPutnik.fromMap(Map<String, dynamic> map) {
    final id = map['id'] as String?;
    if (id == null || id.isEmpty) throw ArgumentError('V2RegistrovaniPutnik.fromMap: id je null ili prazan');
    final v2Tabela = map['_tabela'] as String? ?? '';
    final bool dnevniIliPosiljka = v2Tabela == 'v2_dnevni' || v2Tabela == 'v2_posiljke';
    return V2RegistrovaniPutnik(
      id: id,
      ime: map['ime'] as String? ?? '',
      v2Tabela: v2Tabela,
      status: map['status'] as String? ?? statusAktivan,
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
      createdAt: map['created_at'] != null
          ? (DateTime.tryParse(map['created_at'] as String)?.toLocal() ?? DateTime.now())
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? (DateTime.tryParse(map['updated_at'] as String)?.toLocal() ?? DateTime.now())
          : DateTime.now(),
      adresa: (map['adresa_bc'] is Map ? (map['adresa_bc'] as Map)['naziv'] as String? : null) ??
          (map['adresa_vs'] is Map ? (map['adresa_vs'] as Map)['naziv'] as String? : null),
      grad: map['adresa_bc'] is Map ? 'BC' : (map['adresa_vs'] is Map ? 'VS' : null),
    );
  }

  Map<String, dynamic> toMap() {
    final bool dnevniIliPosiljka = v2Tabela == 'v2_dnevni' || v2Tabela == 'v2_posiljke';
    final result = <String, dynamic>{
      'ime': ime,
      'status': status,
      if (telefon != null) 'telefon': telefon,
      if (adresaBcId != null) 'adresa_bc_id': adresaBcId,
      if (adresaVsId != null) 'adresa_vs_id': adresaVsId,
      if (pin != null) 'pin': pin,
      if (email != null) 'email': email,
      'treba_racun': trebaRacun,
    };

    if (v2Tabela != 'v2_posiljke' && telefon2 != null) result['telefon_2'] = telefon2;
    if (v2Tabela == 'v2_ucenici') {
      if (telefonOca != null) result['telefon_oca'] = telefonOca;
      if (telefonMajke != null) result['telefon_majke'] = telefonMajke;
    }
    if (dnevniIliPosiljka) {
      if (cena != null) result['cena'] = cena;
      if (v2Tabela == 'v2_dnevni') result['broj_mesta'] = brojMesta;
    } else {
      if (cena != null) result['cena_po_danu'] = cena;
      result['broj_mesta'] = brojMesta;
    }

    return result;
  }

  V2RegistrovaniPutnik copyWith({
    String? id,
    String? ime,
    String? v2Tabela,
    String? status,
    Object? telefon = _sentinel,
    Object? telefon2 = _sentinel,
    Object? telefonOca = _sentinel,
    Object? telefonMajke = _sentinel,
    Object? adresaBcId = _sentinel,
    Object? adresaVsId = _sentinel,
    Object? pin = _sentinel,
    Object? email = _sentinel,
    Object? cena = _sentinel,
    bool? trebaRacun,
    int? brojMesta,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? adresa = _sentinel,
    Object? grad = _sentinel,
  }) {
    return V2RegistrovaniPutnik(
      id: id ?? this.id,
      ime: ime ?? this.ime,
      v2Tabela: v2Tabela ?? this.v2Tabela,
      status: status ?? this.status,
      telefon: telefon == _sentinel ? this.telefon : telefon as String?,
      telefon2: telefon2 == _sentinel ? this.telefon2 : telefon2 as String?,
      telefonOca: telefonOca == _sentinel ? this.telefonOca : telefonOca as String?,
      telefonMajke: telefonMajke == _sentinel ? this.telefonMajke : telefonMajke as String?,
      adresaBcId: adresaBcId == _sentinel ? this.adresaBcId : adresaBcId as String?,
      adresaVsId: adresaVsId == _sentinel ? this.adresaVsId : adresaVsId as String?,
      pin: pin == _sentinel ? this.pin : pin as String?,
      email: email == _sentinel ? this.email : email as String?,
      cena: cena == _sentinel ? this.cena : cena as double?,
      trebaRacun: trebaRacun ?? this.trebaRacun,
      brojMesta: brojMesta ?? this.brojMesta,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      adresa: adresa == _sentinel ? this.adresa : adresa as String?,
      grad: grad == _sentinel ? this.grad : grad as String?,
    );
  }

  @override
  String toString() => 'V2RegistrovaniPutnik(id: $id, ime: $ime, v2Tabela: $v2Tabela, '
      'status: $status, brojMesta: $brojMesta, cena: $cena)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (runtimeType == other.runtimeType && other is V2RegistrovaniPutnik && other.id == id);

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
    final grad = selektovaniGrad?.toUpperCase() ?? '';
    final isBC = grad == 'BC' || grad.contains('BELA');
    if (isBC) {
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

const _sentinel = Object();
