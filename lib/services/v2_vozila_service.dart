import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import 'realtime/v2_master_realtime_manager.dart';

/// Servis za upravljanje vozilima — kolska knjiga i tehničko stanje.
class V2VozilaService {
  V2VozilaService._();

  static SupabaseClient get _supabase => supabase;

  static V2MasterRealtimeManager get _rm => V2MasterRealtimeManager.instance;

  /// Dohvati sva vozila iz rm cache-a (sync)
  static List<V2Vozilo> getVozila() {
    return _rm.vozilaCache.values.map((row) => V2Vozilo.fromJson(row)).toList()
      ..sort((a, b) => a.registarskiBroj.compareTo(b.registarskiBroj));
  }

  /// Stream vozila sa realtime osvežavanjem — emituje direktno iz cache-a
  static Stream<List<V2Vozilo>> streamVozila() {
    final controller = StreamController<List<V2Vozilo>>.broadcast();
    // v2_vozila nema RT — emituje jednom iz cache-a
    controller.add(getVozila());
    controller.onCancel = () => controller.close();
    return controller.stream;
  }

  /// Ažuriraj kolsku knjigu vozila
  static Future<bool> updateKolskaKnjiga(String id, Map<String, dynamic> podaci) async {
    try {
      await _supabase.from('v2_vozila').update(podaci).eq('id', id);
      return true;
    } catch (e) {
      debugPrint('[V2VozilaService] Greška u updateKolskaKnjiga(): $e');
      return false;
    }
  }

  // ==================== ISTORIJA SERVISA ====================

  /// Dodaj zapis u istoriju vozila
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
      await _supabase.from('v2_vozila_servis').insert({
        'vozilo_id': voziloId,
        'tip': tip,
        'datum': datum?.toIso8601String().split('T')[0],
        'km': km,
        'opis': opis,
        'cena': cena,
        'pozicija': pozicija,
      });
      return true;
    } catch (e) {
      debugPrint('[V2VozilaService] Greška u addIstorijuServisa(): $e');
      return false;
    }
  }
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
    return V2Vozilo(
      id: json['id']?.toString() ?? '',
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
    return DateTime.tryParse(value.toString());
  }

  /// Prikaži naziv
  String get displayNaziv {
    if (marka != null && model != null) {
      return '$marka $model';
    }
    return registarskiBroj;
  }

  /// Da li registracija ističe uskoro (30 dana)
  bool get registracijaIstice {
    if (registracijaVaziDo == null) return false;
    final danaDoIsteka = registracijaVaziDo!.difference(DateTime.now()).inDays;
    return danaDoIsteka <= 30;
  }

  /// Da li je registracija istekla
  bool get registracijaIstekla {
    if (registracijaVaziDo == null) return false;
    return registracijaVaziDo!.isBefore(DateTime.now());
  }

  /// Koliko dana do isteka registracije
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
  bool operator ==(Object other) => identical(this, other) || (other is V2Vozilo && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
