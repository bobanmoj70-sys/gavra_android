import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../globals.dart';
import '../models/v2_pin_zahtev.dart';
import '../models/v2_putnik.dart';
import 'realtime/v2_master_realtime_manager.dart';
import 'v2_realtime_notification_service.dart';

/// Servis za upravljanje PIN zahtevima putnika
class V2PinZahtevService {
  V2PinZahtevService._();

  static Future<bool> posaljiZahtev({
    required String putnikId,
    required String email,
    required String telefon,
    String? putnikTabela,
  }) async {
    try {
      // Provjeri cache PRVO — izbjegava DB round-trip ako zahtev već postoji
      if (_imaZahtevUCacheu(putnikId)) return true;

      if (putnikTabela == null || putnikTabela.isEmpty) {
        debugPrint(
            '[V2PinZahtevService] posaljiZahtev: putnikTabela nije proslijeđena za putnikId=$putnikId — PIN odobrenje neće moći upisati tabelu!');
      }

      // Cache mogao biti prazan (tek inicijalizovan) — padamo na DB provjeru
      final existing = await supabase
          .from('v2_pin_zahtevi')
          .select('id')
          .eq('putnik_id', putnikId)
          .eq('status', V2PinZahtev.statusCeka)
          .maybeSingle();

      if (existing != null) {
        return true;
      }

      await supabase.from('v2_pin_zahtevi').insert({
        'putnik_id': putnikId,
        'email': email,
        'telefon': telefon,
        'status': V2PinZahtev.statusCeka,
        if (putnikTabela != null && putnikTabela.isNotEmpty) 'putnik_tabela': putnikTabela,
      });

      // Pošalji notifikaciju adminima (fire-and-forget — ne blokira zahtev)
      unawaited(V2RealtimeNotificationService.sendNotificationToAdmins(
        title: '🔔 Novi zahtev za PIN',
        body: 'V2Putnik traži PIN za pristup aplikaciji',
        data: {'type': 'pin_zahtev', 'putnik_id': putnikId},
      ));

      return true;
    } catch (e) {
      debugPrint('[V2PinZahtevService] posaljiZahtev greška: $e');
      return false;
    }
  }

  /// Realtime stream: Prati nove zahteve za PIN — direktno iz pinCache, 0 DB upita
  static Stream<List<Map<String, dynamic>>> streamZahteviKojiCekaju() =>
      V2MasterRealtimeManager.instance.v2StreamFromCache(
        tables: ['v2_pin_zahtevi'],
        build: _buildEnrichedList,
      );

  /// Izgradi enriched listu iz pinCache
  static List<Map<String, dynamic>> _buildEnrichedList() {
    final rm = V2MasterRealtimeManager.instance;
    final zahtevi = rm.pinCache.values.where((z) => z['status'] == V2PinZahtev.statusCeka).toList()
      ..sort((a, b) {
        final ca = a['created_at'] as String? ?? '';
        final cb = b['created_at'] as String? ?? '';
        return ca.compareTo(cb);
      });

    return zahtevi.map((z) {
      final putnikId = z['putnik_id'] as String?;
      final putnikData = putnikId != null ? rm.v2GetPutnikById(putnikId) : null;
      return <String, dynamic>{
        ...z,
        'putnik_ime': putnikData?['ime'],
        'broj_telefona': putnikData?['telefon'],
        'tip': V2Putnik.tipIzTabele(z['putnik_tabela'] as String?),
      };
    }).toList();
  }

  static int brojZahtevaKojiCekaju() {
    return V2MasterRealtimeManager.instance.pinCache.values.where((z) => z['status'] == V2PinZahtev.statusCeka).length;
  }

  static Future<bool> odobriZahtev({
    required String zahtevId,
    required String pin,
  }) async {
    try {
      final zahtev = V2MasterRealtimeManager.instance.pinCache[zahtevId];
      if (zahtev == null) return false;

      final putnikId = zahtev['putnik_id'] as String?;
      if (putnikId == null) return false;
      final putnikTabela = zahtev['putnik_tabela'] as String? ?? '';

      if (putnikTabela.isNotEmpty) {
        await supabase.from(putnikTabela).update({'pin': pin}).eq('id', putnikId);
        // Ažuriraj putnik cache odmah — Realtime event može kasniti
        V2MasterRealtimeManager.instance.v2PatchCache(putnikTabela, putnikId, {'pin': pin});
      } else {
        debugPrint('[V2PinZahtevService] odobriZahtev: putnikTabela je prazan — PIN nije upisan u bazu!');
        return false;
      }

      final now = DateTime.now().toUtc().toIso8601String();
      await supabase.from('v2_pin_zahtevi').update({
        'status': V2PinZahtev.statusOdobren,
        'updated_at': now,
      }).eq('id', zahtevId);
      // patchCache → upsertToCache logika uklanja red jer status != 'ceka'
      V2MasterRealtimeManager.instance
          .v2PatchCache('v2_pin_zahtevi', zahtevId, {'status': V2PinZahtev.statusOdobren, 'updated_at': now});

      // Pošalji push notifikaciju putniku da je PIN odobren
      unawaited(V2RealtimeNotificationService.sendNotificationToPutnik(
        putnikId: putnikId,
        title: '🔑 PIN je dodeljen!',
        body: 'Vaš PIN je spreman. Otvorite aplikaciju i prijavite se.',
        data: {'type': 'pin_odobren', 'putnik_id': putnikId},
      ));

      return true;
    } catch (e) {
      debugPrint('[V2PinZahtevService] odobriZahtev greška: $e');
      return false;
    }
  }

  static Future<bool> odbijZahtev(String zahtevId) async {
    try {
      final zahtev = V2MasterRealtimeManager.instance.pinCache[zahtevId];
      if (zahtev == null) {
        debugPrint('[V2PinZahtevService] odbijZahtev: zahtevId=$zahtevId nije u cache-u');
        return false;
      }

      final now = DateTime.now().toUtc().toIso8601String();
      await supabase.from('v2_pin_zahtevi').update({
        'status': V2PinZahtev.statusOdbijen,
        'updated_at': now,
      }).eq('id', zahtevId);
      // patchCache → upsertToCache logika uklanja red jer status != 'ceka'
      V2MasterRealtimeManager.instance
          .v2PatchCache('v2_pin_zahtevi', zahtevId, {'status': V2PinZahtev.statusOdbijen, 'updated_at': now});

      return true;
    } catch (e) {
      debugPrint('[V2PinZahtevService] odbijZahtev greška: $e');
      return false;
    }
  }

  /// Generisi nasumičan 4-cifreni PIN
  static String generatePin() {
    return (1000 + Random.secure().nextInt(9000)).toString();
  }

  /// Brza sync provjera u pinCache-u — koristi se interno i iz imaZahtevKojiCeka
  static bool _imaZahtevUCacheu(String putnikId) {
    return V2MasterRealtimeManager.instance.pinCache.values
        .any((z) => z['putnik_id'] == putnikId && z['status'] == V2PinZahtev.statusCeka);
  }

  static bool imaZahtevKojiCeka(String putnikId) => _imaZahtevUCacheu(putnikId);

  /// Async verzija — provjerava cache, a ako je prazan pada na DB.
  /// Koristi se pri loginovanju da ne prikaže dialog ako je zahtev već poslat.
  static Future<bool> imaZahtevKojiCekaAsync(String putnikId) async {
    if (_imaZahtevUCacheu(putnikId)) return true;

    try {
      final row = await supabase
          .from('v2_pin_zahtevi')
          .select('id')
          .eq('putnik_id', putnikId)
          .eq('status', V2PinZahtev.statusCeka)
          .maybeSingle();
      return row != null;
    } catch (e) {
      debugPrint('[V2PinZahtevService] imaZahtevKojiCekaAsync greška: $e');
      return false;
    }
  }

  /// Upiši audit zapis u v2_pin_zahtevi kada admin direktno menja PIN
  /// (bez zahteva od putnika — npr. iz V2PinDialog)
  static Future<void> logujDirektnaIzmena({
    required String putnikId,
    required String putnikTabela,
  }) async {
    try {
      await supabase.from('v2_pin_zahtevi').insert({
        'putnik_id': putnikId,
        'putnik_tabela': putnikTabela,
        'status': V2PinZahtev.statusDirektnaIzmena,
        'email': null,
        'telefon': null,
      });
    } catch (e) {
      // audit log greška ne blokira glavnu operaciju
      debugPrint('[V2PinZahtevService] logujDirektnaIzmena greška: $e');
    }
  }

  static Future<bool> azurirajEmail({
    required String putnikId,
    required String putnikTabela,
    required String email,
  }) async {
    try {
      if (putnikTabela.isNotEmpty) {
        await supabase.from(putnikTabela).update({'email': email}).eq('id', putnikId);
        // Ažuriraj putnik cache odmah — Realtime event može kasniti
        V2MasterRealtimeManager.instance.v2PatchCache(putnikTabela, putnikId, {'email': email});
      }
      return true;
    } catch (e) {
      debugPrint('[V2PinZahtevService] azurirajEmail greška: $e');
      return false;
    }
  }
}
