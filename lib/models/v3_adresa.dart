import 'dart:math' as math;

import '../utils/v3_date_utils.dart';

class V3Adresa {
  final String id;
  final String naziv;
  final String? grad;
  final double? gpsLat;
  final double? gpsLng;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  V3Adresa({
    required this.id,
    required this.naziv,
    this.grad,
    this.gpsLat,
    this.gpsLng,
    this.createdAt,
    this.updatedAt,
  });

  factory V3Adresa.fromJson(Map<String, dynamic> json) {
    return V3Adresa(
      id: json['id'] as String? ?? '',
      naziv: json['naziv'] as String? ?? '',
      grad: json['grad'] as String?,
      gpsLat: (json['gps_lat'] as num?)?.toDouble(),
      gpsLng: (json['gps_lng'] as num?)?.toDouble(),
      createdAt: V3DateUtils.parseTs(json['created_at'] as String?),
      updatedAt: V3DateUtils.parseTs(json['updated_at'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'naziv': naziv,
      'grad': grad,
      'gps_lat': gpsLat,
      'gps_lng': gpsLng,
    };
  }

  bool get hasValidCoordinates => gpsLat != null && gpsLng != null;

  double? distanceTo(V3Adresa other) {
    if (!hasValidCoordinates || !other.hasValidCoordinates) return null;

    const double earthRadius = 6371;
    final double dLat = _toRadians(other.gpsLat! - gpsLat!);
    final double dLon = _toRadians(other.gpsLng! - gpsLng!);

    final double a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_toRadians(gpsLat!)) * math.cos(_toRadians(other.gpsLat!)) * math.pow(math.sin(dLon / 2), 2);

    return earthRadius * 2 * math.asin(math.sqrt(a));
  }

  static double _toRadians(double degree) => degree * math.pi / 180;

  @override
  bool operator ==(Object other) => other is V3Adresa && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
