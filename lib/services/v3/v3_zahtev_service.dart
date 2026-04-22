import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../globals.dart';
import '../../models/v3_zahtev.dart';
import '../../utils/v3_status_policy.dart';
import '../../utils/v3_uuid_utils.dart';
import '../realtime/v3_master_realtime_manager.dart';
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
  static final V3ZahtevDomainService _domain = V3ZahtevDomainService(_repository);

  static String _datumKey(DateTime datum) => V3DanHelper.parseIsoDatePart(datum.toIso8601String());

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
      final rowDatum = V3DanHelper.parseIsoDatePart(row['datum'] as String? ?? '');
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

  static List<V3Zahtev> getZahteviByTip(String tip) {
    final cache = V3MasterRealtimeManager.instance.zahteviCache.values;
    // Filtriramo putnike iz cachea da nađemo one koji su traženog tipa
    final putnici = V3MasterRealtimeManager.instance.putniciCache.values
        .where((p) => (p['tip_putnika'] ?? '').toLowerCase() == tip.toLowerCase())
        .map((p) => p['id'] as String)
        .toSet();

    return cache.where((r) => putnici.contains(r['created_by'])).map((r) => V3Zahtev.fromJson(r)).toList()
      ..sort((a, b) => b.createdAt?.compareTo(a.createdAt ?? DateTime(2000)) ?? 0);
  }

  static Stream<List<V3Zahtev>> streamZahteviByTip(String tip) =>
      V3MasterRealtimeManager.instance.v3StreamFromRevisions(
        tables: ['v3_zahtevi', 'v3_auth'],
        build: () => getZahteviByTip(tip),
      );

  static List<V3Zahtev> getPendingZahteviByGrad(String grad) {
    final cache = V3MasterRealtimeManager.instance.zahteviCache.values;
    return cache
        .where((r) => r['grad'] == grad && V3StatusPolicy.isPending(r['status']?.toString()))
        .map((r) => V3Zahtev.fromJson(r))
        .toList()
      ..sort((a, b) => a.datum.compareTo(b.datum));
  }

  static Stream<List<V3Zahtev>> streamPendingZahteviByGrad(String grad) => V3MasterRealtimeManager.instance
      .v3StreamFromRevisions(tables: ['v3_zahtevi'], build: () => getPendingZahteviByGrad(grad));

  static Stream<int> streamPendingZahteviCount() => V3MasterRealtimeManager.instance.v3StreamFromRevisions(
        tables: ['v3_zahtevi'],
        build: () {
          final cache = V3MasterRealtimeManager.instance.zahteviCache.values;
          return cache.where((r) => V3StatusPolicy.isPending(r['status']?.toString())).length;
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
      brojMesta: brojMesta,
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
    final updatedOperativni = await _operativnaRepository.updateByPutnikDatumGradAktivniReturningList(
      putnikId: putnikId,
      datumIso: datumIso,
      grad: grad,
      payload: {
        if (otkazaoPutnikId != null) 'otkazano_by': otkazaoPutnikId,
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

  static List<V3Zahtev> getZahteviByDatumAndGrad(String datumIso, String grad) {
    final cache = V3MasterRealtimeManager.instance.zahteviCache.values;

    return cache
        .where((r) {
          final rDatum = V3DanHelper.parseIsoDatePart(r['datum'] as String? ?? '');
          return rDatum == datumIso &&
              r['grad'] == grad &&
              !V3StatusPolicy.isCanceledOrRejected(r['status']?.toString());
        })
        .map((r) => V3Zahtev.fromJson(r))
        .toList()
      ..sort((a, b) => (a.trazeniPolazakAt).compareTo(b.trazeniPolazakAt));
  }

  /// Dohvata operativne zapise za određeni datum i grad.
  static List<V3Zahtev> getOperativniZahteviByDatumAndGrad(String datum, String grad) {
    final opCache = V3MasterRealtimeManager.instance.operativnaNedeljaCache.values;

    // Prvo nađemo sve operativne redove za taj dan i grad.
    final opFiltered = opCache.where((r) => r['datum'] == datum && r['grad'] == grad).toList();

    // Mapiramo operativne zapise direktno u V3Zahtev objekte.
    // v3_zahtevi služi samo za obradu zahteva, ne za prikaz operativne liste.
    return opFiltered.map((op) {
      final efektivniPolazakAt = (op['polazak_at'] as String?) ?? '00:00';
      return V3Zahtev(
        id: op['id'] as String? ?? 'temp',
        putnikId: op['created_by'] as String? ?? '',
        grad: grad,
        datum: DateTime.tryParse(datum) ?? DateTime.now(),
        trazeniPolazakAt: efektivniPolazakAt,
        polazakAt: efektivniPolazakAt,
        status: V3StatusPolicy.deriveOperativnaStatus(
          otkazanoAt: op['otkazano_at'],
          polazakAt: op['polazak_at'],
        ),
      );
    }).toList()
      ..sort((a, b) => (a.polazakAt ?? '').compareTo(b.polazakAt ?? ''));
  }

  static Stream<List<V3Zahtev>> streamOperativniZahteviByDatumAndGrad(String datum, String grad) =>
      V3MasterRealtimeManager.instance.v3StreamFromRevisions(
        tables: ['v3_operativna_nedelja'],
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
          'otkazano_by': otkazaoVozacId,
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
        final payload2 = {
          if (otkazaoPutnikId != null) 'otkazano_by': otkazaoPutnikId,
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

  static Future<void> updatePolazakAt(String id, String? vreme) async {
    try {
      final row = await _repository.updateRaw(
        id,
        {
          'polazak_at': vreme,
        },
      );
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_zahtevi', row);
    } catch (e) {
      debugPrint('[V3ZahtevService] Vreme update error: $e');
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
