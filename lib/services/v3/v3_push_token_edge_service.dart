import '../../globals.dart';

class V3PushTokenEdgeService {
  V3PushTokenEdgeService._();

  static Future<void> writeLoginColumns({
    required String v3AuthId,
    required String pushToken,
    String? pushToken2,
    String? androidDeviceId,
    String? androidDeviceId2,
    String? androidBuildId,
    String? androidBuildId2,
    String? iosDeviceId,
    String? iosDeviceId2,
    String? iosBuildId,
    String? iosBuildId2,
  }) async {
    final targetId = v3AuthId.trim();
    final safePushToken = pushToken.trim();
    final safeAndroidDeviceId = (androidDeviceId ?? '').trim();
    final safeAndroidDeviceId2 = (androidDeviceId2 ?? '').trim();
    final safeIosDeviceId = (iosDeviceId ?? '').trim();
    final safeIosDeviceId2 = (iosDeviceId2 ?? '').trim();
    final incomingOsDeviceId =
        safeAndroidDeviceId.isNotEmpty ? safeAndroidDeviceId : (safeIosDeviceId.isNotEmpty ? safeIosDeviceId : '');
    final fallbackIncomingOsDeviceId =
        safeAndroidDeviceId2.isNotEmpty ? safeAndroidDeviceId2 : (safeIosDeviceId2.isNotEmpty ? safeIosDeviceId2 : '');

    if (targetId.isEmpty) {
      throw Exception('Nedostaje v3_auth_id za upis login kolona.');
    }
    if (safePushToken.isEmpty) {
      throw Exception('Nedostaje push_token za upis login kolona.');
    }

    final response = await supabase.functions.invoke(
      'sync-login-columns',
      body: {
        'v3_auth_id': targetId,
        'incoming_push_token': safePushToken,
        if (incomingOsDeviceId.isNotEmpty || fallbackIncomingOsDeviceId.isNotEmpty)
          'incoming_os_device_id': incomingOsDeviceId.isNotEmpty ? incomingOsDeviceId : fallbackIncomingOsDeviceId,
        if (safeAndroidDeviceId.isNotEmpty || safeAndroidDeviceId2.isNotEmpty)
          'incoming_android_device_id': safeAndroidDeviceId.isNotEmpty ? safeAndroidDeviceId : safeAndroidDeviceId2,
        if (safeIosDeviceId.isNotEmpty || safeIosDeviceId2.isNotEmpty)
          'incoming_ios_device_id': safeIosDeviceId.isNotEmpty ? safeIosDeviceId : safeIosDeviceId2,
        if ((androidBuildId ?? '').trim().isNotEmpty || (androidBuildId2 ?? '').trim().isNotEmpty)
          'incoming_android_build_id':
              (androidBuildId ?? '').trim().isNotEmpty ? androidBuildId!.trim() : androidBuildId2!.trim(),
        if ((iosBuildId ?? '').trim().isNotEmpty || (iosBuildId2 ?? '').trim().isNotEmpty)
          'incoming_ios_build_id': (iosBuildId ?? '').trim().isNotEmpty ? iosBuildId!.trim() : iosBuildId2!.trim(),
        if ((pushToken2 ?? '').trim().isNotEmpty) 'push_token_2': pushToken2!.trim(),
      },
    );

    final status = response.status;
    final data = response.data;
    final isSuccess = data is Map && data['ok'] == true;

    if (status < 200 || status >= 300 || !isSuccess) {
      throw Exception('Edge sync-login-columns failed (status=$status, data=$data)');
    }
  }
}
