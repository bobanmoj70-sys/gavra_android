/// Model za zahteve za mesta u kombiju (v2_polasci tabela)
class V2Polazak {
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
    this.status = 'obrada',
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
    // Provera da li su podaci o putniku ugneždeni (iz JOIN-a sa v2_radnici/v2_ucenici)
    final putnikData = json['registrovani_putnici'] as Map<String, dynamic>?;

    return V2Polazak(
      id: json['id'] as String,
      putnikId: json['putnik_id'] as String?,
      grad: json['grad'] as String?,
      dan: json['dan'] as String?,
      zeljenoVreme: json['zeljeno_vreme'] as String?,
      dodeljenoVreme: json['dodeljeno_vreme'] as String?,
      status: json['status'] as String? ?? 'obrada',
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String) : null,
      processedAt: json['processed_at'] != null ? DateTime.parse(json['processed_at'] as String) : null,
      alternativeVreme1: json['alternative_vreme_1'] as String?,
      alternativeVreme2: json['alternative_vreme_2'] as String?,
      brojMesta: json['broj_mesta'] as int? ?? 1,
      customAdresaId: json['custom_adresa_id'] as String?,
      cancelledBy: json['cancelled_by'] as String?,
      pokupljenoBy: json['pokupljeno_by'] as String?,
      approvedBy: json['approved_by'] as String?,
      putnikIme: putnikData?['putnik_ime'] ?? json['putnik_ime'] as String?,
      brojTelefona: putnikData?['broj_telefona'] ?? json['broj_telefona'] as String?,
      tipPutnika: putnikData?['tip'] ?? json['tip_putnika'] ?? json['tip'] as String?,
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
}
