import 'package:flutter/foundation.dart';
import 'dart:math';
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
        'putnik_ime': putnikData?['imePrezime'] ?? putnikData?['ime'] ?? 'Nepoznato',
        'broj_telefona': z['telefon'] ?? putnikData?['telefon'] ?? '-',
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
      }).eq('id', putnikId);

      // 2. Obeleži zahtev kao odobren
      final updated = await supabase.from('v3_pin_zahtevi').update({
        'status': 'odobren',
      }).eq('id', zahtevId).select().single();

      rm.v3UpsertToCache('v3_pin_zahtevi', updated);
      return true;
    } catch (e) {
      debugPrint('[V3PinZahtevService] odobriZahtev error: $e');
      return false;
    }
  }

  static Future<bool> odbijZahtev(String zahtevId) async {
    try {
      final updated = await supabase.from('v3_pin_zahtevi').update({
        'status': 'odbijen',
      }).eq('id', zahtevId).select().single();

      V3MasterRealtimeManager.instance.v3UpsertToCache('v3_pin_zahtevi', updated);
      return true;
    } catch (e) {
      debugPrint('[V3PinZahtevService] odbijZahtev error: $e');
      return false;
    }
  }
}
