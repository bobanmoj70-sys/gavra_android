import 'package:flutter/foundation.dart';
import 'package:gavra_android/models/v3_gorivo.dart';
import 'package:gavra_android/services/realtime/v3_master_realtime_manager.dart';

import 'repositories/v3_gorivo_repository.dart';

class V3GorivoService {
  V3GorivoService._();

  static final V3GorivoRepository _repo = V3GorivoRepository();

  /// Kreira početni red u tabeli `v3_gorivo` ako tabela nema podataka
  static Future<bool> ensureInitialData() async {
    try {
      final existing = await _repo.selectFirst();
      if (existing.isNotEmpty) {
        return true;
      }

      final row = await _repo.insertReturning({
        'kapacitet_litri': 3000,
        'trenutno_stanje_litri': 0,
        'alarm_nivo_litri': 500,
        'brojac_pistolj_litri': 0,
        'cena_po_litru': 0,
        'dug_iznos': 0,
      });

      _upsertCache(row);
      return true;
    } catch (e) {
      debugPrint('[V3GorivoService] ensureInitialData error: $e');
      return false;
    }
  }

  /// Dohvata stanje pumpe iz cache-a (tabela: v3_gorivo)
  static V3PumpaStanje? getStanjeSync() {
    final cache = V3MasterRealtimeManager.instance.gorivoCache;
    if (cache.isEmpty) return null;
    return V3PumpaStanje.fromJson(cache.values.first);
  }

  /// Dohvata rezervoar iz cache-a (tabela: v3_gorivo)
  static V3PumpaRezervoar? getRezervoarSync() {
    final cache = V3MasterRealtimeManager.instance.gorivoCache;
    if (cache.isEmpty) return null;
    return V3PumpaRezervoar.fromJson(cache.values.first);
  }

  /// Trenutni dug prema dobavljaču goriva (RSD). 0 ako nema reda.
  static double getDugIznos() {
    return getStanjeSync()?.dugIznos ?? 0;
  }

  /// Stream koji emituje svaki put kad se gorivo promijeni
  static Stream<V3PumpaStanje?> streamStanje() {
    return V3MasterRealtimeManager.instance.v3StreamFromRevisions(
      tables: ['v3_gorivo'],
      build: getStanjeSync,
    );
  }

  static Stream<V3PumpaRezervoar?> streamRezervoar() {
    return V3MasterRealtimeManager.instance.v3StreamFromRevisions(
      tables: ['v3_gorivo'],
      build: getRezervoarSync,
    );
  }

  /// Ažurira trenutno stanje pumpe u bazi
  static Future<bool> updateStanje(String id, double novoStanje, double noviBrojac) async {
    try {
      final row = await _repo.updateByIdReturning(id, {
        'trenutno_stanje_litri': novoStanje,
        'brojac_pistolj_litri': noviBrojac,
      });
      _upsertCache(row);
      return true;
    } catch (e) {
      debugPrint('[V3GorivoService] updateStanje error: $e');
      return false;
    }
  }

  /// Ažurira trenutni nivo rezervoara u bazi
  static Future<bool> updateRezervoar(String id, double novoLitara) async {
    try {
      final row = await _repo.updateByIdReturning(id, {
        'trenutno_stanje_litri': novoLitara,
      });
      _upsertCache(row);
      return true;
    } catch (e) {
      debugPrint('[V3GorivoService] updateRezervoar failed for id $id: $e');
      return false;
    }
  }

  /// Dopuna cisterne: litraža + opciono povećanje duga + opciono nova cena/L.
  ///
  /// [dugDodatoRsd] — koliko se DODAJE na postojeći ukupan dug (npr. litri × cena).
  /// null/0 = dug se ne dira (npr. cena još nije poznata).
  /// [cenaPoLitru] — ako je > 0, čuva se kao referentna cena za sledeće dopune.
  static Future<bool> dopuniRezervoar({
    required String id,
    required double novoLitara,
    double? dugDodatoRsd,
    double? cenaPoLitru,
  }) async {
    try {
      final payload = <String, dynamic>{
        'trenutno_stanje_litri': novoLitara,
      };
      final dodato = dugDodatoRsd ?? 0;
      if (dodato > 0) {
        final trenutniDug = getStanjeSync()?.dugIznos ?? 0;
        payload['dug_iznos'] = trenutniDug + dodato;
      }
      if (cenaPoLitru != null && cenaPoLitru > 0) {
        payload['cena_po_litru'] = cenaPoLitru;
      }
      final row = await _repo.updateByIdReturning(id, payload);
      _upsertCache(row);
      return true;
    } catch (e) {
      debugPrint('[V3GorivoService] dopuniRezervoar failed for id $id: $e');
      return false;
    }
  }

  /// Povećava dug za gorivo (npr. kad se kasnije sazna tačan iznos nabavke).
  static Future<bool> povecajDug(double iznos) async {
    if (iznos <= 0) return true;
    final stanje = getStanjeSync();
    if (stanje == null || stanje.id.isEmpty) {
      debugPrint('[V3GorivoService] povecajDug: nema reda za gorivo');
      return false;
    }
    return _setDugIznos(stanje.id, stanje.dugIznos + iznos);
  }

  /// Umanjuje dug za gorivo pri uplati / trošku iz Finansija (kao kredit.uplati).
  /// Ne ide ispod 0.
  static Future<bool> smanjiDug(double iznos) async {
    if (iznos <= 0) return true;
    final stanje = getStanjeSync();
    if (stanje == null || stanje.id.isEmpty) {
      debugPrint('[V3GorivoService] smanjiDug: nema reda za gorivo');
      return false;
    }
    final novo = stanje.dugIznos - iznos;
    return _setDugIznos(stanje.id, novo < 0 ? 0.0 : novo);
  }

  static Future<bool> _setDugIznos(String id, double dugIznos) async {
    try {
      final row = await _repo.updateByIdReturning(id, {
        'dug_iznos': dugIznos < 0 ? 0.0 : dugIznos,
      });
      _upsertCache(row);
      return true;
    } catch (e) {
      debugPrint('[V3GorivoService] _setDugIznos error: $e');
      return false;
    }
  }

  /// Ažurira sva polja goriva koja se uređuju iz UI forme
  static Future<bool> updateAllFields({
    required String id,
    required double kapacitetLitri,
    required double alarmNivoLitri,
    required double brojacPistoljLitri,
    required double cenaPoLitru,
    required double dugIznos,
  }) async {
    try {
      final row = await _repo.updateByIdReturning(id, {
        'kapacitet_litri': kapacitetLitri,
        'alarm_nivo_litri': alarmNivoLitri,
        'brojac_pistolj_litri': brojacPistoljLitri,
        'cena_po_litru': cenaPoLitru,
        'dug_iznos': dugIznos,
      });
      _upsertCache(row);
      return true;
    } catch (e) {
      debugPrint('[V3GorivoService] updateAllFields error: $e');
      return false;
    }
  }

  /// Pomoćna metoda za sigurno ažuriranje lokalnog cache-a
  static void _upsertCache(Map<String, dynamic> row) {
    if (row.isEmpty) return;
    V3MasterRealtimeManager.instance.v3UpsertToCache('v3_gorivo', row);
  }
}
