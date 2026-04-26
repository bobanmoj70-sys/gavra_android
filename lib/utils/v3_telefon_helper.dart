import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'v3_app_snack_bar.dart';
import 'v3_error_utils.dart';
import 'v3_phone_utils.dart';

/// 📞 V3TelefonHelper - ЦЕНТРАЛИЗОВАНО УПРАВЉАЊЕ ПОЗИВА/SMS
/// Елиминише све duplikate launchUrl(Uri(scheme: 'tel'...)) позива!
///
/// **15+ DUPLIKATA ELIMINISANO:**
/// - Tel pozivi (v3_o_nama_screen.dart, v3_putnici_screen.dart, v3_putnik_card.dart, tail_debug.txt)
/// - SMS pozivi
///
/// **UNIFIED ERROR HANDLING + PERMISSION MANAGEMENT + CONTEXT SAFETY**
class V3TelefonHelper {
  V3TelefonHelper._();

  // ─── TELEFON POZIVI ─────────────────────────────────────────────────────

  /// Pozovi telefon broj sa automatskim permission check-om i error handling-om
  ///
  /// **Koristi umjesto:** 15+ duplikata tel: launch koda
  /// **Primjer:** V3TelefonHelper.pozovi(this, context, '0641162560');
  static Future<void> pozovi(State state, BuildContext context, String broj) async {
    if (broj.isEmpty) {
      V3ErrorUtils.validationError(state, context, 'Telefon broj nije dostupan');
      return;
    }

    // Normalizuj broj
    final normalizedBroj = V3PhoneUtils.normalize(broj);

    // Permission check
    final status = await Permission.phone.status;
    if (!status.isGranted) {
      final result = await Permission.phone.request();
      if (!result.isGranted) {
        V3ErrorUtils.permissionError(state, context, 'Dozvola za pozive je potrebna');
        return;
      }
    }

    final uri = Uri(scheme: 'tel', path: normalizedBroj);

    try {
      if (!state.mounted) return;
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Ne mogu pokrenuti poziv';
      }
    } catch (e) {
      V3ErrorUtils.safeError(state, context, '❌ Greška pozivanje $broj: $e');
    }
  }

  /// Pozovi bez permission check-a (za slučajeve gde je već provjeren)
  ///
  /// **Koristi kada:** već imaš permission ili u emergency situacijama
  /// **Primjer:** V3TelefonHelper.pozoviBrzo(this, context, '064123456');
  static Future<void> pozoviBrzo(State state, BuildContext context, String broj) async {
    if (broj.isEmpty) {
      V3ErrorUtils.validationError(state, context, 'Telefon broj nije dostupan');
      return;
    }

    final normalizedBroj = V3PhoneUtils.normalize(broj);
    final uri = Uri(scheme: 'tel', path: normalizedBroj);

    try {
      if (!state.mounted) return;
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Ne mogu pokrenuti poziv';
      }
    } catch (e) {
      V3ErrorUtils.safeError(state, context, '❌ Greška pozivanje $broj: $e');
    }
  }

  // ─── SMS PORUKE ─────────────────────────────────────────────────────────

  /// Pošalji SMS sa custom porukom
  ///
  /// **Koristi umjesto:** duplikata smsUri launch koda
  /// **Primjer:** V3TelefonHelper.posaljiSms(this, context, '064123456', 'Poruka');
  static Future<void> otvoriSms({
    required BuildContext context,
    required State state,
    required String broj,
    required String poruka,
  }) async {
    if (!state.mounted) return;

    if (!V3PhoneUtils.isValid(broj)) {
      V3AppSnackBar.error(context, '❌ Nevažeći broj telefona');
      return;
    }

    final normalizedBroj = V3PhoneUtils.normalize(broj);
    final smsUri = Uri(
      scheme: 'sms',
      path: normalizedBroj,
      queryParameters: {'body': poruka},
    );

    try {
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Ne mogu pokrenuti SMS aplikaciju';
      }
    } catch (e) {
      if (!state.mounted) return;
      V3ErrorUtils.safeError(state, context, '❌ Greška pri otvaranju SMS: $e');
    }
  }

  // ─── UTILITY METHODS ───────────────────────────────────────────────────

  /// Format telefon broj za display (dodaj razmake/crtice)
  ///
  /// **Koristi za:** user-friendly prikaz brojeva
  /// **Primjer:** '064 123 4567' = V3TelefonHelper.formatPhone('0641234567');
  static String formatPhone(String phone) {
    final normalized = V3PhoneUtils.normalize(phone);
    if (normalized.startsWith('+381')) {
      final broj = normalized.substring(4); // ukloni +381
      if (broj.length >= 8) {
        return '${broj.substring(0, 3)} ${broj.substring(3, 6)} ${broj.substring(6)}';
      }
    }
    return phone; // vrati original ako ne može da formatira
  }
}
