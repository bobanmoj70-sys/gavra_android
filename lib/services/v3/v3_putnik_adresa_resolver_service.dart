import '../../models/v3_putnik.dart';

/// Bira tačan adresa_id iz V3Putnik modela na osnovu grada i opcija.
class V3PutnikAdresaResolverService {
  V3PutnikAdresaResolverService._();

  /// Vraća adresa_id za putnika na osnovu grada, override-a i sekundarne adrese.
  ///
  /// Logika:
  /// 1. Ako postoji adresaIdOverride — koristi njega
  /// 2. Ako koristiSekundarnu == true — bira sekundarnu adresu za grad
  /// 3. Inače — bira primarnu adresu za grad
  static String? resolveAdresaIdFromPutnikModel({
    required V3Putnik putnik,
    required String grad,
    bool koristiSekundarnu = false,
    String adresaIdOverride = '',
  }) {
    final override = adresaIdOverride.trim();
    if (override.isNotEmpty) return override;

    final g = grad.trim().toUpperCase();

    if (koristiSekundarnu) {
      switch (g) {
        case 'BC':
          return putnik.adresaBcId2;
        case 'VS':
          return putnik.adresaVsId2;
      }
    }

    switch (g) {
      case 'BC':
        return putnik.adresaBcId;
      case 'VS':
        return putnik.adresaVsId;
      default:
        return null;
    }
  }
}
