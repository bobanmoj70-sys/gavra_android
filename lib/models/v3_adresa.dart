import '../utils/v3_date_utils.dart';

class V3Adresa {
  final String id;
  final String naziv;
  final String? grad;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  V3Adresa({
    required this.id,
    required this.naziv,
    this.grad,
    this.createdAt,
    this.updatedAt,
  });

  factory V3Adresa.fromJson(Map<String, dynamic> json) {
    return V3Adresa(
      id: json['id'] as String? ?? '',
      naziv: json['naziv'] as String? ?? '',
      grad: json['grad'] as String?,
      createdAt: V3DateUtils.parseTs(json['created_at'] as String?),
      updatedAt: V3DateUtils.parseTs(json['updated_at'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'naziv': naziv,
      'grad': grad,
    };
  }

  @override
  bool operator ==(Object other) => other is V3Adresa && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
