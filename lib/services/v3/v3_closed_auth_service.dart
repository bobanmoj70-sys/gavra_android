import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/v3_phone_utils.dart';
import 'v3_putnik_service.dart';

class V3ClosedAuthService {
  V3ClosedAuthService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static String normalizePhone(String rawPhone) => V3PhoneUtils.normalize(rawPhone.trim());

  static Future<bool> phoneExists(String rawPhone) async {
    final phone = normalizePhone(rawPhone);
    if (phone.isEmpty) return false;

    final res = await _client.rpc('v3_auth_phone_exists', params: {'p_telefon': phone});
    if (res is bool) return res;
    return res == true;
  }

  static Future<void> sendMagicLink({
    required String rawPhone,
    required String email,
  }) async {
    final phone = normalizePhone(rawPhone);
    final safeEmail = email.trim().toLowerCase();

    if (phone.isEmpty) {
      throw Exception('Telefon je obavezan.');
    }
    if (safeEmail.isEmpty) {
      throw Exception('Email je obavezan.');
    }

    final exists = await phoneExists(phone);
    if (!exists) {
      throw Exception('Broj telefona nije pronađen u sistemu.');
    }

    await _client.auth.signInWithOtp(
      email: safeEmail,
      shouldCreateUser: true,
    );
  }

  static Future<bool> linkCurrentUserToPhone(String rawPhone) async {
    final phone = normalizePhone(rawPhone);
    if (phone.isEmpty) return false;

    final res = await _client.rpc('v3_auth_link_current_user', params: {'p_telefon': phone});
    if (res is bool) return res;
    return res == true;
  }

  static Future<String?> getPhoneForCurrentUser() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final row = await _client.from('v3_auth').select('telefon').eq('auth_id', user.id).maybeSingle();
    if (row == null) return null;

    final telefon = row['telefon']?.toString() ?? '';
    if (telefon.trim().isEmpty) return null;
    return normalizePhone(telefon);
  }

  static Future<Map<String, dynamic>?> restorePutnikFromCurrentSession() async {
    final phone = await getPhoneForCurrentUser();
    if (phone == null || phone.isEmpty) return null;

    final putnik = await V3PutnikService.getByPhoneOrCache(phone);
    if (putnik == null) return null;

    V3PutnikService.currentPutnik = putnik;
    return putnik;
  }
}
