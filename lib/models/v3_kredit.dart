import 'dart:convert';

import '../utils/v3_date_utils.dart';
import 'v3_kredit_uplata.dart';

/// Model za tabelu v3_krediti.
/// Predstavlja licna dugovanja firme/vlasnika prema bankama, porodici,
/// dobavljacima i slicno. Razlicita su od potrazivanja od putnika.
class V3Kredit {
  final String id;
  final String naziv;
  final double ukupanIznos;
  final double uplaceno;
  final String? napomena;
  final List<V3KreditUplata> uplate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const V3Kredit({
    required this.id,
    required this.naziv,
    required this.ukupanIznos,
    required this.uplaceno,
    this.napomena,
    this.uplate = const [],
    this.createdAt,
    this.updatedAt,
  });

  /// Preostali iznos za otplatu.
  double get preostalo => ukupanIznos - uplaceno;

  /// Da li je kredit u potpunosti otplacen.
  bool get jeOtplacen => preostalo <= 0;

  /// Procenat otplacenosti (0.0 - 1.0).
  double get procenatOtplacenosti => ukupanIznos > 0 ? (uplaceno / ukupanIznos).clamp(0.0, 1.0) : 0.0;

  /// Ukupan broj uplata.
  int get brojUplata => uplate.length;

  /// Prosecan iznos uplate.
  double get prosecnaUplata => uplate.isNotEmpty ? uplaceno / uplate.length : 0.0;

  /// Najveca uplata.
  double get najvecaUplata => uplate.isNotEmpty ? uplate.map((u) => u.iznos).reduce((a, b) => a > b ? a : b) : 0.0;

  /// Najmanja uplata.
  double get najmanjaUplata => uplate.isNotEmpty ? uplate.map((u) => u.iznos).reduce((a, b) => a < b ? a : b) : 0.0;

  factory V3Kredit.fromJson(Map<String, dynamic> json) {
    List<V3KreditUplata> _parseUplate(dynamic raw) {
      final result = <V3KreditUplata>[];
      try {
        Iterable<dynamic> src;
        if (raw is List) {
          src = raw;
        } else if (raw is String) {
          final decoded = jsonDecode(raw);
          if (decoded is! List) return result;
          src = decoded;
        } else {
          return result;
        }
        for (final item in src) {
          if (item is! Map) continue;
          result.add(V3KreditUplata.fromJson(item as Map<String, dynamic>));
        }
      } catch (_) {
        return result;
      }
      result.sort((a, b) => a.datum.compareTo(b.datum));
      return result;
    }

    return V3Kredit(
      id: json['id']?.toString() ?? '',
      naziv: json['naziv']?.toString() ?? '',
      ukupanIznos: (json['ukupan_iznos'] as num?)?.toDouble() ?? 0.0,
      uplaceno: (json['uplaceno'] as num?)?.toDouble() ?? 0.0,
      napomena: json['napomena']?.toString(),
      uplate: _parseUplate(json['uplate_json']),
      createdAt: V3DateUtils.parseTs(json['created_at']?.toString()),
      updatedAt: V3DateUtils.parseTs(json['updated_at']?.toString()),
    );
  }

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'naziv': naziv,
        'ukupan_iznos': ukupanIznos,
        'uplaceno': uplaceno,
        if (napomena != null && napomena!.isNotEmpty) 'napomena': napomena,
        'uplate_json': uplate.map((u) => u.toJson()).toList(),
      };

  V3Kredit copyWith({
    String? id,
    String? naziv,
    double? ukupanIznos,
    double? uplaceno,
    String? napomena,
    List<V3KreditUplata>? uplate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return V3Kredit(
      id: id ?? this.id,
      naziv: naziv ?? this.naziv,
      ukupanIznos: ukupanIznos ?? this.ukupanIznos,
      uplaceno: uplaceno ?? this.uplaceno,
      napomena: napomena ?? this.napomena,
      uplate: uplate ?? this.uplate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
