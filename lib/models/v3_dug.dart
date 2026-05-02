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
}
