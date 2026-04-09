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
  final String? trazeniPolazakAt;
  final String? polazakAt;
  final String? altVremePre;
  final String? altVremePosle;
  final bool? koristiSekundarnu;
  final String? adresaIdOverride;

  const V3ZahtevPatch({
    required this.id,
    this.status,
    this.trazeniPolazakAt,
    this.polazakAt,
    this.altVremePre,
    this.altVremePosle,
    this.koristiSekundarnu,
    this.adresaIdOverride,
  });
}
