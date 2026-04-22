import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import '../../globals.dart';

class V3PushTokenEdgeService {
  V3PushTokenEdgeService._();

  static String _resolvePlatform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  static Future<String> _resolveAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      final build = info.buildNumber.trim();
      if (version.isEmpty && build.isEmpty) return '';
      if (build.isEmpty) return version;
      if (version.isEmpty) return build;
      return '$version+$build';
    } catch (_) {
      return '';
    }
  }

  static Future<void> writeLoginColumns({
    required String v3AuthId,
    String? pushToken,
    String? installationId,
    String? pushToken2,
  }) async {
    final targetId = v3AuthId.trim();
    final safePushToken = (pushToken ?? '').trim();
    final incomingInstallationId = (installationId ?? '').trim();
    final incomingPlatform = _resolvePlatform();
    final incomingAppVersion = await _resolveAppVersion();
    final safePushToken2 = (pushToken2 ?? '').trim();

    if (targetId.isEmpty) {
      throw Exception('Nedostaje v3_auth_id za upis login kolona.');
    }
    if (incomingInstallationId.isEmpty) {
      throw Exception('Nedostaje incoming_installation_id za upis login kolona.');
    }

    final response = await supabase.functions.invoke(
      'sync-login-columns',
      body: {
        'v3_auth_id': targetId,
        'incoming_installation_id': incomingInstallationId,
        if (safePushToken.isNotEmpty) 'incoming_push_token': safePushToken,
        if (incomingPlatform.isNotEmpty) 'incoming_platform': incomingPlatform,
        if (incomingAppVersion.isNotEmpty) 'incoming_app_version': incomingAppVersion,
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
