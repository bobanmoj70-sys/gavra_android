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
/// - Maps pozivi (v3_vozac_screen.dart, v3_o_nama_screen.dart, v3_putnik_card.dart)
///
/// **UNIFIED ERROR HANDLING + PERMISSION MANAGEMENT + CONTEXT SAFETY**
class V3TelefonHelper {
  V3TelefonHelper._();

  static Future<void> _launchHereAppUri(
    State state,
    BuildContext context,
    Uri uri,
  ) async {
    try {
      if (!state.mounted) return;
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!state.mounted) return;
        V3AppSnackBar.warning(
          context,
          'Instalirajte HERE WeGo aplikaciju ako želite da koristite navigaciju.',
        );
      }
    } catch (e) {
      V3ErrorUtils.safeError(state, context, '❌ HERE WeGo nije dostupan: $e');
    }
  }

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

  // ─── MAPS I NAVIGACIJA ──────────────────────────────────────────────────

  /// Otvara isključivo HERE WeGo aplikaciju (bez web/Google fallback-a)
  ///
  /// Ako aplikacija nije instalirana, prikazuje poruku da je potrebno instalirati HERE WeGo.
  static Future<void> otvoriHereWeGoAppOnly(State state, BuildContext context) async {
    final hereAppUri = Uri.parse('here-route://mylocation');
    await _launchHereAppUri(state, context, hereAppUri);
  }

  /// Otvori HERE WeGo navigaciju do specifične lokacije
  ///
  /// **Koristi umjesto:** here-route:// launch duplikata
  /// **Primjer:** V3TelefonHelper.navigirajDo(this, context, 44.8983, 21.4152);
  static Future<void> navigirajDo(State state, BuildContext context, double lat, double lng) async {
    final hereUrl = Uri.parse('here-route://mylocation/$lat,$lng/now');
    await _launchHereAppUri(state, context, hereUrl);
  }

  /// Otvori HERE WeGo sa specifičnom adresom ili URL-om
  ///
  /// **Koristi umjesto:** Uri.parse(url) launch duplikata
  /// **Primjer:** V3TelefonHelper.otvoriMaps(this, context, 'https://share.here.com/r/44.8983,21.4152');
  static Future<void> otvoriMaps(State state, BuildContext context, String urlOrAddress) async {
    final input = urlOrAddress.trim();
    if (input.isEmpty) {
      V3ErrorUtils.validationError(state, context, 'Neispravna maps adresa');
      return;
    }

    final uri = Uri.tryParse(input);
    if (uri == null || uri.scheme != 'here-route') {
      if (!state.mounted) return;
      V3AppSnackBar.warning(
        context,
        'Podržan je samo HERE WeGo app link (here-route://).',
      );
      return;
    }

    await _launchHereAppUri(state, context, uri);
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

    final waypointsBuffer = StringBuffer('here-route://mylocation/');
    for (int i = 0; i < waypoints.length; i++) {
      final (lat, lng) = waypoints[i];
      waypointsBuffer.write('$lat,$lng');
      if (i < waypoints.length - 1) waypointsBuffer.write('/');
    }
    waypointsBuffer.write('/now');

    final routeUri = Uri.parse(waypointsBuffer.toString());
    await _launchHereAppUri(state, context, routeUri);
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
