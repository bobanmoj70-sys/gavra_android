import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../globals.dart';
import '../../models/v3_zahtev.dart';
import '../../utils/v3_date_utils.dart';
import '../../utils/v3_status_policy.dart';
import '../../utils/v3_uuid_utils.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_operativna_nedelja_repository.dart';
import 'v3_putnik_service.dart';
import 'v3_vozac_service.dart';
import 'zahtevi/v3_zahtev_domain_service.dart';
import 'zahtevi/v3_zahtev_repository.dart';
import 'zahtevi/v3_zahtev_types.dart';

/// Service for V3 passenger travel requests (`v3_zahtevi`).
class V3ZahtevService {
  V3ZahtevService._();

  static final V3ZahtevRepository _repository = V3ZahtevRepository();
  static final V3OperativnaNedeljaRepository _operativnaRepository = V3OperativnaNedeljaRepository();
  static final V3ZahtevDomainService _domain = V3ZahtevDomainService(_repository);

  static String _datumKey(DateTime datum) => V3DateUtils.parseIsoDatePart(datum.toIso8601String());

  static DateTime _parseTs(String? value) {
    if (value == null || value.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  static List<Map<String, dynamic>> _vidljiviRedoviPoKontekstu({
    required String putnikId,
    required DateTime datum,
    required String grad,
  }) {
    final datumIso = _datumKey(datum);
    final targetGrad = grad.trim().toUpperCase();
    final rows = V3MasterRealtimeManager.instance.zahteviCache.values.where((row) {
      final rowDatum = V3DateUtils.parseIsoDatePart(row['datum'] as String? ?? '');
      final rowGrad = (row['grad']?.toString() ?? '').trim().toUpperCase();
      return (row['created_by']?.toString() ?? '') == putnikId &&
          rowDatum == datumIso &&
          rowGrad == targetGrad &&
          V3StatusPolicy.isVisibleForDisplay(
            status: row['status']?.toString(),
          );
    }).toList();

    rows.sort((a, b) {
      final bTs = _parseTs(b['updated_at']?.toString()).isAfter(_parseTs(b['created_at']?.toString()))
          ? _parseTs(b['updated_at']?.toString())
          : _parseTs(b['created_at']?.toString());
      final aTs = _parseTs(a['updated_at']?.toString()).isAfter(_parseTs(a['created_at']?.toString()))
          ? _parseTs(a['updated_at']?.toString())
          : _parseTs(a['created_at']?.toString());
      return bTs.compareTo(aTs);
    });

    return rows;
  }

  static void _assertDatumUTekucojNedelji(DateTime datum) {
    if (!V3DanHelper.isInSchedulingWorkweek(datum)) {
      throw Exception('Zakazivanje je dozvoljeno samo u tekućoj sedmici.');
    }
  }

  static V3Zahtev? getZahtevById(String id) {
    final data = V3MasterRealtimeManager.instance.zahteviCache[id];
    return data != null ? V3Zahtev.fromJson(data) : null;
  }

  static Future<V3Zahtev> createZahtev(V3Zahtev zahtev, {String? createdBy}) async {
    try {
      _assertDatumUTekucojNedelji(zahtev.datum);

      final data = zahtev.toJson();
      final createdByUuid = V3UuidUtils.normalizeUuid(createdBy);
      if (createdByUuid != null) data['created_by'] = createdByUuid;
      if (!data.containsKey('created_at')) {
        data['created_at'] = DateTime.now().toIso8601String();
      }
      final row = await _repository.create(data);

      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_zahtevi', row);
      return V3Zahtev.fromJson(row);
    } catch (e) {
      debugPrint('[V3ZahtevService] Error: $e');
      rethrow;
    }
  }

  static Future<void> sacuvajPolazakPutnikaPoKontekstu({
    required String putnikId,
    required DateTime datum,
    required String grad,
    required String novoVreme,
    required int brojMesta,
    bool koristiSekundarnu = false,
    String? updatedBy,
  }) async {
    final normalizedBrojMesta = V3PutnikService.normalizeBrojMestaForPutnik(
      putnikId: putnikId,
      brojMesta: brojMesta,
    );
    final aktivni = _vidljiviRedoviPoKontekstu(putnikId: putnikId, datum: datum, grad: grad);
    if (aktivni.isNotEmpty) {
      final row = aktivni.first;
      final rowKey = (row['id']?.toString() ?? '').trim();
      if (rowKey.isNotEmpty) {
        final status = row['status']?.toString();
        if (V3StatusPolicy.isOfferLike(status)) {
          await updateStatus(rowKey, 'obrada', updatedBy: updatedBy);
        }
        await updateTrazeniPolazakAt(
          rowKey,
          novoVreme,
          koristiSekundarnu: koristiSekundarnu,
          updatedBy: updatedBy,
        );
        return;
      }
    }

    final zahtev = V3Zahtev(
      id: const Uuid().v4(),
      putnikId: putnikId,
      datum: datum,
      grad: grad,
      trazeniPolazakAt: novoVreme,
      brojMesta: normalizedBrojMesta,
      status: 'obrada',
      koristiSekundarnu: koristiSekundarnu,
    );
    await createZahtev(zahtev, createdBy: updatedBy);
  }

  static Future<void> otkaziPolazakPutnikaPoKontekstu({
    required String putnikId,
    required DateTime datum,
    required String grad,
    String? otkazaoPutnikId,
  }) async {
    final aktivni = _vidljiviRedoviPoKontekstu(putnikId: putnikId, datum: datum, grad: grad);
    if (aktivni.isNotEmpty) {
      final row = aktivni.first;
      final rowKey = (row['id']?.toString() ?? '').trim();
      if (rowKey.isNotEmpty) {
        final updBy = V3UuidUtils.normalizeUuid(otkazaoPutnikId);
        final updated = await _repository.updateRawMaybeSingle(
          rowKey,
          {
            'status': 'otkazano',
            if (updBy != null) 'updated_by': updBy,
          },
        );
        if (updated != null) {
          V3MasterRealtimeManager.instance.v3UpsertToCache('v3_zahtevi', updated);
        }
      }
    }

    final datumIso = _datumKey(datum);
    final updBy = V3UuidUtils.normalizeUuid(otkazaoPutnikId);
    final updatedOperativni = await _operativnaRepository.updateByPutnikDatumGradAktivniReturningList(
      putnikId: putnikId,
      datumIso: datumIso,
      grad: grad,
      payload: {
        if (otkazaoPutnikId != null) 'otkazano_by': otkazaoPutnikId,
        if (updBy != null) 'updated_by': updBy,
      },
    );

    for (final row in updatedOperativni) {
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_operativna_nedelja', row);
    }
  }

  static Future<void> updateStatus(String id, String newStatus, {String? updatedBy}) async {
    try {
      final updByUuid = V3UuidUtils.normalizeUuid(updatedBy, fallback: V3VozacService.currentVozac?.id);
      final status = V3ZahtevStatus.values.firstWhere(
        (value) => value.name == newStatus,
        orElse: () => V3ZahtevStatus.obrada,
      );
      final row = await _domain.setStatus(id: id, status: status, updatedBy: updByUuid);

      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_zahtevi', row);
    } catch (e) {
      debugPrint('[V3ZahtevService] Status update error: $e');
      rethrow;
    }
  }

  /// Prepisuje trazeni_polazak_at i polazak_at postojećeg zahteva (admin use-case).
  static Future<void> updateVreme(String id, String novoVreme, {String? status}) async {
    try {
      final row = await _domain.assignTime(
        id: id,
        vreme: novoVreme,
        status: status,
        updatedBy: V3UuidUtils.normalizeUuid(V3VozacService.currentVozac?.id),
      );
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_zahtevi', row);
    } catch (e) {
      debugPrint('[V3ZahtevService] updateVreme error: $e');
      rethrow;
    }
  }

  static Future<void> otkaziZahtev(String id,
      {String? otkazaoVozacId, String? otkazaoPutnikId, String? operativnaId}) async {
    try {
      if (otkazaoVozacId != null) {
        // Vozač otkazuje — piše samo u v3_operativna_nedelja (jedini izvor istine za vozača)
        final String? updBy = V3UuidUtils.normalizeUuid(otkazaoVozacId);
        final payload = {
          'otkazano_by': otkazaoVozacId,
          if (updBy != null) 'updated_by': updBy,
        };
        if (operativnaId != null && operativnaId.isNotEmpty) {
          final row = await _operativnaRepository.updateByIdReturningSingle(operativnaId, payload);
          V3MasterRealtimeManager.instance.v3UpsertToCache('v3_operativna_nedelja', row);
        } else {
          throw Exception('operativnaId je obavezan za otkazivanje');
        }
      } else {
        // Putnik otkazuje — piše u v3_zahtevi, operativna se propagira triggerom ili ovdje
        final String? updBy = V3UuidUtils.normalizeUuid(otkazaoPutnikId);
        final row = await _repository.updateRaw(
          id,
          {
            'status': 'otkazano',
            if (updBy != null) 'updated_by': updBy,
          },
        );
        V3MasterRealtimeManager.instance.v3UpsertToCache('v3_zahtevi', row);
        final String? updBy2 = V3UuidUtils.normalizeUuid(otkazaoPutnikId);
        final payload2 = {
          if (otkazaoPutnikId != null) 'otkazano_by': otkazaoPutnikId,
          if (updBy2 != null) 'updated_by': updBy2,
        };
        if (operativnaId != null && operativnaId.isNotEmpty) {
          final row2 = await _operativnaRepository.updateByIdReturningSingle(operativnaId, payload2);
          V3MasterRealtimeManager.instance.v3UpsertToCache('v3_operativna_nedelja', row2);
        } else {
          throw Exception('operativnaId je obavezan za otkazivanje');
        }
      }
    } catch (e) {
      debugPrint('[V3ZahtevService] Otkazi error: $e');
      rethrow;
    }
  }

  static Future<void> oznaciPokupljen({String? pokupljenBy, String? operativnaId}) async {
    try {
      final payload = {
        if (pokupljenBy != null) 'pokupljen_by': pokupljenBy,
      };
      if (operativnaId != null && operativnaId.isNotEmpty) {
        final row = await _operativnaRepository.updateByIdReturningSingle(operativnaId, payload);
        V3MasterRealtimeManager.instance.v3UpsertToCache('v3_operativna_nedelja', row);
      } else {
        throw Exception('operativnaId je obavezan za pokupljanje');
      }
    } catch (e) {
      debugPrint('[V3ZahtevService] Pokupljen error: $e');
      rethrow;
    }
  }

  static Future<void> updateTrazeniPolazakAt(
    String id,
    String novoVreme, {
    bool? koristiSekundarnu,
    String? updatedBy,
  }) async {
    try {
      final nowIso = DateTime.now().toIso8601String();
      await _domain.resetToObrada(
        id: id,
        novoVreme: novoVreme,
        koristiSekundarnu: koristiSekundarnu,
        updatedBy: V3UuidUtils.normalizeUuid(updatedBy),
        createdAtIso: nowIso,
      );
    } catch (e) {
      debugPrint('[V3ZahtevService] TrazeniPolazakAt update error: $e');
      rethrow;
    }
  }
}
