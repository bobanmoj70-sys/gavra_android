import '../utils/v3_dan_helper.dart';
import '../utils/v3_date_utils.dart';

class V3Zahtev {
  final String id;
  final String putnikId;
  final DateTime datum;
  final String grad;
  final String zeljenoVreme;
  final int brojMesta;
  final String status; // 'obrada', 'odobreno', 'alternativa', 'otkazano', 'odbijeno'
  final String? napomena;
  final String? dodeljenoVreme;
  final bool koristiSekundarnu;
  final String? adresaIdOverride;
  final String? altVremePre;
  final String? altVremePosle;
  final String? altNapomena;
  final bool aktivno;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;

  V3Zahtev({
    required this.id,
    required this.putnikId,
    required this.datum,
    required this.grad,
    required this.zeljenoVreme,
    this.brojMesta = 1,
    this.status = 'obrada',
    this.napomena,
    this.dodeljenoVreme,
    this.koristiSekundarnu = false,
    this.adresaIdOverride,
    this.altVremePre,
    this.altVremePosle,
    this.altNapomena,
    this.aktivno = true,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
  });

  factory V3Zahtev.fromJson(Map<String, dynamic> json) {
    return V3Zahtev(
      id: json['id'] as String? ?? '',
      putnikId: json['putnik_id'] as String? ?? '',
      datum: json['datum'] != null ? DateTime.parse(json['datum'] as String) : DateTime.now(),
      grad: json['grad'] as String? ?? '',
      zeljenoVreme: json['zeljeno_vreme'] as String? ?? '',
      brojMesta: json['broj_mesta'] as int? ?? 1,
      status: json['status'] as String? ?? 'obrada',
      napomena: json['napomena'] as String?,
      dodeljenoVreme: json['dodeljeno_vreme'] as String?,
      koristiSekundarnu: json['koristi_sekundarnu'] as bool? ?? false,
      adresaIdOverride: json['adresa_id_override'] as String?,
      altVremePre: json['alt_vreme_pre'] as String?,
      altVremePosle: json['alt_vreme_posle'] as String?,
      altNapomena: json['alt_napomena'] as String?,
      aktivno: json['aktivno'] as bool? ?? true,
      createdAt: V3DateUtils.parseTs(json['created_at'] as String?),
      updatedAt: V3DateUtils.parseTs(json['updated_at'] as String?),
      createdBy: json['created_by'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'putnik_id': putnikId.isNotEmpty ? putnikId : null,
      'datum': V3DanHelper.parseIsoDatePart(datum.toIso8601String()),
      'grad': grad,
      'zeljeno_vreme': zeljenoVreme,
      'broj_mesta': brojMesta,
      'status': status,
      'napomena': napomena,
      'dodeljeno_vreme': dodeljenoVreme,
      'koristi_sekundarnu': koristiSekundarnu,
      'adresa_id_override': adresaIdOverride,
      'alt_vreme_pre': altVremePre,
      'alt_vreme_posle': altVremePosle,
      'alt_napomena': altNapomena,
      'aktivno': aktivno,
      if (createdBy != null) 'created_by': createdBy,
    };
  }

  V3Zahtev copyWith({
    String? id,
    String? putnikId,
    DateTime? datum,
    String? grad,
    String? zeljenoVreme,
    int? brojMesta,
    String? status,
    String? napomena,
    String? dodeljenoVreme,
    bool? koristiSekundarnu,
    String? adresaIdOverride,
    String? altVremePre,
    String? altVremePosle,
    String? altNapomena,
    bool? aktivno,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return V3Zahtev(
      id: id ?? this.id,
      putnikId: putnikId ?? this.putnikId,
      datum: datum ?? this.datum,
      grad: grad ?? this.grad,
      zeljenoVreme: zeljenoVreme ?? this.zeljenoVreme,
      brojMesta: brojMesta ?? this.brojMesta,
      status: status ?? this.status,
      napomena: napomena ?? this.napomena,
      dodeljenoVreme: dodeljenoVreme ?? this.dodeljenoVreme,
      koristiSekundarnu: koristiSekundarnu ?? this.koristiSekundarnu,
      adresaIdOverride: adresaIdOverride ?? this.adresaIdOverride,
      altVremePre: altVremePre ?? this.altVremePre,
      altVremePosle: altVremePosle ?? this.altVremePosle,
      altNapomena: altNapomena ?? this.altNapomena,
      aktivno: aktivno ?? this.aktivno,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
