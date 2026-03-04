/// Model za trenutno stanje kućne pumpe goriva (v2_pumpa_stanje VIEW)
class V2PumpaStanje {
  final double kapacitetLitri;
  final double alarmNivo;
  final double pocetnoStanje;
  final double ukupnoPunjeno;
  final double ukupnoUtroseno;
  final double trenutnoStanje;
  final double procenatPune;

  V2PumpaStanje({
    required this.kapacitetLitri,
    required this.alarmNivo,
    required this.pocetnoStanje,
    required this.ukupnoPunjeno,
    required this.ukupnoUtroseno,
    required this.trenutnoStanje,
    required this.procenatPune,
  });

  factory V2PumpaStanje.fromJson(Map<String, dynamic> j) => V2PumpaStanje(
        kapacitetLitri: (j['kapacitet_litri'] as num?)?.toDouble() ?? 3000,
        alarmNivo: (j['alarm_nivo'] as num?)?.toDouble() ?? 500,
        pocetnoStanje: (j['pocetno_stanje'] as num?)?.toDouble() ?? 0,
        ukupnoPunjeno: (j['ukupno_punjeno'] as num?)?.toDouble() ?? 0,
        ukupnoUtroseno: (j['ukupno_utroseno'] as num?)?.toDouble() ?? 0,
        trenutnoStanje: (j['trenutno_stanje'] as num?)?.toDouble() ?? 0,
        procenatPune: (j['procenat_pune'] as num?)?.toDouble() ?? 0,
      );

  bool get ispodAlarma => trenutnoStanje <= alarmNivo;
  bool get prazna => trenutnoStanje <= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is V2PumpaStanje &&
          kapacitetLitri == other.kapacitetLitri &&
          alarmNivo == other.alarmNivo &&
          pocetnoStanje == other.pocetnoStanje &&
          ukupnoPunjeno == other.ukupnoPunjeno &&
          ukupnoUtroseno == other.ukupnoUtroseno &&
          trenutnoStanje == other.trenutnoStanje &&
          procenatPune == other.procenatPune;

  @override
  int get hashCode => Object.hash(
        kapacitetLitri,
        alarmNivo,
        pocetnoStanje,
        ukupnoPunjeno,
        ukupnoUtroseno,
        trenutnoStanje,
        procenatPune,
      );
}
