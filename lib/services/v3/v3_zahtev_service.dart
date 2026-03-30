import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../globals.dart';
import '../../models/v3_zahtev.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'v3_vozac_service.dart';

/// Service for V3 passenger travel requests (`v3_zahtevi`).
class V3ZahtevService {
  V3ZahtevService._();

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
      final rowStatus = (row['status']?.toString() ?? '').trim().toLowerCase();
      return (row['putnik_id']?.toString() ?? '') == putnikId &&
          rowDatum == datumIso &&
          rowGrad == targetGrad &&
          row['aktivno'] == true &&
          rowStatus != 'otkazano' &&
          rowStatus != 'odbijeno';
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

  static Stream<List<V3Zahtev>> streamZahteviByTip(String tip) => V3MasterRealtimeManager.instance.v3StreamFromCache(
        tables: ['v3_zahtevi', 'v3_putnici'],
        build: () => getZahteviByTip(tip),
      );

  static List<V3Zahtev> getPendingZahteviByGrad(String grad) {
    final cache = V3MasterRealtimeManager.instance.zahteviCache.values;
    return cache.where((r) => r['grad'] == grad && r['status'] == 'obrada').map((r) => V3Zahtev.fromJson(r)).toList()
      ..sort((a, b) => a.datum.compareTo(b.datum));
  }

  static Stream<List<V3Zahtev>> streamPendingZahteviByGrad(String grad) => V3MasterRealtimeManager.instance
      .v3StreamFromCache(tables: ['v3_zahtevi'], build: () => getPendingZahteviByGrad(grad));

  static Stream<int> streamPendingZahteviCount() => V3MasterRealtimeManager.instance.v3StreamFromCache(
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
      if (createdBy != null) data['created_by'] = createdBy;
      final row = await supabase.from('v3_zahtevi').insert(data).select().single();

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
        if (status == 'alternativa' || status == 'ponuda') {
          await updateStatus(rowKey, 'obrada', updatedBy: updatedBy ?? 'putnik:reset_alternative');
        }
        await updateZeljenoVreme(
          rowKey,
          novoVreme,
          koristiSekundarnu: koristiSekundarnu,
          updatedBy: updatedBy ?? 'putnik:sistem',
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
    await createZahtev(zahtev, createdBy: updatedBy ?? 'putnik:sistem');
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
        final updBy = otkazaoPutnikId != null ? 'putnik:$otkazaoPutnikId' : 'putnik:sistem';
        final updated = await supabase
            .from('v3_zahtevi')
            .update({'status': 'otkazano', 'updated_by': updBy})
            .eq('id', rowKey)
            .select()
            .maybeSingle();
        if (updated != null) {
          V3MasterRealtimeManager.instance.v3UpsertToCache('v3_zahtevi', updated);
        }
      }
    }

    final datumIso = _datumKey(datum);
    final updatedOperativni = await supabase
        .from('v3_operativna_nedelja')
        .update({
          'status_final': 'otkazano',
          if (otkazaoPutnikId != null) 'otkazao_putnik_id': otkazaoPutnikId,
        })
        .eq('putnik_id', putnikId)
        .eq('datum', datumIso)
        .eq('grad', grad)
        .eq('aktivno', true)
        .select();

    for (final row in updatedOperativni) {
      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_operativna_nedelja', row);
    }
  }

  static Future<void> updateStatus(String id, String newStatus, {String? updatedBy}) async {
    try {
      final row = await supabase
          .from('v3_zahtevi')
          .update({
            'status': newStatus,
            'updated_by': updatedBy ?? 'vozac:${V3VozacService.currentVozac?.id ?? "sistem"}',
          })
          .eq('id', id)
          .select()
          .single();

      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_zahtevi', row);
    } catch (e) {
      debugPrint('[V3ZahtevService] Status update error: $e');
      rethrow;
    }
  }

  /// Prepisuje zeljeno_vreme i dodeljeno_vreme postojećeg zahteva (admin use-case).
  static Future<void> updateVreme(String id, String novoVreme, {String? status}) async {
    try {
      final payload = <String, dynamic>{
        'zeljeno_vreme': novoVreme,
        'dodeljeno_vreme': novoVreme,
        if (status != null) 'status': status,
        'updated_by': 'vozac:${V3VozacService.currentVozac?.id ?? "sistem"}',
      };
      final row = await supabase.from('v3_zahtevi').update(payload).eq('id', id).select().single();
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
      V3MasterRealtimeManager.instance.v3StreamFromCache(
        tables: ['v3_zahtevi', 'v3_operativna_nedelja'],
        build: () => getOperativniZahteviByDatumAndGrad(datum, grad),
      );

  static Stream<List<V3Zahtev>> streamZahteviByDatumAndGrad(String datumIso, String grad) =>
      V3MasterRealtimeManager.instance.v3StreamFromCache(
        tables: ['v3_zahtevi'],
        build: () => getZahteviByDatumAndGrad(datumIso, grad),
      );

  static Future<void> deleteZahtev(String id) async {
    try {
      await supabase.from('v3_zahtevi').delete().eq('id', id);
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
        final query = supabase.from('v3_operativna_nedelja').update({
          'status_final': 'otkazano',
          'otkazao_vozac_id': otkazaoVozacId,
        });
        if (operativnaId != null && operativnaId.isNotEmpty) {
          final row = await query.eq('id', operativnaId).select().single();
          V3MasterRealtimeManager.instance.v3UpsertToCache('v3_operativna_nedelja', row);
        } else {
          throw Exception('operativnaId je obavezan za otkazivanje');
        }
      } else {
        // Putnik otkazuje — piše u v3_zahtevi, operativna se propagira triggerom ili ovdje
        final String updBy = otkazaoPutnikId != null ? 'putnik:$otkazaoPutnikId' : 'sistem';
        final row = await supabase
            .from('v3_zahtevi')
            .update({'status': 'otkazano', 'updated_by': updBy})
            .eq('id', id)
            .select()
            .single();
        V3MasterRealtimeManager.instance.v3UpsertToCache('v3_zahtevi', row);
        final query2 = supabase.from('v3_operativna_nedelja').update({
          'status_final': 'otkazano',
          if (otkazaoPutnikId != null) 'otkazao_putnik_id': otkazaoPutnikId,
        });
        if (operativnaId != null && operativnaId.isNotEmpty) {
          final row2 = await query2.eq('id', operativnaId).select().single();
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
      final query = supabase.from('v3_operativna_nedelja').update({
        'vreme_pokupljen': DateTime.now().toIso8601String(),
        'pokupljen': true,
        if (pokupljenVozacId != null) 'pokupljen_vozac_id': pokupljenVozacId,
      });
      if (operativnaId != null && operativnaId.isNotEmpty) {
        final row = await query.eq('id', operativnaId).select().single();
        V3MasterRealtimeManager.instance.v3UpsertToCache('v3_operativna_nedelja', row);
      } else {
        throw Exception('operativnaId je obavezan za pokupljanje');
      }
    } catch (e) {
      debugPrint('[V3ZahtevService] Pokupljen error: $e');
      rethrow;
    }
  }

  static Future<void> updatedodeljenoVreme(String id, String? vreme) async {
    try {
      await supabase
          .from('v3_zahtevi')
          .update({'dodeljeno_vreme': vreme, 'updated_by': 'dispecer:sistem'}).eq('id', id);
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

      // Reset na isto stanje kao novi zahtev:
      // - ide nazad u `obrada`
      // - resetuje dodeljeno vreme i alternative
      // - resetuje scheduling metapodatke da dispecer ide od nule
      final updateData = <String, dynamic>{
        'zeljeno_vreme': novoVreme,
        'dodeljeno_vreme': null,
        'scheduled_at': null,
        'created_at': nowIso,
        'status': 'obrada',
        'alt_vreme_pre': null,
        'alt_vreme_posle': null,
        'alt_napomena': null,
        'aktivno': true,
        'updated_by': updatedBy ?? 'putnik:sistem',
      };
      if (koristiSekundarnu != null) {
        updateData['koristi_sekundarnu'] = koristiSekundarnu;
      }
      await supabase.from('v3_zahtevi').update(updateData).eq('id', id);
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
      await supabase.from('v3_zahtevi').update({
        'status': 'alternativa',
        'alt_vreme_pre': vremePre,
        'alt_vreme_posle': vremePosle,
        'alt_napomena': napomena,
        'updated_by': 'dispecer:sistem',
      }).eq('id', id);
    } catch (e) {
      debugPrint('[V3ZahtevService] Ponuda error: $e');
      rethrow;
    }
  }

  static Future<void> prihvatiPonudu(String id, String izabranoVreme) async {
    String toHHmm(String value) {
      final normalized = value.trim();
      final parts = normalized.split(':');
      if (parts.length < 2) {
        throw Exception('Neispravan format vremena: $value');
      }
      final h = parts[0].padLeft(2, '0');
      final m = parts[1].padLeft(2, '0');
      return '$h:$m';
    }

    final izabranoVremeNormalized = izabranoVreme.trim();
    if (izabranoVremeNormalized.isEmpty) {
      throw Exception('Izabrano vreme je prazno.');
    }
    final selectedHHmm = toHHmm(izabranoVremeNormalized);

    final zahtev = await supabase
        .from('v3_zahtevi')
        .select('id, status, grad, datum, putnik_id, alt_vreme_pre, alt_vreme_posle')
        .eq('id', id)
        .maybeSingle();

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

    final kapacitetRow = await supabase
        .from('v3_kapacitet_slots')
        .select('max_mesta')
        .eq('grad', grad)
        .eq('datum', datum)
        .eq('vreme', izabranoVremeNormalized)
        .eq('aktivno', true)
        .maybeSingle();

    if (kapacitetRow == null) {
      throw Exception('Slot više ne postoji u kapacitetu.');
    }

    final maxMesta = int.tryParse('${kapacitetRow['max_mesta'] ?? 0}') ?? 0;
    final usedRows = await supabase
        .from('v3_operativna_nedelja')
        .select('dodeljeno_vreme, zeljeno_vreme')
        .eq('grad', grad)
        .eq('datum', datum)
        .eq('status_final', 'odobreno')
        .eq('aktivno', true);

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

    await supabase.from('v3_zahtevi').update({
      'status': 'odobreno',
      'zeljeno_vreme': izabranoVremeNormalized,
      'dodeljeno_vreme': izabranoVremeNormalized,
      'alt_vreme_pre': null,
      'alt_vreme_posle': null,
      'updated_by': 'putnik:sistem',
    }).eq('id', id);
  }

  static Future<void> odbijPonudu(String id) async {
    await supabase.from('v3_zahtevi').update({
      'status': 'odbijeno',
      'alt_vreme_pre': null,
      'alt_vreme_posle': null,
      'updated_by': 'putnik:sistem',
    }).eq('id', id);
  }
}
