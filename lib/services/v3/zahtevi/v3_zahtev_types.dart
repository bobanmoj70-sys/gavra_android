enum V3ZahtevStatus {
  obrada,
  odobreno,
  alternativa,
  otkazano,
  odbijeno,
}

class V3ZahtevPatch {
  final String id;
  final V3ZahtevStatus? status;
  final String? zeljenoVreme;
  final String? dodeljenoVreme;
  final String? altVremePre;
  final String? altVremePosle;
  final String? altNapomena;
  final bool? koristiSekundarnu;
  final String? adresaIdOverride;

  const V3ZahtevPatch({
    required this.id,
    this.status,
    this.zeljenoVreme,
    this.dodeljenoVreme,
    this.altVremePre,
    this.altVremePosle,
    this.altNapomena,
    this.koristiSekundarnu,
    this.adresaIdOverride,
  });
}
