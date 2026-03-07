import 'package:flutter/foundation.dart';

import '../globals.dart';
import '../models/v2_pumpa_punjenje.dart';
import '../models/v2_pumpa_stanje.dart';
import '../models/v2_pumpa_tocenje.dart';
import '../models/v2_vozilo_statistika.dart';
import 'v2_finansije_service.dart';
import 'v2_pumpa_service.dart';

/// Orchestrator za gorivo: stanje pumpe (VIEW) + statistike + koordinacija
/// Direktni CRUD delegiran na:
///   - V2PumpaConfigService  (v2_pumpa_config)
///   - V2PumpaPunjenjaService (v2_pumpa_punjenja)
///   - V2PumpaTocenjaService  (v2_pumpa_tocenja)
class V2GorivoService {
  V2GorivoService._();

  // ─────────────────────────────────────────────────────────────
  // STANJE PUMPE (v2_pumpa_stanje VIEW)
  // ─────────────────────────────────────────────────────────────

  /// Dohvati trenutno stanje pumpe
  static Future<V2PumpaStanje?> getStanje() async {
    try {
      final response = await supabase
          .from('v2_pumpa_stanje')
          .select(
              'kapacitet_litri,alarm_nivo,pocetno_stanje,ukupno_punjeno,ukupno_utroseno,trenutno_stanje,procenat_pune')
          .single();
      return V2PumpaStanje.fromJson(response);
    } catch (e) {
      debugPrint('[V2GorivoService] getStanje greška: $e');
      return null;
    }
  }

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

  static Future<bool> deletePunjenje(String id) => V2PumpaPunjenjaService.deletePunjenje(id);

  static Future<double?> getPoslednaCenaPoPLitru() => V2PumpaPunjenjaService.getPoslednaCenaPoPLitru();

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
        await supabase.from('v2_vozila').update({'kilometraza': kmVozila}).eq('id', voziloId);
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

      return true;
    } catch (e) {
      debugPrint('[V2GorivoService] addTocenje greška: $e');
      return false;
    }
  }

  static Future<bool> deleteTocenje(String id) => V2PumpaTocenjaService.deleteTocenje(id);

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
      debugPrint('[V2GorivoService] getStatistikePoVozilu greška: $e');
      return [];
    }
  }
}
