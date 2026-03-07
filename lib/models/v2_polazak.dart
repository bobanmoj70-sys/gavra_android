import 'v2_putnik.dart';

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

  // Polja iz join-a (opciono)
  final String? putnikIme;
  final String? brojTelefona;
  final String? tipPutnika;

  V2Polazak({
    required this.id,
    this.putnikId,
    this.grad,
    this.dan,
    this.zeljenoVreme,
    this.dodeljenoVreme,
    this.status = statusObrada,
    this.createdAt,
    this.updatedAt,
    this.processedAt,
    this.alternativeVreme1,
    this.alternativeVreme2,
    this.brojMesta = 1,
    this.customAdresaId,
    this.cancelledBy,
    this.pokupljenoBy,
    this.approvedBy,
    this.putnikIme,
    this.brojTelefona,
    this.tipPutnika,
  });

  factory V2Polazak.fromJson(Map<String, dynamic> json) {
    // putnikIme, brojTelefona, tipPutnika se enrichuju u servisu iz v2_* cache-a
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) throw ArgumentError('V2Polazak.fromJson: id je null/prazan');
    final putnikTabela = json['putnik_tabela'] as String?;
    final tipPutnika = V2Putnik.tipIzTabele(putnikTabela) ?? json['tip_putnika'] as String? ?? json['tip'] as String?;

    return V2Polazak(
      id: id,
      putnikId: json['putnik_id'] as String?,
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
      customAdresaId: json['custom_adresa_id'] as String?,
      cancelledBy: json['otkazao'] as String?,
      pokupljenoBy: json['pokupio'] as String?,
      approvedBy: json['odobrio'] as String?,
      putnikIme: json['putnik_ime'] as String?, // enrichuje se u servisu
      brojTelefona: json['broj_telefona'] as String?, // enrichuje se u servisu
      tipPutnika: tipPutnika,
    );
  }

  V2Polazak copyWith({
    String? id,
    String? putnikId,
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
    String? customAdresaId,
    String? cancelledBy,
    String? pokupljenoBy,
    String? approvedBy,
    String? putnikIme,
    String? brojTelefona,
    String? tipPutnika,
  }) {
    return V2Polazak(
      id: id ?? this.id,
      putnikId: putnikId ?? this.putnikId,
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
      customAdresaId: customAdresaId ?? this.customAdresaId,
      cancelledBy: cancelledBy ?? this.cancelledBy,
      pokupljenoBy: pokupljenoBy ?? this.pokupljenoBy,
      approvedBy: approvedBy ?? this.approvedBy,
      putnikIme: putnikIme ?? this.putnikIme,
      brojTelefona: brojTelefona ?? this.brojTelefona,
      tipPutnika: tipPutnika ?? this.tipPutnika,
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
