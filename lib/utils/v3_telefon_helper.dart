import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_translations.dart';
import '../services/v3_locale_manager.dart';
import 'v3_app_snack_bar.dart';
import 'v3_error_utils.dart';
import 'v3_phone_utils.dart';

String _telefonTr(String key) {
  final code = V3LocaleManager().currentLocale.languageCode;
  final t = AppTranslations.ns('telefonHelper');
  return t[key]?[code] ?? t[key]?['sr'] ?? key;
}

String _telefonTrf(String key, Map<String, String> params) {
  var text = _telefonTr(key);
  params.forEach((placeholder, value) {
    text = text.replaceAll('%$placeholder%', value);
  });
  return text;
}

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
  /// **Koristi umesto:** 15+ duplikata tel: launch koda
  /// **Primjer:** V3TelefonHelper.pozovi(this, context, '0641162560');
  static Future<void> pozovi(State state, BuildContext context, String broj) async {
    if (broj.isEmpty) {
      V3ErrorUtils.validationError(state, context, _telefonTr('telefonBrojNijeDostupan'));
      return;
    }

    // Normalizuj broj
    final normalizedBroj = V3PhoneUtils.normalize(broj);

    // Permission check
    final status = await Permission.phone.status;
    if (!status.isGranted) {
      final result = await Permission.phone.request();
      if (!result.isGranted) {
        V3ErrorUtils.permissionError(state, context, _telefonTr('dozvolaZaPozive'));
        return;
      }
    }

    final uri = Uri(scheme: 'tel', path: normalizedBroj);

    try {
      if (!state.mounted) return;
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw _telefonTr('neMoguPokrenutiPoziv');
      }
    } catch (e) {
      V3ErrorUtils.safeError(state, context, _telefonTrf('greskaPozivanje', {'BROJ': broj, 'ERROR': '$e'}));
    }
  }

  /// Pozovi bez permission check-a (za slučajeve gde je već provjeren)
  ///
  /// **Koristi kada:** već imaš permission ili u emergency situacijama
  /// **Primjer:** V3TelefonHelper.pozoviBrzo(this, context, '064123456');
  static Future<void> pozoviBrzo(State state, BuildContext context, String broj) async {
    if (broj.isEmpty) {
      V3ErrorUtils.validationError(state, context, _telefonTr('telefonBrojNijeDostupan'));
      return;
    }

    final normalizedBroj = V3PhoneUtils.normalize(broj);
    final uri = Uri(scheme: 'tel', path: normalizedBroj);

    try {
      if (!state.mounted) return;
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw _telefonTr('neMoguPokrenutiPoziv');
      }
    } catch (e) {
      V3ErrorUtils.safeError(state, context, _telefonTrf('greskaPozivanje', {'BROJ': broj, 'ERROR': '$e'}));
    }
  }

  // ─── SMS PORUKE ─────────────────────────────────────────────────────────

  /// Pošalji SMS sa custom porukom
  ///
  /// **Koristi umesto:** duplikata smsUri launch koda
  /// **Primjer:** V3TelefonHelper.posaljiSms(this, context, '064123456', 'Poruka');
  static Future<void> otvoriSms({
    required BuildContext context,
    required State state,
    required String broj,
    required String poruka,
  }) async {
    if (!state.mounted) return;

    if (!V3PhoneUtils.isValid(broj)) {
      V3AppSnackBar.error(context, _telefonTr('nevaziciBrojTelefona'));
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
        throw _telefonTr('neMoguPokrenutiSms');
      }
    } catch (e) {
      if (!state.mounted) return;
      V3ErrorUtils.safeError(state, context, _telefonTrf('greskaPriOtvaranjuSms', {'ERROR': '$e'}));
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
