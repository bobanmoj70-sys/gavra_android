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

  // ─── Firebase Phone Auth sesija ─────────────────────────────────

  /// Sačuvaj normalizovani telefon nakon uspešne Firebase SMS verifikacije.
  static Future<void> saveFirebasePutnikPhone(String normalizedPhone) async {
    await _storage.write(key: _firebasePhoneKey, value: normalizedPhone);
  }

  /// Obrisi sačuvani Firebase phone (pri odjavi).
  static Future<void> clearFirebasePutnikPhone() async {
    await _storage.delete(key: _firebasePhoneKey);
  }

  static Future<Map<String, dynamic>> bridgeFirebaseSessionToV3Auth() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      throw Exception('Firebase sesija ne postoji.');
    }

    final firebaseIdToken = (await firebaseUser.getIdToken(true)) ?? '';
    if (firebaseIdToken.isEmpty) {
      throw Exception('Ne mogu da preuzmem Firebase ID token.');
    }

    final response = await _client.functions.invoke(
      'firebase-auth-bridge',
      body: {
        'firebase_id_token': firebaseIdToken,
      },
    );

    final data = response.data;
    if (data is! Map) {
      throw Exception('Neispravan odgovor bridge funkcije.');
    }

    final payload = Map<String, dynamic>.from(data);
    if (payload['ok'] != true) {
      throw Exception(payload['error']?.toString() ?? 'Bridge funkcija je odbila pristup.');
    }

    final v3Auth = payload['v3_auth'];
    if (v3Auth is! Map) {
      throw Exception('Bridge funkcija nije vratila v3_auth payload.');
    }

    // Garantovano: auth_id je uvek popunjen nakon bridge poziva
    final result = Map<String, dynamic>.from(v3Auth);
    if (result['auth_id'] == null || result['auth_id'].toString().isEmpty) {
      throw Exception('Bridge nije vratio auth_id - auth.users kreiranje nije uspelo.');
    }

    return result;
  }

  /// Vraća auth_id (= auth.users UUID) iz keširane bridge sesije.
  /// Ovo je kanonski UUID korisnika za created_by/updated_by kolone.
  static String? extractAuthId(Map<String, dynamic> bridgeRow) {
    return bridgeRow['auth_id']?.toString();
  }

  /// Pokušaj auto-login via Firebase sesije + sačuvanog telefona.
  /// Vraća putnika ako Firebase currentUser postoji i telefon je u bazi.
  static Future<Map<String, dynamic>?> restorePutnikFromFirebaseSession() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return null;

    final gateRow = await bridgeFirebaseSessionToV3Auth();

    final phone = normalizePhone(gateRow['telefon']?.toString() ?? '');
    if (phone.isEmpty) return null;

    final storedPhone = await _storage.read(key: _firebasePhoneKey);
    if (storedPhone == null || storedPhone != phone) {
      await saveFirebasePutnikPhone(phone);
    }

    final putnik = await V3PutnikService.getByPhoneOrCache(phone);
    if (putnik == null) return null;

    V3PutnikService.currentPutnik = putnik;
    return putnik;
  }
}
