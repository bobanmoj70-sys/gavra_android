import '../../globals.dart';
import '../../utils/v3_time_utils.dart';

class V3DriverPushNotificationService {
  V3DriverPushNotificationService._();

  static Future<void> notifyPassengersDriverStarted({
    required String vozacId,
    required String datumIso,
    required String grad,
    required String vreme,
  }) async {
    final safeVozacId = vozacId.trim();
    final safeDatumIso = datumIso.trim();
    final safeGrad = grad.trim().toUpperCase();
    final safeVreme = V3TimeUtils.normalizeToHHmm(vreme);

    if (safeVozacId.isEmpty || safeDatumIso.isEmpty || safeGrad.isEmpty || safeVreme.isEmpty) {
      return;
    }

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

      if (response is Map<String, dynamic> && response['ok'] == false) {
        final reason = (response['reason'] ?? 'unknown').toString();
        throw Exception(reason);
      }
    } catch (e) {
      throw Exception('Driver start push failed: $e');
    }
  }
}
