class V3Dug {
  final String id;
  final String putnikId;
  final String imePrezime;
  final String tipPutnika;
  final String vozacId;
  final String vozacIme;
  final DateTime datum;
  final DateTime? vremePokupljen;
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
    this.vremePokupljen,
    required this.iznos,
    this.placeno = false,
    this.createdAt,
  });

  factory V3Dug.fromJson(Map<String, dynamic> json) {
    return V3Dug(
      id: json['id'] as String? ?? '',
      putnikId: json['putnik_id'] as String? ?? '',
      imePrezime: json['ime_prezime'] as String? ?? json['putnik_ime'] as String? ?? 'Nepoznato',
      tipPutnika: json['tip_putnika'] as String? ?? 'dnevni',
      vozacId: json['vozac_id'] as String? ?? '',
      vozacIme: json['vozac_ime'] as String? ?? '',
      datum: json['datum'] != null ? DateTime.parse(json['datum'] as String) : DateTime.now(),
      vremePokupljen: json['vreme_pokupljen'] != null ? DateTime.tryParse(json['vreme_pokupljen'] as String) : null,
      iznos: (json['iznos'] as num?)?.toDouble() ?? 0.0,
      placeno: json['placeno'] as bool? ?? false,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id.isEmpty ? null : id,
      'putnik_id': putnikId,
      'ime_prezime': imePrezime,
      'tip_putnika': tipPutnika,
      'vozac_id': vozacId,
      'vozac_ime': vozacIme,
      'datum': datum.toIso8601String(),
      'vreme_pokupljen': vremePokupljen?.toIso8601String(),
      'iznos': iznos,
      'placeno': placeno,
    };
  }

  /// Kreira V3Dug iz reda tabele v3_operativna_nedelja.
  /// [putnikData] — red iz v3_putnici cache-a za ovog putnika.
  factory V3Dug.fromOperacija(
    Map<String, dynamic> json, {
    Map<String, dynamic>? putnikData,
  }) {
    final tip = putnikData?['tip_putnika'] as String? ?? 'dnevni';
    // Iznos = cena po pokupljenju iz profila putnika (jedini relevantan iznos za dnevne/posiljke)
    final iznos = (putnikData?['cena_po_pokupljenju'] as num?)?.toDouble() ?? 0.0;
    return V3Dug(
      id: json['id']?.toString() ?? '',
      putnikId: json['putnik_id']?.toString() ?? '',
      imePrezime: putnikData?['ime_prezime'] as String? ??
          json['ime_prezime'] as String? ??
          json['putnik_ime'] as String? ??
          'Nepoznato',
      tipPutnika: tip,
      vozacId: json['vozac_id']?.toString() ?? '',
      vozacIme: json['vozac_ime']?.toString() ?? '',
      datum: json['datum'] != null ? DateTime.tryParse(json['datum'] as String) ?? DateTime.now() : DateTime.now(),
      vremePokupljen: json['vreme_pokupljen'] != null ? DateTime.tryParse(json['vreme_pokupljen'] as String) : null,
      iznos: iznos,
      placeno: (json['naplata_status'] as String?) == 'placeno',
      createdAt: null,
    );
  }
}
