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
      vozacId: (json['naplaceno_by'] ?? json['vozac_v3_auth_id'])?.toString(),
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

// --- Backward compat aliases za stari kod ---

/// @deprecated Koristi V3Trosak — mapira se na v3_finansije
class V3FinansijskiUnos {
  final String id;
  final String tip;
  final String kategorija;
  final String opis;
  final double iznos;
  final DateTime datum;
  final String? vozacId;
  final String? voziloId;
  final String? putnikId;
  final DateTime createdAt;

  V3FinansijskiUnos({
    required this.id,
    required this.tip,
    required this.kategorija,
    required this.opis,
    required this.iznos,
    required this.datum,
    this.vozacId,
    this.voziloId,
    this.putnikId,
    required this.createdAt,
  });

  factory V3FinansijskiUnos.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return V3FinansijskiUnos(
      id: json['id']?.toString() ?? '',
      tip: json['tip'] as String? ?? 'trosak',
      kategorija: json['kategorija'] as String? ?? 'ostalo',
      opis: json['naziv'] as String? ?? json['opis'] as String? ?? '',
      iznos: (json['iznos'] as num?)?.toDouble() ?? 0.0,
      datum: V3DateUtils.parseTs(json['created_at'] as String?) ?? now,
      vozacId: (json['naplaceno_by'] ?? json['vozac_v3_auth_id'])?.toString(),
      voziloId: null,
      putnikId: null,
      createdAt: now,
    );
  }

  Map<String, dynamic> toJson() => {
        'naziv': opis,
        'kategorija': kategorija,
        'iznos': iznos,
        'naplaceno_by': vozacId,
      };
}

class V3FinansijskiIzvestaj {
  final double prihodDanas;
  final double trosakDanas;
  final double prihodMesec;
  final double trosakMesec;
  final Map<String, double> troskoviPoKategoriji;

  V3FinansijskiIzvestaj({
    this.prihodDanas = 0,
    this.trosakDanas = 0,
    this.prihodMesec = 0,
    this.trosakMesec = 0,
    this.troskoviPoKategoriji = const {},
  });

  double get netoDanas => prihodDanas - trosakDanas;
  double get netoMesec => prihodMesec - trosakMesec;
}
