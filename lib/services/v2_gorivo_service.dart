import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import 'v2_finansije_service.dart';

/// ⛽ GORIVO SERVICE
/// Upravljanje kućnom pumpom goriva: punjenja, točenja, stanje, statistike
class V2GorivoService {
  static SupabaseClient get _db => supabase;

  // ─────────────────────────────────────────────────────────────
  // STANJE PUMPE
  // ─────────────────────────────────────────────────────────────

  /// Dohvati trenutno stanje pumpe
  static Future<PumpaStanje?> getStanje() async {
    try {
      final response = await _db
          .from('v2_pumpa_stanje')
          .select(
              'kapacitet_litri,alarm_nivo,pocetno_stanje,ukupno_punjeno,ukupno_utroseno,trenutno_stanje,procenat_pune')
          .single();
      return PumpaStanje.fromJson(response);
    } catch (e) {
      debugPrint('❌ [Gorivo] getStanje error: $e');
      return null;
    }
  }

  /// Ažuriraj konfiguraciju pumpe (kapacitet, alarm nivo, početno stanje)
  static Future<bool> updateConfig({
    double? kapacitet,
    double? alarmNivo,
    double? pocetnoStanje,
  }) async {
    try {
      final Map<String, dynamic> data = {
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (kapacitet != null) data['kapacitet_litri'] = kapacitet;
      if (alarmNivo != null) data['alarm_nivo'] = alarmNivo;
      if (pocetnoStanje != null) data['pocetno_stanje'] = pocetnoStanje;

      await _db.from('v2_pumpa_config').update(data);
      return true;
    } catch (e) {
      debugPrint('❌ [Gorivo] updateConfig error: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // PUNJENJA (nabavka goriva)
  // ─────────────────────────────────────────────────────────────

  /// Dohvati sva punjenja (najnovija prva)
  static Future<List<PumpaPunjenje>> getPunjenja({int limit = 50}) async {
    try {
      final response = await _db
          .from('v2_pumpa_punjenja')
          .select('id,datum,litri,cena_po_litru,ukupno_cena,napomena,created_at')
          .order('datum', ascending: false)
          .order('created_at', ascending: false)
          .limit(limit);
      return (response as List).map((r) => PumpaPunjenje.fromJson(r)).toList();
    } catch (e) {
      debugPrint('❌ [Gorivo] getPunjenja error: $e');
      return [];
    }
  }

  /// Dodaj punjenje pumpe
  static Future<bool> addPunjenje({
    required DateTime datum,
    required double litri,
    double? cenaPoPLitru,
    String? napomena,
  }) async {
    try {
      await _db.from('v2_pumpa_punjenja').insert({
        'datum': datum.toIso8601String().split('T')[0],
        'litri': litri,
        'cena_po_litru': cenaPoPLitru,
        'ukupno_cena': (cenaPoPLitru != null) ? litri * cenaPoPLitru : null,
        'napomena': napomena,
      });
      debugPrint('✅ [Gorivo] Punjenje dodato: $litri L');
      return true;
    } catch (e) {
      debugPrint('❌ [Gorivo] addPunjenje error: $e');
      return false;
    }
  }

  /// Obriši punjenje
  static Future<bool> deletePunjenje(String id) async {
    try {
      await _db.from('v2_pumpa_punjenja').delete().eq('id', id);
      return true;
    } catch (e) {
      debugPrint('❌ [Gorivo] deletePunjenje error: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // TOČENJA (po vozilu)
  // ─────────────────────────────────────────────────────────────

  /// Dohvati sva točenja (najnovija prva)
  static Future<List<PumpaTocenje>> getTocenja({
    int limit = 100,
    String? voziloId,
  }) async {
    try {
      var selectQuery = _db.from('v2_pumpa_tocenja').select('*, v2_vozila(registarski_broj, marka, model)');

      final response = await (voziloId != null ? selectQuery.eq('vozilo_id', voziloId) : selectQuery)
          .order('datum', ascending: false)
          .order('created_at', ascending: false)
          .limit(limit);
      return (response as List).map((r) => PumpaTocenje.fromJson(r)).toList();
    } catch (e) {
      debugPrint('❌ [Gorivo] getTocenja error: $e');
      return [];
    }
  }

  /// Dodaj točenje — i automatski kreira trošak u finansijama
  static Future<bool> addTocenje({
    required DateTime datum,
    required String voziloId,
    required double litri,
    int? kmVozila,
    String? napomena,
    double? cenaPoPLitru, // za obračun troška
  }) async {
    try {
      await _db.from('v2_pumpa_tocenja').insert({
        'datum': datum.toIso8601String().split('T')[0],
        'vozilo_id': voziloId,
        'litri': litri,
        'km_vozila': kmVozila,
        'napomena': napomena,
      });

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

      debugPrint('✅ [Gorivo] Točenje dodato: $litri L za vozilo $voziloId');
      return true;
    } catch (e) {
      debugPrint('❌ [Gorivo] addTocenje error: $e');
      return false;
    }
  }

  /// Obriši točenje
  static Future<bool> deleteTocenje(String id) async {
    try {
      await _db.from('v2_pumpa_tocenja').delete().eq('id', id);
      return true;
    } catch (e) {
      debugPrint('❌ [Gorivo] deleteTocenje error: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // STATISTIKE
  // ─────────────────────────────────────────────────────────────

  /// Potrošnja po vozilu za period
  static Future<List<VoziloStatistika>> getStatistikePoVozilu({
    DateTime? od,
    DateTime? do_,
  }) async {
    try {
      var query =
          _db.from('v2_pumpa_tocenja').select('vozilo_id, litri, km_vozila, v2_vozila(registarski_broj, marka, model)');

      if (od != null) {
        query = query.gte('datum', od.toIso8601String().split('T')[0]);
      }
      if (do_ != null) {
        query = query.lte('datum', do_.toIso8601String().split('T')[0]);
      }

      final response = await query;
      final List data = response as List;

      // Agregiraj po vozilu
      final Map<String, VoziloStatistika> mapa = {};
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
          mapa[voziloId] = VoziloStatistika(
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
      debugPrint('❌ [Gorivo] getStatistikePoVozilu error: $e');
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
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MODELI
// ─────────────────────────────────────────────────────────────────────────────

class PumpaStanje {
  final double kapacitetLitri;
  final double alarmNivo;
  final double pocetnoStanje;
  final double ukupnoPunjeno;
  final double ukupnoUtroseno;
  final double trenutnoStanje;
  final double procenatPune;

  PumpaStanje({
    required this.kapacitetLitri,
    required this.alarmNivo,
    required this.pocetnoStanje,
    required this.ukupnoPunjeno,
    required this.ukupnoUtroseno,
    required this.trenutnoStanje,
    required this.procenatPune,
  });

  factory PumpaStanje.fromJson(Map<String, dynamic> j) => PumpaStanje(
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
}

class PumpaPunjenje {
  final String id;
  final DateTime datum;
  final double litri;
  final double? cenaPoPLitru;
  final double? ukupnoCena;
  final String? napomena;
  final DateTime createdAt;

  PumpaPunjenje({
    required this.id,
    required this.datum,
    required this.litri,
    this.cenaPoPLitru,
    this.ukupnoCena,
    this.napomena,
    required this.createdAt,
  });

  factory PumpaPunjenje.fromJson(Map<String, dynamic> j) => PumpaPunjenje(
        id: j['id'] as String,
        datum: DateTime.parse(j['datum'] as String),
        litri: (j['litri'] as num).toDouble(),
        cenaPoPLitru: (j['cena_po_litru'] as num?)?.toDouble(),
        ukupnoCena: (j['ukupno_cena'] as num?)?.toDouble(),
        napomena: j['napomena'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      );
}

class PumpaTocenje {
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

  PumpaTocenje({
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

  factory PumpaTocenje.fromJson(Map<String, dynamic> j) {
    final vozilo = j['v2_vozila'] as Map<String, dynamic>?;
    return PumpaTocenje(
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
}

class VoziloStatistika {
  final String voziloId;
  final String registarskiBroj;
  final String marka;
  final String model;
  final double ukupnoLitri;
  final int brojTocenja;

  VoziloStatistika({
    required this.voziloId,
    required this.registarskiBroj,
    required this.marka,
    required this.model,
    required this.ukupnoLitri,
    required this.brojTocenja,
  });

  VoziloStatistika copyWith({double? ukupnoLitri, int? brojTocenja}) => VoziloStatistika(
        voziloId: voziloId,
        registarskiBroj: registarskiBroj,
        marka: marka,
        model: model,
        ukupnoLitri: ukupnoLitri ?? this.ukupnoLitri,
        brojTocenja: brojTocenja ?? this.brojTocenja,
      );
}
