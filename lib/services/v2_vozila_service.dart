import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import 'realtime/v2_master_realtime_manager.dart';

/// 🚗 VOZILA SERVICE - Kolska knjiga
/// Evidencija vozila i njihovo tehničko stanje
class V2VozilaService {
  static SupabaseClient get _supabase => supabase;

  static StreamSubscription? _vozilaSubscription;
  static final StreamController<List<Vozilo>> _vozilaController = StreamController<List<Vozilo>>.broadcast();

  /// Dohvati sva vozila
  static Future<List<Vozilo>> getVozila() async {
    try {
      final response = await _supabase.from('v2_vozila').select().order('registarski_broj');
      return (response as List).map((row) => Vozilo.fromJson(row)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Stream vozila sa realtime osvežavanjem
  static Stream<List<Vozilo>> streamVozila() {
    if (_vozilaSubscription == null) {
      _vozilaSubscription = V2MasterRealtimeManager.instance.subscribe('v2_vozila').listen((payload) {
        _refreshVozilaStream();
      });
      // Inicijalno učitavanje
      _refreshVozilaStream();
    }
    return _vozilaController.stream;
  }

  static void _refreshVozilaStream() async {
    final vozila = await getVozila();
    if (!_vozilaController.isClosed) {
      _vozilaController.add(vozila);
    }
  }

  /// 🧹 Čisti realtime subscription
  static void dispose() {
    _vozilaSubscription?.cancel();
    _vozilaSubscription = null;
    _vozilaController.close();
  }

  /// Ažuriraj kolsku knjigu vozila
  static Future<bool> updateKolskaKnjiga(String id, Map<String, dynamic> podaci) async {
    try {
      await _supabase.from('v2_vozila').update(podaci).eq('id', id);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Ažuriraj broj mesta vozila
  static Future<bool> updateBrojMesta(String id, int brojMesta) async {
    try {
      await _supabase.from('v2_vozila').update({'broj_mesta': brojMesta}).eq('id', id);
      return true;
    } catch (e) {
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
      return false;
    }
  }
}

/// Model za vozilo - Kolska knjiga
class Vozilo {
  final String id;
  final String registarskiBroj;
  final String? marka;
  final String? model;
  final int? godinaProizvodnje;
  final int? brojMesta;
  final String? naziv;

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

  Vozilo({
    required this.id,
    required this.registarskiBroj,
    this.marka,
    this.model,
    this.godinaProizvodnje,
    this.brojMesta,
    this.naziv,
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

  factory Vozilo.fromJson(Map<String, dynamic> json) {
    return Vozilo(
      id: json['id']?.toString() ?? '',
      registarskiBroj: json['registarski_broj'] as String? ?? '',
      marka: json['marka'] as String?,
      model: json['model'] as String?,
      godinaProizvodnje: json['godina_proizvodnje'] as int?,
      brojMesta: json['broj_mesta'] as int?,
      naziv: json['naziv'] as String?,
      brojSasije: json['broj_sasije'] as String?,
      registracijaVaziDo: _parseDate(json['registracija_vazi_do']),
      maliServisDatum: _parseDate(json['mali_servis_datum']),
      maliServisKm: json['mali_servis_km'] as int?,
      velikiServisDatum: _parseDate(json['veliki_servis_datum']),
      velikiServisKm: json['veliki_servis_km'] as int?,
      alternatorDatum: _parseDate(json['alternator_datum']),
      alternatorKm: json['alternator_km'] as int?,
      gumeDatum: _parseDate(json['gume_datum']),
      gumeOpis: json['gume_opis'] as String?,
      gumePrednjeDatum: _parseDate(json['gume_prednje_datum']),
      gumePrednjeOpis: json['gume_prednje_opis'] as String?,
      gumePrednjeKm: json['gume_prednje_km'] as int?,
      gumeZadnjeDatum: _parseDate(json['gume_zadnje_datum']),
      gumeZadnjeOpis: json['gume_zadnje_opis'] as String?,
      gumeZadnjeKm: json['gume_zadnje_km'] as int?,
      akumulatorDatum: _parseDate(json['akumulator_datum']),
      akumulatorKm: json['akumulator_km'] as int?,
      plociceDatum: _parseDate(json['plocice_datum']),
      plociceKm: json['plocice_km'] as int?,
      plocicePrednjeDatum: _parseDate(json['plocice_prednje_datum']),
      plocicePrednjeKm: json['plocice_prednje_km'] as int?,
      plociceZadnjeDatum: _parseDate(json['plocice_zadnje_datum']),
      plociceZadnjeKm: json['plocice_zadnje_km'] as int?,
      trapDatum: _parseDate(json['trap_datum']),
      trapKm: json['trap_km'] as int?,
      radio: json['radio'] as String?,
      napomena: json['napomena'] as String?,
      kilometraza: (json['kilometraza'] as num?)?.toDouble(),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  /// Prikaži naziv
  String get displayNaziv {
    if (naziv != null && naziv!.isNotEmpty) return naziv!;
    if (marka != null && model != null) {
      return '$marka $model${brojMesta != null ? ' ($brojMesta mesta)' : ''}';
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
}
