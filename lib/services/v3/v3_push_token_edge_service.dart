import '../../globals.dart';

class V3PushTokenEdgeService {
  V3PushTokenEdgeService._();

  static String _firstNonEmpty(String? a, String? b, [String? c]) {
    final values = [a, b, c];
    for (final value in values) {
      final safe = (value ?? '').trim();
      if (safe.isNotEmpty) return safe;
    }
    return '';
  }

  static String _tokenDeviceMarker(String token) {
    final safeToken = token.trim();
    if (safeToken.isEmpty) return '';
    final marker = safeToken.length > 48 ? safeToken.substring(0, 48) : safeToken;
    return 'token:$marker';
  }

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

    final incomingAndroidDeviceId = _firstNonEmpty(safeAndroidDeviceId, safeAndroidDeviceId2);
    final incomingIosDeviceId = _firstNonEmpty(safeIosDeviceId, safeIosDeviceId2);
    final incomingOsDeviceId = _firstNonEmpty(
      incomingAndroidDeviceId,
      incomingIosDeviceId,
      _tokenDeviceMarker(safePushToken),
    );

    final incomingAndroidBuildId = _firstNonEmpty(androidBuildId, androidBuildId2);
    final incomingIosBuildId = _firstNonEmpty(iosBuildId, iosBuildId2);
    final safePushToken2 = (pushToken2 ?? '').trim();

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
        if (incomingOsDeviceId.isNotEmpty) 'incoming_os_device_id': incomingOsDeviceId,
        if (incomingAndroidDeviceId.isNotEmpty) 'incoming_android_device_id': incomingAndroidDeviceId,
        if (incomingIosDeviceId.isNotEmpty) 'incoming_ios_device_id': incomingIosDeviceId,
        if (incomingAndroidBuildId.isNotEmpty) 'incoming_android_build_id': incomingAndroidBuildId,
        if (incomingIosBuildId.isNotEmpty) 'incoming_ios_build_id': incomingIosBuildId,
        if (safePushToken2.isNotEmpty) 'push_token_2': safePushToken2,
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
