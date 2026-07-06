import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../globals.dart';
import '../../utils/v3_phone_utils.dart';
import 'v3_device_identity_service.dart';
import 'v3_putnik_service.dart';
import 'v3_vozac_service.dart';

class V3LoginVerification {
  final bool ok;
  final String? authId;
  final bool deviceRecognized;
  final bool deviceAllowed;
  final bool deviceSlotsFull;
  final String? reason;

  const V3LoginVerification({
    required this.ok,
    this.authId,
    this.deviceRecognized = false,
    this.deviceAllowed = true,
    this.deviceSlotsFull = false,
    this.reason,
  });
}

class V3ClosedAuthService {
  V3ClosedAuthService._();

  static SupabaseClient get _client => Supabase.instance.client;
  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  static const _manualSmsPutnikPhoneKey = 'v3_manual_sms_putnik_phone';
  static const _manualSmsPutnikAuthIdKey = 'v3_manual_sms_putnik_auth_id';
  static const _manualSmsVozacPhoneKey = 'v3_manual_sms_vozac_phone';
  static const _manualSmsVozacAuthIdKey = 'v3_manual_sms_vozac_auth_id';

  static String normalizePhone(String rawPhone) => V3PhoneUtils.normalize(rawPhone.trim());

  static Future<bool> ensureClientReady() => ensureSupabaseReady();

  static Future<V3LoginVerification> verifyLogin({
    required String rawPhone,
    required String expectedAuthId,
    String? installationId,
    String? hardwareId,
  }) async {
    final ready = await ensureClientReady();
    if (!ready) {
      return const V3LoginVerification(ok: false, reason: 'supabase_not_ready');
    }

    final phone = normalizePhone(rawPhone);
    if (phone.isEmpty) {
      return const V3LoginVerification(ok: false, reason: 'missing_phone');
    }

    final expectedId = expectedAuthId.trim();
    if (expectedId.isEmpty) {
      return const V3LoginVerification(ok: false, reason: 'missing_v3_auth_id');
    }

    try {
      final body = <String, dynamic>{
        'telefon': phone,
        'v3_auth_id': expectedId,
      };
      final incomingInstallationId = (installationId ?? '').trim();
      if (incomingInstallationId.isNotEmpty) {
        body['installation_id'] = incomingInstallationId;
      }
      final incomingHardwareId = (hardwareId ?? '').trim();
      if (incomingHardwareId.isNotEmpty) {
        body['hardware_id'] = incomingHardwareId;
      }

      final response = await _client.functions.invoke(
        'verify-login',
        body: body,
      );

      final status = response.status;
      final data = response.data;
      if (status < 200 || status >= 300 || data is! Map) {
        return const V3LoginVerification(ok: false, reason: 'edge_error');
      }

      final ok = data['ok'] == true;
      final verifiedId = data['v3_auth_id']?.toString().trim() ?? '';
      final reason = data['reason']?.toString();

      return V3LoginVerification(
        ok: ok,
        authId: verifiedId.isNotEmpty ? verifiedId : expectedId,
        deviceRecognized: data['device_recognized'] == true,
        deviceAllowed: ok,
        deviceSlotsFull: data['device_slots_full'] == true,
        reason: reason,
      );
    } catch (_) {
      return const V3LoginVerification(ok: false, reason: 'unexpected_error');
    }
  }

  static Future<String?> findAuthIdByPhone(String rawPhone) async {
    debugPrint('[findAuthIdByPhone] Called with: $rawPhone');
    final ready = await ensureClientReady();
    debugPrint('[findAuthIdByPhone] Client ready: $ready');
    if (!ready) return null;

    final phone = normalizePhone(rawPhone);
    debugPrint('[findAuthIdByPhone] Normalized phone: $phone');
    if (phone.isEmpty) return null;

    debugPrint('[findAuthIdByPhone] Calling RPC v3_auth_find_id_by_phone...');
    final data = await _client.rpc(
      'v3_auth_find_id_by_phone',
      params: {'p_telefon': phone},
    );
    debugPrint('[findAuthIdByPhone] RPC response: $data');

    final authId = data?.toString().trim() ?? '';
    debugPrint('[findAuthIdByPhone] AuthId: $authId');
    if (authId.isEmpty) return null;
    return authId;
  }

  static Future<String?> findAuthIdByPhoneViaEdge(
    String rawPhone, {
    String? expectedAuthId,
  }) async {
    final deviceId = await V3DeviceIdentityService.getStableDeviceId();
    final hardwareId = await V3DeviceIdentityService.getHardwareId();
    final verification = await verifyLogin(
      rawPhone: rawPhone,
      expectedAuthId: expectedAuthId ?? '',
      installationId: deviceId,
      hardwareId: hardwareId,
    );
    if (!verification.ok || !verification.deviceAllowed) return null;
    return verification.authId;
  }

  // ─── Manual SMS sesija ──────────────────────────────────────────

  static Future<void> saveManualSmsPutnikSession({
    required String normalizedPhone,
    required String authId,
  }) async {
    await _storage.write(key: _manualSmsPutnikPhoneKey, value: normalizedPhone);
    await _storage.write(key: _manualSmsPutnikAuthIdKey, value: authId.trim());
  }

  static Future<void> saveManualSmsVozacSession({
    required String normalizedPhone,
    required String authId,
  }) async {
    await _storage.write(key: _manualSmsVozacPhoneKey, value: normalizedPhone);
    await _storage.write(key: _manualSmsVozacAuthIdKey, value: authId.trim());
  }

  static Future<Set<String>> getStoredManualSmsAuthIds() async {
    final putnikAuthId = (await _storage.read(key: _manualSmsPutnikAuthIdKey))?.trim() ?? '';
    final vozacAuthId = (await _storage.read(key: _manualSmsVozacAuthIdKey))?.trim() ?? '';

    return <String>{
      if (putnikAuthId.isNotEmpty) putnikAuthId,
      if (vozacAuthId.isNotEmpty) vozacAuthId,
    };
  }

  /// Obriši sačuvani putnik telefon (pri odjavi).
  static Future<void> clearManualSmsPutnikPhone() async {
    await _storage.delete(key: _manualSmsPutnikPhoneKey);
    await _storage.delete(key: _manualSmsPutnikAuthIdKey);
  }

  /// Obriši sačuvani vozač telefon (pri odjavi).
  static Future<void> clearManualSmsVozacPhone() async {
    await _storage.delete(key: _manualSmsVozacPhoneKey);
    await _storage.delete(key: _manualSmsVozacAuthIdKey);
  }

  /// Auto-login: telefon je sačuvan u SecureStorage.
  /// Direktno čita v3_auth tabelu.
  static Future<Map<String, dynamic>?> restorePutnikFromManualSmsSession() async {
    final storedPhone = await _storage.read(key: _manualSmsPutnikPhoneKey);
    final storedAuthId = (await _storage.read(key: _manualSmsPutnikAuthIdKey))?.trim() ?? '';
    if (storedPhone == null || storedPhone.isEmpty) return null;
    if (storedAuthId.isEmpty) return null;

    final phone = normalizePhone(storedPhone);
    if (phone.isEmpty) return null;

    final verifiedAuthId = await findAuthIdByPhoneViaEdge(
      phone,
      expectedAuthId: storedAuthId,
    );
    if (verifiedAuthId == null || verifiedAuthId.isEmpty) return null;

    final putnik = await V3PutnikService.getActiveById(verifiedAuthId);
    if (putnik == null) return null;

    V3PutnikService.currentPutnik = putnik;
    return putnik;
  }

  /// Auto-login: sačuvan telefon vozača u SecureStorage.
  static Future<void> restoreVozacFromManualSmsSession() async {
    final storedPhone = await _storage.read(key: _manualSmsVozacPhoneKey);
    final storedAuthId = (await _storage.read(key: _manualSmsVozacAuthIdKey))?.trim() ?? '';
    if (storedPhone == null || storedPhone.isEmpty) return;
    if (storedAuthId.isEmpty) return;

    final phone = normalizePhone(storedPhone);
    if (phone.isEmpty) return;

    final verifiedAuthId = await findAuthIdByPhoneViaEdge(
      phone,
      expectedAuthId: storedAuthId,
    );
    if (verifiedAuthId == null || verifiedAuthId.isEmpty) return;

    var vozac = V3VozacService.getVozacById(verifiedAuthId);
    vozac ??= await V3VozacService.getVozacByIdDirect(verifiedAuthId);
    if (vozac == null || vozac.id.trim() != verifiedAuthId) return;

    V3VozacService.currentVozac = vozac;
  }
}
