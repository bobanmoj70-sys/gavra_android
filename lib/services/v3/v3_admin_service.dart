import 'v3_app_update_service.dart';
import 'v3_vozac_service.dart';

/// Centralizovana provera admin autorizacije za celu aplikaciju.
///
/// Ovo je JEDINI izvor istine (single source of truth) za "da li je trenutni
/// korisnik admin" — koristi se od logovanja pa nadalje (home screen meni,
/// ulazak u [V3AdminScreen] i svaki dublji admin ekran/akcija).
///
/// Admin nalog je UVEK i vozač (ima [V3VozacService.currentVozac] popunjen),
/// pa admin automatski zadržava sve "vozačke" funkcije. Ova klasa samo
/// dodaje dodatnu proveru privilegije iznad toga — ne menja niti ograničava
/// vozačke/putničke funkcije.
class V3AdminService {
  V3AdminService._();

  /// v3_auth.id vrednosti koje imaju admin privilegije.
  static const Set<String> adminUserIds = <String>{
    V3AppUpdateService.bojanUserId,
  };

  /// True ako je trenutno ulogovani vozač admin nalog.
  static bool get isCurrentUserAdmin => isAdminId(V3VozacService.currentVozac?.id);

  /// True ako dati v3_auth id pripada adminu.
  static bool isAdminId(String? vozacId) {
    final id = vozacId?.trim() ?? '';
    return id.isNotEmpty && adminUserIds.contains(id);
  }
}
