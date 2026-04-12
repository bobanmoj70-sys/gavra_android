import '../../globals.dart';

class V3PushTokenEdgeService {
  V3PushTokenEdgeService._();

  static Future<void> syncPushToken({
    required String pushToken,
    required String provider,
    required String slot,
    String? expectedTip,
    String? expectedV3AuthId,
  }) async {
    final targetId = (expectedV3AuthId ?? '').trim();
    if (targetId.isEmpty) {
      throw Exception('Nedostaje expectedV3AuthId za sync push tokena.');
    }

    final response = await supabase.functions.invoke(
      'sync-push-token',
      body: {
        'v3_auth_id': targetId,
        'push_token': pushToken,
        'push_provider': provider,
        'slot': slot,
        if (expectedTip != null && expectedTip.isNotEmpty) 'expected_tip': expectedTip,
      },
    );

    final status = response.status;
    final data = response.data;
    final isOk = data is Map && data['ok'] == true;

    if (status < 200 || status >= 300 || !isOk) {
      throw Exception('Edge sync-push-token failed (status=$status, data=$data)');
    }
  }
}
