/// Model za statistiku potrošnje goriva po vozilu
class V2VoziloStatistika {
  final String voziloId;
  final String registarskiBroj;
  final String marka;
  final String model;
  final double ukupnoLitri;
  final int brojTocenja;

  V2VoziloStatistika({
    required this.voziloId,
    required this.registarskiBroj,
    required this.marka,
    required this.model,
    required this.ukupnoLitri,
    required this.brojTocenja,
  });

  V2VoziloStatistika copyWith({double? ukupnoLitri, int? brojTocenja}) => V2VoziloStatistika(
        voziloId: voziloId,
        registarskiBroj: registarskiBroj,
        marka: marka,
        model: model,
        ukupnoLitri: ukupnoLitri ?? this.ukupnoLitri,
        brojTocenja: brojTocenja ?? this.brojTocenja,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is V2VoziloStatistika &&
          voziloId == other.voziloId &&
          ukupnoLitri == other.ukupnoLitri &&
          brojTocenja == other.brojTocenja;

  @override
  int get hashCode => Object.hash(voziloId, ukupnoLitri, brojTocenja);
}
