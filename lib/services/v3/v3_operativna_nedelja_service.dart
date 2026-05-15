import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../../utils/v3_date_utils.dart';
import '../../utils/v3_status_policy.dart';
import '../../utils/v3_string_utils.dart';
import '../../utils/v3_uuid_utils.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_operativna_nedelja_repository.dart';
import 'v3_trenutna_dodela_service.dart';
import 'v3_trenutna_dodela_slot_service.dart';

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

  static DateTime _zahtevOrderingTs(Map<String, dynamic> row) {
    final updated = V3DateUtils.parseTs(row['updated_at']?.toString());
    if (updated != null) return updated;
    final created = V3DateUtils.parseTs(row['created_at']?.toString());
    if (created != null) return created;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static bool _isZahtevVisible(Map<String, dynamic> row) {
    final status = row['status']?.toString();
    return !V3StatusPolicy.isCanceledOrRejected(status);
  }

  static Future<void> _syncZahtevForVozacContext({
    required String putnikId,
    required String datum,
    required String grad,
    required String polazakAt,
    String? updatedBy,
    bool? koristiSekundarnu,
    String? adresaIdOverride,
  }) async {
    final gradNorm = grad.trim().toUpperCase();
    if (putnikId.isEmpty || datum.isEmpty || gradNorm.isEmpty || polazakAt.isEmpty) return;

    final zahtevCache = V3MasterRealtimeManager.instance.zahteviCache.values;
    final contextRows = zahtevCache.where((row) {
      final rowPutnikId = (row['created_by']?.toString() ?? '').trim();
      final rowDatum = V3DateUtils.parseIsoDatePart(row['datum'] as String? ?? '');
      final rowGrad = (row['grad']?.toString() ?? '').trim().toUpperCase();
      return rowPutnikId == putnikId && rowDatum == datum && rowGrad == gradNorm;
    }).toList();

    final visibleRows = contextRows.where(_isZahtevVisible).toList()
      ..sort((a, b) => _zahtevOrderingTs(b).compareTo(_zahtevOrderingTs(a)));

    final actor = V3UuidUtils.normalizeUuid(updatedBy);
    final zahtevPayload = {
      'status': 'odobreno',
      'trazeni_polazak_at': polazakAt,
      'polazak_at': polazakAt,
      'alternativa_pre_at': null,
      'alternativa_posle_at': null,
      if (actor != null) 'updated_by': actor,
      if (koristiSekundarnu != null) 'koristi_sekundarnu': koristiSekundarnu,
      'adresa_override_id': adresaIdOverride,
    };

    if (visibleRows.isNotEmpty) {
      final primaryId = (visibleRows.first['id']?.toString() ?? '').trim();
      if (primaryId.isNotEmpty) {
        final updated = await supabase.from('v3_zahtevi').update(zahtevPayload).eq('id', primaryId).select().single();
        V3MasterRealtimeManager.instance.v3UpsertToCache('v3_zahtevi', updated);
      }

      for (final stale in visibleRows.skip(1)) {
        final staleId = (stale['id']?.toString() ?? '').trim();
        if (staleId.isEmpty) continue;
        final canceled = await supabase
            .from('v3_zahtevi')
            .update({
              'status': 'otkazano',
              if (actor != null) 'updated_by': actor,
            })
            .eq('id', staleId)
            .select()
            .single();
        V3MasterRealtimeManager.instance.v3UpsertToCache('v3_zahtevi', canceled);
      }
      return;
    }

    final inserted = await supabase
        .from('v3_zahtevi')
        .insert({
          'datum': datum,
          'grad': gradNorm,
          'created_by': putnikId,
          ...zahtevPayload,
        })
        .select()
        .single();
    V3MasterRealtimeManager.instance.v3UpsertToCache('v3_zahtevi', inserted);
  }

  static Future<void> syncTerminDodelaFromSlotForRow({
    required Map<String, dynamic> operativnaRow,
    String? updatedBy,
  }) async {
    final terminId = (operativnaRow['id']?.toString() ?? '').trim();
    final putnikId = (operativnaRow['created_by']?.toString() ?? '').trim();
    final datumIso = V3DateUtils.parseIsoDatePart(operativnaRow['datum'] as String? ?? '');
    final grad = (operativnaRow['grad']?.toString() ?? '').trim();
    final vreme = (operativnaRow['polazak_at']?.toString() ?? operativnaRow['vreme']?.toString() ?? '').trim();

    if (terminId.isEmpty || putnikId.isEmpty || datumIso.isEmpty || grad.isEmpty || vreme.isEmpty) return;

    final canAssign = V3StatusPolicy.canAssign(
      status: operativnaRow['status']?.toString(),
      otkazanoAt: operativnaRow['otkazano_at'],
      pokupljenAt: operativnaRow['pokupljen_at'],
    );

    if (!canAssign) {
      await V3TrenutnaDodelaService.deleteByTerminId(terminId);
      return;
    }

    final slotAssignments = await V3TrenutnaDodelaSlotService.loadActiveVozacBySlotKey(
      datumIso: datumIso,
    );

    final slotKey = V3TrenutnaDodelaSlotService.slotKey(
      datumIso: datumIso,
      grad: grad,
      vreme: vreme,
    );
    final vozacId = (slotAssignments[slotKey] ?? '').trim();

    if (vozacId.isEmpty) {
      await V3TrenutnaDodelaService.deleteByTerminId(terminId);
      return;
    }

    await V3TrenutnaDodelaService.upsertActiveTerminDodela(
      terminId: terminId,
      putnikId: putnikId,
      vozacId: vozacId,
      updatedBy: updatedBy,
    );
  }

  static Future<void> syncTerminDodelaFromSlotForRows({
    required Iterable<Map<String, dynamic>> operativnaRows,
    String? updatedBy,
  }) async {
    for (final row in operativnaRows) {
      await syncTerminDodelaFromSlotForRow(
        operativnaRow: row,
        updatedBy: updatedBy,
      );
    }
  }

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
      // Provjeri postoji li već zapis
      final cache = V3MasterRealtimeManager.instance.operativnaNedeljaCache.values;
      final postojeci = cache.where((r) {
        final rDatum = V3DateUtils.parseIsoDatePart(r['datum'] as String? ?? '');
        final rowPutnikId = r['created_by']?.toString();
        return rowPutnikId == putnikId && rDatum == datum && r['grad'] == grad && _isOperativnaAktivna(r);
      }).toList();

      if (postojeci.isNotEmpty) {
        // UPDATE: prepiši polazak_at
        final updatedRow = await _repo.updateByIdReturningSingle(postojeci.first['id'] as String, {
          'polazak_at': polazakAt,
          if (actor != null) 'updated_by': actor,
          if (koristiSekundarnu != null) 'koristi_sekundarnu': koristiSekundarnu,
          'adresa_override_id': adresaIdOverride, // null = briše override
        });
        V3MasterRealtimeManager.instance.v3UpsertToCache('v3_operativna_nedelja', updatedRow);
        try {
          await syncTerminDodelaFromSlotForRow(
            operativnaRow: updatedRow,
            updatedBy: actor,
          );
        } catch (e) {
          debugPrint('[V3OperativnaNedeljaService] sync assignment after update error: $e');
        }
        await _syncZahtevForVozacContext(
          putnikId: putnikId,
          datum: datum,
          grad: grad,
          polazakAt: polazakAt,
          updatedBy: actor,
          koristiSekundarnu: koristiSekundarnu,
          adresaIdOverride: adresaIdOverride,
        );
      } else {
        // INSERT direktno u operativna_nedelja
        final insertedRow = await _repo.insertReturning({
          'created_by': putnikId,
          'datum': datum,
          'grad': grad,
          'polazak_at': polazakAt,
          if (actor != null) 'updated_by': actor,
          if (koristiSekundarnu != null) 'koristi_sekundarnu': koristiSekundarnu,
          if (adresaIdOverride != null) 'adresa_override_id': adresaIdOverride,
        });
        V3MasterRealtimeManager.instance.v3UpsertToCache('v3_operativna_nedelja', insertedRow);
        try {
          await syncTerminDodelaFromSlotForRow(
            operativnaRow: insertedRow,
            updatedBy: actor,
          );
        } catch (e) {
          debugPrint('[V3OperativnaNedeljaService] sync assignment after insert error: $e');
        }
        await _syncZahtevForVozacContext(
          putnikId: putnikId,
          datum: datum,
          grad: grad,
          polazakAt: polazakAt,
          updatedBy: actor,
          koristiSekundarnu: koristiSekundarnu,
          adresaIdOverride: adresaIdOverride,
        );
      }
    } catch (e) {
      debugPrint('[V3OperativnaNedeljaService] createOrUpdateByVozac error: $e');
      rethrow;
    }
  }
}
