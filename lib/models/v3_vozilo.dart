import '../utils/v3_dan_helper.dart';

class V3Vozilo {
  final String id;
  final String registracija;
  final String? marka;
  final String? model;
  final double trenutnaKm;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Kolska knjiga polja
  final String? brojSasije;
  final int? godinaProizvodnje;
  final String? napomena;
  final DateTime? registracijaVaziDo;
  final DateTime? maliServisDatum;
  final int? maliServisKm;
  final DateTime? velikiServisDatum;
  final int? velikiServisKm;
  final DateTime? alternatorDatum;
  final int? alternatorKm;
  final DateTime? akumulatorDatum;
  final int? akumulatorKm;
  final DateTime? plocicePrednjeDatum;
  final int? plocicePrednjeKm;
  final DateTime? plociceZadnjeDatum;
  final int? plociceZadnjeKm;
  final DateTime? trapDatum;
  final int? trapKm;
  final DateTime? gumePrednjeDatum;
  final String? gumePrednjeOpis;
  final int? gumePrednjeKm;
  final DateTime? gumeZadnjeDatum;
  final String? gumeZadnjeOpis;
  final int? gumeZadnjeKm;
  final String? radio;

  V3Vozilo({
    required this.id,
    required this.registracija,
    this.marka,
    this.model,
    this.trenutnaKm = 0.0,
    this.createdAt,
    this.updatedAt,
    this.brojSasije,
    this.godinaProizvodnje,
    this.napomena,
    this.registracijaVaziDo,
    this.maliServisDatum,
    this.maliServisKm,
    this.velikiServisDatum,
    this.velikiServisKm,
    this.alternatorDatum,
    this.alternatorKm,
    this.akumulatorDatum,
    this.akumulatorKm,
    this.plocicePrednjeDatum,
    this.plocicePrednjeKm,
    this.plociceZadnjeDatum,
    this.plociceZadnjeKm,
    this.trapDatum,
    this.trapKm,
    this.gumePrednjeDatum,
    this.gumePrednjeOpis,
    this.gumePrednjeKm,
    this.gumeZadnjeDatum,
    this.gumeZadnjeOpis,
    this.gumeZadnjeKm,
    this.radio,
  });

  String get naziv => marka != null ? '$marka $model' : (model ?? registracija);

  String get displayNaziv {
    final parts = <String>[];
    if (marka != null) parts.add(marka!);
    if (model != null) parts.add(model!);
    return parts.isEmpty ? registracija : parts.join(' ');
  }

  static String formatDatum(DateTime? d) {
    if (d == null) return '-';
    return V3DanHelper.formatDatumPuni(d);
  }

  bool get registracijaIstekla => registracijaVaziDo != null && registracijaVaziDo!.isBefore(DateTime.now());

  bool get registracijaIstice {
    if (registracijaVaziDo == null) return false;
    final days = registracijaVaziDo!.difference(DateTime.now()).inDays;
    return days >= 0 && days <= 30;
  }

  int get danaDoIstekaRegistracije => registracijaVaziDo?.difference(DateTime.now()).inDays ?? 0;

  factory V3Vozilo.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic val) => val != null ? DateTime.tryParse(val as String) : null;

    return V3Vozilo(
      id: json['id'] as String? ?? '',
      registracija: json['registracija'] as String? ?? '',
      marka: json['marka'] as String?,
      model: json['model'] as String?,
      trenutnaKm: (json['trenutna_km'] as num?)?.toDouble() ?? 0.0,
      createdAt: parseDate(json['created_at']),
      updatedAt: parseDate(json['updated_at']),
      brojSasije: json['broj_sasije'] as String?,
      godinaProizvodnje: json['godina_proizvodnje'] as int?,
      napomena: json['napomena'] as String?,
      registracijaVaziDo: parseDate(json['registracija_vazi_do']),
      maliServisDatum: parseDate(json['mali_servis_datum']),
      maliServisKm: json['mali_servis_km'] as int?,
      velikiServisDatum: parseDate(json['veliki_servis_datum']),
      velikiServisKm: json['veliki_servis_km'] as int?,
      alternatorDatum: parseDate(json['alternator_datum']),
      alternatorKm: json['alternator_km'] as int?,
      akumulatorDatum: parseDate(json['akumulator_datum']),
      akumulatorKm: json['akumulator_km'] as int?,
      plocicePrednjeDatum: parseDate(json['plocice_prednje_datum']),
      plocicePrednjeKm: json['plocice_prednje_km'] as int?,
      plociceZadnjeDatum: parseDate(json['plocice_zadnje_datum']),
      plociceZadnjeKm: json['plocice_zadnje_km'] as int?,
      trapDatum: parseDate(json['trap_datum']),
      trapKm: json['trap_km'] as int?,
      gumePrednjeDatum: parseDate(json['gume_prednje_datum']),
      gumePrednjeOpis: json['gume_prednje_opis'] as String?,
      gumePrednjeKm: json['gume_prednje_km'] as int?,
      gumeZadnjeDatum: parseDate(json['gume_zadnje_datum']),
      gumeZadnjeOpis: json['gume_zadnje_opis'] as String?,
      gumeZadnjeKm: json['gume_zadnje_km'] as int?,
      radio: json['radio'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'registracija': registracija,
      'marka': marka,
      'model': model,
      'trenutna_km': trenutnaKm,
      if (brojSasije != null) 'broj_sasije': brojSasije,
      if (godinaProizvodnje != null) 'godina_proizvodnje': godinaProizvodnje,
      if (napomena != null) 'napomena': napomena,
      if (registracijaVaziDo != null)
        'registracija_vazi_do': V3DanHelper.parseIsoDatePart(registracijaVaziDo!.toIso8601String()),
      if (maliServisDatum != null)
        'mali_servis_datum': V3DanHelper.parseIsoDatePart(maliServisDatum!.toIso8601String()),
      if (maliServisKm != null) 'mali_servis_km': maliServisKm,
      if (velikiServisDatum != null)
        'veliki_servis_datum': V3DanHelper.parseIsoDatePart(velikiServisDatum!.toIso8601String()),
      if (velikiServisKm != null) 'veliki_servis_km': velikiServisKm,
      if (alternatorDatum != null) 'alternator_datum': V3DanHelper.parseIsoDatePart(alternatorDatum!.toIso8601String()),
      if (alternatorKm != null) 'alternator_km': alternatorKm,
      if (akumulatorDatum != null) 'akumulator_datum': V3DanHelper.parseIsoDatePart(akumulatorDatum!.toIso8601String()),
      if (akumulatorKm != null) 'akumulator_km': akumulatorKm,
      if (plocicePrednjeDatum != null)
        'plocice_prednje_datum': V3DanHelper.parseIsoDatePart(plocicePrednjeDatum!.toIso8601String()),
      if (plocicePrednjeKm != null) 'plocice_prednje_km': plocicePrednjeKm,
      if (plociceZadnjeDatum != null)
        'plocice_zadnje_datum': V3DanHelper.parseIsoDatePart(plociceZadnjeDatum!.toIso8601String()),
      if (plociceZadnjeKm != null) 'plocice_zadnje_km': plociceZadnjeKm,
      if (trapDatum != null) 'trap_datum': V3DanHelper.parseIsoDatePart(trapDatum!.toIso8601String()),
      if (trapKm != null) 'trap_km': trapKm,
      if (gumePrednjeDatum != null)
        'gume_prednje_datum': V3DanHelper.parseIsoDatePart(gumePrednjeDatum!.toIso8601String()),
      if (gumePrednjeOpis != null) 'gume_prednje_opis': gumePrednjeOpis,
      if (gumePrednjeKm != null) 'gume_prednje_km': gumePrednjeKm,
      if (gumeZadnjeDatum != null)
        'gume_zadnje_datum': V3DanHelper.parseIsoDatePart(gumeZadnjeDatum!.toIso8601String()),
      if (gumeZadnjeOpis != null) 'gume_zadnje_opis': gumeZadnjeOpis,
      if (gumeZadnjeKm != null) 'gume_zadnje_km': gumeZadnjeKm,
      if (radio != null) 'radio': radio,
    };
  }
}
