import '../utils/v3_date_utils.dart';

class V3Zahtev {
  final String id;
  final String putnikId;
  final DateTime datum;
  final String grad;
  final String trazeniPolazakAt;
  final String status; // 'obrada', 'odobreno', 'alternativa', 'otkazano', 'odbijeno'
  final String? polazakAt;
  final bool koristiSekundarnu;
  final String? adresaIdOverride;
  final String? altVremePre;
  final String? altVremePosle;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;

  V3Zahtev({
    required this.id,
    required this.putnikId,
    required this.datum,
    required this.grad,
    required this.trazeniPolazakAt,
    this.status = 'obrada',
    this.polazakAt,
    this.koristiSekundarnu = false,
    this.adresaIdOverride,
    this.altVremePre,
    this.altVremePosle,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
  });

  factory V3Zahtev.fromJson(Map<String, dynamic> json) {
    final putnikId = (json['created_by'] as String?) ?? '';

    return V3Zahtev(
      id: json['id'] as String? ?? '',
      putnikId: putnikId,
      datum: json['datum'] != null ? DateTime.parse(json['datum'] as String) : DateTime.now(),
      grad: json['grad'] as String? ?? '',
      trazeniPolazakAt: json['trazeni_polazak_at'] as String? ?? '',
      status: json['status'] as String? ?? 'obrada',
      polazakAt: json['polazak_at'] as String?,
      koristiSekundarnu: json['koristi_sekundarnu'] as bool? ?? false,
      adresaIdOverride: json['adresa_override_id'] as String?,
      altVremePre: json['alternativa_pre_at'] as String?,
      altVremePosle: json['alternativa_posle_at'] as String?,
      createdAt: V3DateUtils.parseTs(json['created_at'] as String?),
      updatedAt: V3DateUtils.parseTs(json['updated_at'] as String?),
      createdBy: json['created_by'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final effectiveCreatedBy =
        (createdBy != null && createdBy!.isNotEmpty) ? createdBy : (putnikId.isNotEmpty ? putnikId : null);

    return {
      if (id.isNotEmpty) 'id': id,
      'datum': V3DateUtils.parseIsoDatePart(datum.toIso8601String()),
      'grad': grad,
      'trazeni_polazak_at': trazeniPolazakAt.isEmpty ? null : trazeniPolazakAt,
      'status': status,
      'polazak_at': polazakAt,
      'koristi_sekundarnu': koristiSekundarnu,
      'adresa_override_id': adresaIdOverride,
      'alternativa_pre_at': altVremePre,
      'alternativa_posle_at': altVremePosle,
      if (effectiveCreatedBy != null) 'created_by': effectiveCreatedBy,
    };
  }
}
