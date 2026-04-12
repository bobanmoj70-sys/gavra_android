import 'package:flutter/foundation.dart';

import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_app_settings_repository.dart';

class V3AppSettingsService {
  V3AppSettingsService._();
  static final V3AppSettingsRepository _repo = V3AppSettingsRepository();

  static Future<Map<String, dynamic>> loadGlobal({String? selectColumns}) async {
    try {
      final row = await _repo.getGlobal(selectColumns: selectColumns ?? '*');
      return row == null ? <String, dynamic>{} : Map<String, dynamic>.from(row);
    } catch (e) {
      debugPrint('[V3AppSettingsService] loadGlobal error: $e');
      rethrow;
    }
  }

  static Future<void> upsertGlobal(Map<String, dynamic> payload) async {
    try {
      await _repo.upsertGlobal(payload);
    } catch (e) {
      debugPrint('[V3AppSettingsService] upsertGlobal error: $e');
      rethrow;
    }
  }

  static Future<void> updateGlobal(Map<String, dynamic> payload) async {
    try {
      final row = await _repo.updateGlobal(payload);

      if (row != null) {
        V3MasterRealtimeManager.instance.v3UpsertToCache('v3_app_settings', row);
      }
    } catch (e) {
      debugPrint('[V3AppSettingsService] updateGlobal error: $e');
      rethrow;
    }
  }
}
