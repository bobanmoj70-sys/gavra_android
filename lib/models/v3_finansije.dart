import '../utils/v3_date_utils.dart';

/// Model za tabelu v3_finansije
class V3Trosak {
  final String id;
  final String tip; // 'prihod' | 'rashod'
  final String naziv;
  final String? kategorija;
  final double iznos;
  final String isplataIz; // 'pazar', 'racun', ...
  final bool ponavljajMesecno;
  final int mesec;
  final int godina;
  final String? vozacId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  V3Trosak({
    required this.id,
    this.tip = 'rashod',
    required this.naziv,
    this.kategorija,
    this.iznos = 0,
    this.isplataIz = 'pazar',
    this.ponavljajMesecno = true,
    required this.mesec,
    required this.godina,
    this.vozacId,
    this.createdAt,
    this.updatedAt,
  });

  factory V3Trosak.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return V3Trosak(
      id: json['id']?.toString() ?? '',
      tip: json['tip'] as String? ?? 'rashod',
      naziv: json['naziv'] as String? ?? '',
      kategorija: json['kategorija'] as String?,
      iznos: (json['iznos'] as num?)?.toDouble() ?? 0,
      isplataIz: json['isplata_iz'] as String? ?? 'pazar',
      ponavljajMesecno: json['ponavljaj_mesecno'] as bool? ?? true,
      mesec: json['mesec'] as int? ?? now.month,
      godina: json['godina'] as int? ?? now.year,
      vozacId: json['naplaceno_by']?.toString(),
      createdAt: V3DateUtils.parseTs(json['created_at'] as String?),
      updatedAt: V3DateUtils.parseTs(json['updated_at'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'tip': tip,
        'naziv': naziv,
        'kategorija': kategorija,
        'iznos': iznos,
        'isplata_iz': isplataIz,
        'ponavljaj_mesecno': ponavljajMesecno,
        'mesec': mesec,
        'godina': godina,
        'naplaceno_by': vozacId,
      };
}
