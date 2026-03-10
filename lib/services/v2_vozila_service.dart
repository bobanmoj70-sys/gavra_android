import 'package:flutter/foundation.dart';

import '../globals.dart';
import 'realtime/v2_master_realtime_manager.dart';
// V2VozilaServisService se nalazi na dnu ovog fajla (spojen sa v2_vozila_servis_service.dart)

/// Servis za upravljanje vozilima — kolska knjiga i tehničko stanje.
class V2VozilaService {
  V2VozilaService._();

  static V2MasterRealtimeManager get _rm => V2MasterRealtimeManager.instance;

  /// Dohvati sva vozila iz rm cache-a (sync)
  static List<V2Vozilo> getVozila() {
    return _rm.vozilaCache.values.map((row) => V2Vozilo.fromJson(row)).toList()
      ..sort((a, b) => a.registarskiBroj.compareTo(b.registarskiBroj));
  }

  static Stream<List<V2Vozilo>> streamVozila() => _rm.v2StreamFromCache(tables: ['v2_vozila'], build: getVozila);

  /// Ažuriraj kolsku knjigu vozila
  static Future<bool> updateKolskaKnjiga(String id, Map<String, dynamic> podaci) async {
    try {
      await supabase.from('v2_vozila').update(podaci).eq('id', id);
      _rm.v2PatchCache('v2_vozila', id, podaci);
      return true;
    } catch (e) {
      debugPrint('[V2VozilaService] updateKolskaKnjiga greška: $e');
      return false;
    }
  }

  // ==================== SERVISNA ISTORIJA (delegirano na V2VozilaServisService) ====================

  /// Dodaj zapis u servisnu istoriju — delegira na V2VozilaServisService
  static Future<bool> addIstorijuServisa({
    required String voziloId,
    required String tip,
    DateTime? datum,
    int? km,
    String? opis,
    double? cena,
    String? pozicija,
  }) =>
      V2VozilaServisService.addIstorijuServisa(
        voziloId: voziloId,
        tip: tip,
        datum: datum,
        km: km,
        opis: opis,
        cena: cena,
        pozicija: pozicija,
      );
}

/// Model za vozilo - Kolska knjiga
class V2Vozilo {
  final String id;
  final String registarskiBroj;
  final String? marka;
  final String? model;
  final int? godinaProizvodnje;

  // Kolska knjiga
  final String? brojSasije;
  final DateTime? registracijaVaziDo;
  final DateTime? maliServisDatum;
  final int? maliServisKm;
  final DateTime? velikiServisDatum;
  final int? velikiServisKm;
  final DateTime? alternatorDatum;
  final int? alternatorKm;
  final DateTime? gumeDatum;
  final String? gumeOpis;
  final DateTime? gumePrednjeDatum;
  final String? gumePrednjeOpis;
  final int? gumePrednjeKm;
  final DateTime? gumeZadnjeDatum;
  final String? gumeZadnjeOpis;
  final int? gumeZadnjeKm;
  final String? napomena;
  // Nova polja
  final DateTime? akumulatorDatum;
  final int? akumulatorKm;
  final DateTime? plociceDatum;
  final int? plociceKm;
  final DateTime? plocicePrednjeDatum;
  final int? plocicePrednjeKm;
  final DateTime? plociceZadnjeDatum;
  final int? plociceZadnjeKm;
  final DateTime? trapDatum;
  final int? trapKm;
  final String? radio;
  final double? kilometraza;

  V2Vozilo({
    required this.id,
    required this.registarskiBroj,
    this.marka,
    this.model,
    this.godinaProizvodnje,
    this.brojSasije,
    this.registracijaVaziDo,
    this.maliServisDatum,
    this.maliServisKm,
    this.velikiServisDatum,
    this.velikiServisKm,
    this.alternatorDatum,
    this.alternatorKm,
    this.gumeDatum,
    this.gumeOpis,
    this.gumePrednjeDatum,
    this.gumePrednjeOpis,
    this.gumePrednjeKm,
    this.gumeZadnjeDatum,
    this.gumeZadnjeOpis,
    this.gumeZadnjeKm,
    this.napomena,
    this.akumulatorDatum,
    this.akumulatorKm,
    this.plociceDatum,
    this.plociceKm,
    this.plocicePrednjeDatum,
    this.plocicePrednjeKm,
    this.plociceZadnjeDatum,
    this.plociceZadnjeKm,
    this.trapDatum,
    this.trapKm,
    this.radio,
    this.kilometraza,
  });

  factory V2Vozilo.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) throw ArgumentError('V2Vozilo.fromJson: id je null ili prazan');
    return V2Vozilo(
      id: id,
      registarskiBroj: json['registarski_broj']?.toString() ?? '',
      marka: json['marka']?.toString(),
      model: json['model']?.toString(),
      godinaProizvodnje: (json['godina_proizvodnje'] as num?)?.toInt(),
      brojSasije: json['broj_sasije']?.toString(),
      registracijaVaziDo: _parseDate(json['registracija_vazi_do']),
      maliServisDatum: _parseDate(json['mali_servis_datum']),
      maliServisKm: (json['mali_servis_km'] as num?)?.toInt(),
      velikiServisDatum: _parseDate(json['veliki_servis_datum']),
      velikiServisKm: (json['veliki_servis_km'] as num?)?.toInt(),
      alternatorDatum: _parseDate(json['alternator_datum']),
      alternatorKm: (json['alternator_km'] as num?)?.toInt(),
      gumeDatum: _parseDate(json['gume_datum']),
      gumeOpis: json['gume_opis']?.toString(),
      gumePrednjeDatum: _parseDate(json['gume_prednje_datum']),
      gumePrednjeOpis: json['gume_prednje_opis']?.toString(),
      gumePrednjeKm: (json['gume_prednje_km'] as num?)?.toInt(),
      gumeZadnjeDatum: _parseDate(json['gume_zadnje_datum']),
      gumeZadnjeOpis: json['gume_zadnje_opis']?.toString(),
      gumeZadnjeKm: (json['gume_zadnje_km'] as num?)?.toInt(),
      akumulatorDatum: _parseDate(json['akumulator_datum']),
      akumulatorKm: (json['akumulator_km'] as num?)?.toInt(),
      plociceDatum: _parseDate(json['plocice_datum']),
      plociceKm: (json['plocice_km'] as num?)?.toInt(),
      plocicePrednjeDatum: _parseDate(json['plocice_prednje_datum']),
      plocicePrednjeKm: (json['plocice_prednje_km'] as num?)?.toInt(),
      plociceZadnjeDatum: _parseDate(json['plocice_zadnje_datum']),
      plociceZadnjeKm: (json['plocice_zadnje_km'] as num?)?.toInt(),
      trapDatum: _parseDate(json['trap_datum']),
      trapKm: (json['trap_km'] as num?)?.toInt(),
      radio: json['radio']?.toString(),
      napomena: json['napomena']?.toString(),
      kilometraza: (json['kilometraza'] as num?)?.toDouble(),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  /// Prikaži naziv
  String get displayNaziv {
    if (marka != null && model != null) {
      return '$marka $model';
    }
    return registarskiBroj;
  }

  /// Da li registracija ističe uskoro (30 dana), ali još nije istekla
  bool get registracijaIstice {
    if (registracijaVaziDo == null) return false;
    final danaDoIsteka = registracijaVaziDo!.difference(DateTime.now()).inDays;
    return danaDoIsteka >= 0 && danaDoIsteka <= 30;
  }

  /// Da li je registracija istekla
  bool get registracijaIstekla {
    if (registracijaVaziDo == null) return false;
    return registracijaVaziDo!.isBefore(DateTime.now());
  }

  /// Koliko dana do isteka registracije (negativno = već istekla)
  int? get danaDoIstekaRegistracije {
    if (registracijaVaziDo == null) return null;
    return registracijaVaziDo!.difference(DateTime.now()).inDays;
  }

  /// Formatiran datum
  static String formatDatum(DateTime? datum) {
    if (datum == null) return '-';
    return '${datum.day}.${datum.month}.${datum.year}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (runtimeType == other.runtimeType && other is V2Vozilo && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'V2Vozilo(id: $id, registarskiBroj: $registarskiBroj, '
      'marka: $marka, model: $model, kilometraza: $kilometraza)';
}

// =============================================================================
// Spojeno iz v2_vozila_servis_service.dart
// =============================================================================

/// Servis za tabelu v2_vozila_servis (servisna knjiga vozila)
class V2VozilaServisService {
  V2VozilaServisService._();

  static const String tabela = 'v2_vozila_servis';

  /// Dodaj zapis u servisnu istoriju
  static Future<bool> addIstorijuServisa({
    required String voziloId,
    required String tip,
    DateTime? datum,
    int? km,
    String? opis,
    double? cena,
    String? pozicija,
  }) async {
    try {
      await supabase.from(tabela).insert({
        'vozilo_id': voziloId,
        'tip': tip,
        'datum': (datum ?? DateTime.now()).toIso8601String().split('T')[0],
        'km': km,
        'opis': opis,
        'cena': cena,
        'pozicija': pozicija,
      });
      return true;
    } catch (e) {
      debugPrint('[V2VozilaServisService] addIstorijuServisa greška: $e');
      return false;
    }
  }
}
