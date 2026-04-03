import 'v3_zahtev_types.dart';

class V3ZahtevMapper {
  V3ZahtevMapper._();

  static Map<String, dynamic> patchToDb(V3ZahtevPatch patch) {
    return {
      if (patch.status != null) 'status': patch.status!.name,
      if (patch.zeljenoVreme != null) 'zeljeno_vreme': patch.zeljenoVreme,
      if (patch.dodeljenoVreme != null) 'dodeljeno_vreme': patch.dodeljenoVreme,
      if (patch.altVremePre != null) 'alt_vreme_pre': patch.altVremePre,
      if (patch.altVremePosle != null) 'alt_vreme_posle': patch.altVremePosle,
      if (patch.altNapomena != null) 'alt_napomena': patch.altNapomena,
      if (patch.koristiSekundarnu != null) 'koristi_sekundarnu': patch.koristiSekundarnu,
      if (patch.adresaIdOverride != null) 'adresa_id_override': patch.adresaIdOverride,
    };
  }
}
