import 'package:flutter/material.dart';
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

/// 📞 V3TelefonHelper — pozivi/SMS preko sistemskih intent-a (bez CALL_PHONE / SEND_SMS).
///
/// Play Store: `tel:` i `sms:` otvaraju dialer/SMS app — nije potrebna osetljiva
/// phone/SMS permisija u manifestu.
class V3TelefonHelper {
  V3TelefonHelper._();

  // ─── TELEFON POZIVI ─────────────────────────────────────────────────────

  /// Otvara sistemski dialer sa brojem (bez CALL_PHONE permisije).
  static Future<void> pozovi(State state, BuildContext context, String broj) async {
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

  /// Isto kao [pozovi] — zadržano radi postojećih poziva.
  static Future<void> pozoviBrzo(State state, BuildContext context, String broj) => pozovi(state, context, broj);

  // ─── SMS PORUKE ─────────────────────────────────────────────────────────

  /// Otvara SMS app sa brojem i porukom (bez SEND_SMS permisije).
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

  static String formatPhone(String phone) {
    final normalized = V3PhoneUtils.normalize(phone);
    if (normalized.startsWith('+381')) {
      final broj = normalized.substring(4);
      if (broj.length >= 8) {
        return '${broj.substring(0, 3)} ${broj.substring(3, 6)} ${broj.substring(6)}';
      }
    }
    return phone;
  }
}
