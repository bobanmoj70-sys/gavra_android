/// Model za zahteve za mesta u kombiju (v2_polasci tabela)
class V2Polazak {
  /// Mogući statusi polaska.
  static const String statusObrada = 'obrada';
  static const String statusOdobreno = 'odobreno';
  static const String statusOdbijeno = 'odbijeno';
  static const String statusOtkazano = 'otkazano';
  static const String statusPokupljen = 'pokupljen';

  final String id;
  final String? putnikId;
  final String? grad;
  final String? dan;
  final String? zeljenoVreme;
  final String? dodeljenoVreme;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? processedAt;
  final String? alternativeVreme1;
  final String? alternativeVreme2;
  final int brojMesta;
  final String? customAdresaId;
  final String? cancelledBy; // Ime vozača koji je otkazao
  final String? pokupljenoBy; // Ime vozača koji je pokupio putnika
  final String? approvedBy; // Ime vozača/admina koji je odobrio

  final String? putnikTabela;
  final String? adresaId;
  final DateTime? datumAkcije;
  final DateTime? pokupljenDatum;
  final bool placen;
  final double? placenIznos;
  final String? placenVozacId;
  final String? placenVozacIme;
  final String? placenTip;
  final DateTime? placenAt;
  final String? pokupioVozacId;
  final String? otkazaoVozacId;
  final String? datumSedmice;
  final String? brojTelefona;

  // Denormalizovana polja iz v2_home View-a ili triggera
  final String? putnikIme;
  final String? adresaNaziv;
  final String? adresaBcNaziv;
  final String? adresaVsNaziv;
  final String? tipPutnika;

  V2Polazak({
    required this.id,
    required this.putnikId,
    this.putnikTabela,
    this.dan,
    this.grad,
    this.zeljenoVreme,
    this.dodeljenoVreme,
    this.status = statusObrada,
    this.brojMesta = 1,
    this.adresaId,
    this.createdAt,
    this.updatedAt,
    this.processedAt,
    this.alternativeVreme1,
    this.alternativeVreme2,
    this.customAdresaId,
    this.cancelledBy,
    this.pokupljenoBy,
    this.approvedBy,
    this.datumAkcije,
    this.pokupljenDatum,
    this.placen = false,
    this.placenIznos,
    this.placenVozacId,
    this.placenVozacIme,
    this.placenTip,
    this.placenAt,
    this.pokupioVozacId,
    this.otkazaoVozacId,
    this.datumSedmice,
    this.putnikIme,
    this.adresaNaziv,
    this.adresaBcNaziv,
    this.adresaVsNaziv,
    this.tipPutnika,
    this.brojTelefona,
  });

  factory V2Polazak.fromJson(Map<String, dynamic> json) {
    return V2Polazak(
      id: json['id'] as String? ?? '',
      putnikId: json['putnik_id'] as String?,
      putnikTabela: json['putnik_tabela'] as String?,
      grad: json['grad'] as String?,
      dan: json['dan'] as String?,
      zeljenoVreme: json['zeljeno_vreme'] as String?,
      dodeljenoVreme: json['dodeljeno_vreme'] as String?,
      status: json['status'] as String? ?? statusObrada,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String)?.toLocal() : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String)?.toLocal() : null,
      processedAt: json['processed_at'] != null ? DateTime.tryParse(json['processed_at'] as String)?.toLocal() : null,
      alternativeVreme1: json['alternativno_vreme_1'] as String?,
      alternativeVreme2: json['alternativno_vreme_2'] as String?,
      brojMesta: (json['broj_mesta'] as num?)?.toInt() ?? 1,
      adresaId: json['adresa_id'] as String?,
      customAdresaId: json['custom_adresa_id'] as String?,
      cancelledBy: json['cancelled_by'] as String?,
      pokupljenoBy: json['pokupio'] as String?,
      approvedBy: json['odobrio'] as String?,
      datumAkcije: json['datum_akcije'] != null ? DateTime.tryParse(json['datum_akcije'] as String)?.toLocal() : null,
      pokupljenDatum:
          json['pokupljen_datum'] != null ? DateTime.tryParse(json['pokupljen_datum'] as String)?.toLocal() : null,
      placen: json['placen'] as bool? ?? false,
      placenIznos: (json['placen_iznos'] as num?)?.toDouble(),
      placenVozacId: json['placen_vozac_id'] as String?,
      placenVozacIme: json['placen_vozac_ime'] as String?,
      placenTip: json['placen_tip'] as String?,
      placenAt: json['placen_at'] != null ? DateTime.tryParse(json['placen_at'] as String)?.toLocal() : null,
      pokupioVozacId: json['pokupio_vozac_id'] as String?,
      otkazaoVozacId: json['otkazao_vozac_id'] as String?,
      datumSedmice: json['datum_sedmice'] as String?,
      putnikIme: json['putnik_ime'] as String?,
      adresaNaziv: json['adresa_naziv'] as String?,
      adresaBcNaziv: json['adresa_bc_naziv'] as String?,
      adresaVsNaziv: json['adresa_vs_naziv'] as String?,
      tipPutnika: json['tip_putnika'] as String?,
      brojTelefona: json['broj_telefona'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'putnik_id': putnikId,
      'putnik_tabela': putnikTabela,
      'grad': grad,
      'dan': dan,
      'zeljeno_vreme': zeljenoVreme,
      'dodeljeno_vreme': dodeljenoVreme,
      'status': status,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'processed_at': processedAt?.toIso8601String(),
      'alternativno_vreme_1': alternativeVreme1,
      'alternativno_vreme_2': alternativeVreme2,
      'broj_mesta': brojMesta,
      'adresa_id': adresaId,
      'custom_adresa_id': customAdresaId,
      'cancelled_by': cancelledBy,
      'pokupio': pokupljenoBy,
      'odobrio': approvedBy,
      'datum_akcije': datumAkcije?.toIso8601String(),
      'pokupljen_datum': pokupljenDatum?.toIso8601String(),
      'placen': placen,
      'placen_iznos': placenIznos,
      'placen_vozac_id': placenVozacId,
      'placen_vozac_ime': placenVozacIme,
      'placen_tip': placenTip,
      'placen_at': placenAt?.toIso8601String(),
      'pokupio_vozac_id': pokupioVozacId,
      'otkazao_vozac_id': otkazaoVozacId,
      'datum_sedmice': datumSedmice,
      'putnik_ime': putnikIme,
      'adresa_naziv': adresaNaziv,
      'adresa_bc_naziv': adresaBcNaziv,
      'adresa_vs_naziv': adresaVsNaziv,
      'tip_putnika': tipPutnika,
      'broj_telefona': brojTelefona,
    };
  }

  V2Polazak copyWith({
    String? id,
    String? putnikId,
    String? putnikTabela,
    String? grad,
    String? dan,
    String? zeljenoVreme,
    String? dodeljenoVreme,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? processedAt,
    String? alternativeVreme1,
    String? alternativeVreme2,
    int? brojMesta,
    String? adresaId,
    String? customAdresaId,
    String? cancelledBy,
    String? pokupljenoBy,
    String? approvedBy,
    DateTime? datumAkcije,
    DateTime? pokupljenDatum,
    bool? placen,
    double? placenIznos,
    String? placenVozacId,
    String? placenVozacIme,
    String? placenTip,
    DateTime? placenAt,
    String? pokupioVozacId,
    String? otkazaoVozacId,
    String? datumSedmice,
    String? putnikIme,
    String? adresaNaziv,
    String? adresaBcNaziv,
    String? adresaVsNaziv,
    String? tipPutnika,
    String? brojTelefona,
  }) {
    return V2Polazak(
      id: id ?? this.id,
      putnikId: putnikId ?? this.putnikId,
      putnikTabela: putnikTabela ?? this.putnikTabela,
      grad: grad ?? this.grad,
      dan: dan ?? this.dan,
      zeljenoVreme: zeljenoVreme ?? this.zeljenoVreme,
      dodeljenoVreme: dodeljenoVreme ?? this.dodeljenoVreme,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      processedAt: processedAt ?? this.processedAt,
      alternativeVreme1: alternativeVreme1 ?? this.alternativeVreme1,
      alternativeVreme2: alternativeVreme2 ?? this.alternativeVreme2,
      brojMesta: brojMesta ?? this.brojMesta,
      adresaId: adresaId ?? this.adresaId,
      customAdresaId: customAdresaId ?? this.customAdresaId,
      cancelledBy: cancelledBy ?? this.cancelledBy,
      pokupljenoBy: pokupljenoBy ?? this.pokupljenoBy,
      approvedBy: approvedBy ?? this.approvedBy,
      datumAkcije: datumAkcije ?? this.datumAkcije,
      pokupljenDatum: pokupljenDatum ?? this.pokupljenDatum,
      placen: placen ?? this.placen,
      placenIznos: placenIznos ?? this.placenIznos,
      placenVozacId: placenVozacId ?? this.placenVozacId,
      placenVozacIme: placenVozacIme ?? this.placenVozacIme,
      placenTip: placenTip ?? this.placenTip,
      placenAt: placenAt ?? this.placenAt,
      pokupioVozacId: pokupioVozacId ?? this.pokupioVozacId,
      otkazaoVozacId: otkazaoVozacId ?? this.otkazaoVozacId,
      datumSedmice: datumSedmice ?? this.datumSedmice,
      putnikIme: putnikIme ?? this.putnikIme,
      adresaNaziv: adresaNaziv ?? this.adresaNaziv,
      adresaBcNaziv: adresaBcNaziv ?? this.adresaBcNaziv,
      adresaVsNaziv: adresaVsNaziv ?? this.adresaVsNaziv,
      tipPutnika: tipPutnika ?? this.tipPutnika,
      brojTelefona: brojTelefona ?? this.brojTelefona,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is V2Polazak && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'V2Polazak(id: $id, putnik: $putnikIme, status: $status, dan: $dan, vreme: $zeljenoVreme)';
}
