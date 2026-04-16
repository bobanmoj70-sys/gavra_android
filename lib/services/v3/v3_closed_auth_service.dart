import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../globals.dart';
import '../../utils/v3_phone_utils.dart';
import 'v3_os_device_id_service.dart';
import 'v3_putnik_service.dart';
import 'v3_vozac_service.dart';

class V3ClosedAuthService {
  V3ClosedAuthService._();

  static SupabaseClient get _client => Supabase.instance.client;
  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  static const _manualSmsPutnikPhoneKey = 'v3_manual_sms_putnik_phone';
  static const _manualSmsVozacPhoneKey = 'v3_manual_sms_vozac_phone';

  static String normalizePhone(String rawPhone) => V3PhoneUtils.normalize(rawPhone.trim());

  static Future<bool> ensureClientReady() => ensureSupabaseReady();

  static Future<bool> phoneExists(String rawPhone) async {
    final ready = await ensureClientReady();
    if (!ready) return false;

    final phone = normalizePhone(rawPhone);
    if (phone.isEmpty) return false;

    final candidates = <String>{};

    void addCandidate(String? value) {
      final safe = (value ?? '').trim();
      if (safe.isNotEmpty) candidates.add(safe);
    }

    addCandidate(rawPhone);
    addCandidate(phone);

    final digits = phone.replaceAll('+', '');
    addCandidate(digits);
    if (digits.isNotEmpty) {
      addCandidate('+$digits');
    }
    if (digits.startsWith('381') && digits.length > 3) {
      addCandidate('0${digits.substring(3)}');
    }

    if (candidates.isEmpty) return false;

    final clauses = <String>[];
    for (final candidate in candidates) {
      clauses.add('telefon.eq.$candidate');
      clauses.add('telefon_2.eq.$candidate');
    }

    final row = await _client.from('v3_auth').select('id').or(clauses.join(',')).limit(1).maybeSingle();
    return row != null;
  }

  // ─── Manual SMS sesija ──────────────────────────────────────────

  /// Sačuvaj normalizovani telefon nakon uspešne manual SMS verifikacije.
  static Future<void> saveManualSmsPutnikPhone(String normalizedPhone) async {
    await _storage.write(key: _manualSmsPutnikPhoneKey, value: normalizedPhone);
  }

  /// Sačuvaj normalizovani telefon vozača nakon uspešne manual SMS verifikacije.
  static Future<void> saveManualSmsVozacPhone(String normalizedPhone) async {
    await _storage.write(key: _manualSmsVozacPhoneKey, value: normalizedPhone);
  }

  /// Obriši sačuvani putnik telefon (pri odjavi).
  static Future<void> clearManualSmsPutnikPhone() async {
    await _storage.delete(key: _manualSmsPutnikPhoneKey);
  }

  /// Obriši sačuvani vozač telefon (pri odjavi).
  static Future<void> clearManualSmsVozacPhone() async {
    await _storage.delete(key: _manualSmsVozacPhoneKey);
  }

  /// Auto-login: telefon je sačuvan u SecureStorage.
  /// Direktno čita v3_auth tabelu.
  static Future<Map<String, dynamic>?> restorePutnikFromManualSmsSession() async {
    final storedPhone = await _storage.read(key: _manualSmsPutnikPhoneKey);
    if (storedPhone == null || storedPhone.isEmpty) return null;

    final phone = normalizePhone(storedPhone);
    if (phone.isEmpty) return null;

    final osDeviceId = (await V3OsDeviceIdService.getOsDeviceId() ?? '').trim();
    if (osDeviceId.isEmpty) return null;

    final putnik = await V3PutnikService.getByPhoneDirect(phone, osDeviceId: osDeviceId);
    if (putnik == null) return null;

    V3PutnikService.currentPutnik = putnik;
    return putnik;
  }

  /// Auto-login: sačuvan telefon vozača u SecureStorage.
  static Future<void> restoreVozacFromManualSmsSession() async {
    final storedPhone = await _storage.read(key: _manualSmsVozacPhoneKey);
    if (storedPhone == null || storedPhone.isEmpty) return;

    final phone = normalizePhone(storedPhone);
    if (phone.isEmpty) return;

    final osDeviceId = (await V3OsDeviceIdService.getOsDeviceId() ?? '').trim();
    if (osDeviceId.isEmpty) return;

    final vozac = await V3VozacService.getVozacByPhoneDirect(phone, osDeviceId: osDeviceId);
    if (vozac == null) return;

    V3VozacService.currentVozac = vozac;
  }
}
