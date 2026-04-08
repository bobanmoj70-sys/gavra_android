import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Rezultat slanja SMS verifikacionog koda
class SmsSendResult {
  final bool success;
  final bool autoVerified;
  final String? verificationId;
  final String? errorMessage;

  const SmsSendResult._({
    required this.success,
    this.autoVerified = false,
    this.verificationId,
    this.errorMessage,
  });

  factory SmsSendResult.ok(String verificationId) => SmsSendResult._(success: true, verificationId: verificationId);

  factory SmsSendResult.autoVerified() => const SmsSendResult._(success: true, autoVerified: true);

  factory SmsSendResult.fail(String message) => SmsSendResult._(success: false, errorMessage: message);
}

/// Rezultat verifikacije OTP koda
class OtpVerifyResult {
  final bool success;
  final String? errorMessage;

  const OtpVerifyResult._({required this.success, this.errorMessage});

  factory OtpVerifyResult.ok() => const OtpVerifyResult._(success: true);

  factory OtpVerifyResult.fail(String message) => OtpVerifyResult._(success: false, errorMessage: message);
}

/// Firebase Phone Auth servis za SMS verifikaciju putnika.
///
/// Flow:
/// 1. [sendSmsCode] → pošalje SMS, vrati [SmsSendResult] sa verificationId
/// 2. [verifySmsCode] → provjeri OTP kod, vrati [OtpVerifyResult]
class V3FirebaseSmsService {
  V3FirebaseSmsService._();

  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static const bool _appVerificationTestingMode = bool.fromEnvironment(
    'FIREBASE_APP_VERIFICATION_DISABLED_FOR_TESTING',
    defaultValue: false,
  );

  static Future<void> _configureAppVerification() async {
    try {
      await _auth.setSettings(
        appVerificationDisabledForTesting: _appVerificationTestingMode,
      );
      if (_appVerificationTestingMode) {
        debugPrint('[SMS] UPOZORENJE: app verification testing mode je UKLJUČEN.');
      }
    } catch (e) {
      debugPrint('[SMS] Ne mogu da primenim app verification podešavanje: $e');
    }
  }

  // ─── Slanje SMS koda ────────────────────────────────────────────

  /// Šalje SMS verifikacioni kod na [phoneNumber] (u +381 formatu).
  /// Vraća [SmsSendResult.ok] sa verificationId ili [SmsSendResult.fail] sa porukom.
  static Future<SmsSendResult> sendSmsCode({
    required String phoneNumber,
    required void Function(String message) onStatusUpdate,
  }) async {
    final completer = _SmsSendCompleter();

    try {
      final firebaseReady = await _ensureFirebaseInitialized();
      if (!firebaseReady) {
        return SmsSendResult.fail('Firebase nije inicijalizovan. Pokušaj ponovo za par sekundi.');
      }

      await _configureAppVerification();

      onStatusUpdate('📨 Šaljem SMS kod...');

      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),

        // ✅ Automatska verifikacija (Android samo) – retko se dešava
        verificationCompleted: (PhoneAuthCredential credential) async {
          debugPrint('[SMS] Auto-verifikacija (Android) uspešna.');
          try {
            await _auth.signInWithCredential(credential);
            if (!completer.isCompleted) {
              completer.complete(SmsSendResult.autoVerified());
            }
          } catch (e) {
            debugPrint('[SMS] Greška pri auto-verifikaciji: $e');
            if (!completer.isCompleted) {
              completer.complete(SmsSendResult.fail('Greška pri automatskoj verifikaciji: $e'));
            }
          }
        },

        // ❌ Greška pri slanju
        verificationFailed: (FirebaseAuthException e) {
          debugPrint('[SMS] Greška pri slanju: ${e.code} - ${e.message}');
          final msg = _mapFirebaseError(e.code);
          completer.complete(SmsSendResult.fail(msg));
        },

        // 📨 SMS uspešno poslat
        codeSent: (String verificationId, int? resendToken) {
          debugPrint('[SMS] Kod poslat.');
          onStatusUpdate('✅ SMS kod je poslat!');
          completer.complete(SmsSendResult.ok(verificationId));
        },

        // ⏱️ Timeout
        codeAutoRetrievalTimeout: (String verificationId) {
          debugPrint('[SMS] Auto-retrieval timeout');
          // Timeout znači samo da Android auto-verify nije stigao - SMS je već ranije potvrđen
          // kroz codeSent callback, tako da ne radimo ništa ovde
          if (!completer.isCompleted) {
            // Ako smo ovde a completer nije završen, znači ni codeSent ni error nisu stigli
            completer.complete(SmsSendResult.fail('❌ Timeout: SMS nije mogao da se pošalje. Pokušaj ponovo.'));
          }
        },
      );

      return completer.future;
    } catch (e) {
      debugPrint('[SMS] Neočekivana greška: $e');
      return SmsSendResult.fail('Greška pri slanju SMS-a: $e');
    }
  }

  // ─── Verifikacija OTP koda ──────────────────────────────────────

  /// Verifikuje [smsCode] koristeći [verificationId] iz [sendSmsCode].
  /// Prijavljuje korisnika u Firebase Auth i vraća [OtpVerifyResult].
  static Future<OtpVerifyResult> verifySmsCode({
    required String verificationId,
    required String smsCode,
  }) async {
    if (smsCode.trim().length != 6) {
      return OtpVerifyResult.fail('Kod mora imati tačno 6 cifara.');
    }

    try {
      final firebaseReady = await _ensureFirebaseInitialized();
      if (!firebaseReady) {
        return OtpVerifyResult.fail('Firebase nije inicijalizovan. Pokušaj ponovo za par sekundi.');
      }

      await _configureAppVerification();

      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode.trim(),
      );

      await _auth.signInWithCredential(credential);
      debugPrint('[SMS] Verifikacija uspešna, korisnik prijavljen u Firebase.');
      return OtpVerifyResult.ok();
    } on FirebaseAuthException catch (e) {
      debugPrint('[SMS] OTP greška: ${e.code} - ${e.message}');
      return OtpVerifyResult.fail(_mapFirebaseError(e.code));
    } catch (e) {
      debugPrint('[SMS] Neočekivana greška pri verifikaciji: $e');
      return OtpVerifyResult.fail('Greška pri verifikaciji: $e');
    }
  }

  // ─── Odjava iz Firebase Auth ────────────────────────────────────

  /// Odjavljuje korisnika iz Firebase Auth (ne utiče na Supabase sesiju).
  static Future<void> signOut() async {
    try {
      final firebaseReady = await _ensureFirebaseInitialized();
      if (!firebaseReady) return;

      await _auth.signOut();
    } catch (e) {
      debugPrint('[SMS] Greška pri odjavi: $e');
    }
  }

  static Future<bool> _ensureFirebaseInitialized() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      return Firebase.apps.isNotEmpty;
    } catch (e) {
      debugPrint('[SMS] Firebase init check greška: $e');
      return false;
    }
  }

  // ─── Mapiranje grešaka ──────────────────────────────────────────

  static String _mapFirebaseError(String code) {
    switch (code) {
      case 'invalid-phone-number':
        return '❌ Neispravan format broja telefona.';
      case 'too-many-requests':
        return '❌ Previše pokušaja. Pokušaj ponovo za nekoliko minuta.';
      case 'invalid-verification-code':
        return '❌ Pogrešan kod. Proveri SMS i pokušaj ponovo.';
      case 'session-expired':
        return '❌ Kod je istekao. Zatraži novi SMS.';
      case 'quota-exceeded':
        return '❌ Dnevni limit SMS-ova je dostignut.';
      case 'network-request-failed':
        return '❌ Greška sa mrežom. Proveri internet vezu.';
      case 'missing-phone-number':
        return '❌ Unesite broj telefona.';
      default:
        return '❌ Greška: $code';
    }
  }
}

// ─── Pomoćna klasa za async completer ──────────────────────────────

class _SmsSendCompleter {
  final _completer = Completer<SmsSendResult>();
  bool get isCompleted => _completer.isCompleted;
  Future<SmsSendResult> get future => _completer.future;
  void complete(SmsSendResult result) {
    if (!_completer.isCompleted) _completer.complete(result);
  }
}
