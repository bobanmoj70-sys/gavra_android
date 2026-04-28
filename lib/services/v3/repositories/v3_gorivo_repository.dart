import '../../../globals.dart';

class V3GorivoRepository {
  Future<Map<String, dynamic>> updateByIdReturning(String id, Map<String, dynamic> payload) {
    return supabase.from('v3_gorivo').update(payload).eq('id', id).select().single();
  }
}
