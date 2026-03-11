import 'v2_text_utils.dart';

/// UTIL ZA VALIDACIJU GRADOVA I ADRESA
/// Ogranicava aplikaciju na opštine Bela Crkva i Vrsac
class V2GradAdresaValidator {
  V2GradAdresaValidator._();

  /// Proveri da li je grad Bela Crkva (ili BC skracenica)
  static bool isBelaCrkva(String? grad) {
    if (grad == null || grad.trim().isEmpty) return false;
    final normalized = normalizeString(grad);
    return normalized.contains('bela') || normalized == 'bc';
  }

  /// Proveri da li je grad Vrsac (ili VS skracenica)
  static bool isVrsac(String? grad) {
    if (grad == null || grad.trim().isEmpty) return false;
    final normalized = normalizeString(grad); // uvek lowercase
    return normalized == 'vs' || normalized.startsWith('vrs') || normalized.contains('vrsac');
  }

  /// JEDNOSTAVNO GRAD POREĐENJE - samo 2 glavna grada
  /// LOGIKA: Bela Crkva ili Vrsac - filtrira po gradu putnika
  /// NAPOMENA: [putnikAdresa] se trenutno ne koristi, rezervisano za buducnost
  static bool isGradMatch(
    String? putnikGrad,
    String? putnikAdresa,
    String selectedGrad,
  ) {
    if (isBelaCrkva(selectedGrad) && isBelaCrkva(putnikGrad)) {
      return true; // V2Putnik je iz Bele Crkve i selektovana je Bela Crkva
    }
    if (isVrsac(selectedGrad) && isVrsac(putnikGrad)) {
      return true; // V2Putnik je iz Vrsca i selektovan je Vrsac
    }

    return false; // Gradovi se ne poklapaju
  }

  /// Normalizuj srpske karaktere - delegira na V2TextUtils.normalizeText()
  /// Vraca lowercase string bez dijakritika.
  static String normalizeString(String? input) {
    if (input == null) return '';
    return V2TextUtils.normalizeText(input);
  }

  /// Normalizuj grad - uvek vraca 'BC' ili 'VS'
  /// Ovo je jedini ispravan nacin da se grad normalizuje u cijeloj aplikaciji.
  /// DB trigger garantuje da se u bazi uvek cuva 'BC' ili 'VS'.
  static String normalizeGrad(String? grad) {
    if (grad == null || grad.trim().isEmpty) return 'BC';
    final normalized = normalizeString(grad); // lowercase, bez dijakritika
    if (normalized == 'vs' || normalized.startsWith('vrs') || normalized.contains('vrsac')) return 'VS';
    if (normalized == 'bc' || normalized.contains('bela') || normalized.contains('crkva')) return 'BC';
    // Nepoznat grad - u debug modu upozori, u release-u fallback na BC
    assert(false, '[V2GradAdresaValidator.normalizeGrad] Nepoznat grad: "$grad" - fallback na BC');
    return 'BC';
  }

  /// Sigurno parsiranje broja iz Supabase-a (može biti num ili String).
  /// Jedino kanonsko mjesto — koristi se svuda umjesto inline double.tryParse.
  static double parseDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? 0.0;
    return 0.0;
  }

  /// Normalizuje broj telefona za poređenje — uklanja razmake/crtice/zagrade
  /// i konvertuje +381/00381 prefiks u lokalni format (06x...).
  /// Jedino kanonsko mjesto — koristi se svuda gdje se porede telefoni.
  static String normalizePhone(String telefon) {
    var cleaned = telefon.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (cleaned.startsWith('+381')) {
      cleaned = '0${cleaned.substring(4)}';
    } else if (cleaned.startsWith('00381')) {
      cleaned = '0${cleaned.substring(5)}';
    }
    return cleaned;
  }

  /// NORMALIZUJ VREME - konvertuj "05:00:00" ili "5:00" u "05:00" (HH:MM format)
  /// Delegira na TimeValidator.normalizeTimeFormat() za konzistentnost
  static String normalizeTime(String? time) {
    if (time == null || time.isEmpty) return '';
    final t = time.trim();
    // HH:MM:SS -> HH:MM
    final parts = t.split(':');
    if (parts.length >= 2) {
      final h = parts[0].padLeft(2, '0');
      final m = parts[1].padLeft(2, '0');
      return '$h:$m';
    }
    // Samo sati
    if (parts.length == 1 && int.tryParse(parts[0]) != null) {
      return '${parts[0].padLeft(2, '0')}:00';
    }
    return t;
  }
}
