import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../globals.dart';
import '../../models/v3_zahtev.dart';
import '../../utils/v3_date_utils.dart';
import '../../utils/v3_status_policy.dart';
import '../../utils/v3_string_utils.dart';
import '../../utils/v3_uuid_utils.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_operativna_nedelja_repository.dart';
import 'v3_operativna_nedelja_service.dart';
import 'v3_trenutna_dodela_slot_service.dart';
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

  static Future<void> _syncOperativnaAssignmentsForContext({
    required String putnikId,
    required DateTime datum,
    required String grad,
    String? updatedBy,
  }) async {
    final datumIso = _datumKey(datum);
    final targetGrad = grad.trim().toUpperCase();
    if (putnikId.trim().isEmpty || datumIso.isEmpty || targetGrad.isEmpty) return;

    final rows = await _operativnaRepository.selectByPutnikDatumGradAktivni(
      putnikId: putnikId,
      datumIso: datumIso,
      grad: targetGrad,
    );

    final normalizedActor = V3UuidUtils.normalizeUuid(updatedBy);
    final mappedRows = rows.whereType<Map<String, dynamic>>().toList(growable: false);
    await V3OperativnaNedeljaService.syncTerminDodelaFromSlotForRows(
      operativnaRows: mappedRows,
      updatedBy: normalizedActor,
    );
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
    bool koristiSekundarnu = false,
    String? updatedBy,
  }) async {
    final aktivni = _vidljiviRedoviPoKontekstu(putnikId: putnikId, datum: datum, grad: grad);
    final targetGrad = grad.trim().toUpperCase();
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
        await _syncOperativnaAssignmentsForContext(
          putnikId: putnikId,
          datum: datum,
          grad: targetGrad,
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
      status: 'obrada',
      koristiSekundarnu: koristiSekundarnu,
    );
    await createZahtev(zahtev, createdBy: updatedBy);

    // Proveri da li postoji slot dodela za ovo vreme - ako da, automatski kreiraj operativna red
    final datumIso = _datumKey(datum);
    final slotAssignments = await V3TrenutnaDodelaSlotService.loadActiveVozacBySlotKey(
      datumIso: datumIso,
    );
    final slotKey = V3TrenutnaDodelaSlotService.slotKey(
      datumIso: datumIso,
      grad: targetGrad,
      vreme: novoVreme,
    );
    final assignedVozacId = (slotAssignments[slotKey] ?? '').trim();

    // Učitaj sve slotove za datum (bez status filtera) da pokupimo i neaktivne zauzete termine
    final allSlotsForDatum = await supabase
        .from('v3_trenutna_dodela_slot')
        .select('datum, grad, vreme, vozac_v3_auth_id')
        .eq('datum', datumIso);
    final allSlotAssignments = <String, String>{};
    for (final row in (allSlotsForDatum as List<dynamic>)) {
      final mapped = row as Map<String, dynamic>;
      final slotDatum = V3DateUtils.parseIsoDatePart(mapped['datum']?.toString());
      final slotGrad = (mapped['grad']?.toString() ?? '').trim().toUpperCase();
      final slotVreme = V3StringUtils.trimTimeToHhMm(mapped['vreme']?.toString() ?? '');
      final slotVozacId = (mapped['vozac_v3_auth_id']?.toString() ?? '').trim();
      if (slotDatum.isNotEmpty && slotGrad.isNotEmpty && slotVreme.isNotEmpty && slotVozacId.isNotEmpty) {
        allSlotAssignments['$slotDatum|$slotGrad|$slotVreme'] = slotVozacId;
      }
    }
    final assignedVozacIdFromAll = (allSlotAssignments[slotKey] ?? '').trim();

    if (assignedVozacIdFromAll.isNotEmpty) {
      // Postoji slot dodela - kreiraj operativna red automatski
      await V3OperativnaNedeljaService.createOrUpdateByVozac(
        putnikId: putnikId,
        datum: datumIso,
        grad: targetGrad,
        polazakAt: novoVreme,
        createdBy: updatedBy,
        koristiSekundarnu: koristiSekundarnu,
      );
    } else {
      await _syncOperativnaAssignmentsForContext(
        putnikId: putnikId,
        datum: datum,
        grad: targetGrad,
        updatedBy: updatedBy,
      );
    }
  }

  static Future<void> otkaziPolazakPutnikaPoKontekstu({
    required String putnikId,
    required DateTime datum,
    required String grad,
    String? otkazaoPutnikId,
  }) async {
    final targetGrad = grad.trim().toUpperCase();
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
    final otkazanoAt = DateTime.now().toIso8601String();

    // Pre nego što ažuriramo, proverimo da li uopšte ima aktivnih redova.
    // Ako ih nema, verovatno je već otkazano u međuvremenu — ne radimo ništa.
    final aktivniOperativni = await _operativnaRepository.selectByPutnikDatumGradAktivni(
      putnikId: putnikId,
      datumIso: datumIso,
      grad: targetGrad,
    );
    if (aktivniOperativni.isEmpty) {
      debugPrint('[V3ZahtevService] Preskačem otkazivanje — nema aktivnih operativnih redova za '
          'putnikId=$putnikId, datum=$datumIso, grad=$targetGrad.');
      return;
    }

    final updatedOperativni = await _operativnaRepository.updateByPutnikDatumGradAktivniReturningList(
      putnikId: putnikId,
      datumIso: datumIso,
      grad: targetGrad,
      payload: {
        if (otkazaoPutnikId != null) 'otkazano_by': otkazaoPutnikId,
        'otkazano_at': otkazanoAt,
        if (updBy != null) 'updated_by': updBy,
      },
    );

    for (final row in updatedOperativni) {
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_operativna_nedelja', row);

      await V3OperativnaNedeljaService.syncTerminDodelaFromSlotForRow(
        operativnaRow: row,
        updatedBy: updBy,
      );

      // Trigger v3_sync_otkazane_voznje_to_finansije automatski ažurira arhivu.
    }

    await _syncOperativnaAssignmentsForContext(
      putnikId: putnikId,
      datum: datum,
      grad: targetGrad,
      updatedBy: otkazaoPutnikId,
    );
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

  static Future<void> otkaziZahtev(String id,
      {String? otkazaoVozacId, String? otkazaoPutnikId, String? operativnaId, String? putnikId}) async {
    try {
      final safeVozacId = (otkazaoVozacId ?? '').trim();
      final safePutnikOtkazaoId = (otkazaoPutnikId ?? '').trim();
      final hasVozacActor = safeVozacId.isNotEmpty;
      final hasPutnikActor = safePutnikOtkazaoId.isNotEmpty;

      if (hasVozacActor == hasPutnikActor) {
        throw Exception('Obavezno je navesti tačno jednog aktera otkazivanja');
      }

      final otkazanoAt = DateTime.now().toIso8601String();

      if (hasVozacActor) {
        // Vozač otkazuje — piše samo u v3_operativna_nedelja (jedini izvor istine za vozača)
        final String? updBy = V3UuidUtils.normalizeUuid(safeVozacId);
        final payload = {
          'otkazano_by': safeVozacId,
          'otkazano_at': otkazanoAt,
          if (updBy != null) 'updated_by': updBy,
        };
        if (operativnaId == null || operativnaId.isEmpty) {
          throw Exception('operativnaId je obavezan za otkazivanje');
        }

        // Sigurnosna provera: ne dozvoli duplo otkazivanje istog operativnog reda
        final existingOperativna =
            await supabase.from('v3_operativna_nedelja').select('otkazano_at').eq('id', operativnaId).maybeSingle();
        if (existingOperativna != null && existingOperativna['otkazano_at'] != null) {
          debugPrint('[V3ZahtevService] Preskačem otkazivanje — operativnaId=$operativnaId je već otkazana.');
          return;
        }

        final row = await _operativnaRepository.updateByIdReturningSingle(operativnaId, payload);
        V3MasterRealtimeManager.instance.v3UpsertToCache('v3_operativna_nedelja', row);
        await V3OperativnaNedeljaService.syncTerminDodelaFromSlotForRow(
          operativnaRow: row,
          updatedBy: updBy,
        );
      } else {
        // Putnik otkazuje — piše u v3_zahtevi, operativna se propagira triggerom ili ovde
        final safeZahtevId = id.trim();
        if (safeZahtevId.isEmpty) {
          throw Exception('id zahteva je obavezan kada putnik otkazuje');
        }

        final String? updBy = V3UuidUtils.normalizeUuid(safePutnikOtkazaoId);
        final row = await _repository.updateRaw(
          safeZahtevId,
          {
            'status': 'otkazano',
            if (updBy != null) 'updated_by': updBy,
          },
        );
        V3MasterRealtimeManager.instance.v3UpsertToCache('v3_zahtevi', row);
        final payload2 = {
          'otkazano_by': safePutnikOtkazaoId,
          'otkazano_at': otkazanoAt,
          if (updBy != null) 'updated_by': updBy,
        };
        if (operativnaId != null && operativnaId.isNotEmpty) {
          // Sigurnosna provera: ne dozvoli duplo otkazivanje istog operativnog reda
          final existingOperativna =
              await supabase.from('v3_operativna_nedelja').select('otkazano_at').eq('id', operativnaId).maybeSingle();
          if (existingOperativna != null && existingOperativna['otkazano_at'] != null) {
            debugPrint('[V3ZahtevService] Preskačem otkazivanje — operativnaId=$operativnaId je već otkazana.');
            return;
          }

          final row2 = await _operativnaRepository.updateByIdReturningSingle(operativnaId, payload2);
          V3MasterRealtimeManager.instance.v3UpsertToCache('v3_operativna_nedelja', row2);
          await V3OperativnaNedeljaService.syncTerminDodelaFromSlotForRow(
            operativnaRow: row2,
            updatedBy: updBy,
          );
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
        'pokupljen_at': DateTime.now().toIso8601String(),
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
