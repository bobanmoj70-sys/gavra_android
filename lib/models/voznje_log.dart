/// Model za evidenciju vožnji i plaćanja (voznje_log tabela)
class VoznjeLog {
  final String id;
  final String? putnikId;
  final DateTime? datum;
  final String? tip;
  final double iznos;
  final String? vozacId;
  final DateTime? createdAt;
  final int? placeniMesec;
  final int? placenaGodina;
  final int? satiPrePolaska;
  final int brojMesta;
  final String? detalji;
  final Map<String, dynamic>? meta;
  final String? tipPlacanja;
  final String? status;
  final String? grad;
  final String? vremePolaska;
  final String? vozacIme;

  VoznjeLog({
    required this.id,
    this.putnikId,
    this.datum,
    this.tip,
    this.iznos = 0.0,
    this.vozacId,
    this.createdAt,
    this.placeniMesec,
    this.placenaGodina,
    this.satiPrePolaska,
    this.brojMesta = 1,
    this.detalji,
    this.meta,
    this.tipPlacanja,
    this.status,
    this.grad,
    this.vremePolaska,
    this.vozacIme,
  });

  factory VoznjeLog.fromJson(Map<String, dynamic> json) {
    return VoznjeLog(
      id: json['id'] as String,
      putnikId: json['putnik_id'] as String?,
      datum: json['datum'] != null ? DateTime.parse(json['datum'] as String) : null,
      tip: json['tip'] as String?,
      iznos: (json['iznos'] as num?)?.toDouble() ?? 0.0,
      vozacId: json['vozac_id'] as String?,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : null,
      placeniMesec: json['placeni_mesec'] as int?,
      placenaGodina: json['placena_godina'] as int?,
      satiPrePolaska: json['sati_pre_polaska'] as int?,
      brojMesta: json['broj_mesta'] as int? ?? 1,
      detalji: json['detalji'] as String?,
      meta: json['meta'] as Map<String, dynamic>?,
      tipPlacanja: json['tip_placanja'] as String?,
      status: json['status'] as String?,
      grad: json['grad'] as String?,
      vremePolaska: json['vreme_polaska'] as String?,
      vozacIme: json['vozac_ime'] as String?,
    );
  }

  VoznjeLog copyWith({
    String? id,
    String? putnikId,
    DateTime? datum,
    String? tip,
    double? iznos,
    String? vozacId,
    DateTime? createdAt,
    int? placeniMesec,
    int? placenaGodina,
    int? satiPrePolaska,
    int? brojMesta,
    String? detalji,
    Map<String, dynamic>? meta,
    String? tipPlacanja,
    String? status,
    String? grad,
    String? vremePolaska,
    String? vozacIme,
  }) {
    return VoznjeLog(
      id: id ?? this.id,
      putnikId: putnikId ?? this.putnikId,
      datum: datum ?? this.datum,
      tip: tip ?? this.tip,
      iznos: iznos ?? this.iznos,
      vozacId: vozacId ?? this.vozacId,
      createdAt: createdAt ?? this.createdAt,
      placeniMesec: placeniMesec ?? this.placeniMesec,
      placenaGodina: placenaGodina ?? this.placenaGodina,
      satiPrePolaska: satiPrePolaska ?? this.satiPrePolaska,
      brojMesta: brojMesta ?? this.brojMesta,
      detalji: detalji ?? this.detalji,
      meta: meta ?? this.meta,
      tipPlacanja: tipPlacanja ?? this.tipPlacanja,
      status: status ?? this.status,
      grad: grad ?? this.grad,
      vremePolaska: vremePolaska ?? this.vremePolaska,
      vozacIme: vozacIme ?? this.vozacIme,
    );
  }
}
