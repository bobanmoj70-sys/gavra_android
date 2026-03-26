import '../utils/v3_date_utils.dart';

class V3PutnikArhiva {
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

  V3PutnikArhiva({
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

  factory V3PutnikArhiva.fromJson(Map<String, dynamic> json) {
    return V3PutnikArhiva(
      id: json['id']?.toString() ?? '',
      createdAt: V3DateUtils.parseTs(json['created_at'] as String?),
      updatedAt: V3DateUtils.parseTs(json['updated_at'] as String?),
      putnikId: json['putnik_id']?.toString() ?? '',
      putnikImePrezime: json['putnik_ime_prezime'] as String? ?? '',
      iznos: (json['iznos'] as num?)?.toDouble() ?? 0,
      tipAkcije: json['tip_akcije'] as String? ?? '',
      zaMesec: json['za_mesec'] as int? ?? 0,
      zaGodinu: json['za_godinu'] as int? ?? 0,
      vozacId: json['vozac_id']?.toString() ?? '',
      vozacImePrezime: json['vozac_ime_prezime'] as String? ?? '',
      aktivno: json['aktivno'] as bool? ?? true,
      updatedBy: json['updated_by'] as String?,
      createdBy: json['created_by'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'putnik_id': putnikId,
        'putnik_ime_prezime': putnikImePrezime,
        'iznos': iznos,
        'tip_akcije': tipAkcije,
        'za_mesec': zaMesec,
        'za_godinu': zaGodinu,
        'vozac_id': vozacId,
        'vozac_ime_prezime': vozacImePrezime,
        'aktivno': aktivno,
        'updated_by': updatedBy,
        'created_by': createdBy,
      };
}
