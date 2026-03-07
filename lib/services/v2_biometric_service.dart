import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Servis za biometrijsku autentifikaciju (otisak prsta, Face ID)
class V2BiometricService {
  V2BiometricService._();

  static final LocalAuthentication _auth = LocalAuthentication();
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  // Ključevi za storage
  static const String _biometricEnabledKey = 'biometric_enabled';
  static const String _savedPhoneKey = 'biometric_saved_phone';
  static const String _savedPinKey = 'biometric_saved_pin';

  /// Proveri da li uređaj podržava biometriju
  static Future<bool> isDeviceSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } on PlatformException catch (e) {
      debugPrint('[V2BiometricService] isDeviceSupported greška: $e');
      return false;
    }
  }

  /// Proveri da li uređaj ima upisane biometrijske podatke
  static Future<bool> canCheckBiometrics() async {
    try {
      return await _auth.canCheckBiometrics;
    } on PlatformException catch (e) {
      debugPrint('[V2BiometricService] canCheckBiometrics greška: $e');
      return false;
    }
  }

  /// Dobij listu dostupnih biometrijskih tipova
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } on PlatformException catch (e) {
      debugPrint('[V2BiometricService] getAvailableBiometrics greška: $e');
      return [];
    }
  }

  /// Da li je biometrija dostupna (uređaj podržava + ima upisane podatke)
  static Future<bool> isBiometricAvailable() async {
    final results = await Future.wait([
      isDeviceSupported(),
      canCheckBiometrics(),
    ]);
    return results[0] && results[1];
  }

  /// Da li je biometrija uključena za korisnika
  static Future<bool> isBiometricEnabled() async {
    final value = await _secureStorage.read(key: _biometricEnabledKey);
    return value == 'true';
  }

  /// Uključi/isključi biometriju
  static Future<void> setBiometricEnabled(bool enabled) async {
    await _secureStorage.write(
      key: _biometricEnabledKey,
      value: enabled.toString(),
    );
  }

  /// Sačuvaj kredencijale za biometrijsku prijavu
  static Future<void> saveCredentials({
    required String phone,
    required String pin,
  }) async {
    await Future.wait([
      _secureStorage.write(key: _savedPhoneKey, value: phone),
      _secureStorage.write(key: _savedPinKey, value: pin),
    ]);
    await setBiometricEnabled(true);
  }

  /// Dobij sačuvane kredencijale
  static Future<Map<String, String>?> getSavedCredentials() async {
    final results = await Future.wait([
      _secureStorage.read(key: _savedPhoneKey),
      _secureStorage.read(key: _savedPinKey),
    ]);
    final phone = results[0];
    final pin = results[1];

    if (phone != null && pin != null) {
      return {'phone': phone, 'pin': pin};
    }
    return null;
  }

  /// Obriši sačuvane kredencijale
  static Future<void> clearCredentials() async {
    await Future.wait([
      _secureStorage.delete(key: _savedPhoneKey),
      _secureStorage.delete(key: _savedPinKey),
    ]);
    await setBiometricEnabled(false);
  }

  /// Autentifikuj korisnika biometrijom
  /// Vraća true ako je uspešno, false ako nije
  static Future<bool> authenticate({
    String reason = 'Prijavite se otiskom prsta',
  }) async {
    try {
      final isAvailable = await isBiometricAvailable();
      if (!isAvailable) return false;

      return await _auth.authenticate(
        localizedReason: reason,
      );
    } on PlatformException catch (e) {
      debugPrint('[V2BiometricService] authenticate greška: $e');
      return false;
    }
  }

  /// Dobij tekst i ikonu za tip biometrije odjednom (jedan platform channel poziv)
  static Future<({String text, String icon})> getBiometricInfo() async {
    final types = await getAvailableBiometrics();
    if (types.contains(BiometricType.face)) {
      return (text: 'Face ID', icon: '\uD83E\uDEAA');
    } else if (types.contains(BiometricType.fingerprint)) {
      return (text: 'otisak prsta', icon: '\uD83D\uDC46');
    } else if (types.contains(BiometricType.iris)) {
      return (text: 'iris', icon: '\uD83D\uDC41');
    }
    return (text: 'biometriju', icon: '\uD83D\uDD10');
  }

  /// Dobij tekst za tip biometrije (za UI)
  static Future<String> getBiometricTypeText() async {
    final info = await getBiometricInfo();
    return info.text;
  }

  /// Dobij ikonu za tip biometrije
  static Future<String> getBiometricIcon() async {
    final info = await getBiometricInfo();
    return info.icon;
  }
}
