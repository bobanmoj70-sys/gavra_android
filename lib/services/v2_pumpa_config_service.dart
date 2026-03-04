import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../models/v2_pumpa_config.dart';

/// Servis za tabelu v2_pumpa_config (konfiguracija kućne pumpe)
class V2PumpaConfigService {
  V2PumpaConfigService._();

  static const String tabela = 'v2_pumpa_config';

  static SupabaseClient get _db => supabase;

  /// Dohvati konfiguraciju pumpe
  static Future<V2PumpaConfig?> getConfig() async {
    try {
      final response = await _db
          .from(tabela)
          .select('id,kapacitet_litri,alarm_nivo,pocetno_stanje,updated_at')
          .limit(1)
          .maybeSingle();
      if (response == null) return null;
      return V2PumpaConfig.fromJson(response);
    } catch (e) {
      debugPrint('[V2PumpaConfigService] getConfig error: $e');
      return null;
    }
  }

  /// Ažuriraj konfiguraciju pumpe
  static Future<bool> updateConfig({
    double? kapacitet,
    double? alarmNivo,
    double? pocetnoStanje,
  }) async {
    try {
      final Map<String, dynamic> data = {
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (kapacitet != null) data['kapacitet_litri'] = kapacitet;
      if (alarmNivo != null) data['alarm_nivo'] = alarmNivo;
      if (pocetnoStanje != null) data['pocetno_stanje'] = pocetnoStanje;

      await _db.from(tabela).update(data);
      return true;
    } catch (e) {
      debugPrint('[V2PumpaConfigService] updateConfig error: $e');
      return false;
    }
  }
}
