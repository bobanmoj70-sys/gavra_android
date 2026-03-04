/// Model za sekvencu brojeva računa (v2_racun_sequence tabela)
class V2RacunSequence {
  final int godina;
  final int poslednjiBroj;
  final DateTime? updatedAt;

  V2RacunSequence({
    required this.godina,
    required this.poslednjiBroj,
    this.updatedAt,
  });

  factory V2RacunSequence.fromJson(Map<String, dynamic> json) {
    return V2RacunSequence(
      godina: (json['godina'] as num).toInt(),
      poslednjiBroj: (json['poslednji_broj'] as num?)?.toInt() ?? 0,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'godina': godina,
      'poslednji_broj': poslednjiBroj,
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) => identical(this, other) || other is V2RacunSequence && godina == other.godina;

  @override
  int get hashCode => godina.hashCode;
}
