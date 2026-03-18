import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../realtime/v3_master_realtime_manager.dart';

class V3PinZahtevService {
  V3PinZahtevService._();

  static String generatePin() {
    final random = Random();
    return (random.nextInt(9000) + 1000).toString();
  }

  static Stream<List<Map<String, dynamic>>> streamZahteviKojiCekaju() {
    return V3MasterRealtimeManager.instance.v3StreamFromCache(
      tables: ['v3_pin_zahtevi'],
      build: _buildEnrichedList,
    );
  }

  static List<Map<String, dynamic>> buildEnrichedListSync() {
    return _buildEnrichedList();
  }

  static Future<bool> imaZahtevKojiCekaAsync(String putnikId) async {
    try {
      final rm = V3MasterRealtimeManager.instance;
      // Proveri prvo cache
      final uCacheu =
          rm.pinZahteviCache.values.any((z) => z['putnik_id']?.toString() == putnikId && z['status'] == 'ceka');
      if (uCacheu) return true;

      // Za svaki slucaj proveri DB (ako RM još nije dovukao sve)
      final res = await supabase
          .from('v3_pin_zahtevi')
          .select('id')
          .eq('putnik_id', putnikId)
          .eq('status', 'ceka')
          .limit(1)
          .maybeSingle();

      return res != null;
    } catch (e) {
      debugPrint('[V3PinZahtevService] imaZahtevKojiCekaAsync error: $e');
      return false;
    }
  }

  static Future<bool> azurirajEmail(String putnikId, String email) async {
    try {
      await supabase.from('v3_putnici').update({'email': email}).eq('id', putnikId);
      return true;
    } catch (e) {
      debugPrint('[V3PinZahtevService] azurirajEmail error: $e');
      return false;
    }
  }

  static Future<bool> posaljiZahtev({
    required String putnikId,
    required String telefon,
    required String gcmId,
  }) async {
    try {
      final row = {
        'putnik_id': putnikId,
        'telefon': telefon,
        'gcm_id': gcmId,
        'status': 'ceka',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };
      // V3 Arhitektura: Fire and Forget (Realtime će odraditi sync preko updated_at)
      await supabase.from('v3_pin_zahtevi').insert(row);
      return true;
    } catch (e) {
      debugPrint('[V3PinZahtevService] posaljiZahtev error: $e');
      return false;
    }
  }

  static List<Map<String, dynamic>> _buildEnrichedList() {
    final rm = V3MasterRealtimeManager.instance;
    final zahtevi = rm.pinZahteviCache.values.where((z) => z['status'] == 'ceka').toList()
      ..sort((a, b) {
        final ca = a['created_at'] as String? ?? '';
        final cb = b['created_at'] as String? ?? '';
        return ca.compareTo(cb);
      });

    return zahtevi.map((z) {
      final putnikId = z['putnik_id']?.toString();
      final putnikData = putnikId != null ? rm.putniciCache[putnikId] : null;
      return <String, dynamic>{
        ...z,
        'putnik_ime': putnikData?['ime_prezime'] ?? 'Nepoznato',
        'broj_telefona': z['telefon'] ?? putnikData?['telefon_1'] ?? '-',
      };
    }).toList();
  }

  static Future<bool> odobriZahtev({
    required String zahtevId,
    required String pin,
  }) async {
    try {
      final rm = V3MasterRealtimeManager.instance;
      final zahtev = rm.pinZahteviCache[zahtevId];
      if (zahtev == null) return false;

      final putnikId = zahtev['putnik_id']?.toString();
      if (putnikId == null) return false;

      // 1. Ažuriraj putnika sa novim PIN-om u v3_putnici
      await supabase.from('v3_putnici').update({
        'pin': pin,
        'updated_by': 'admin:sistem',
      }).eq('id', putnikId);

      // 2. Obeleži zahtev kao odobren (Fire and Forget)
      await supabase.from('v3_pin_zahtevi').update({
        'status': 'odobren',
      }).eq('id', zahtevId);

      return true;
    } catch (e) {
      debugPrint('[V3PinZahtevService] odobriZahtev error: $e');
      return false;
    }
  }

  static Future<bool> odbijZahtev(String zahtevId) async {
    try {
      // 2. Obeleži zahtev kao odbijen (Fire and Forget)
      await supabase.from('v3_pin_zahtevi').update({
        'status': 'odbijen',
      }).eq('id', zahtevId);

      return true;
    } catch (e) {
      debugPrint('[V3PinZahtevService] odbijZahtev error: $e');
      return false;
    }
  }
}
