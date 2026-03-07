/// Model za trenutno stanje kućne pumpe goriva (v2_pumpa_stanje VIEW)
class V2PumpaStanje {
  static const double defaultKapacitet = 3000;
  static const double defaultAlarmNivo = 500;

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
        kapacitetLitri: (j['kapacitet_litri'] as num?)?.toDouble() ?? defaultKapacitet,
        alarmNivo: (j['alarm_nivo'] as num?)?.toDouble() ?? defaultAlarmNivo,
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
      (other is V2PumpaStanje &&
          runtimeType == other.runtimeType &&
          kapacitetLitri == other.kapacitetLitri &&
          alarmNivo == other.alarmNivo &&
          pocetnoStanje == other.pocetnoStanje &&
          ukupnoPunjeno == other.ukupnoPunjeno &&
          ukupnoUtroseno == other.ukupnoUtroseno &&
          trenutnoStanje == other.trenutnoStanje &&
          procenatPune == other.procenatPune);

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

  V2PumpaStanje copyWith({
    double? kapacitetLitri,
    double? alarmNivo,
    double? pocetnoStanje,
    double? ukupnoPunjeno,
    double? ukupnoUtroseno,
    double? trenutnoStanje,
    double? procenatPune,
  }) {
    return V2PumpaStanje(
      kapacitetLitri: kapacitetLitri ?? this.kapacitetLitri,
      alarmNivo: alarmNivo ?? this.alarmNivo,
      pocetnoStanje: pocetnoStanje ?? this.pocetnoStanje,
      ukupnoPunjeno: ukupnoPunjeno ?? this.ukupnoPunjeno,
      ukupnoUtroseno: ukupnoUtroseno ?? this.ukupnoUtroseno,
      trenutnoStanje: trenutnoStanje ?? this.trenutnoStanje,
      procenatPune: procenatPune ?? this.procenatPune,
    );
  }

  @override
  String toString() =>
      'V2PumpaStanje(trenutno: $trenutnoStanje L, kapacitet: $kapacitetLitri L, procenat: $procenatPune%)';
}
