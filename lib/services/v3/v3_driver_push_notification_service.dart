import '../../globals.dart';
import '../../utils/v3_time_utils.dart';

class V3DriverPushNotificationService {
  V3DriverPushNotificationService._();

  static Future<Map<String, dynamic>> notifyPassengersDriverStarted({
    required String vozacId,
    required String datumIso,
    required String grad,
    required String vreme,
  }) async {
    final safeVozacId = vozacId.trim();
    final safeDatumIso = datumIso.trim();
    final safeGrad = grad.trim().toUpperCase();
    final safeVreme = V3TimeUtils.normalizeToHHmm(vreme);

    try {
      final response = await supabase.rpc(
        'v3_notify_passengers_driver_started',
        params: {
          'p_vozac_id': safeVozacId,
          'p_datum': safeDatumIso,
          'p_grad': safeGrad,
          'p_vreme': safeVreme,
        },
      );

      if (response is! Map) {
        throw Exception('Unexpected RPC response format: $response');
      }

      final map = Map<String, dynamic>.from(response);

      if (map['ok'] == false) {
        final reason = (map['reason'] ?? 'unknown').toString();
        throw Exception(reason);
      }

      return map;
    } catch (e) {
      throw Exception('Driver start push failed: $e');
    }
  }
}
