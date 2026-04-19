import '../../globals.dart';

class V3PushTokenEdgeService {
  V3PushTokenEdgeService._();

  static Future<void> writeLoginColumns({
    required String v3AuthId,
    required String pushToken,
    String? pushToken2,
    String? osDeviceId,
    String? osDeviceId2,
    String? androidDeviceId,
    String? androidDeviceId2,
    String? androidBuildId,
    String? androidBuildId2,
    String? iosDeviceId,
    String? iosDeviceId2,
    String? iosBuildId,
    String? iosBuildId2,
    String? expectedTip,
  }) async {
    final targetId = v3AuthId.trim();
    if (targetId.isEmpty) {
      throw Exception('Nedostaje v3_auth_id za upis login kolona.');
    }

    final response = await supabase.functions.invoke(
      'sync-push-token',
      body: {
        'v3_auth_id': targetId,
        'push_token': pushToken.trim(),
        if ((pushToken2 ?? '').trim().isNotEmpty) 'push_token_2': pushToken2!.trim(),
        if ((osDeviceId ?? '').trim().isNotEmpty) 'os_device_id': osDeviceId!.trim(),
        if ((osDeviceId2 ?? '').trim().isNotEmpty) 'os_device_id_2': osDeviceId2!.trim(),
        if ((androidDeviceId ?? '').trim().isNotEmpty) 'android_device_id': androidDeviceId!.trim(),
        if ((androidDeviceId2 ?? '').trim().isNotEmpty) 'android_device_id_2': androidDeviceId2!.trim(),
        if ((androidBuildId ?? '').trim().isNotEmpty) 'android_build_id': androidBuildId!.trim(),
        if ((androidBuildId2 ?? '').trim().isNotEmpty) 'android_build_id_2': androidBuildId2!.trim(),
        if ((iosDeviceId ?? '').trim().isNotEmpty) 'ios_device_id': iosDeviceId!.trim(),
        if ((iosDeviceId2 ?? '').trim().isNotEmpty) 'ios_device_id_2': iosDeviceId2!.trim(),
        if ((iosBuildId ?? '').trim().isNotEmpty) 'ios_build_id': iosBuildId!.trim(),
        if ((iosBuildId2 ?? '').trim().isNotEmpty) 'ios_build_id_2': iosBuildId2!.trim(),
        if ((expectedTip ?? '').trim().isNotEmpty) 'expected_tip': expectedTip!.trim(),
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
