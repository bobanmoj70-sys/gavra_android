import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/v3_phone_utils.dart';
import 'v3_putnik_service.dart';

class V3ClosedAuthService {
  V3ClosedAuthService._();

  static SupabaseClient get _client => Supabase.instance.client;
  static final _storage = const FlutterSecureStorage();
  static const _firebasePhoneKey = 'v3_firebase_putnik_phone';

  static String normalizePhone(String rawPhone) => V3PhoneUtils.normalize(rawPhone.trim());

  static Future<bool> phoneExists(String rawPhone) async {
    final phone = normalizePhone(rawPhone);
    if (phone.isEmpty) return false;

    final res = await _client.rpc('v3_auth_phone_exists', params: {'p_telefon': phone});
    if (res is bool) return res;
    return res == true;
  }

  // ─── Firebase Phone Auth sesija ─────────────────────────────────

  /// Sačuvaj normalizovani telefon nakon uspešne Firebase SMS verifikacije.
  static Future<void> saveFirebasePutnikPhone(String normalizedPhone) async {
    await _storage.write(key: _firebasePhoneKey, value: normalizedPhone);
  }

  /// Obrisi sačuvani Firebase phone (pri odjavi).
  static Future<void> clearFirebasePutnikPhone() async {
    await _storage.delete(key: _firebasePhoneKey);
  }

  /// Auto-login: Firebase sesija postoji + telefon je sačuvan u SecureStorage.
  /// Direktno čita v3_auth tabelu.
  static Future<Map<String, dynamic>?> restorePutnikFromFirebaseSession() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return null;

    final storedPhone = await _storage.read(key: _firebasePhoneKey);
    if (storedPhone == null || storedPhone.isEmpty) return null;

    final phone = normalizePhone(storedPhone);
    if (phone.isEmpty) return null;

    final putnik = await V3PutnikService.getByPhoneOrCache(phone);
    if (putnik == null) return null;

    V3PutnikService.currentPutnik = putnik;
    return putnik;
  }
}
