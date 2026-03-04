import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import 'v2_finansije_service.dart';
import 'v2_pumpa_config_service.dart';
import 'v2_pumpa_punjenja_service.dart';
import 'v2_pumpa_tocenja_service.dart';

/// Orchestrator za gorivo: stanje pumpe (VIEW) + statistike + koordinacija
/// Direktni CRUD delegiran na:
///   - V2PumpaConfigService  (v2_pumpa_config)
///   - V2PumpaPunjenjaService (v2_pumpa_punjenja)
///   - V2PumpaTocenjaService  (v2_pumpa_tocenja)
class V2GorivoService {
  V2GorivoService._();

  static SupabaseClient get _db => supabase;

  // ─────────────────────────────────────────────────────────────
  // STANJE PUMPE (v2_pumpa_stanje VIEW)
  // ─────────────────────────────────────────────────────────────

  /// Dohvati trenutno stanje pumpe
  static Future<V2PumpaStanje?> getStanje() async {
    try {
      final response = await _db
          .from('v2_pumpa_stanje')
          .select(
              'kapacitet_litri,alarm_nivo,pocetno_stanje,ukupno_punjeno,ukupno_utroseno,trenutno_stanje,procenat_pune')
          .single();
      return V2PumpaStanje.fromJson(response);
    } catch (e) {
      debugPrint('[GorivoService] getStanje error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // DELEGIRANO na V2PumpaConfigService
  // ─────────────────────────────────────────────────────────────

  static Future<bool> updateConfig({
    double? kapacitet,
    double? alarmNivo,
    double? pocetnoStanje,
  }) =>
      V2PumpaConfigService.updateConfig(
        kapacitet: kapacitet,
        alarmNivo: alarmNivo,
        pocetnoStanje: pocetnoStanje,
      );

  // ─────────────────────────────────────────────────────────────
  // DELEGIRANO na V2PumpaPunjenjaService
  // ─────────────────────────────────────────────────────────────

  static Future<List<V2PumpaPunjenje>> getPunjenja({int limit = 50}) =>
      V2PumpaPunjenjaService.getPunjenja(limit: limit);

  static Future<bool> addPunjenje({
    required DateTime datum,
    required double litri,
    double? cenaPoPLitru,
    String? napomena,
  }) =>
      V2PumpaPunjenjaService.addPunjenje(
        datum: datum,
        litri: litri,
        cenaPoPLitru: cenaPoPLitru,
        napomena: napomena,
      );

  static Future<bool> deletePunjenje(String id) =>
      V2PumpaPunjenjaService.deletePunjenje(id);

  static Future<double?> getPoslednaCenaPoPLitru() =>
      V2PumpaPunjenjaService.getPoslednaCenaPoPLitru();

  // ─────────────────────────────────────────────────────────────
  // DELEGIRANO na V2PumpaTocenjaService
  // ─────────────────────────────────────────────────────────────

  static Future<List<V2PumpaTocenje>> getTocenja({
    int limit = 100,
    String? voziloId,
  }) =>
      V2PumpaTocenjaService.getTocenja(limit: limit, voziloId: voziloId);

  /// Dodaj točenje — i automatski kreira trošak u finansijama
  static Future<bool> addTocenje({
    required DateTime datum,
    required String voziloId,
    required double litri,
    int? kmVozila,
    String? napomena,
    double? cenaPoPLitru,
  }) async {
    try {
      await V2PumpaTocenjaService.addTocenje(
        datum: datum,
        voziloId: voziloId,
        litri: litri,
        kmVozila: kmVozila,
        napomena: napomena,
      );

      // Ažuriraj kilometražu vozila ako je unesena
      if (kmVozila != null) {
        await _db.from('v2_vozila').update({'kilometraza': kmVozila}).eq('id', voziloId);
      }

      // Kreiraj trošak u finansijama (ako postoji cijena)
      if (cenaPoPLitru != null && cenaPoPLitru > 0) {
        final iznos = litri * cenaPoPLitru;
        await V2FinansijeService.addTrosak(
          'Gorivo',
          'gorivo',
          iznos,
          mesec: datum.month,
          godina: datum.year,
        );
      }

      debugPrint('[GorivoService] Tocenje dodato: $litri L za vozilo $voziloId');
      return true;
    } catch (e) {
      debugPrint('[GorivoService] addTocenje error: $e');
      return false;
    }
  }

  static Future<bool> deleteTocenje(String id) =>
      V2PumpaTocenjaService.deleteTocenje(id);

  // ─────────────────────────────────────────────────────────────
  // STATISTIKE (orchestrator — agregira podatke iz V2PumpaTocenjaService)
  // ─────────────────────────────────────────────────────────────

  /// Potrošnja po vozilu za period
  static Future<List<V2VoziloStatistika>> getStatistikePoVozilu({
    DateTime? od,
    DateTime? do_,
  }) async {
    try {
      final data = await V2PumpaTocenjaService.getTocenjaZaStatistike(od: od, do_: do_);

      // Agregiraj po vozilu
      final Map<String, V2VoziloStatistika> mapa = {};
      for (final row in data) {
        final voziloId = row['vozilo_id'] as String? ?? '';
        final litri = (row['litri'] as num?)?.toDouble() ?? 0;
        final vozilo = row['v2_vozila'] as Map<String, dynamic>?;
        final regBroj = vozilo?['registarski_broj'] as String? ?? voziloId;
        final marka = vozilo?['marka'] as String? ?? '';
        final model = vozilo?['model'] as String? ?? '';

        if (mapa.containsKey(voziloId)) {
          mapa[voziloId] = mapa[voziloId]!.copyWith(
            ukupnoLitri: mapa[voziloId]!.ukupnoLitri + litri,
            brojTocenja: mapa[voziloId]!.brojTocenja + 1,
          );
        } else {
          mapa[voziloId] = V2VoziloStatistika(
            voziloId: voziloId,
            registarskiBroj: regBroj,
            marka: marka,
            model: model,
            ukupnoLitri: litri,
            brojTocenja: 1,
          );
        }
      }

      final lista = mapa.values.toList();
      lista.sort((a, b) => b.ukupnoLitri.compareTo(a.ukupnoLitri));
      return lista;
    } catch (e) {
      debugPrint('[GorivoService] getStatistikePoVozilu error: $e');
      return [];
    }
  }

  /// Posljednja cijena po litru (iz punjenja)
  static Future<double?> getPoslednaCenaPoPLitru() async {
    try {
      final response = await _db
          .from('v2_pumpa_punjenja')
          .select('cena_po_litru')
          .not('cena_po_litru', 'is', null)
          .order('datum', ascending: false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (response == null) return null;
      return (response['cena_po_litru'] as num?)?.toDouble();
    } catch (e) {
      debugPrint('[GorivoService] getPoslednaCenaPoPLitru error: $e');
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MODELI
// ─────────────────────────────────────────────────────────────────────────────

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

class V2PumpaPunjenje {
  final String id;
  final DateTime datum;
  final double litri;
  final double? cenaPoPLitru;
  final double? ukupnoCena;
  final String? napomena;
  final DateTime createdAt;

  V2PumpaPunjenje({
    required this.id,
    required this.datum,
    required this.litri,
    this.cenaPoPLitru,
    this.ukupnoCena,
    this.napomena,
    required this.createdAt,
  });

  factory V2PumpaPunjenje.fromJson(Map<String, dynamic> j) => V2PumpaPunjenje(
        id: j['id'] as String,
        datum: DateTime.parse(j['datum'] as String),
        litri: (j['litri'] as num).toDouble(),
        cenaPoPLitru: (j['cena_po_litru'] as num?)?.toDouble(),
        ukupnoCena: (j['ukupno_cena'] as num?)?.toDouble(),
        napomena: j['napomena'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      );

  @override
  bool operator ==(Object other) => identical(this, other) || other is V2PumpaPunjenje && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class V2PumpaTocenje {
  final String id;
  final DateTime datum;
  final String? voziloId;
  final String? registarskiBroj;
  final String? marka;
  final String? model;
  final double litri;
  final int? kmVozila;
  final String? napomena;
  final DateTime createdAt;

  V2PumpaTocenje({
    required this.id,
    required this.datum,
    this.voziloId,
    this.registarskiBroj,
    this.marka,
    this.model,
    required this.litri,
    this.kmVozila,
    this.napomena,
    required this.createdAt,
  });

  factory V2PumpaTocenje.fromJson(Map<String, dynamic> j) {
    final vozilo = j['v2_vozila'] as Map<String, dynamic>?;
    return V2PumpaTocenje(
      id: j['id'] as String,
      datum: DateTime.parse(j['datum'] as String),
      voziloId: j['vozilo_id'] as String?,
      registarskiBroj: vozilo?['registarski_broj'] as String?,
      marka: vozilo?['marka'] as String?,
      model: vozilo?['model'] as String?,
      litri: (j['litri'] as num).toDouble(),
      kmVozila: j['km_vozila'] as int?,
      napomena: j['napomena'] as String?,
      createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
    );
  }

  String get voziloNaziv {
    if (registarskiBroj != null) {
      return '$registarskiBroj${marka != null ? ' ($marka)' : ''}';
    }
    return 'Nepoznato vozilo';
  }

  @override
  bool operator ==(Object other) => identical(this, other) || other is V2PumpaTocenje && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

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
