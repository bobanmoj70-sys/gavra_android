import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'v3_app_snack_bar.dart';
import 'v3_error_utils.dart';
import 'v3_phone_utils.dart';
import 'v3_state_utils.dart';

/// 📞 V3TelefonHelper - ЦЕНТРАЛИЗОВАНО УПРАВЉАЊЕ ПОЗИВА/SMS/EMAIL
/// Елиминише све duplikate launchUrl(Uri(scheme: 'tel'...)) позива!
///
/// **15+ DUPLIKATA ELIMINISANO:**
/// - Tel pozivi (v3_o_nama_screen.dart, v3_putnici_screen.dart, v3_putnik_card.dart, tail_debug.txt)
/// - SMS pozivi (v3_pin_zahtevi_screen.dart, _pinPosaljiSms funkcija)
/// - Email pozivi (v3_o_nama_screen.dart)
/// - Maps pozivi (v3_vozac_screen.dart, v3_o_nama_screen.dart, v3_putnik_card.dart)
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

    final uri = Uri(scheme: 'tel', path: normalizedBroj.replaceFirst('+', ''));

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
    final uri = Uri(scheme: 'tel', path: normalizedBroj.replaceFirst('+', ''));

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
  /// **Primjer:** V3TelefonHelper.posaljiSms(this, context, '064123456', 'Vaš PIN: 1234');
  static Future<void> posaljiSms(State state, BuildContext context, String broj, String poruka) async {
    if (broj.isEmpty) {
      V3ErrorUtils.validationError(state, context, 'Telefon broj nije dostupan');
      return;
    }

    final normalizedBroj = V3PhoneUtils.normalize(broj);
    final smsUri = Uri(
      scheme: 'sms',
      path: normalizedBroj.replaceFirst('+', ''),
      queryParameters: {'body': poruka},
    );

    try {
      if (!state.mounted) return;
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri, mode: LaunchMode.externalApplication);
      } else {
        V3StateUtils.safeSetState(state, () {
          V3AppSnackBar.warning(context, 'Ne mogu da otvorim SMS aplikaciju');
        });
      }
    } catch (e) {
      V3ErrorUtils.safeError(state, context, '❌ Greška pri otvaranju SMS: $e');
    }
  }

  /// Pošalji PIN SMS sa standardnom Gavra 013 porukom
  ///
  /// **Koristi umjesto:** _pinPosaljiSms duplikata
  /// **Primjer:** V3TelefonHelper.posaljiPin(this, context, '064123456', '1234', 'Marko Marković');
  static Future<void> posaljiPin(State state, BuildContext context, String broj, String pin, String ime) async {
    final poruka = 'Vaš PIN za aplikaciju Gavra 013 je: $pin\n\n'
        'Koristite ovaj PIN zajedno sa brojem telefona za pristup.\n'
        '- Gavra 013';

    await posaljiSms(state, context, broj, poruka);
  }

  // ─── EMAIL POZIVI ───────────────────────────────────────────────────────

  /// Otvori email aplikaciju sa predefined email adresom
  ///
  /// **Koristi umjesto:** mailto: launch duplikata
  /// **Primjer:** V3TelefonHelper.posaljiEmail(this, context, 'gavriconi19@gmail.com');
  static Future<void> posaljiEmail(State state, BuildContext context, String email) async {
    if (email.isEmpty) {
      V3ErrorUtils.validationError(state, context, 'Email adresa nije dostupna');
      return;
    }

    final uri = Uri(scheme: 'mailto', path: email);

    try {
      if (!state.mounted) return;
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        V3StateUtils.safeSetState(state, () {
          V3AppSnackBar.error(context, 'Ne mogu da otvorim email aplikaciju');
        });
      }
    } catch (e) {
      V3ErrorUtils.safeError(state, context, '❌ Greška pri otvaranju emaila: $e');
    }
  }

  // ─── MAPS I NAVIGACIJA ──────────────────────────────────────────────────

  /// Otvori HERE WeGo navigaciju do specifične lokacije
  ///
  /// **Koristi umjesto:** here-route:// launch duplikata
  /// **Primjer:** V3TelefonHelper.navigirajDo(this, context, 44.8983, 21.4152);
  static Future<void> navigirajDo(State state, BuildContext context, double lat, double lng) async {
    // Pokušaj HERE WeGo prvo
    final hereUrl = Uri.parse('here-route://mylocation/$lat,$lng/now');

    try {
      if (!state.mounted) return;
      if (await canLaunchUrl(hereUrl)) {
        await launchUrl(hereUrl, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (e) {
      debugPrint('[V3TelefonHelper] HERE WeGo nedostupan: $e');
    }

    // Fallback na web HERE
    final webHereUrl = Uri.parse('https://wego.here.com/directions/drive/mypos/$lat,$lng');

    try {
      if (!state.mounted) return;
      if (await canLaunchUrl(webHereUrl)) {
        await launchUrl(webHereUrl, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (e) {
      debugPrint('[V3TelefonHelper] Web HERE nedostupan: $e');
    }

    // Poslednji fallback - Google Maps
    final googleUrl = Uri.parse('https://maps.google.com/?q=$lat,$lng');

    try {
      if (!state.mounted) return;
      if (await canLaunchUrl(googleUrl)) {
        await launchUrl(googleUrl, mode: LaunchMode.externalApplication);
      } else {
        V3StateUtils.safeSetState(state, () {
          V3AppSnackBar.error(context, 'Ne mogu da otvorim aplikaciju za mape');
        });
      }
    } catch (e) {
      V3ErrorUtils.safeError(state, context, '❌ Greška pri otvaranju mapa: $e');
    }
  }

  /// Otvori HERE WeGo sa specifičnom adresom ili URL-om
  ///
  /// **Koristi umjesto:** Uri.parse(url) launch duplikata
  /// **Primjer:** V3TelefonHelper.otvoriMaps(this, context, 'https://share.here.com/r/44.8983,21.4152');
  static Future<void> otvoriMaps(State state, BuildContext context, String urlOrAddress) async {
    final uri = Uri.tryParse(urlOrAddress);
    if (uri == null) {
      V3ErrorUtils.validationError(state, context, 'Neispravna maps adresa');
      return;
    }

    try {
      if (!state.mounted) return;
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        V3StateUtils.safeSetState(state, () {
          V3AppSnackBar.error(context, 'Ne mogu da otvorim aplikaciju za mape');
        });
      }
    } catch (e) {
      V3ErrorUtils.safeError(state, context, '❌ Greška pri otvaranju mapa: $e');
    }
  }

  // ─── MULTI-DESTINATION NAVIGACIJA ──────────────────────────────────────

  /// Kreiraj HERE WeGo multi-stop rutu iz liste koordinata
  ///
  /// **Koristi umjesto:** ručnog pravljenja waypoints URL-a
  /// **Primjer:** V3TelefonHelper.navigirajMultiStop(this, context, [(44.89, 21.41), (44.90, 21.42)]);
  static Future<void> navigirajMultiStop(State state, BuildContext context, List<(double, double)> waypoints) async {
    if (waypoints.isEmpty) {
      V3ErrorUtils.validationError(state, context, 'Nema destinacija za navigaciju');
      return;
    }

    final waypointsBuffer = StringBuffer('https://wego.here.com/directions/drive/');
    for (int i = 0; i < waypoints.length; i++) {
      final (lat, lng) = waypoints[i];
      if (i == 0) {
        waypointsBuffer.write('mylocation/');
      }
      waypointsBuffer.write('$lat,$lng');
      if (i < waypoints.length - 1) waypointsBuffer.write('/');
    }

    await otvoriMaps(state, context, waypointsBuffer.toString());
  }

  // ─── UTILITY METHODS ───────────────────────────────────────────────────

  /// Provjeri da li je telefon broj valjan
  ///
  /// **Koristi za:** validaciju pre poziva
  /// **Primjer:** if (V3TelefonHelper.isValidPhone('064123456')) { ... }
  static bool isValidPhone(String? phone) {
    if (phone == null || phone.trim().isEmpty) return false;
    return V3PhoneUtils.isValid(phone);
  }

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
