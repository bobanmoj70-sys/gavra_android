import '../utils/v3_date_utils.dart';

/// Jedna dnevna uplata pazara unutar meseca.
class V3DnevnaUplataPazara {
  final int dan;
  final double predao;
  final double ukupno;
  final double razlika;

  V3DnevnaUplataPazara({
    required this.dan,
    required this.predao,
    required this.ukupno,
    required this.razlika,
  });

  factory V3DnevnaUplataPazara.fromJson(Map<String, dynamic> json) {
    return V3DnevnaUplataPazara(
      dan: (json['dan'] as num?)?.toInt() ?? 0,
      predao: (json['predao'] as num?)?.toDouble() ?? 0,
      ukupno: (json['ukupno'] as num?)?.toDouble() ?? 0,
      razlika: (json['razlika'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'dan': dan,
        'predao': predao,
        'ukupno': ukupno,
        'razlika': razlika,
      };
}

/// Mesecna evidencija uplata pazara za jednog vozaca.
class V3UplataPazara {
  final String id;
  final String vozacId;
  final int mesec;
  final int godina;
  final List<V3DnevnaUplataPazara> dnevneUplate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  V3UplataPazara({
    required this.id,
    required this.vozacId,
    required this.mesec,
    required this.godina,
    this.dnevneUplate = const [],
    this.createdAt,
    this.updatedAt,
  });

  factory V3UplataPazara.fromJson(Map<String, dynamic> json) {
    final rawList = json['dnevne_uplate_json'];
    List<dynamic> list;
    if (rawList is List) {
      list = rawList;
    } else if (rawList is String && rawList.isNotEmpty) {
      list = [];
    } else {
      list = [];
    }

    return V3UplataPazara(
      id: json['id'] as String? ?? '',
      vozacId: json['vozac_id'] as String? ?? '',
      mesec: (json['mesec'] as num?)?.toInt() ?? 0,
      godina: (json['godina'] as num?)?.toInt() ?? 0,
      dnevneUplate: list.map((e) => V3DnevnaUplataPazara.fromJson(e as Map<String, dynamic>)).toList(),
      createdAt: V3DateUtils.parseTs(json['created_at'] as String?),
      updatedAt: V3DateUtils.parseTs(json['updated_at'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'vozac_id': vozacId,
        'mesec': mesec,
        'godina': godina,
        'dnevne_uplate_json': dnevneUplate.map((e) => e.toJson()).toList(),
      };

  /// Vraca uplatu za konkretan dan ili null ako ne postoji.
  V3DnevnaUplataPazara? uplataZaDan(int dan) {
    for (final u in dnevneUplate) {
      if (u.dan == dan) return u;
    }
    return null;
  }

  /// Vraca novu instancu sa izmenjenom ili dodatom dnevnom uplatom.
  V3UplataPazara withUplata(V3DnevnaUplataPazara uplata) {
    final updated = <V3DnevnaUplataPazara>[];
    var replaced = false;
    for (final u in dnevneUplate) {
      if (u.dan == uplata.dan) {
        updated.add(uplata);
        replaced = true;
      } else {
        updated.add(u);
      }
    }
    if (!replaced) updated.add(uplata);
    updated.sort((a, b) => a.dan.compareTo(b.dan));

    return V3UplataPazara(
      id: id,
      vozacId: vozacId,
      mesec: mesec,
      godina: godina,
      dnevneUplate: updated,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
