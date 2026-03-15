import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../../models/v3_zahtev.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'v3_audit_log_service.dart';

/// Service for V3 passenger travel requests (`v3_zahtevi`).
class V3ZahtevService {
  V3ZahtevService._();

  static List<V3Zahtev> getZahteviByTip(String tip) {
    final cache = V3MasterRealtimeManager.instance.zahteviCache.values;
    // Filtriramo putnike iz cachea da nađemo one koji su traženog tipa
    final putnici = V3MasterRealtimeManager.instance.putniciCache.values
        .where((p) => (p['tip'] ?? '').toLowerCase() == tip.toLowerCase())
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

  static Future<V3Zahtev> createZahtev(V3Zahtev zahtev) async {
    try {
      final data = zahtev.toJson();
      final row = await supabase.from('v3_zahtevi').insert(data).select().single();

      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_zahtevi', row);
      V3AuditLogService.log(
        tip: 'zahtev_kreiran',
        putnikId: zahtev.putnikId,
        putnikIme: zahtev.imePrezime,
        datumIso: zahtev.datum.toIso8601String().split('T')[0],
        grad: zahtev.grad,
        vreme: zahtev.zeljenoVreme,
      );
      return V3Zahtev.fromJson(row);
    } catch (e) {
      debugPrint('[V3ZahtevService] Error: $e');
      rethrow;
    }
  }

  static Future<void> updateStatus(String id, String newStatus) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final row = await supabase
          .from('v3_zahtevi')
          .update({'status': newStatus, 'updated_at': now})
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
  static Future<void> updateVreme(String id, String novoVreme) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final row = await supabase
          .from('v3_zahtevi')
          .update({'zeljeno_vreme': novoVreme, 'dodeljeno_vreme': novoVreme, 'updated_at': now})
          .eq('id', id)
          .select()
          .single();
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
          final rDatum = (r['datum'] as String? ?? '').split('T')[0];
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
      final zahtevId = op['izvor_id'] as String?;
      if (zahtevId != null && op['izvor_tip'] == 'zahtev') {
        final base = zCache.firstWhere((z) => z['id'] == zahtevId, orElse: () => <String, dynamic>{});
        if (base.isNotEmpty) {
          final z = V3Zahtev.fromJson(base);
          // Prepisujemo operativnim podacima
          return z.copyWith(
            status: op['status_final'] as String? ?? z.status,
            dodeljenoVreme: op['vreme'] as String?,
          );
        }
      }
      // Ako nema baze (ili je izvor tipa 'putnik' ili dr.), kreiramo dummy/osnovni
      return V3Zahtev(
        id: op['id'] as String? ?? 'temp',
        putnikId: op['putnik_id'] as String? ?? '',
        grad: grad,
        datum: DateTime.tryParse(datum) ?? DateTime.now(),
        zeljenoVreme: op['vreme'] as String? ?? '00:00',
        dodeljenoVreme: op['vreme'] as String?,
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

  static Future<void> otkaziZahtev(String id, {String? otkazaoVozacId, String? otkazaoPutnikId}) async {
    try {
      await supabase.from('v3_zahtevi').update({'status': 'otkazano'}).eq('id', id);
      await supabase.from('v3_operativna_nedelja').update({
        if (otkazaoVozacId != null) 'otkazao_vozac_id': otkazaoVozacId,
        if (otkazaoPutnikId != null) 'otkazao_putnik_id': otkazaoPutnikId,
      }).eq('izvor_id', id);
      V3AuditLogService.log(
        tip: 'zahtev_otkazan',
        aktorId: otkazaoVozacId,
        aktorTip: otkazaoVozacId != null ? 'vozac' : null,
        detalji: 'zahtev_id: $id',
      );
    } catch (e) {
      debugPrint('[V3ZahtevService] Otkazi error: $e');
      rethrow;
    }
  }

  static Future<void> oznaciPokupljen(String id, {String? pokupljenVozacId}) async {
    try {
      await supabase.from('v3_operativna_nedelja').update({
        'vreme_pokupljen': DateTime.now().toIso8601String(),
        'status_final': 'pokupljen',
        if (pokupljenVozacId != null) 'pokupljen_vozac_id': pokupljenVozacId,
      }).eq('izvor_id', id);
      V3AuditLogService.log(
        tip: 'pokupljen',
        aktorId: pokupljenVozacId,
        aktorTip: pokupljenVozacId != null ? 'vozac' : null,
        detalji: 'zahtev_id: $id',
      );
    } catch (e) {
      debugPrint('[V3ZahtevService] Pokupljen error: $e');
      rethrow;
    }
  }

  static Future<void> updatedodeljenoVreme(String id, String? vreme) async {
    try {
      await supabase.from('v3_zahtevi').update({'dodeljeno_vreme': vreme}).eq('id', id);
    } catch (e) {
      debugPrint('[V3ZahtevService] Vreme update error: $e');
      rethrow;
    }
  }

  static Future<void> updateZeljenoVreme(String id, String novoVreme) async {
    try {
      // Scenario 3: reset na isto stanje kao novi zahtev
      // dodeljeno_vreme = NULL jer kron mora ponovo da odluci
      await supabase.from('v3_zahtevi').update({
        'zeljeno_vreme': novoVreme,
        'dodeljeno_vreme': null,
        'status': 'obrada',
      }).eq('id', id);
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
        'status': 'ponuda',
        'alt_vreme_pre': vremePre,
        'alt_vreme_posle': vremePosle,
        'alt_napomena': napomena,
      }).eq('id', id);
    } catch (e) {
      debugPrint('[V3ZahtevService] Ponuda error: $e');
      rethrow;
    }
  }

  static Future<void> prihvatiPonudu(String id, String izabranoVreme) async {
    await supabase.from('v3_zahtevi').update({
      'status': 'odobreno',
      'zeljeno_vreme': izabranoVreme,
      'dodeljeno_vreme': izabranoVreme,
      'alt_vreme_pre': null,
      'alt_vreme_posle': null,
    }).eq('id', id);
  }

  static Future<void> odbijPonudu(String id) async {
    await supabase.from('v3_zahtevi').update({
      'status': 'odbijeno',
      'alt_vreme_pre': null,
      'alt_vreme_posle': null,
    }).eq('id', id);
  }
}
