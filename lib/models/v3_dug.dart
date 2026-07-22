import '../utils/v3_date_utils.dart';

class V3Dug {
  final String id;
  final String putnikId;
  final String imePrezime;
  final String tipPutnika;
  final int godina;
  final int mesec;
  final int brojVoznji;
  final double cena;
  final double ukupnaObaveza;
  final double uplaceno;
  final String vozacId;
  final String vozacIme;
  final String pokupioVozacId;
  final String pokupioVozacIme;
  final DateTime datum;
  final DateTime? pokupljenAt;
  final double iznos;
  final bool placeno;
  final DateTime? createdAt;
  final DateTime? naplacenoAt;
  final String? naplacenoBy;
  final DateTime? updatedAt;
  final String? updatedBy;
  final String? finansijeNaziv;
  final String? finansijeKategorija;

  V3Dug({
    required this.id,
    required this.putnikId,
    required this.imePrezime,
    required this.tipPutnika,
    required this.godina,
    required this.mesec,
    required this.brojVoznji,
    required this.cena,
    required this.ukupnaObaveza,
    required this.uplaceno,
    required this.vozacId,
    this.vozacIme = '',
    this.pokupioVozacId = '',
    this.pokupioVozacIme = '',
    required this.datum,
    this.pokupljenAt,
    required this.iznos,
    this.placeno = false,
    this.createdAt,
    this.naplacenoAt,
    this.naplacenoBy,
    this.updatedAt,
    this.updatedBy,
    this.finansijeNaziv,
    this.finansijeKategorija,
  });

  factory V3Dug.fromJson(Map<String, dynamic> json) {
    return V3Dug(
      id: json['id']?.toString() ?? '',
      putnikId: json['putnik_id']?.toString() ?? '',
      imePrezime: json['ime_prezime']?.toString() ?? '',
      tipPutnika: json['tip_putnika']?.toString() ?? '',
      godina: (json['godina'] as num?)?.toInt() ?? 0,
      mesec: (json['mesec'] as num?)?.toInt() ?? 0,
      brojVoznji: (json['broj_voznji'] as num?)?.toInt() ?? 0,
      cena: (json['cena'] as num?)?.toDouble() ?? 0.0,
      ukupnaObaveza: (json['ukupna_obaveza'] as num?)?.toDouble() ?? 0.0,
      uplaceno: (json['uplaceno'] as num?)?.toDouble() ?? 0.0,
      vozacId: json['vozac_id']?.toString() ?? '',
      vozacIme: json['vozac_ime']?.toString() ?? '',
      pokupioVozacId: json['pokupio_vozac_id']?.toString() ?? '',
      pokupioVozacIme: json['pokupio_vozac_ime']?.toString() ?? '',
      datum: V3DateUtils.parseTs(json['datum']?.toString()) ?? DateTime.now(),
      pokupljenAt: V3DateUtils.parseTs(json['pokupljen_at']?.toString()),
      iznos: (json['iznos'] as num?)?.toDouble() ?? 0.0,
      placeno: json['placeno'] as bool? ?? false,
      createdAt: V3DateUtils.parseTs(json['created_at']?.toString()),
      naplacenoAt: V3DateUtils.parseTs(json['naplaceno_at']?.toString()),
      naplacenoBy: json['naplaceno_by']?.toString(),
      updatedAt: V3DateUtils.parseTs(json['updated_at']?.toString()),
      updatedBy: json['updated_by']?.toString(),
      finansijeNaziv: json['finansije_naziv']?.toString(),
      finansijeKategorija: json['finansije_kategorija']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'putnik_id': putnikId,
        'ime_prezime': imePrezime,
        'tip_putnika': tipPutnika,
        'godina': godina,
        'mesec': mesec,
        'broj_voznji': brojVoznji,
        'cena': cena,
        'ukupna_obaveza': ukupnaObaveza,
        'uplaceno': uplaceno,
        'vozac_id': vozacId,
        'vozac_ime': vozacIme,
        'pokupio_vozac_id': pokupioVozacId,
        'pokupio_vozac_ime': pokupioVozacIme,
        'datum': V3DateUtils.toIsoUtc(datum),
        if (pokupljenAt != null) 'pokupljen_at': V3DateUtils.toIsoUtc(pokupljenAt!),
        'iznos': iznos,
        'placeno': placeno,
        if (createdAt != null) 'created_at': V3DateUtils.toIsoUtc(createdAt!),
        if (naplacenoAt != null) 'naplaceno_at': V3DateUtils.toIsoUtc(naplacenoAt!),
        if (naplacenoBy != null) 'naplaceno_by': naplacenoBy,
        if (updatedAt != null) 'updated_at': V3DateUtils.toIsoUtc(updatedAt!),
        if (updatedBy != null) 'updated_by': updatedBy,
        if (finansijeNaziv != null) 'finansije_naziv': finansijeNaziv,
        if (finansijeKategorija != null) 'finansije_kategorija': finansijeKategorija,
      };
}
