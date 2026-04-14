import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../../utils/v3_audit_korisnik.dart';
import '../../utils/v3_date_utils.dart';
import '../../utils/v3_status_filters.dart';
import '../../utils/v3_string_utils.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_operativna_nedelja_repository.dart';

class V3OperativnaNedeljaEntry {
  final String id;
  final String putnikId;
  final DateTime datum;
  final String? grad;
  final String? polazakAt;
  final String? statusFinal;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int brojMesta;
  final DateTime? pokupljenAt;
  final double iznosNaplacen;
  final DateTime? naplacenAt;
  final String naplataStatus;
  final String? pokupljenBy;
  final String? naplacenBy;
  final String? otkazanoBy;
  final DateTime? otkazanoAt;
  final int? maxMesta;
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
    this.polazakAt,
    this.statusFinal,
    this.createdAt,
    this.updatedAt,
    this.brojMesta = 1,
    this.pokupljenAt,
    this.iznosNaplacen = 0,
    this.naplacenAt,
    this.naplataStatus = 'nije_placeno',
    this.pokupljenBy,
    this.naplacenBy,
    this.otkazanoBy,
    this.otkazanoAt,
    this.maxMesta,
    this.altVremePre,
    this.altVremePosle,
    this.koristiSekundarnu = false,
    this.adresaIdOverride,
    this.createdBy,
  });

  factory V3OperativnaNedeljaEntry.fromJson(Map<String, dynamic> json) {
    final effectivePutnikId = (json['created_by'] as String?) ?? '';

    return V3OperativnaNedeljaEntry(
      id: json['id'] as String? ?? '',
      putnikId: effectivePutnikId,
      datum: json['datum'] != null ? DateTime.parse(json['datum'] as String) : DateTime.now(),
      grad: json['grad'] as String?,
      polazakAt: json['polazak_at'] as String?,
      statusFinal: V3StatusFilters.deriveOperativnaStatus(json),
      createdAt: V3DateUtils.parseTs(json['created_at'] as String?),
      updatedAt: V3DateUtils.parseTs(json['updated_at'] as String?),
      brojMesta: (json['broj_mesta'] as num?)?.toInt() ?? 1,
      pokupljenAt: V3DateUtils.parseTs(json['pokupljen_at'] as String?),
      iznosNaplacen: (json['naplacen_iznos'] as num?)?.toDouble() ?? 0,
      naplacenAt: V3DateUtils.parseTs(json['naplacen_at'] as String?),
      naplataStatus: V3StatusFilters.isNaplacenAt(json['naplacen_at']) ? 'placeno' : 'nije_placeno',
      pokupljenBy: json['pokupljen_by'] as String?,
      naplacenBy: json['naplacen_by'] as String?,
      otkazanoBy: json['otkazano_by'] as String?,
      otkazanoAt: V3DateUtils.parseTs(json['otkazano_at'] as String?),
      maxMesta: (json['max_mesta'] as num?)?.toInt(),
      altVremePre: json['alternativa_pre_at'] as String?,
      altVremePosle: json['alternativa_posle_at'] as String?,
      koristiSekundarnu: json['koristi_sekundarnu'] as bool? ?? false,
      adresaIdOverride: json['adresa_override_id'] as String?,
      createdBy: json['created_by'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final effectiveCreatedBy = createdBy ?? (putnikId.isNotEmpty ? putnikId : null);
    return {
      'id': id,
      if (effectiveCreatedBy != null) 'created_by': effectiveCreatedBy,
      'datum': V3DanHelper.parseIsoDatePart(datum.toIso8601String()),
      'grad': grad,
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      if (polazakAt != null) 'polazak_at': polazakAt,
      if (pokupljenAt != null) 'pokupljen_at': pokupljenAt!.toIso8601String(),
      'naplacen_iznos': iznosNaplacen,
      if (naplacenAt != null) 'naplacen_at': naplacenAt!.toIso8601String(),
      if (pokupljenBy != null) 'pokupljen_by': pokupljenBy,
      if (naplacenBy != null) 'naplacen_by': naplacenBy,
      if (otkazanoBy != null) 'otkazano_by': otkazanoBy,
      if (otkazanoAt != null) 'otkazano_at': otkazanoAt!.toIso8601String(),
      if (altVremePre != null) 'alternativa_pre_at': altVremePre,
      if (altVremePosle != null) 'alternativa_posle_at': altVremePosle,
      'koristi_sekundarnu': koristiSekundarnu,
      if (adresaIdOverride != null) 'adresa_override_id': adresaIdOverride,
    };
  }
}

class V3OperativnaNedeljaService {
  V3OperativnaNedeljaService._();
  static final V3OperativnaNedeljaRepository _repo = V3OperativnaNedeljaRepository();

  static bool _isOperativnaAktivna(Map<String, dynamic> row) {
    final status = V3StatusFilters.deriveOperativnaStatus(row);
    return !V3StatusFilters.isCanceledOrRejected(status);
  }

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
          return r['grad'] == grad &&
              r['polazak_at'] == vreme &&
              r['datum'].toString() == datumStr &&
              _isOperativnaAktivna(r);
        })
        .map((r) => V3OperativnaNedeljaEntry.fromJson(r))
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
  }

  static Stream<List<V3OperativnaNedeljaEntry>> streamOperativnaNedeljaByFilter({
    required String grad,
    required String vreme,
    required DateTime datum,
  }) {
    return V3MasterRealtimeManager.instance.v3StreamFromRevisions(
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
    return V3MasterRealtimeManager.instance.v3StreamFromRevisions(
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
    return V3MasterRealtimeManager.instance.v3StreamFromRevisions(
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
    return V3MasterRealtimeManager.instance.v3StreamFromRevisions(
      tables: ['v3_operativna_nedelja'],
      build: () => getOperativnaNedeljaByDatum(datumIso),
    );
  }

  static Future<void> updateNaplata({
    required String id,
    required double iznos,
    String? naplacenBy,
  }) async {
    try {
      final row = await _repo.updateByIdReturningSingle(id, {
        'naplacen_iznos': iznos,
        'naplacen_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        if (naplacenBy != null) 'naplacen_by': naplacenBy,
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
    final datumIso = V3DanHelper.parseIsoDatePart(datum.toIso8601String());
    final trazeniGrad = grad.trim().toUpperCase();
    final trazenoVreme = V3StringUtils.trimTimeToHhMm(vreme);

    if (isNeradanDan(datumIso: datumIso, grad: trazeniGrad.toLowerCase())) {
      return 0;
    }

    final cache = V3MasterRealtimeManager.instance.kapacitetSlotsCache.values;
    for (final r in cache) {
      final rGrad = (r['grad']?.toString() ?? '').trim().toUpperCase();
      if (rGrad != trazeniGrad) continue;

      final rVreme = V3StringUtils.trimTimeToHhMm(r['vreme']?.toString() ?? '');
      if (rVreme != trazenoVreme) continue;

      final rDatum = r['datum']?.toString() ?? '';
      if (rDatum.startsWith(datumIso)) {
        return (r['max_mesta'] as num?)?.toInt();
      }
    }
    return null;
  }

  /// Čita broj zauzetih mesta — suma broj_mesta aktivnih operativnih zapisa.
  /// Aktivni status je izveden iz operativnih kolona (`otkazano_at`, `alternativa_*`, `polazak_at`).
  static int getZauzetaMesta(String grad, String vreme, DateTime datum) {
    const aktivniStatusi = {'obrada', 'odobreno', 'alternativa'};
    final zapisi = getOperativnaNedeljaByFilter(grad: grad, vreme: vreme, datum: datum);
    return zapisi.where((e) => aktivniStatusi.contains(e.statusFinal)).fold(0, (sum, e) => sum + e.brojMesta);
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

  /// Direktan INSERT u v3_operativna_nedelja — za vozača koji dodaje putnika.
  /// Upisuje: polazak_at, created_by UUID (ako je dostupan).
  /// Ako već postoji zapis za isti putnik+datum+grad → UPDATE `polazak_at`.
  static Future<void> createOrUpdateByVozac({
    required String putnikId,
    required String datum, // yyyy-MM-dd
    required String grad,
    required String polazakAt, // HH:mm
    required int brojMesta,
    String? createdBy,
    bool? koristiSekundarnu,
    String? adresaIdOverride,
  }) async {
    try {
      final actor = V3AuditKorisnik.normalize(createdBy);

      // Provjeri postoji li već zapis
      final cache = V3MasterRealtimeManager.instance.operativnaNedeljaCache.values;
      final postojeci = cache.where((r) {
        final rDatum = V3DanHelper.parseIsoDatePart(r['datum'] as String? ?? '');
        final rowPutnikId = r['created_by']?.toString();
        return rowPutnikId == putnikId && rDatum == datum && r['grad'] == grad && _isOperativnaAktivna(r);
      }).toList();

      if (postojeci.isNotEmpty) {
        // UPDATE: prepiši polazak_at
        await _repo.updateById(postojeci.first['id'] as String, {
          'polazak_at': polazakAt,
          'updated_at': DateTime.now().toIso8601String(),
          if (actor != null) 'updated_by': actor,
          if (koristiSekundarnu != null) 'koristi_sekundarnu': koristiSekundarnu,
          'adresa_override_id': adresaIdOverride, // null = briše override
        });
      } else {
        // INSERT direktno u operativna_nedelja
        await _repo.insert({
          'created_by': putnikId,
          'datum': datum,
          'grad': grad,
          'polazak_at': polazakAt,
          'broj_mesta': brojMesta,
          'updated_at': DateTime.now().toIso8601String(),
          if (actor != null) 'updated_by': actor,
          if (koristiSekundarnu != null) 'koristi_sekundarnu': koristiSekundarnu,
          if (adresaIdOverride != null) 'adresa_override_id': adresaIdOverride,
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
    final actor = V3AuditKorisnik.normalize(updatedBy);

    for (final id in operativnaIds) {
      await _updateById(id, {
        'pokupljen_by': vozacId,
        'updated_at': DateTime.now().toIso8601String(),
        if (actor != null) 'updated_by': actor,
      });
    }
  }

  static Future<void> removeVozacByTermin({
    required String datumIso,
    required String grad,
    required String polazakAt,
    String? updatedBy,
  }) async {
    final actor = V3AuditKorisnik.normalize(updatedBy);
    final updatedRows = await _repo.updateByTerminReturningList(
      datumIso: datumIso,
      grad: grad,
      polazakAt: polazakAt,
      payload: {
        'pokupljen_by': null,
        'updated_at': DateTime.now().toIso8601String(),
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
    final actor = V3AuditKorisnik.normalize(updatedBy);
    await _updateById(operativnaId, {
      'pokupljen_by': vozacId,
      'updated_at': DateTime.now().toIso8601String(),
      if (actor != null) 'updated_by': actor,
    });
  }

  static Future<void> removeVozacByPutnikAndTermin({
    required String putnikId,
    required String grad,
    required String polazakAt,
    required String datumIso,
    String? updatedBy,
  }) async {
    final actor = V3AuditKorisnik.normalize(updatedBy);
    final updatedRows = await _repo.updateByPutnikGradPolazakAtDatumReturningList(
      putnikId: putnikId,
      grad: grad,
      polazakAt: polazakAt,
      datumIso: datumIso,
      payload: {
        'pokupljen_by': null,
        'updated_at': DateTime.now().toIso8601String(),
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
    debugPrint(
      '[V3OperativnaNedeljaService] updateRouteOrderById skipped: column route_order ne postoji u v3_operativna_nedelja',
    );
  }
}
