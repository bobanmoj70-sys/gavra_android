import '../utils/v3_date_utils.dart';

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

  /// Kreira V3Dug iz reda tabele v3_operativna_nedelja.
  /// [putnikData] — red iz logical `v3_putnici` cache-a za ovog putnika (`v3_auth` source).
  factory V3Dug.fromOperacija(
    Map<String, dynamic> json, {
    Map<String, dynamic>? putnikData,
  }) {
    final tip = putnikData?['tip_putnika'] as String? ?? 'dnevni';
    // Iznos = cena po vožnji iz profila putnika (jedini relevantan iznos za dnevne/pošiljke)
    final iznos = (putnikData?['cena_po_pokupljenju'] as num?)?.toDouble() ?? 0.0;
    return V3Dug(
      id: json['id']?.toString() ?? '',
      putnikId: json['created_by']?.toString() ?? '',
      imePrezime: putnikData?['ime_prezime'] as String? ??
          json['ime_prezime'] as String? ??
          json['putnik_ime'] as String? ??
          'Nepoznato',
      tipPutnika: tip,
      vozacId: json['pokupljen_by']?.toString() ?? '',
      vozacIme: json['vozac_ime']?.toString() ?? '',
      datum: V3DateUtils.parseDatumOr(json['datum'] as String?, DateTime.now()),
      pokupljenAt: V3DateUtils.parseTs(json['pokupljen_at'] as String?),
      iznos: iznos,
      placeno: json['placeno_finansije'] as bool? ?? false,
      createdAt: null,
    );
  }
}
