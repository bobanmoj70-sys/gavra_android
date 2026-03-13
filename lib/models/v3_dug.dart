class V3Dug {
  final String id;
  final String putnikId;
  final String putnikIme;
  final String tipPutnika;
  final String vozacId;
  final DateTime datum;
  final double iznos;
  final bool placeno;
  final DateTime? createdAt;

  V3Dug({
    required this.id,
    required this.putnikId,
    required this.putnikIme,
    required this.tipPutnika,
    required this.vozacId,
    required this.datum,
    required this.iznos,
    this.placeno = false,
    this.createdAt,
  });

  factory V3Dug.fromJson(Map<String, dynamic> json) {
    return V3Dug(
      id: json['id'] as String? ?? '',
      putnikId: json['putnik_id'] as String? ?? '',
      putnikIme: json['putnik_ime'] as String? ?? 'Nepoznato',
      tipPutnika: json['tip_putnika'] as String? ?? 'dnevni',
      vozacId: json['vozac_id'] as String? ?? '',
      datum: json['datum'] != null ? DateTime.parse(json['datum'] as String) : DateTime.now(),
      iznos: (json['iznos'] as num?)?.toDouble() ?? 0.0,
      placeno: json['placeno'] as bool? ?? false,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id.isEmpty ? null : id,
      'putnik_id': putnikId,
      'putnik_ime': putnikIme,
      'tip_putnika': tipPutnika,
      'vozac_id': vozacId,
      'datum': datum.toIso8601String(),
      'iznos': iznos,
      'placeno': placeno,
    };
  }
}
