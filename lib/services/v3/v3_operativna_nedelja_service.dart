import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../../utils/v3_date_utils.dart';
import '../../utils/v3_status_policy.dart';
import '../../utils/v3_string_utils.dart';
import '../../utils/v3_uuid_utils.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_operativna_nedelja_repository.dart';
import 'v3_putnik_service.dart';

class V3OperativnaNedeljaEntry {
  final String id;
  final String putnikId;
  final DateTime datum;
  final String? grad;
  final String? polazakAt;
  final String? statusFinal;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? updatedBy;
  final int brojMesta;
  final DateTime? pokupljenAt;
  final String? pokupljenBy;
  final String? otkazanoBy;
  final DateTime? otkazanoAt;
  final int? maxMesta;
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
    this.updatedBy,
    this.brojMesta = 1,
    this.pokupljenAt,
    this.pokupljenBy,
    this.otkazanoBy,
    this.otkazanoAt,
    this.maxMesta,
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
      statusFinal: V3StatusPolicy.deriveOperativnaStatus(
        otkazanoAt: json['otkazano_at'],
        polazakAt: json['polazak_at'],
      ),
      createdAt: V3DateUtils.parseTs(json['created_at'] as String?),
      updatedAt: V3DateUtils.parseTs(json['updated_at'] as String?),
      updatedBy: json['updated_by'] as String?,
      brojMesta: (json['broj_mesta'] as num?)?.toInt() ?? 1,
      pokupljenAt: V3DateUtils.parseTs(json['pokupljen_at'] as String?),
      pokupljenBy: json['pokupljen_by'] as String?,
      otkazanoBy: json['otkazano_by'] as String?,
      otkazanoAt: V3DateUtils.parseTs(json['otkazano_at'] as String?),
      maxMesta: (json['max_mesta'] as num?)?.toInt(),
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
      'datum': V3DateUtils.parseIsoDatePart(datum.toIso8601String()),
      'grad': grad,
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      if (updatedBy != null) 'updated_by': updatedBy,
      if (polazakAt != null) 'polazak_at': polazakAt,
      if (pokupljenAt != null) 'pokupljen_at': pokupljenAt!.toIso8601String(),
      if (pokupljenBy != null) 'pokupljen_by': pokupljenBy,
      if (otkazanoBy != null) 'otkazano_by': otkazanoBy,
      if (otkazanoAt != null) 'otkazano_at': otkazanoAt!.toIso8601String(),
      'koristi_sekundarnu': koristiSekundarnu,
      if (adresaIdOverride != null) 'adresa_override_id': adresaIdOverride,
    };
  }
}

class V3OperativnaNedeljaService {
  V3OperativnaNedeljaService._();
  static final V3OperativnaNedeljaRepository _repo = V3OperativnaNedeljaRepository();

  static bool _isOperativnaAktivna(Map<String, dynamic> row) {
    return !V3StatusPolicy.isTimestampSet(row['otkazano_at']);
  }

  /// Vraća sve zapise za tačan datum (svi gradovi).
  static List<V3OperativnaNedeljaEntry> getOperativnaNedeljaByDatum(String datumIso) {
    final cache = V3MasterRealtimeManager.instance.operativnaNedeljaCache.values;
    return cache
        .where((r) {
          final rDatum = V3DateUtils.parseIsoDatePart(r['datum'] as String? ?? '');
          return rDatum == datumIso;
        })
        .map((r) => V3OperativnaNedeljaEntry.fromJson(r))
        .toList();
  }

  /// Čita max_mesta za dati grad/vreme/datum iz v3_kapacitet_slots cache-a.
  /// Vraća null ako slot nije pronađen.
  static int? getKapacitetVozila(String grad, String vreme, DateTime datum) {
    final datumIso = V3DateUtils.parseIsoDatePart(datum.toIso8601String());
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

  /// Direktan INSERT u v3_operativna_nedelja — za vozača koji dodaje putnika.
  /// Upisuje: polazak_at, created_by UUID (ako je dostupan).
  /// Ako već postoji zapis za isti putnik+datum+grad → UPDATE `polazak_at`.
  static Future<void> createOrUpdateByVozac({
    required String putnikId,
    required String datum, // yyyy-MM-dd
    required String grad,
    required String polazakAt, // HH:mm
    String? createdBy,
    bool? koristiSekundarnu,
    String? adresaIdOverride,
  }) async {
    try {
      final actor = V3UuidUtils.normalizeUuid(createdBy);
      const normalizedBrojMesta = 1;

      // Provjeri postoji li već zapis
      final cache = V3MasterRealtimeManager.instance.operativnaNedeljaCache.values;
      final postojeci = cache.where((r) {
        final rDatum = V3DateUtils.parseIsoDatePart(r['datum'] as String? ?? '');
        final rowPutnikId = r['created_by']?.toString();
        return rowPutnikId == putnikId && rDatum == datum && r['grad'] == grad && _isOperativnaAktivna(r);
      }).toList();

      if (postojeci.isNotEmpty) {
        // UPDATE: prepiši polazak_at i broj_mesta
        final updatedRow = await _repo.updateByIdReturningSingle(postojeci.first['id'] as String, {
          'polazak_at': polazakAt,
          'broj_mesta': normalizedBrojMesta,
          if (actor != null) 'updated_by': actor,
          if (koristiSekundarnu != null) 'koristi_sekundarnu': koristiSekundarnu,
          'adresa_override_id': adresaIdOverride, // null = briše override
        });
        V3MasterRealtimeManager.instance.v3UpsertToCache('v3_operativna_nedelja', updatedRow);
      } else {
        // INSERT direktno u operativna_nedelja
        final insertedRow = await _repo.insertReturning({
          'created_by': putnikId,
          'datum': datum,
          'grad': grad,
          'polazak_at': polazakAt,
          'broj_mesta': normalizedBrojMesta,
          if (actor != null) 'updated_by': actor,
          if (koristiSekundarnu != null) 'koristi_sekundarnu': koristiSekundarnu,
          if (adresaIdOverride != null) 'adresa_override_id': adresaIdOverride,
        });
        V3MasterRealtimeManager.instance.v3UpsertToCache('v3_operativna_nedelja', insertedRow);
      }
    } catch (e) {
      debugPrint('[V3OperativnaNedeljaService] createOrUpdateByVozac error: $e');
      rethrow;
    }
  }
}
