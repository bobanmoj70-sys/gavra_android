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

  factory V3Dug.fromJson(Map<String, dynamic> json) {
    return V3Dug(
      id: json['id'] as String? ?? '',
      putnikId: (json['created_by'] as String?) ?? '',
      imePrezime: json['ime_prezime'] as String? ??
          json['putnik_ime'] as String? ??
          'Nepoznato',
      tipPutnika: json['tip_putnika'] as String? ?? 'dnevni',
      vozacId: json['pokupljen_by'] as String? ?? '',
      vozacIme: json['vozac_ime'] as String? ?? '',
      datum: V3DateUtils.parseDatumOr(json['datum'] as String?, DateTime.now()),
      pokupljenAt: V3DateUtils.parseTs(json['pokupljen_at'] as String?),
      iznos: (json['iznos'] as num?)?.toDouble() ?? 0.0,
      placeno: json['placeno'] as bool? ?? false,
      createdAt: V3DateUtils.parseTs(json['created_at'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id.isEmpty ? null : id,
      'putnik_id': putnikId,
      'ime_prezime': imePrezime,
      'tip_putnika': tipPutnika,
      'pokupljen_by': vozacId,
      'vozac_ime': vozacIme,
      'datum': datum.toIso8601String(),
      'pokupljen_at': pokupljenAt?.toIso8601String(),
      'iznos': iznos,
      'placeno': placeno,
    };
  }

  /// Kreira V3Dug iz reda tabele v3_operativna_nedelja.
  /// [putnikData] — red iz logical `v3_putnici` cache-a za ovog putnika (`v3_auth` source).
  factory V3Dug.fromOperacija(
    Map<String, dynamic> json, {
    Map<String, dynamic>? putnikData,
  }) {
    final tip = putnikData?['tip_putnika'] as String? ?? 'dnevni';
    // Iznos = cena po pokupljenju iz profila putnika (jedini relevantan iznos za dnevne/posiljke)
    final iznos =
        (putnikData?['cena_po_pokupljenju'] as num?)?.toDouble() ?? 0.0;
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
      placeno: json['naplacen_at'] != null,
      createdAt: null,
    );
  }
}
