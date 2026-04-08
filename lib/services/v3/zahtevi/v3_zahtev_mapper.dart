import 'v3_zahtev_types.dart';

class V3ZahtevMapper {
  V3ZahtevMapper._();

  static Map<String, dynamic> patchToDb(V3ZahtevPatch patch) {
    return {
      if (patch.status != null) 'status': patch.status!.name,
      if (patch.zeljenoVreme != null) 'trazeni_polazak_at': patch.zeljenoVreme,
      if (patch.dodeljenoVreme != null) 'polazak_at': patch.dodeljenoVreme,
      if (patch.altVremePre != null) 'alternativa_pre_at': patch.altVremePre,
      if (patch.altVremePosle != null) 'alternativa_posle_at': patch.altVremePosle,
      if (patch.koristiSekundarnu != null) 'koristi_sekundarnu': patch.koristiSekundarnu,
      if (patch.adresaIdOverride != null) 'adresa_override_id': patch.adresaIdOverride,
    };
  }
}
