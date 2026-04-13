import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class V3BiometricService {
  static final V3BiometricService _instance = V3BiometricService._internal();
  factory V3BiometricService() => _instance;
  V3BiometricService._internal();

  final LocalAuthentication _auth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static const String _keyBiometricEnabled = 'biometric_enabled';
  static const String _keyRememberMe = 'remember_me_enabled';
  static const String _keySavedPhone = 'biometric_saved_phone';
  static const String _keySavedSecret = 'biometric_saved_secret';
  static const String _keySmsLoginPhone = 'v3_biometric_login_phone';

  // Provjeri da li uređaj podržava biometriju
  Future<bool> isDeviceSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (e) {
      return false;
    }
  }

  // Provjeri da li ima registrovanih biometrijskih podataka
  Future<bool> canCheckBiometrics() async {
    try {
      return await _auth.canCheckBiometrics;
    } catch (e) {
      return false;
    }
  }

  // Kombinovana provjera
  Future<bool> isBiometricAvailable() async {
    final supported = await isDeviceSupported();
    final canCheck = await canCheckBiometrics();
    return supported && canCheck;
  }

  // Da li je biometrija uključena za ovog korisnika
  Future<bool> isBiometricEnabled() async {
    final val = await _secureStorage.read(key: _keyBiometricEnabled);
    return val == 'true';
  }

  // Uključi/isključi biometriju
  Future<void> setBiometricEnabled(bool enabled) async {
    await _secureStorage.write(key: _keyBiometricEnabled, value: enabled.toString());
  }

  // Remember Me logic
  Future<bool> isRememberMeEnabled() async {
    final val = await _secureStorage.read(key: _keyRememberMe);
    return val == 'true';
  }

  Future<void> setRememberMeEnabled(bool enabled) async {
    await _secureStorage.write(key: _keyRememberMe, value: enabled.toString());
  }

  // Sačuvaj kredencijale (telefon + dodatni credential)
  Future<void> saveCredentials(String phone, String secret, {bool isBiometric = true}) async {
    await _secureStorage.write(key: _keySavedPhone, value: phone);
    await _secureStorage.write(key: _keySavedSecret, value: secret);
    if (isBiometric) {
      await setBiometricEnabled(true);
      await setRememberMeEnabled(false);
    } else {
      await setRememberMeEnabled(true);
      await setBiometricEnabled(false);
    }
  }

  // Dohvati sačuvane kredencijale
  Future<Map<String, String>?> getSavedCredentials() async {
    final phone = await _secureStorage.read(key: _keySavedPhone);
    final secret = await _secureStorage.read(key: _keySavedSecret);
    if (phone == null || secret == null || phone.isEmpty || secret.isEmpty) return null;
    return {'phone': phone, 'secret': secret};
  }

  // Obriši sačuvane kredencijale
  Future<void> clearCredentials() async {
    await _secureStorage.delete(key: _keySavedPhone);
    await _secureStorage.delete(key: _keySavedSecret);
    await _secureStorage.delete(key: _keySmsLoginPhone);
    await setBiometricEnabled(false);
    await setRememberMeEnabled(false);
  }

  // Autentifikacija biometrijom
  Future<bool> authenticate({String reason = 'Potvrdite identitet za pristup'}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          sensitiveTransaction: false,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  // Dohvati tip biometrije i odgovarajuću ikonu
  Future<({String text, IconData icon})> getBiometricInfo() async {
    try {
      final types = await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.face)) {
        return (text: 'Face ID', icon: Icons.face_retouching_natural);
      } else if (types.contains(BiometricType.fingerprint)) {
        return (text: 'otisak prsta', icon: Icons.fingerprint);
      } else if (types.contains(BiometricType.iris)) {
        return (text: 'iris skeniranje', icon: Icons.remove_red_eye_outlined);
      }
    } catch (_) {}
    return (text: 'biometriju', icon: Icons.fingerprint);
  }

  // Samo tekst tipa
  Future<String> getBiometricTypeText() async {
    final info = await getBiometricInfo();
    return info.text;
  }

  // Samo ikona
  Future<IconData> getBiometricIcon() async {
    final info = await getBiometricInfo();
    return info.icon;
  }
}
