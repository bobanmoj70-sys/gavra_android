import 'package:flutter/foundation.dart';

import '../globals.dart';
import '../models/v2_pumpa_punjenje.dart';
import '../models/v2_pumpa_stanje.dart';
import '../models/v2_pumpa_tocenje.dart';
import '../models/v2_vozilo_statistika.dart';
import 'realtime/v2_master_realtime_manager.dart';
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

  /// Stanje pumpe — kalkulisano iz RM cache-a (0 DB upita, instant)
  /// Replasira DB VIEW v2_pumpa_stanje: pocetno_stanje + ukupno_punjeno - ukupno_utroseno
  static V2PumpaStanje? getStanjeSync() {
    final rm = V2MasterRealtimeManager.instance;
    final config = rm.pumpaCache.values.firstOrNull;
    if (config == null) return null;

    final kapacitet = (config['kapacitet_litri'] as num?)?.toDouble() ?? 0.0;
    final alarmNivo = (config['alarm_nivo'] as num?)?.toDouble() ?? 0.0;
    final pocetnoStanje = (config['pocetno_stanje'] as num?)?.toDouble() ?? 0.0;

    final ukupnoPunjeno = rm.punjenjaCache.values.fold(0.0, (s, r) => s + ((r['litri'] as num?)?.toDouble() ?? 0.0));
    final ukupnoUtroseno = rm.tocenjaCache.values.fold(0.0, (s, r) => s + ((r['litri'] as num?)?.toDouble() ?? 0.0));

    final trenutnoStanje = pocetnoStanje + ukupnoPunjeno - ukupnoUtroseno;
    final procenat = kapacitet > 0 ? (trenutnoStanje / kapacitet * 100.0).clamp(0.0, 100.0) : 0.0;

    return V2PumpaStanje(
      kapacitetLitri: kapacitet,
      alarmNivo: alarmNivo,
      pocetnoStanje: pocetnoStanje,
      ukupnoPunjeno: ukupnoPunjeno,
      ukupnoUtroseno: ukupnoUtroseno,
      trenutnoStanje: trenutnoStanje,
      procenatPune: procenat,
    );
  }

  /// Async wrapper za kompatibilnost sa postojećim pozivima
  static Future<V2PumpaStanje?> getStanje() async => getStanjeSync();

  /// Stream stanja pumpe — autorefresh pri svakoj promjeni cache-a
  static Stream<V2PumpaStanje?> streamStanje() => V2MasterRealtimeManager.instance.v2StreamFromCache<V2PumpaStanje?>(
        tables: ['v2_pumpa_config', 'v2_pumpa_punjenja', 'v2_pumpa_tocenja'],
        build: getStanjeSync,
      );

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
      final ok = await V2PumpaTocenjaService.addTocenje(
        datum: datum,
        voziloId: voziloId,
        litri: litri,
        kmVozila: kmVozila,
        napomena: napomena,
      );
      if (!ok) return false;

      // Ažuriraj kilometražu vozila ako je unesena — greška ne poništava točenje
      if (kmVozila != null) {
        try {
          await supabase.from('v2_vozila').update({'kilometraza': kmVozila}).eq('id', voziloId);
          // Optimistički cache patch — streamVozila se odmah osvježava
          V2MasterRealtimeManager.instance.v2PatchCache('v2_vozila', voziloId, {'kilometraza': kmVozila});
        } catch (e) {
          debugPrint('[V2GorivoService] addTocenje updateKilometraza greška: $e');
        }
      }

      // Kreiraj trošak u finansijama (ako postoji cijena) — greška ne poništava točenje
      if (cenaPoPLitru != null && cenaPoPLitru > 0) {
        try {
          final iznos = litri * cenaPoPLitru;
          await V2FinansijeService.addTrosak(
            'Gorivo',
            'gorivo',
            iznos,
            mesec: datum.month,
            godina: datum.year,
          );
        } catch (e) {
          debugPrint('[V2GorivoService] addTocenje addTrosak greška: $e');
        }
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

        final existing = mapa[voziloId];
        if (existing != null) {
          mapa[voziloId] = existing.copyWith(
            ukupnoLitri: existing.ukupnoLitri + litri,
            brojTocenja: existing.brojTocenja + 1,
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
