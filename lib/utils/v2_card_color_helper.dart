import 'package:flutter/material.dart';

import '../models/v2_putnik.dart';

/// Enum za stanja kartice putnika
enum CardState {
  odsustvo, // Godišnji/bolovanje
  otkazano, // Otkazano
  placeno, // Plaćeno/mesečno
  pokupljeno, // Pokupljeno neplaćeno
  tudji, // Tuđi V2Putnik (dodeljen drugom vozaču)
  nepokupljeno, // Nepokupljeno (default)
}

/// CARD COLOR HELPER - Centralizovana logika boja za kartice putnika
///
/// ## Prioritet boja (od najvišeg ka najnižem):
/// 1.  ŽUTO - Odsustvo (godišnji/bolovanje) - `CardState.odsustvo`
/// 2.  CRVENO - Otkazani putnici - `CardState.otkazano`
/// 3.  ZELENO - Pokupljeni plaćeni/mesečni - `CardState.placeno`
/// 4.  PLAVO - Pokupljeni neplaćeni - `CardState.pokupljeno`
/// 5.  SIVO - Tuđi V2Putnik (dodeljen drugom vozaču) - `CardState.tudji`
/// 6.  BELO - Nepokupljeni (default) - `CardState.nepokupljeno`
///
/// ## Cheat Sheet Boja:
///
/// ### POZADINA KARTICE:
/// | Stanje | Boja | Hex |
/// |--------|------|-----|
/// | Odsustvo | Svetlo žuta | #FFF59D |
/// | Otkazano | Svetlo crvena | #FFE5E5 |
/// | Placeno | Zelena | #388E3C |
/// | Pokupljeno | Svetlo plava | #7FB3D3 |
/// | Nepokupljeno | Bela 70% | #FFFFFF (alpha 0.70) |
///
/// ### TEKST:
/// | Stanje | Boja | Hex |
/// |--------|------|-----|
/// | Odsustvo | Orange | #F57C00 |
/// | Otkazano | Crvena | #EF5350 |
/// | Placeno | Zelena (successPrimary) | iz teme |
/// | Pokupljeno | Tamno plava | #0D47A1 |
/// | Nepokupljeno | Crna | #000000 |
///
/// ### BORDER:
/// | Stanje | Boja | Alpha |
/// |--------|------|-------|
/// | Odsustvo | #FFC107 | 0.6 |
/// | Otkazano | Crvena | 0.25 |
/// | Placeno | #388E3C | 0.4 |
/// | Pokupljeno | #7FB3D3 | 0.4 |
/// | Nepokupljeno | Siva | 0.10 |
///
/// ### SHADOW:
/// | Stanje | Boja | Alpha |
/// |--------|------|-------|
/// | Odsustvo | #FFC107 | 0.2 |
/// | Otkazano | Crvena | 0.08 |
/// | Placeno | #388E3C | 0.15 |
/// | Pokupljeno | #7FB3D3 | 0.15 |
/// | Nepokupljeno | Crna | 0.07 |
///
/// ## Primer korišćenja:
/// ```dart
/// final decoration = CardColorHelper.getCardDecoration(V2Putnik);
/// final textColor = CardColorHelper.getTextColorWithTheme(
/// V2Putnik,
/// context,
/// successPrimary: Theme.of(context).colorScheme.successPrimary,
/// );
/// ```
class CardColorHelper {
  // ---------------------------------------------------------------------------
  // KONSTANTE BOJA
  // ---------------------------------------------------------------------------

  // ODSUSTVO (godišnji/bolovanje) - NAJVEĆI PRIORITET
  static const Color odsustvoBackground = Color(0xFFFFF59D);
  static const Color odsusuvoBorder = Color(0xFFFFC107);
  static const Color odsustvoText = Color(0xFFF57C00); // Colors.orange[700]

  // OTKAZANO - DRUGI PRIORITET
  static const Color otkazanoBackground = Color(0xFFEF9A9A); // Red[200] - tamnija crvena
  static const Color otkazanoBorder = Colors.red;
  static const Color otkazanoText = Color(0xFFEF5350); // Colors.red[400]

  // PLACENO/MESECNO - TREĆI PRIORITET
  static const Color placenoBackground = Color(0xFF388E3C);
  static const Color placenoBorder = Color(0xFF388E3C);

  // POKUPLJENO NEPLACENO - ČETVRTI PRIORITET
  static const Color pokupljenoBackground = Color(0xFF7FB3D3);
  static const Color pokupljenoBorder = Color(0xFF7FB3D3);
  static const Color pokupljenoText = Color(0xFF0D47A1);

  // TUĐI V2Putnik (dodeljen drugom vozaču)
  static const Color tudjiBackground = Color(0xFF9E9E9E); // Grey[500]
  static const Color tudjiBorder = Color(0xFF757575); // Grey[600]
  static const Color tudjiText = Color(0xFF424242); // Grey[800]

  // NEPOKUPLJENO - DEFAULT
  static const Color defaultBackground = Colors.white;
  static const Color defaultBorder = Colors.grey;
  static const Color defaultText = Colors.black;

  // ---------------------------------------------------------------------------
  // STANJE PUTNIKA
  // ---------------------------------------------------------------------------

  /// Enum za stanje kartice sa proverom vozaca (za sivu boju)
  /// [currentDriver] - ime trenutnog vozaca koji gleda listu
  static CardState getCardStateWithDriver(V2Putnik putnik, String currentDriver) {
    // Provera po prioritetu - odsustvo i otkazano imaju najveci prioritet
    if (putnik.jeOdsustvo) {
      return CardState.odsustvo;
    }
    if (putnik.jeOtkazan) {
      return CardState.otkazano;
    }
    if (putnik.jePokupljen) {
      // PRAVI FIX: Proveravamo `placeno` polje umesto iznosa
      final bool isPlaceno = putnik.placeno == true;
      final bool isMesecniTip = putnik.isMesecniTip;
      if (isPlaceno || isMesecniTip) {
        return CardState.placeno;
      }
      return CardState.pokupljeno;
    }
    // TUĐI putnik: ima vozaca, vozac nije trenutni i nije "Nedodeljen"
    if (putnik.dodeljenVozac != null &&
        putnik.dodeljenVozac!.isNotEmpty &&
        putnik.dodeljenVozac != 'Nedodeljen' &&
        putnik.dodeljenVozac != currentDriver) {
      return CardState.tudji;
    }
    return CardState.nepokupljeno;
  }

  // ---------------------------------------------------------------------------
  // BORDER KARTICE
  // ---------------------------------------------------------------------------

  /// Vraca BoxDecoration kartice SA proverom vozaca
  BoxDecoration getCardDecorationWithDriver(V2Putnik putnik, String currentDriver) {
    final state = getCardStateWithDriver(putnik, currentDriver);
    final gradient = _getGradientForState(state);

    return BoxDecoration(
      gradient: gradient,
      color: gradient == null ? _getBackgroundForState(state) : null,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: _getBorderForState(state),
        width: _getBorderWidthForState(state),
      ),
      boxShadow: [
        BoxShadow(
          color: _getShadowForState(state),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  /// Vraca boju teksta SA proverom vozaca
  Color getTextColorWithDriver(
    V2Putnik putnik,
    String currentDriver,
    BuildContext context, {
    required Color successPrimary,
  }) {
    final state = getCardStateWithDriver(putnik, currentDriver);
    return _getTextForState(state, successPrimary);
  }

  /// Vraca sekundarnu boju teksta SA proverom vozaca
  Color getSecondaryTextColorWithDriver(V2Putnik putnik, String currentDriver) {
    final state = getCardStateWithDriver(putnik, currentDriver);
    return _getSecondaryTextForState(state);
  }

  // ---------------------------------------------------------------------------
  // PRIVATNE HELPER METODE ZA STATE
  // ---------------------------------------------------------------------------

  Color _getBackgroundForState(CardState state) {
    switch (state) {
      case CardState.odsustvo:
        return odsustvoBackground;
      case CardState.otkazano:
        return otkazanoBackground;
      case CardState.placeno:
        return placenoBackground;
      case CardState.pokupljeno:
        return pokupljenoBackground;
      case CardState.tudji:
        return tudjiBackground;
      case CardState.nepokupljeno:
        return defaultBackground.withOpacity(0.70);
    }
  }

  Gradient? _getGradientForState(CardState state) {
    switch (state) {
      case CardState.odsustvo:
        return LinearGradient(
          colors: [
            Colors.white.withOpacity(0.98),
            odsustvoBackground,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case CardState.otkazano:
        return LinearGradient(
          colors: [
            Colors.white.withOpacity(0.98),
            otkazanoBackground,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case CardState.placeno:
        return LinearGradient(
          colors: [
            Colors.white.withOpacity(0.98),
            placenoBackground,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case CardState.pokupljeno:
        return LinearGradient(
          colors: [
            Colors.white.withOpacity(0.98),
            pokupljenoBackground,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case CardState.tudji:
        return LinearGradient(
          colors: [
            const Color(0xFFBDBDBD), // Colors.grey[400]
            const Color(0xFF9E9E9E), // Colors.grey[500]
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case CardState.nepokupljeno:
        return LinearGradient(
          colors: [
            Colors.white.withOpacity(0.98),
            Colors.white.withOpacity(0.98),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  Color _getBorderForState(CardState state) {
    switch (state) {
      case CardState.odsustvo:
        return odsusuvoBorder.withOpacity(0.6);
      case CardState.otkazano:
        return otkazanoBorder.withOpacity(0.25);
      case CardState.placeno:
        return placenoBorder.withOpacity(0.4);
      case CardState.pokupljeno:
        return pokupljenoBorder.withOpacity(0.4);
      case CardState.tudji:
        return tudjiBorder;
      case CardState.nepokupljeno:
        return defaultBorder.withOpacity(0.10);
    }
  }

  double _getBorderWidthForState(CardState state) {
    return 1.2;
  }

  Color _getShadowForState(CardState state) {
    switch (state) {
      case CardState.odsustvo:
        return odsusuvoBorder.withOpacity(0.2);
      case CardState.otkazano:
        return otkazanoBorder.withOpacity(0.08);
      case CardState.placeno:
        return placenoBorder.withOpacity(0.15);
      case CardState.pokupljeno:
        return pokupljenoBorder.withOpacity(0.15);
      case CardState.tudji:
        return tudjiBorder.withOpacity(0.15);
      case CardState.nepokupljeno:
        return Colors.black.withOpacity(0.07);
    }
  }

  Color _getTextForState(CardState state, Color successPrimary) {
    switch (state) {
      case CardState.odsustvo:
        return odsustvoText;
      case CardState.otkazano:
        return otkazanoText;
      case CardState.placeno:
        return successPrimary;
      case CardState.pokupljeno:
        return pokupljenoText;
      case CardState.tudji:
        return tudjiText;
      case CardState.nepokupljeno:
        return defaultText;
    }
  }

  Color _getSecondaryTextForState(CardState state) {
    switch (state) {
      case CardState.odsustvo:
        return const Color(0xFFFF9800).withOpacity(0.8);
      case CardState.otkazano:
        return const Color(0xFFE57373).withOpacity(0.8);
      case CardState.placeno:
        return const Color(0xFF4CAF50).withOpacity(0.8);
      case CardState.pokupljeno:
        return pokupljenoText.withOpacity(0.8);
      case CardState.tudji:
        return const Color(0xFF757575).withOpacity(0.8);
      case CardState.nepokupljeno:
        return const Color(0xFF757575).withOpacity(0.8);
    }
  }
}
