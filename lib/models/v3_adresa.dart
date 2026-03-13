import 'dart:math' as math;

class V3Adresa {
  final String id;
  final String naziv;
  final String? grad;
  final double? gpsLat;
  final double? gpsLng;
  final bool aktivno;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  V3Adresa({
    required this.id,
    required this.naziv,
    this.grad,
    this.gpsLat,
    this.gpsLng,
    this.aktivno = true,
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
      aktivno: json['aktivno'] as bool? ?? true,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'naziv': naziv,
      'grad': grad,
      'gps_lat': gpsLat,
      'gps_lng': gpsLng,
      'aktivno': aktivno,
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
}
