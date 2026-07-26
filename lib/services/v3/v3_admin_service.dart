import '../../models/v3_vozac.dart';
import 'v3_vozac_service.dart';

/// Centralizovana provera role/privilegija za celu aplikaciju.
///
/// Rola se čita iz baze (`v3_auth.uloga`), NE iz hardkodovane liste u kodu —
/// admin/dispečer se mogu dodeliti kroz bazu, bez potrebe za novim build-om.
///
/// Ovo je JEDINI izvor istine (single source of truth) za role provere —
/// koristi se od logovanja pa nadalje (rutiranje posle logina, home screen
/// meni, ulazak u [V3AdminScreen] i svaki dublji admin ekran/akcija).
///
/// Admin/dispečer nalozi su UVEK i vozači (`tip='vozac'`, imaju
/// [V3VozacService.currentVozac] popunjen), pa automatski zadržavaju sve
/// "vozačke" funkcije. Ova klasa samo dodaje proveru privilegije iznad toga.
class V3AdminService {
  V3AdminService._();

  static const String roleVozac = 'vozac';
  static const String roleAdmin = 'admin';
  static const String roleDispecer = 'dispecer';
  static const String rolePutnik = 'putnik';

  /// Sve dostupne role za vozac-tip naloge (za budući admin UI za dodelu uloga).
  /// [rolePutnik] se NE dodeljuje kroz ovaj UI — to je automatska uloga
  /// putnik-tip naloga i ne prolazi kroz [setUloga].
  static const List<String> allRoles = <String>[roleVozac, roleAdmin, roleDispecer];

  static String _rolaOf(V3Vozac? vozac) {
    final uloga = vozac?.uloga.trim() ?? '';
    return uloga.isEmpty ? roleVozac : uloga;
  }

  /// True ako je trenutno ulogovani vozač admin.
  static bool get isCurrentUserAdmin => isAdmin(V3VozacService.currentVozac);

  /// True ako je trenutno ulogovani vozač dispečer.
  static bool get isCurrentUserDispecer => isDispecer(V3VozacService.currentVozac);

  /// True ako trenutni korisnik sme na Home operativnu tablu (admin ili dispečer).
  static bool get canCurrentUserAccessHome => canAccessHome(V3VozacService.currentVozac);

  static bool isAdmin(V3Vozac? vozac) => _rolaOf(vozac) == roleAdmin;

  static bool isDispecer(V3Vozac? vozac) => _rolaOf(vozac) == roleDispecer;

  /// Admin i dispečer imaju pristup zajedničkoj operativnoj tabli (Home).
  /// Dispečer NE dobija admin panel (to se kontroliše preko [isAdmin] posebno).
  static bool canAccessHome(V3Vozac? vozac) => isAdmin(vozac) || isDispecer(vozac);

  /// True ako dati v3_auth id (iz keša vozača) pripada adminu.
  /// Koristi se kad nemamo direktno [V3Vozac] objekat pri ruci.
  static bool isAdminId(String? vozacId) => isAdmin(_lookup(vozacId));

  static bool canAccessHomeById(String? vozacId) => canAccessHome(_lookup(vozacId));

  static V3Vozac? _lookup(String? vozacId) {
    final id = vozacId?.trim() ?? '';
    if (id.isEmpty) return null;
    return V3VozacService.getVozacById(id);
  }

  /// Ažurira ulogu vozača u bazi (za budući admin ekran "Upravljanje ulogama").
  static Future<void> setUloga({required String vozacId, required String uloga}) async {
    if (!allRoles.contains(uloga)) {
      throw ArgumentError('Nepoznata uloga: $uloga');
    }
    await V3VozacService.updateUloga(vozacId: vozacId, uloga: uloga);
  }
}
