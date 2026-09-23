import 'package:flutter/foundation.dart';
import 'package:gavra_android/models/v3_gorivo.dart';
import 'package:gavra_android/services/realtime/v3_master_realtime_manager.dart';
import 'package:gavra_android/utils/v3_belgrade_time.dart';
import 'package:gavra_android/utils/v3_dan_helper.dart';

import 'repositories/v3_gorivo_repository.dart';

class V3GorivoDopunaObracun {
  final double staraCenaPoLitru;
  final double novaCenaPoLitru;
  final double cenaZaObracun;
  final double dodatiDug;
  final double ukupanDugPosle;

  const V3GorivoDopunaObracun({
    required this.staraCenaPoLitru,
    required this.novaCenaPoLitru,
    required this.cenaZaObracun,
    required this.dodatiDug,
    required this.ukupanDugPosle,
  });
}

class V3GorivoUplataObracun {
  final double stariDug;
  final double iznosUplate;
  final double pokrivenoDuga;
  final double preplata;
  final double noviDug;

  const V3GorivoUplataObracun({
    required this.stariDug,
    required this.iznosUplate,
    required this.pokrivenoDuga,
    required this.preplata,
    required this.noviDug,
  });
}

class V3GorivoService {
  V3GorivoService._();

  static final V3GorivoRepository _repo = V3GorivoRepository();

  static double _roundMoney(double v) => (v * 100).roundToDouble() / 100;

  static V3GorivoDopunaObracun izracunajDopunuObracun({
    required double trenutniDug,
    required double staraCenaPoLitru,
    required double dodatoLitara,
    double? novaCenaPoLitru,
    double? rucniDodatiDug,
  }) {
    final safeTrenutniDug = trenutniDug < 0 ? 0.0 : trenutniDug;
    final safeStaraCena = staraCenaPoLitru > 0 ? staraCenaPoLitru : 0.0;
    final safeNovaCena = (novaCenaPoLitru != null && novaCenaPoLitru > 0) ? novaCenaPoLitru : safeStaraCena;
    final safeLitri = dodatoLitara > 0 ? dodatoLitara : 0.0;

    double dodatiDug;
    if (rucniDodatiDug != null && rucniDodatiDug >= 0) {
      dodatiDug = rucniDodatiDug;
    } else if (safeLitri > 0 && safeNovaCena > 0) {
      dodatiDug = safeLitri * safeNovaCena;
    } else {
      dodatiDug = 0.0;
    }

    final roundedDodatiDug = _roundMoney(dodatiDug);
    final roundedUkupanDug = _roundMoney(safeTrenutniDug + roundedDodatiDug);

    return V3GorivoDopunaObracun(
      staraCenaPoLitru: _roundMoney(safeStaraCena),
      novaCenaPoLitru: _roundMoney(safeNovaCena),
      cenaZaObracun: _roundMoney(safeNovaCena),
      dodatiDug: roundedDodatiDug,
      ukupanDugPosle: roundedUkupanDug,
    );
  }

  static V3GorivoUplataObracun izracunajUplatuObracun({
    required double trenutniDug,
    required double iznosUplate,
  }) {
    final stari = trenutniDug < 0 ? 0.0 : trenutniDug;
    final uplata = iznosUplate < 0 ? 0.0 : iznosUplate;
    final pokriveno = uplata <= stari ? uplata : stari;
    final preplata = uplata > stari ? (uplata - stari) : 0.0;
    final novi = stari - pokriveno;

    return V3GorivoUplataObracun(
      stariDug: _roundMoney(stari),
      iznosUplate: _roundMoney(uplata),
      pokrivenoDuga: _roundMoney(pokriveno),
      preplata: _roundMoney(preplata),
      noviDug: _roundMoney(novi < 0 ? 0.0 : novi),
    );
  }

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

  /// Dopuna: trenutno += litri, opciono dug += iznos, opciono nova cena/L.
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

  /// Umanjuje dug za gorivo pri uplati / trošku iz Finansija (kao kredit.uplati).
  /// Ne ide ispod 0.
  static Future<bool> smanjiDug(double iznos) async {
    if (iznos <= 0) return true;
    final stanje = getStanjeSync();
    if (stanje == null || stanje.id.isEmpty) {
      debugPrint('[V3GorivoService] smanjiDug: nema reda za gorivo');
      return false;
    }
    final obracun = izracunajUplatuObracun(
      trenutniDug: stanje.dugIznos,
      iznosUplate: iznos,
    );
    return _setDugIznos(stanje.id, obracun.noviDug);
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
    required double trenutnoStanjeLitri,
    required double alarmNivoLitri,
    required double brojacPistoljLitri,
    required double cenaPoLitru,
    required double dugIznos,
  }) async {
    try {
      final row = await _repo.updateByIdReturning(id, {
        'kapacitet_litri': kapacitetLitri,
        'trenutno_stanje_litri': trenutnoStanjeLitri,
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

  static Future<V3GorivoPotrosnjaPregled> getPotrosnjaPregled() async {
    final now = V3BelgradeTime.now();
    final danas = V3DanHelper.dateOnlyFrom(now.year, now.month, now.day);
    final sutra = danas.add(const Duration(days: 1));

    final aktivnaNedelja = V3DanHelper.schedulingWeekRange(now: now);
    final nedeljaStart = aktivnaNedelja.start;
    final nedeljaEnd = aktivnaNedelja.end;
    final nedeljaEndExclusive = nedeljaEnd.add(const Duration(days: 1));

    final mesStart = V3DanHelper.dateOnlyFrom(now.year, now.month, 1);
    final mesEnd = V3DanHelper.dateOnlyFrom(now.year, now.month + 1, 1);

    final godStart = V3DanHelper.dateOnlyFrom(now.year, 1, 1);
    final godEnd = V3DanHelper.dateOnlyFrom(now.year + 1, 1, 1);

    double dan = 0;
    double ned = 0;
    double mes = 0;
    double god = 0;

    try {
      final rows = await _repo.selectPotrosnjaBetween(
        startIsoUtc: godStart.toUtc().toIso8601String(),
        endIsoUtc: godEnd.toUtc().toIso8601String(),
      );

      for (final raw in rows) {
        final row = (raw as Map).cast<String, dynamic>();
        final dt = V3BelgradeTime.parseTs(row['created_at']?.toString());
        if (dt == null) continue;
        final litri = (row['litri'] as num?)?.toDouble() ?? 0.0;
        if (litri <= 0) continue;

        if (!dt.isBefore(danas) && dt.isBefore(sutra)) {
          dan += litri;
        }
        if (!dt.isBefore(nedeljaStart) && dt.isBefore(nedeljaEndExclusive)) {
          ned += litri;
        }
        if (!dt.isBefore(mesStart) && dt.isBefore(mesEnd)) {
          mes += litri;
        }
        if (!dt.isBefore(godStart) && dt.isBefore(godEnd)) {
          god += litri;
        }
      }
    } catch (e) {
      debugPrint('[V3GorivoService] getPotrosnjaPregled error: $e');
    }

    return V3GorivoPotrosnjaPregled(
      danasLitri: dan,
      nedeljaLitri: ned,
      mesecLitri: mes,
      godinaLitri: god,
      danasPeriod: V3DanHelper.formatDanMesec(danas),
      nedeljaPeriod: '${V3DanHelper.formatDanMesec(nedeljaStart)} - ${V3DanHelper.formatDanMesec(nedeljaEnd)}',
    );
  }
}
