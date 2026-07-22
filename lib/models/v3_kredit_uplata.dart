import '../utils/v3_date_utils.dart';

/// Pojedinačna uplata na kredit.
class V3KreditUplata {
  final String uplataId;
  final DateTime datum;
  final double iznos;
  final String? napomena;

  const V3KreditUplata({
    required this.uplataId,
    required this.datum,
    required this.iznos,
    this.napomena,
  });

  factory V3KreditUplata.fromJson(Map<String, dynamic> json) {
    return V3KreditUplata(
      uplataId: json['uplata_id']?.toString() ?? '',
      datum: V3DateUtils.parseTs(json['datum']?.toString()) ??
          DateTime.tryParse(json['datum']?.toString() ?? '') ??
          DateTime.now(),
      iznos: (json['iznos'] as num?)?.toDouble() ?? 0.0,
      napomena: json['napomena']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'uplata_id': uplataId,
        'datum': V3DateUtils.toIsoUtc(datum),
        'iznos': iznos,
        if (napomena != null && napomena!.isNotEmpty) 'napomena': napomena,
      };

  V3KreditUplata copyWith({
    String? uplataId,
    DateTime? datum,
    double? iznos,
    String? napomena,
  }) {
    return V3KreditUplata(
      uplataId: uplataId ?? this.uplataId,
      datum: datum ?? this.datum,
      iznos: iznos ?? this.iznos,
      napomena: napomena ?? this.napomena,
    );
  }
}
