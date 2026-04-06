import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../globals.dart';
import '../../models/v3_zahtev.dart';
import '../../utils/v3_audit_korisnik.dart';
import '../../utils/v3_status_filters.dart';
import '../../utils/v3_time_utils.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_kapacitet_slots_repository.dart';
import 'repositories/v3_operativna_nedelja_repository.dart';
import 'v3_vozac_service.dart';
import 'zahtevi/v3_zahtev_domain_service.dart';
import 'zahtevi/v3_zahtev_repository.dart';
import 'zahtevi/v3_zahtev_types.dart';

/// Service for V3 passenger travel requests (`v3_zahtevi`).
class V3ZahtevService {
  V3ZahtevService._();

  static final V3ZahtevRepository _repository = V3ZahtevRepository();
  static final V3OperativnaNedeljaRepository _operativnaRepository = V3OperativnaNedeljaRepository();
  static final V3KapacitetSlotsRepository _kapacitetRepository = V3KapacitetSlotsRepository();
  static final V3ZahtevDomainService _domain = V3ZahtevDomainService(_repository);

  static String _datumKey(DateTime datum) => V3DanHelper.parseIsoDatePart(datum.toIso8601String());

  static DateTime _parseTs(String? value) {
    if (value == null || value.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  static List<Map<String, dynamic>> _aktivniRedoviPoKontekstu({
    required String putnikId,
    required DateTime datum,
    required String grad,
  }) {
    final datumIso = _datumKey(datum);
    final targetGrad = grad.trim().toUpperCase();
    final rows = V3MasterRealtimeManager.instance.zahteviCache.values.where((row) {
      final rowDatum = V3DanHelper.parseIsoDatePart(row['datum'] as String? ?? '');
      final rowGrad = (row['grad']?.toString() ?? '').trim().toUpperCase();
      return (row['putnik_id']?.toString() ?? '') == putnikId &&
          rowDatum == datumIso &&
          rowGrad == targetGrad &&
          V3StatusFilters.isActiveForDisplay(
            aktivno: row['aktivno'] == true,
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
      throw Exception('Zakazivanje je dozvoljeno samo u aktivnoj sedmici.');
    }
  }

  static List<V3Zahtev> getZahteviByTip(String tip) {
    final cache = V3MasterRealtimeManager.instance.zahteviCache.values;
    // Filtriramo putnike iz cachea da nađemo one koji su traženog tipa
    final putnici = V3MasterRealtimeManager.instance.putniciCache.values
        .where((p) => (p['tip_putnika'] ?? '').toLowerCase() == tip.toLowerCase())
        .map((p) => p['id'] as String)
        .toSet();

    return cache.where((r) => putnici.contains(r['putnik_id'])).map((r) => V3Zahtev.fromJson(r)).toList()
      ..sort((a, b) => b.createdAt?.compareTo(a.createdAt ?? DateTime(2000)) ?? 0);
  }

  static Stream<List<V3Zahtev>> streamZahteviByTip(String tip) =>
      V3MasterRealtimeManager.instance.v3StreamFromRevisions(
        tables: ['v3_zahtevi', 'v3_putnici'],
        build: () => getZahteviByTip(tip),
      );

  static List<V3Zahtev> getPendingZahteviByGrad(String grad) {
    final cache = V3MasterRealtimeManager.instance.zahteviCache.values;
    return cache.where((r) => r['grad'] == grad && r['status'] == 'obrada').map((r) => V3Zahtev.fromJson(r)).toList()
      ..sort((a, b) => a.datum.compareTo(b.datum));
  }

  static Stream<List<V3Zahtev>> streamPendingZahteviByGrad(String grad) => V3MasterRealtimeManager.instance
      .v3StreamFromRevisions(tables: ['v3_zahtevi'], build: () => getPendingZahteviByGrad(grad));

  static Stream<int> streamPendingZahteviCount() => V3MasterRealtimeManager.instance.v3StreamFromRevisions(
        tables: ['v3_zahtevi'],
        build: () {
          final cache = V3MasterRealtimeManager.instance.zahteviCache.values;
          return cache.where((r) => r['status'] == 'obrada').length;
        },
      );

  static V3Zahtev? getZahtevById(String id) {
    final data = V3MasterRealtimeManager.instance.zahteviCache[id];
    return data != null ? V3Zahtev.fromJson(data) : null;
  }

  static Future<V3Zahtev> createZahtev(V3Zahtev zahtev, {String? createdBy}) async {
    try {
      _assertDatumUTekucojNedelji(zahtev.datum);

      final data = zahtev.toJson();
      final createdByUuid = V3AuditKorisnik.normalize(createdBy);
      if (createdByUuid != null) data['created_by'] = createdByUuid;
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
    final aktivni = _aktivniRedoviPoKontekstu(putnikId: putnikId, datum: datum, grad: grad);
    if (aktivni.isNotEmpty) {
      final row = aktivni.first;
      final rowKey = (row['id']?.toString() ?? '').trim();
      if (rowKey.isNotEmpty) {
        final status = (row['status']?.toString() ?? '').trim().toLowerCase();
        if (status == 'alternativa') {
          await updateStatus(rowKey, 'obrada', updatedBy: updatedBy);
        }
        await updateZeljenoVreme(
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
      zeljenoVreme: novoVreme,
      brojMesta: brojMesta,
      status: 'obrada',
      koristiSekundarnu: koristiSekundarnu,
      aktivno: true,
    );
    await createZahtev(zahtev, createdBy: updatedBy);
  }

  static Future<void> otkaziPolazakPutnikaPoKontekstu({
    required String putnikId,
    required DateTime datum,
    required String grad,
    String? otkazaoPutnikId,
  }) async {
    final aktivni = _aktivniRedoviPoKontekstu(putnikId: putnikId, datum: datum, grad: grad);
    if (aktivni.isNotEmpty) {
      final row = aktivni.first;
      final rowKey = (row['id']?.toString() ?? '').trim();
      if (rowKey.isNotEmpty) {
        final updBy = V3AuditKorisnik.normalize(otkazaoPutnikId);
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
    final updatedOperativni = await _operativnaRepository.updateByPutnikDatumGradAktivnoReturningList(
      putnikId: putnikId,
      datumIso: datumIso,
      grad: grad,
      payload: {
        'status_final': 'otkazano',
        if (otkazaoPutnikId != null) 'otkazao_putnik_id': otkazaoPutnikId,
      },
    );

    for (final row in updatedOperativni) {
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_operativna_nedelja', row);
    }
  }

  static Future<void> updateStatus(String id, String newStatus, {String? updatedBy}) async {
    try {
      final updByUuid = V3AuditKorisnik.normalize(updatedBy, fallback: V3VozacService.currentVozac?.id);
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

  /// Prepisuje zeljeno_vreme i dodeljeno_vreme postojećeg zahteva (admin use-case).
  static Future<void> updateVreme(String id, String novoVreme, {String? status}) async {
    try {
      final row = await _domain.assignTime(
        id: id,
        vreme: novoVreme,
        status: status,
        updatedBy: V3AuditKorisnik.normalize(V3VozacService.currentVozac?.id),
      );
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_zahtevi', row);
    } catch (e) {
      debugPrint('[V3ZahtevService] updateVreme error: $e');
      rethrow;
    }
  }

  static List<V3Zahtev> getZahteviByDatumAndGrad(String datumIso, String grad) {
    final cache = V3MasterRealtimeManager.instance.zahteviCache.values;

    return cache
        .where((r) {
          final rDatum = V3DanHelper.parseIsoDatePart(r['datum'] as String? ?? '');
          return rDatum == datumIso && r['grad'] == grad && r['aktivno'] == true;
        })
        .map((r) => V3Zahtev.fromJson(r))
        .toList()
      ..sort((a, b) => (a.zeljenoVreme).compareTo(b.zeljenoVreme));
  }

  /// Dohvata zahteve iz operativnog plana za određeni datum i grad.
  static List<V3Zahtev> getOperativniZahteviByDatumAndGrad(String datum, String grad) {
    // Ovde možemo kombinovati redovne zahteve i operativni plan
    final opCache = V3MasterRealtimeManager.instance.operativnaNedeljaCache.values;
    final zCache = V3MasterRealtimeManager.instance.zahteviCache.values;

    // Prvo nađemo sve u operativnoj nedelji za taj dan
    final opFiltered = opCache.where((r) => r['datum'] == datum && r['grad'] == grad).toList();

    // Mapiramo ih nazad u V3Zahtev objekte
    return opFiltered.map((op) {
      final efektivnoDodeljeno = (op['dodeljeno_vreme'] as String?) ?? (op['zeljeno_vreme'] as String?) ?? '00:00';
      final efektivnoZeljeno = (op['zeljeno_vreme'] as String?) ?? efektivnoDodeljeno;
      final putnikId = op['putnik_id'] as String?;
      if (putnikId != null) {
        final base = zCache.firstWhere(
          (z) =>
              z['putnik_id'] == putnikId &&
              (z['datum'] as String? ?? '').startsWith(datum) &&
              z['grad'] == grad &&
              z['aktivno'] == true,
          orElse: () => <String, dynamic>{},
        );
        if (base.isNotEmpty) {
          final z = V3Zahtev.fromJson(base);
          // Prepisujemo operativnim podacima
          return z.copyWith(
            status: op['status_final'] as String? ?? z.status,
            zeljenoVreme: efektivnoZeljeno,
            dodeljenoVreme: efektivnoDodeljeno,
          );
        }
      }
      // Ako nema zahteva (vozačev direktan unos), kreiramo dummy/osnovni
      return V3Zahtev(
        id: op['id'] as String? ?? 'temp',
        putnikId: op['putnik_id'] as String? ?? '',
        grad: grad,
        datum: DateTime.tryParse(datum) ?? DateTime.now(),
        zeljenoVreme: efektivnoZeljeno,
        dodeljenoVreme: efektivnoDodeljeno,
        status: op['status_final'] as String? ?? 'obrada',
      );
    }).toList()
      ..sort((a, b) => (a.dodeljenoVreme ?? a.zeljenoVreme).compareTo(b.dodeljenoVreme ?? b.zeljenoVreme));
  }

  static Stream<List<V3Zahtev>> streamOperativniZahteviByDatumAndGrad(String datum, String grad) =>
      V3MasterRealtimeManager.instance.v3StreamFromRevisions(
        tables: ['v3_zahtevi', 'v3_operativna_nedelja'],
        build: () => getOperativniZahteviByDatumAndGrad(datum, grad),
      );

  static Stream<List<V3Zahtev>> streamZahteviByDatumAndGrad(String datumIso, String grad) =>
      V3MasterRealtimeManager.instance.v3StreamFromRevisions(
        tables: ['v3_zahtevi'],
        build: () => getZahteviByDatumAndGrad(datumIso, grad),
      );

  static Future<void> deleteZahtev(String id) async {
    try {
      await _repository.deleteById(id);
      V3MasterRealtimeManager.instance.zahteviCache.remove(id);
    } catch (e) {
      debugPrint('[V3ZahtevService] Delete error: $e');
      rethrow;
    }
  }

  static Future<void> otkaziZahtev(String id,
      {String? otkazaoVozacId, String? otkazaoPutnikId, String? operativnaId}) async {
    try {
      if (otkazaoVozacId != null) {
        // Vozač otkazuje — piše samo u v3_operativna_nedelja (jedini izvor istine za vozača)
        final payload = {
          'status_final': 'otkazano',
          'otkazao_vozac_id': otkazaoVozacId,
        };
        if (operativnaId != null && operativnaId.isNotEmpty) {
          final row = await _operativnaRepository.updateByIdReturningSingle(operativnaId, payload);
          V3MasterRealtimeManager.instance.v3UpsertToCache('v3_operativna_nedelja', row);
        } else {
          throw Exception('operativnaId je obavezan za otkazivanje');
        }
      } else {
        // Putnik otkazuje — piše u v3_zahtevi, operativna se propagira triggerom ili ovdje
        final String? updBy = V3AuditKorisnik.normalize(otkazaoPutnikId);
        final row = await _repository.updateRaw(
          id,
          {
            'status': 'otkazano',
            if (updBy != null) 'updated_by': updBy,
          },
        );
        V3MasterRealtimeManager.instance.v3UpsertToCache('v3_zahtevi', row);
        final payload2 = {
          'status_final': 'otkazano',
          if (otkazaoPutnikId != null) 'otkazao_putnik_id': otkazaoPutnikId,
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

  static Future<void> oznaciPokupljen({String? pokupljenVozacId, String? operativnaId}) async {
    try {
      final payload = {
        'vreme_pokupljen': DateTime.now().toIso8601String(),
        'pokupljen': true,
        if (pokupljenVozacId != null) 'pokupljen_vozac_id': pokupljenVozacId,
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

  static Future<void> updateDodeljenoVreme(String id, String? vreme) async {
    try {
      final row = await _repository.updateRaw(
        id,
        {'dodeljeno_vreme': vreme},
      );
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_zahtevi', row);
    } catch (e) {
      debugPrint('[V3ZahtevService] Vreme update error: $e');
      rethrow;
    }
  }

  static Future<void> updateZeljenoVreme(
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
        updatedBy: V3AuditKorisnik.normalize(updatedBy),
        createdAtIso: nowIso,
      );
    } catch (e) {
      debugPrint('[V3ZahtevService] ZeljenoVreme update error: $e');
      rethrow;
    }
  }

  static Future<void> ponudiAlternativu({
    required String id,
    String? vremePre,
    String? vremePosle,
    String? napomena,
  }) async {
    try {
      await _domain.offerAlternative(
        id: id,
        vremePre: vremePre,
        vremePosle: vremePosle,
        napomena: napomena,
      );
    } catch (e) {
      debugPrint('[V3ZahtevService] Alternativa error: $e');
      rethrow;
    }
  }

  static Future<void> prihvatiAlternativu(String id, String izabranoVreme) async {
    String toHHmm(String value) {
      final normalized = V3TimeUtils.normalizeToHHmm(value);
      if (!RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(normalized)) {
        throw Exception('Neispravan format vremena: $value');
      }
      return normalized;
    }

    final izabranoVremeNormalized = izabranoVreme.trim();
    if (izabranoVremeNormalized.isEmpty) {
      throw Exception('Izabrano vreme je prazno.');
    }
    final selectedHHmm = toHHmm(izabranoVremeNormalized);

    final zahtev = await _repository.getById(id);

    if (zahtev == null) {
      throw Exception('Zahtev nije pronađen.');
    }

    final status = (zahtev['status'] as String? ?? '').trim();
    if (status != 'alternativa') {
      throw Exception('Zahtev više nije u statusu alternativa.');
    }

    final altPre = (zahtev['alt_vreme_pre']?.toString() ?? '').trim();
    final altPosle = (zahtev['alt_vreme_posle']?.toString() ?? '').trim();
    final allowedTimes = <String>{
      if (altPre.isNotEmpty) toHHmm(altPre),
      if (altPosle.isNotEmpty) toHHmm(altPosle),
    };

    if (allowedTimes.isNotEmpty && !allowedTimes.contains(selectedHHmm)) {
      throw Exception('Izabrano vreme nije među ponuđenim alternativama.');
    }

    final grad = (zahtev['grad'] as String? ?? '').trim();
    final datum = (zahtev['datum'] as String? ?? '').split('T').first;

    final kapacitetRow = await _kapacitetRepository.getSlotByGradDatumVreme(
      grad: grad,
      datum: datum,
      vreme: izabranoVremeNormalized,
    );

    if (kapacitetRow == null) {
      throw Exception('Slot više ne postoji u kapacitetu.');
    }

    final maxMesta = int.tryParse('${kapacitetRow['max_mesta'] ?? 0}') ?? 0;
    final usedRows = V3MasterRealtimeManager.instance.operativnaNedeljaCache.values.where((row) {
      final rowGrad = (row['grad']?.toString() ?? '').trim();
      final rowDatum = (row['datum']?.toString() ?? '').split('T').first;
      final rowStatus = (row['status_final']?.toString() ?? '').trim();
      return rowGrad == grad && rowDatum == datum && rowStatus == 'odobreno' && row['aktivno'] == true;
    }).toList();

    final usedCount = usedRows.where((row) {
      final assigned = (row['dodeljeno_vreme']?.toString() ?? '').trim();
      final desired = (row['zeljeno_vreme']?.toString() ?? '').trim();
      final effective = assigned.isNotEmpty ? assigned : desired;
      if (effective.isEmpty) return false;
      return toHHmm(effective) == selectedHHmm;
    }).length;
    if (maxMesta > 0 && usedCount >= maxMesta) {
      throw Exception('Termin $izabranoVremeNormalized je trenutno popunjen.');
    }

    final row = await _repository.updateRaw(
      id,
      {
        'status': 'odobreno',
        'zeljeno_vreme': izabranoVremeNormalized,
        'dodeljeno_vreme': izabranoVremeNormalized,
        'alt_vreme_pre': null,
        'alt_vreme_posle': null,
      },
    );
    V3MasterRealtimeManager.instance.v3UpsertToCache('v3_zahtevi', row);
  }

  static Future<void> odbijAlternativu(String id) async {
    final row = await _repository.updateRaw(
      id,
      {
        'status': 'odbijeno',
        'alt_vreme_pre': null,
        'alt_vreme_posle': null,
      },
    );
    V3MasterRealtimeManager.instance.v3UpsertToCache('v3_zahtevi', row);
  }
}
