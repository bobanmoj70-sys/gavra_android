import '../utils/v3_date_utils.dart';

class V3UplataArhiva {
  final String id;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String putnikId;
  final String putnikImePrezime;
  final double iznos;
  final String tipAkcije;
  final int zaMesec;
  final int zaGodinu;
  final String vozacId;
  final String vozacImePrezime;
  final bool aktivno;
  final String? updatedBy;
  final String? createdBy;

  V3UplataArhiva({
    required this.id,
    this.createdAt,
    this.updatedAt,
    required this.putnikId,
    required this.putnikImePrezime,
    this.iznos = 0,
    required this.tipAkcije,
    this.zaMesec = 0,
    this.zaGodinu = 0,
    required this.vozacId,
    required this.vozacImePrezime,
    this.aktivno = true,
    this.updatedBy,
    this.createdBy,
  });

  factory V3UplataArhiva.fromJson(Map<String, dynamic> json) {
    return V3UplataArhiva(
      id: json['id']?.toString() ?? '',
      createdAt: V3DateUtils.parseTs(json['created_at'] as String?),
      updatedAt: V3DateUtils.parseTs(json['updated_at'] as String?),
      putnikId: (json['created_by'] ?? json['putnik_id'])?.toString() ?? '',
      putnikImePrezime: json['putnik_ime'] as String? ?? '',
      iznos: (json['iznos'] as num?)?.toDouble() ?? 0,
      tipAkcije: (json['tip_akcije'] as String?) ?? (json['isplata_iz'] as String?) ?? 'uplata',
      zaMesec: (json['za_mesec'] as int?) ?? (json['mesec'] as int?) ?? 0,
      zaGodinu: (json['za_godinu'] as int?) ?? (json['godina'] as int?) ?? 0,
      vozacId: (json['naplatio_vozac_id'] ?? json['vozac_id'])?.toString() ?? '',
      vozacImePrezime: json['vozac_ime'] as String? ?? '',
      aktivno: json['aktivno'] as bool? ?? true,
      updatedBy: json['updated_by'] as String?,
      createdBy: json['created_by'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'created_by': createdBy ?? (putnikId.isNotEmpty ? putnikId : null),
        'putnik_ime': putnikImePrezime,
        'iznos': iznos,
        'isplata_iz': tipAkcije,
        'kategorija': 'voznja',
        'mesec': zaMesec,
        'godina': zaGodinu,
        'naplatio_vozac_id': vozacId,
        'vozac_ime': vozacImePrezime,
        'aktivno': aktivno,
        'updated_by': updatedBy,
      };
}
