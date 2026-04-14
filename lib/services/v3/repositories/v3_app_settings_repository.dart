import '../../../globals.dart';

class V3AppSettingsRepository {
  Future<Map<String, dynamic>?> getGlobal({String selectColumns = '*'}) {
    return supabase
        .from('v3_app_settings')
        .select(selectColumns)
        .eq('id', 'global')
        .maybeSingle();
  }

  Future<void> upsertGlobal(Map<String, dynamic> payload) {
    return supabase
        .from('v3_app_settings')
        .upsert({'id': 'global', ...payload});
  }

  Future<Map<String, dynamic>?> updateGlobal(Map<String, dynamic> payload) {
    return supabase
        .from('v3_app_settings')
        .update(payload)
        .eq('id', 'global')
        .select()
        .maybeSingle();
  }
}
