import 'dart:math' as math;

import 'package:uuid/uuid.dart';

const _sentinel = Object();

/// Model za adrese
class V2Adresa {
  static const _uuid = Uuid();
  V2Adresa({
    String? id,
    required this.naziv,
    this.grad,
    this.gpsLat,
    this.gpsLng,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory V2Adresa.fromMap(Map<String, dynamic> map) {
    final id = map['id'] as String?;
    if (id == null || id.isEmpty) throw ArgumentError('V2Adresa.fromMap: id je null ili prazan');
    return V2Adresa(
      id: id,
      naziv: map['naziv'] as String? ?? '',
      grad: _normalizeGrad(map['grad'] as String?),
      gpsLat: double.tryParse(map['gps_lat']?.toString() ?? ''),
      gpsLng: double.tryParse(map['gps_lng']?.toString() ?? ''),
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
    );
  }

  final String id;
  final String naziv;
  final String? grad;
  final double? gpsLat;
  final double? gpsLng;
  final DateTime createdAt;
  final DateTime updatedAt;

  double? get latitude => gpsLat;
  double? get longitude => gpsLng;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'naziv': naziv,
      if (grad != null) 'grad': grad,
      if (gpsLat != null) 'gps_lat': gpsLat,
      if (gpsLng != null) 'gps_lng': gpsLng,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  bool get hasValidCoordinates => gpsLat != null && gpsLng != null;

  /// Udaljenost između dvije adrese (Haversine formula), u kilometrima.
  double? distanceTo(V2Adresa other) {
    if (!hasValidCoordinates || !other.hasValidCoordinates) return null;

    const double earthRadius = 6371;
    final double dLat = _toRadians(other.gpsLat! - gpsLat!);
    final double dLon = _toRadians(other.gpsLng! - gpsLng!);

    final double a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_toRadians(gpsLat!)) * math.cos(_toRadians(other.gpsLat!)) * math.pow(math.sin(dLon / 2), 2);

    return earthRadius * 2 * math.asin(math.sqrt(a));
  }

  V2Adresa copyWith({
    String? id,
    String? naziv,
    Object? grad = _sentinel,
    Object? gpsLat = _sentinel,
    Object? gpsLng = _sentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return V2Adresa(
      id: id ?? this.id,
      naziv: naziv ?? this.naziv,
      grad: identical(grad, _sentinel) ? this.grad : grad as String?,
      gpsLat: identical(gpsLat, _sentinel) ? this.gpsLat : gpsLat as double?,
      gpsLng: identical(gpsLng, _sentinel) ? this.gpsLng : gpsLng as double?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Normalizuj grad: 'Vršac'/'Vrsac'/'vrsac'/'vs' → 'VS', 'Bela Crkva'/'bc' → 'BC'
  static String? _normalizeGrad(String? g) {
    if (g == null) return null;
    final l = g.toLowerCase().trim();
    if (l == 'vs' || l == 'vrsac' || l == 'vršac' || l.contains('vršac') || l.contains('vrsac')) return 'VS';
    if (l == 'bc' || l.contains('bela crkva') || l.contains('bela-crkva')) return 'BC';
    return g;
  }

  static double _toRadians(double degrees) => degrees * (math.pi / 180);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is V2Adresa && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'V2Adresa{id: $id, naziv: $naziv, '
        'koordinate: ${hasValidCoordinates ? "($gpsLat,$gpsLng)" : "none"}}';
  }
}
