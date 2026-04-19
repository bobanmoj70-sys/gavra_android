import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../globals.dart';
import '../../utils/v3_phone_utils.dart';
import 'v3_putnik_service.dart';
import 'v3_vozac_service.dart';

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

  static Future<String?> findAuthIdByPhone(String rawPhone) async {
    final ready = await ensureClientReady();
    if (!ready) return null;

    final phone = normalizePhone(rawPhone);
    if (phone.isEmpty) return null;

    final data = await _client.rpc(
      'v3_auth_find_id_by_phone',
      params: {'p_telefon': phone},
    );

    final authId = data?.toString().trim() ?? '';
    if (authId.isEmpty) return null;
    return authId;
  }

  static Future<String?> findAuthIdByPhoneViaEdge(
    String rawPhone, {
    String? expectedAuthId,
  }) async {
    final ready = await ensureClientReady();
    if (!ready) return null;

    final phone = normalizePhone(rawPhone);
    if (phone.isEmpty) return null;
    final expectedId = (expectedAuthId ?? '').trim();
    if (expectedId.isEmpty) return null;

    try {
      final response = await _client.functions.invoke(
        'verify-login',
        body: {
          'telefon': phone,
          'v3_auth_id': expectedId,
        },
      );

      final status = response.status;
      final data = response.data;
      if (status < 200 || status >= 300 || data is! Map) {
        return null;
      }

      final ok = data['ok'] == true;
      if (!ok) return null;

      final verifiedId = data['v3_auth_id']?.toString().trim() ?? '';
      if (verifiedId.isNotEmpty) {
        if (expectedId.isNotEmpty && verifiedId != expectedId) {
          return null;
        }
        return verifiedId;
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  // ─── Manual SMS sesija ──────────────────────────────────────────

  /// Sačuvaj normalizovani telefon nakon uspešne manual SMS verifikacije.
  static Future<void> saveManualSmsPutnikPhone(String normalizedPhone) async {
    await _storage.write(key: _manualSmsPutnikPhoneKey, value: normalizedPhone);
    await _storage.delete(key: _manualSmsPutnikAuthIdKey);
  }

  static Future<void> saveManualSmsPutnikSession({
    required String normalizedPhone,
    required String authId,
  }) async {
    await _storage.write(key: _manualSmsPutnikPhoneKey, value: normalizedPhone);
    await _storage.write(key: _manualSmsPutnikAuthIdKey, value: authId.trim());
  }

  /// Sačuvaj normalizovani telefon vozača nakon uspešne manual SMS verifikacije.
  static Future<void> saveManualSmsVozacPhone(String normalizedPhone) async {
    await _storage.write(key: _manualSmsVozacPhoneKey, value: normalizedPhone);
    await _storage.delete(key: _manualSmsVozacAuthIdKey);
  }

  static Future<void> saveManualSmsVozacSession({
    required String normalizedPhone,
    required String authId,
  }) async {
    await _storage.write(key: _manualSmsVozacPhoneKey, value: normalizedPhone);
    await _storage.write(key: _manualSmsVozacAuthIdKey, value: authId.trim());
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
