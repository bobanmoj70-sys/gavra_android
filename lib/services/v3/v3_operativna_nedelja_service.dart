import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../../utils/v3_audit_actor.dart';
import '../../utils/v3_date_utils.dart';
import '../../utils/v3_string_utils.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_operativna_nedelja_repository.dart';

class V3OperativnaNedeljaEntry {
  final String id;
  final String putnikId;
  final DateTime datum;
  final String? grad;
  final String? vreme;
  final String? statusFinal;
  final bool aktivno;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int brojMesta;
  final String? zeljenoVreme;
  final String? dodeljivoVreme;
  final DateTime? vremePokupljen;
  final double iznosNaplacen;
  final DateTime? vremePlacen;
  final String naplataStatus;
  final String? pokupljenVozacId;
  final String? naplatioVozacId;
  final String? otkazaoVozacId;
  final String? otkazaoPutnikId;
  final int? maxMesta;
  final bool pokupljen;
  final String? altVremePre;
  final String? altVremePosle;
  final bool koristiSekundarnu;
  final String? adresaIdOverride;
  final String? createdBy;

  V3OperativnaNedeljaEntry({
    required this.id,
    required this.putnikId,
    required this.datum,
    this.grad,
    this.vreme,
    this.statusFinal,
    this.aktivno = true,
    this.createdAt,
    this.updatedAt,
    this.brojMesta = 1,
    this.zeljenoVreme,
    this.dodeljivoVreme,
    this.vremePokupljen,
    this.iznosNaplacen = 0,
    this.vremePlacen,
    this.naplataStatus = 'nije_placeno',
    this.pokupljenVozacId,
    this.naplatioVozacId,
    this.otkazaoVozacId,
    this.otkazaoPutnikId,
    this.maxMesta,
    this.pokupljen = false,
    this.altVremePre,
    this.altVremePosle,
    this.koristiSekundarnu = false,
    this.adresaIdOverride,
    this.createdBy,
  });

  factory V3OperativnaNedeljaEntry.fromJson(Map<String, dynamic> json) {
    final efektivnoVreme = (json['dodeljeno_vreme'] as String?) ?? (json['zeljeno_vreme'] as String?);

    return V3OperativnaNedeljaEntry(
      id: json['id'] as String? ?? '',
      putnikId: json['putnik_id'] as String? ?? '',
      datum: json['datum'] != null ? DateTime.parse(json['datum'] as String) : DateTime.now(),
      grad: json['grad'] as String?,
      vreme: efektivnoVreme,
      statusFinal: json['status_final'] as String?,
      aktivno: json['aktivno'] as bool? ?? true,
      createdAt: V3DateUtils.parseTs(json['created_at'] as String?),
      updatedAt: V3DateUtils.parseTs(json['updated_at'] as String?),
      brojMesta: (json['broj_mesta'] as num?)?.toInt() ?? 1,
      zeljenoVreme: json['zeljeno_vreme'] as String?,
      dodeljivoVreme: json['dodeljeno_vreme'] as String?,
      vremePokupljen: V3DateUtils.parseTs(json['vreme_pokupljen'] as String?),
      iznosNaplacen: (json['iznos_naplacen'] as num?)?.toDouble() ?? 0,
      vremePlacen: V3DateUtils.parseTs(json['vreme_placen'] as String?),
      naplataStatus: json['naplata_status'] as String? ?? 'nije_placeno',
      pokupljenVozacId: json['pokupljen_vozac_id'] as String?,
      naplatioVozacId: json['naplatio_vozac_id'] as String?,
      otkazaoVozacId: json['otkazao_vozac_id'] as String?,
      otkazaoPutnikId: json['otkazao_putnik_id'] as String?,
      maxMesta: (json['max_mesta'] as num?)?.toInt(),
      pokupljen: json['pokupljen'] as bool? ?? false,
      altVremePre: json['alt_vreme_pre'] as String?,
      altVremePosle: json['alt_vreme_posle'] as String?,
      koristiSekundarnu: json['koristi_sekundarnu'] as bool? ?? false,
      adresaIdOverride: json['adresa_id_override'] as String?,
      createdBy: json['created_by'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'putnik_id': putnikId,
      'datum': V3DanHelper.parseIsoDatePart(datum.toIso8601String()),
      'grad': grad,
      'status_final': statusFinal,
      'aktivno': aktivno,
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      if (zeljenoVreme != null) 'zeljeno_vreme': zeljenoVreme,
      if (dodeljivoVreme != null) 'dodeljeno_vreme': dodeljivoVreme,
      if (vremePokupljen != null) 'vreme_pokupljen': vremePokupljen!.toIso8601String(),
      'iznos_naplacen': iznosNaplacen,
      if (vremePlacen != null) 'vreme_placen': vremePlacen!.toIso8601String(),
      'naplata_status': naplataStatus,
      if (pokupljenVozacId != null) 'pokupljen_vozac_id': pokupljenVozacId,
      if (naplatioVozacId != null) 'naplatio_vozac_id': naplatioVozacId,
      if (otkazaoVozacId != null) 'otkazao_vozac_id': otkazaoVozacId,
      if (otkazaoPutnikId != null) 'otkazao_putnik_id': otkazaoPutnikId,
      if (maxMesta != null) 'max_mesta': maxMesta,
      if (altVremePre != null) 'alt_vreme_pre': altVremePre,
      if (altVremePosle != null) 'alt_vreme_posle': altVremePosle,
      'koristi_sekundarnu': koristiSekundarnu,
      if (adresaIdOverride != null) 'adresa_id_override': adresaIdOverride,
      if (createdBy != null) 'created_by': createdBy,
    };
  }
}

class V3OperativnaNedeljaService {
  V3OperativnaNedeljaService._();
  static final V3OperativnaNedeljaRepository _repo = V3OperativnaNedeljaRepository();

  static Future<void> _updateById(
    String id,
    Map<String, dynamic> payload,
  ) async {
    final row = await _repo.updateByIdReturningMaybeSingle(id, payload);
    if (row != null) {
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_operativna_nedelja', row);
    }
  }

  static List<V3OperativnaNedeljaEntry> getOperativnaNedeljaByFilter({
    required String grad,
    required String vreme,
    required DateTime datum,
  }) {
    final cache = V3MasterRealtimeManager.instance.operativnaNedeljaCache.values;
    final datumStr = V3DanHelper.parseIsoDatePart(datum.toIso8601String());

    return cache
        .where((r) {
          final efektivnoVreme = (r['dodeljeno_vreme'] as String?) ?? (r['zeljeno_vreme'] as String?);
          return r['grad'] == grad &&
              efektivnoVreme == vreme &&
              r['datum'].toString() == datumStr &&
              r['aktivno'] == true;
        })
        .map((r) => V3OperativnaNedeljaEntry.fromJson(r))
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id)); // Default sort
  }

  static Stream<List<V3OperativnaNedeljaEntry>> streamOperativnaNedeljaByFilter({
    required String grad,
    required String vreme,
    required DateTime datum,
  }) {
    return V3MasterRealtimeManager.instance.v3StreamFromCache(
      tables: ['v3_operativna_nedelja'],
      build: () => getOperativnaNedeljaByFilter(grad: grad, vreme: vreme, datum: datum),
    );
  }

  /// Vraća sve zapise za dati grad za celu nedelju (bez filtera po danu).
  static List<V3OperativnaNedeljaEntry> getOperativnaNedeljaByGrad(String grad) {
    final cache = V3MasterRealtimeManager.instance.operativnaNedeljaCache.values;
    return cache.where((r) => r['grad'] == grad).map((r) => V3OperativnaNedeljaEntry.fromJson(r)).toList();
  }

  /// Stream koji emituje sve zapise za dati grad za celu nedelju.
  static Stream<List<V3OperativnaNedeljaEntry>> streamOperativnaNedeljaByGrad(String grad) {
    return V3MasterRealtimeManager.instance.v3StreamFromCache(
      tables: ['v3_operativna_nedelja'],
      build: () => getOperativnaNedeljaByGrad(grad),
    );
  }

  /// Vraća sve zapise za tačan datum i grad iz cache-a.
  static List<V3OperativnaNedeljaEntry> getOperativnaNedeljaByDatumAndGrad(String datumIso, String grad) {
    final cache = V3MasterRealtimeManager.instance.operativnaNedeljaCache.values;
    return cache
        .where((r) {
          final rDatum = V3DanHelper.parseIsoDatePart(r['datum'] as String? ?? '');
          return rDatum == datumIso && r['grad'] == grad;
        })
        .map((r) => V3OperativnaNedeljaEntry.fromJson(r))
        .toList();
  }

  /// Stream koji emituje zapise za tačan datum i grad.
  static Stream<List<V3OperativnaNedeljaEntry>> streamOperativnaNedeljaByDatumAndGrad(String datumIso, String grad) {
    return V3MasterRealtimeManager.instance.v3StreamFromCache(
      tables: ['v3_operativna_nedelja'],
      build: () => getOperativnaNedeljaByDatumAndGrad(datumIso, grad),
    );
  }

  /// Vraća sve zapise za tačan datum (svi gradovi).
  static List<V3OperativnaNedeljaEntry> getOperativnaNedeljaByDatum(String datumIso) {
    final cache = V3MasterRealtimeManager.instance.operativnaNedeljaCache.values;
    return cache
        .where((r) {
          final rDatum = V3DanHelper.parseIsoDatePart(r['datum'] as String? ?? '');
          return rDatum == datumIso;
        })
        .map((r) => V3OperativnaNedeljaEntry.fromJson(r))
        .toList();
  }

  /// Stream koji emituje sve zapise za tačan datum (svi gradovi).
  static Stream<List<V3OperativnaNedeljaEntry>> streamOperativnaNedeljaByDatum(String datumIso) {
    return V3MasterRealtimeManager.instance.v3StreamFromCache(
      tables: ['v3_operativna_nedelja'],
      build: () => getOperativnaNedeljaByDatum(datumIso),
    );
  }

  static Future<void> updateStatus({
    required String id,
    required String status,
  }) async {
    try {
      // V3 Arhitektura: Fire and Forget (Realtime će odraditi sync preko updated_at)
      await _repo.updateById(id, {
        'status_final': status,
      });
    } catch (e) {
      debugPrint('[V3OperativnaNedeljaService] Update status error: $e');
      rethrow;
    }
  }

  static Future<void> updateNaplata({
    required String id,
    required double iznos,
    String? naplatioVozacId,
  }) async {
    try {
      final row = await _repo.updateByIdReturningSingle(id, {
        'naplata_status': 'placeno',
        'iznos_naplacen': iznos,
        'vreme_placen': DateTime.now().toIso8601String(),
        if (naplatioVozacId != null) 'naplatio_vozac_id': naplatioVozacId,
      });
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_operativna_nedelja', row);
    } catch (e) {
      debugPrint('[V3OperativnaNedeljaService] updateNaplata error: $e');
      rethrow;
    }
  }

  /// Čita max_mesta za dati grad/vreme/datum iz v3_kapacitet_slots cache-a.
  /// Vraća null ako slot nije pronađen.
  static int? getKapacitetVozila(String grad, String vreme, DateTime datum) {
    final cache = V3MasterRealtimeManager.instance.kapacitetSlotsCache.values;
    final datumStr = V3DanHelper.parseIsoDatePart(datum.toIso8601String());
    for (final r in cache) {
      if (r['grad'] == grad &&
          V3StringUtils.trimTimeToHhMm(r['vreme'].toString()) == vreme &&
          r['datum'].toString().startsWith(datumStr) &&
          r['aktivno'] == true) {
        return (r['max_mesta'] as num?)?.toInt();
      }
    }
    return null;
  }

  /// Čita broj zauzetih mesta — suma broj_mesta zapisa sa statusom koji zauzima mjesto.
  /// Filtrira: aktivno=true i status_final IN (obrada, odobreno, alternativa).
  /// Napomena: pokupljeni putnici imaju status_final='odobreno' + pokupljen=true, pa su već u skupu.
  static int getZauzetaMesta(String grad, String vreme, DateTime datum) {
    const aktivniStatusi = {'obrada', 'odobreno', 'alternativa'};
    final zapisi = getOperativnaNedeljaByFilter(grad: grad, vreme: vreme, datum: datum);
    return zapisi
        .where((e) => e.aktivno && aktivniStatusi.contains(e.statusFinal))
        .fold(0, (sum, e) => sum + e.brojMesta);
  }

  /// Čita broj slobodnih mesta za dati grad/vreme/datum.
  /// slobodna = max_mesta - zauzetaMesta (min 0).
  /// Vraća null ako max_mesta nije postavljeno.
  static int? getSlobodnaMesta(String grad, String vreme, DateTime datum) {
    final kapacitet = getKapacitetVozila(grad, vreme, datum);
    if (kapacitet == null) return null;
    final zauzeto = getZauzetaMesta(grad, vreme, datum);
    return (kapacitet - zauzeto).clamp(0, kapacitet);
  }

  /// Stream koji emituje [kapacitet, zauzeto, slobodna] za dati termin.
  static Stream<({int? kapacitet, int zauzeto, int? slobodna})> streamMesta({
    required String grad,
    required String vreme,
    required DateTime datum,
  }) {
    return V3MasterRealtimeManager.instance.v3StreamFromCache(
      tables: ['v3_operativna_nedelja'],
      build: () {
        final kapacitet = getKapacitetVozila(grad, vreme, datum);
        final zauzeto = getZauzetaMesta(grad, vreme, datum);
        final slobodna = kapacitet != null ? (kapacitet - zauzeto).clamp(0, kapacitet) : null;
        return (kapacitet: kapacitet, zauzeto: zauzeto, slobodna: slobodna);
      },
    );
  }

  /// Direktan INSERT u v3_operativna_nedelja — za vozača koji dodaje putnika.
  /// Upisuje: zeljeno_vreme, dodeljeno_vreme, status_final='odobreno', created_by UUID (ako je dostupan).
  /// Ako već postoji aktivan zapis za isti putnik+datum+grad → UPDATE vreme+status.
  static Future<void> createOrUpdateByVozac({
    required String putnikId,
    required String datum, // yyyy-MM-dd
    required String grad,
    required String zeljenoVreme, // HH:mm
    required String dodeljivoVreme, // HH:mm
    required int brojMesta,
    String? createdBy,
    bool? koristiSekundarnu,
    String? adresaIdOverride,
  }) async {
    try {
      final actor = V3AuditActor.normalize(createdBy);

      // Provjeri postoji li već aktivan zapis
      final cache = V3MasterRealtimeManager.instance.operativnaNedeljaCache.values;
      final postojeci = cache.where((r) {
        final rDatum = V3DanHelper.parseIsoDatePart(r['datum'] as String? ?? '');
        return r['putnik_id'] == putnikId && rDatum == datum && r['grad'] == grad && r['aktivno'] == true;
      }).toList();

      if (postojeci.isNotEmpty) {
        // UPDATE: prepiši vreme i status
        await _repo.updateById(postojeci.first['id'] as String, {
          'zeljeno_vreme': zeljenoVreme,
          'dodeljeno_vreme': dodeljivoVreme,
          'status_final': 'odobreno',
          if (actor != null) 'updated_by': actor,
          if (koristiSekundarnu != null) 'koristi_sekundarnu': koristiSekundarnu,
          'adresa_id_override': adresaIdOverride, // null = briše override
        });
      } else {
        // INSERT direktno u operativna_nedelja
        await _repo.insert({
          'putnik_id': putnikId,
          'datum': datum,
          'grad': grad,
          'zeljeno_vreme': zeljenoVreme,
          'dodeljeno_vreme': dodeljivoVreme,
          'broj_mesta': brojMesta,
          'status_final': 'odobreno',
          'aktivno': true,
          'pokupljen': false,
          if (actor != null) 'created_by': actor,
          if (koristiSekundarnu != null) 'koristi_sekundarnu': koristiSekundarnu,
          if (adresaIdOverride != null) 'adresa_id_override': adresaIdOverride,
        });
      }
    } catch (e) {
      debugPrint('[V3OperativnaNedeljaService] createOrUpdateByVozac error: $e');
      rethrow;
    }
  }

  static Future<void> assignVozacBulkByIds({
    required List<String> operativnaIds,
    required String vozacId,
    required String navBarType,
    String? updatedBy,
  }) async {
    if (operativnaIds.isEmpty) return;
    final actor = V3AuditActor.normalize(updatedBy);

    for (final id in operativnaIds) {
      await _updateById(id, {
        'vozac_id': vozacId,
        'nav_bar_type': navBarType,
        if (actor != null) 'updated_by': actor,
      });
    }
  }

  static Future<void> removeVozacByTermin({
    required String datumIso,
    required String grad,
    required String dodeljenoVreme,
    String? updatedBy,
  }) async {
    final actor = V3AuditActor.normalize(updatedBy);
    final updatedRows = await _repo.updateByTerminReturningList(
      datumIso: datumIso,
      grad: grad,
      dodeljenoVreme: dodeljenoVreme,
      payload: {
        'vozac_id': null,
        'route_order': null,
        if (actor != null) 'updated_by': actor,
      },
    );

    for (final row in updatedRows) {
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_operativna_nedelja', row);
    }
  }

  static Future<void> assignVozacByOperativnaId({
    required String operativnaId,
    required String vozacId,
    required String navBarType,
    String? updatedBy,
  }) async {
    final actor = V3AuditActor.normalize(updatedBy);
    await _updateById(operativnaId, {
      'vozac_id': vozacId,
      'nav_bar_type': navBarType,
      if (actor != null) 'updated_by': actor,
    });
  }

  static Future<void> removeVozacByPutnikAndTermin({
    required String putnikId,
    required String grad,
    required String dodeljenoVreme,
    required String datumIso,
    String? updatedBy,
  }) async {
    final actor = V3AuditActor.normalize(updatedBy);
    final updatedRows = await _repo.updateByPutnikGradDodeljenoDatumReturningList(
      putnikId: putnikId,
      grad: grad,
      dodeljenoVreme: dodeljenoVreme,
      datumIso: datumIso,
      payload: {
        'vozac_id': null,
        'route_order': null,
        if (actor != null) 'updated_by': actor,
      },
    );

    for (final row in updatedRows) {
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_operativna_nedelja', row);
    }
  }

  static Future<void> updateRouteOrderById({
    required String operativnaId,
    int? routeOrder,
  }) async {
    await _updateById(operativnaId, {
      'route_order': routeOrder,
    });
  }
}
