class V3Dug {
  final String id;
  final String putnikId;
  final String imePrezime;
  final String tipPutnika;
  final String vozacId;
  final String vozacIme;
  final DateTime datum;
  final DateTime? pokupljenAt;
  final double iznos;
  final bool placeno;
  final DateTime? createdAt;

  V3Dug({
    required this.id,
    required this.putnikId,
    required this.imePrezime,
    required this.tipPutnika,
    required this.vozacId,
    this.vozacIme = '',
    required this.datum,
    this.pokupljenAt,
    required this.iznos,
    this.placeno = false,
    this.createdAt,
  });
}
