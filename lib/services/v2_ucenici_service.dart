import '../models/v2_registrovani_putnik.dart';
import '../models/v2_ucenik.dart';
import 'v2_profil_service.dart';

/// Servis za učenike (v2_ucenici tabela).
/// Delegira na V2ProfilService sa fiksnom tabelom 'v2_ucenici'.
class V2UceniciService {
  V2UceniciService._();

  static const String _tabela = 'v2_ucenici';

  // ---------------------------------------------------------------------------
  // CITANJE — iz RM cache-a (sync, 0 DB upita)
  // ---------------------------------------------------------------------------

  static List<V2RegistrovaniPutnik> getAktivne() => V2ProfilService.getAktivne(_tabela);

  static List<V2RegistrovaniPutnik> getSve() => V2ProfilService.getSve(_tabela);

  static V2RegistrovaniPutnik? getById(String id) => V2ProfilService.getById(id, _tabela);

  static String? getImeById(String id) => V2ProfilService.getImeById(id, _tabela);

  static V2RegistrovaniPutnik? getByPin(String pin) => V2ProfilService.getByPin(pin, _tabela);

  // ---------------------------------------------------------------------------
  // STREAM
  // ---------------------------------------------------------------------------

  static Stream<List<V2RegistrovaniPutnik>> streamAktivne() => V2ProfilService.streamAktivne(_tabela);

  // ---------------------------------------------------------------------------
  // CREATE
  // ---------------------------------------------------------------------------

  static Future<V2RegistrovaniPutnik?> create({
    required String ime,
    String? telefon,
    String? telefonOca,
    String? telefonMajke,
    String? adresaBcId,
    String? adresaVsId,
    String? pin,
    String? email,
    double? cenaPoDanu,
    int? brojMesta,
    String status = 'aktivan',
  }) =>
      V2ProfilService.createUcenik(
        ime: ime,
        telefon: telefon,
        telefonOca: telefonOca,
        telefonMajke: telefonMajke,
        adresaBcId: adresaBcId,
        adresaVsId: adresaVsId,
        pin: pin,
        email: email,
        cenaPosDanu: cenaPoDanu,
        brojMesta: brojMesta,
        status: status,
      );

  // ---------------------------------------------------------------------------
  // UPDATE / DELETE
  // ---------------------------------------------------------------------------

  static Future<bool> update(String id, Map<String, dynamic> updates) => V2ProfilService.update(id, _tabela, updates);

  static Future<bool> setStatus(String id, String status) => V2ProfilService.setStatus(id, _tabela, status);

  static Future<bool> delete(String id) => V2ProfilService.delete(id, _tabela);

  // ---------------------------------------------------------------------------
  // KONVERZIJA — V2RegistrovaniPutnik → V2Ucenik (typed model)
  // ---------------------------------------------------------------------------

  /// Vraca typed V2Ucenik model iz cache-a
  static V2Ucenik? getUcenikById(String id) {
    final row = V2ProfilService.getById(id, _tabela);
    if (row == null) return null;
    return V2Ucenik.fromJson(row.toMap());
  }

  /// Vraca sve aktivne ucenike kao typed modele
  static List<V2Ucenik> getAktivneKaoModele() => getAktivne().map((r) => V2Ucenik.fromJson(r.toMap())).toList();
}
