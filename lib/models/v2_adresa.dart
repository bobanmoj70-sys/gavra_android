import 'dart:math' as math;

import 'package:uuid/uuid.dart';

/// Model za adrese
class V2Adresa {
  V2Adresa({
    String? id,
    required this.naziv,
    this.grad,
    this.gpsLat, // Direct DECIMAL column
    this.gpsLng, // Direct DECIMAL column
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory V2Adresa.fromMap(Map<String, dynamic> map) {
    // Normalizuj grad: 'Vršac'/'Vrsac'/'vs' → 'VS', 'Bela Crkva'/'bc' → 'BC'
    String? _normalizeGrad(String? g) {
      if (g == null) return null;
      final l = g.toLowerCase();
      if (l.contains('vrs') || l.contains('vr') || l == 'vs') return 'VS';
      if (l.contains('bela') || l == 'bc') return 'BC';
      return g;
    }

    return V2Adresa(
      id: map['id'] as String,
      naziv: map['naziv'] as String,
      grad: _normalizeGrad(map['grad'] as String?),
      gpsLat: (map['gps_lat'] as num?)?.toDouble(), // numeric → double
      gpsLng: (map['gps_lng'] as num?)?.toDouble(), // numeric → double
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at'] as String) : DateTime.now(),
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at'] as String) : DateTime.now(),
    );
  }

  final String id;
  final String naziv;
  final String? grad;
  final double? gpsLat; // Direct DECIMAL column
  final double? gpsLng; // Direct DECIMAL column
  final DateTime createdAt;
  final DateTime updatedAt;

  dynamic get koordinate => gpsLat != null && gpsLng != null ? {'lat': gpsLat, 'lng': gpsLng} : null;

  // Virtuelna polja za latitude/longitude iz direktnih kolona
  double? get latitude => gpsLat;
  double? get longitude => gpsLng;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'naziv': naziv,
      'grad': grad,
      'gps_lat': gpsLat, // Direct column
      'gps_lng': gpsLng, // Direct column
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Validation methods
  bool get hasValidCoordinates => gpsLat != null && gpsLng != null;

  /// Distance calculation between two addresses
  double? distanceTo(V2Adresa other) {
    if (!hasValidCoordinates || !other.hasValidCoordinates) {
      return null;
    }

    final lat1 = latitude!;
    final lon1 = longitude!;
    final lat2 = other.latitude!;
    final lon2 = other.longitude!;

    // Haversine formula
    const double earthRadius = 6371; // km
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);

    final double a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) * math.pow(math.sin(dLon / 2), 2);

    final double c = 2 * math.asin(math.sqrt(a));
    return earthRadius * c;
  }

  // COPY AND MODIFICATION METHODS

  /// Create a copy with updated fields
  V2Adresa copyWith({
    String? id,
    String? naziv,
    String? grad,
    double? gpsLat,
    double? gpsLng,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return V2Adresa(
      id: id ?? this.id,
      naziv: naziv ?? this.naziv,
      grad: grad ?? this.grad,
      gpsLat: gpsLat ?? this.gpsLat,
      gpsLng: gpsLng ?? this.gpsLng,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  double _toRadians(double degrees) => degrees * (math.pi / 180);

  /// Enhanced toString for debugging
  @override
  String toString() {
    return 'V2Adresa{id: $id, naziv: $naziv, '
        'koordinate: ${hasValidCoordinates ? "($latitude,$longitude)" : "none"}}';
  }
}

// Remove the extension as we're using dart:math directly
