import '../services/v2_adresa_supabase_service.dart'; // DODATO za fallback ucitavanje adrese
import '../utils/v2_dan_utils.dart';
import '../utils/v2_registrovani_helpers.dart';
import 'v2_polazak.dart'; // DODATO

class V2Putnik {
  V2Putnik({
    this.id,
    required this.ime,
    required this.polazak,
    this.pokupljen,
    this.vremeDodavanja,
    required this.dan,
    this.status,
    this.statusVreme,
    this.vremePokupljenja,
    this.vremePlacanja,
    this.placeno,
    this.cena,
    this.iznosUplate,
    this.naplatioVozac,
    this.pokupioVozac,
    this.dodeljenVozac,
    this.vozac,
    required this.grad,
    this.otkazaoVozac,
    this.vremeOtkazivanja,
    this.adresa,
    this.adresaId, // NOVO - UUID reference u tabelu adrese
    this.obrisan = false,
    this.brojTelefona,
    this.datum,
    this.brojMesta = 1,
    this.tipPutnika,
    this.otkazanZaPolazak = false,
    this.requestId,
    this.pokupioVozacId,
    this.naplatioVozacId,
    this.otkazaoVozacId,
  });

  factory V2Putnik.fromMap(Map<String, dynamic> map) {
    return V2Putnik.v2FromProfil(map);
  }

  // Centralno mapiranje tabele u tip putnika
  static String? tipIzTabele(String? tabela) {
    return switch (tabela) {
      'v2_radnici' => 'radnik',
      'v2_ucenici' => 'ucenik',
      'v2_dnevni' => 'dnevni',
      'v2_posiljke' => 'posiljka',
      _ => null,
    };
  }

  // Factory za v2 putnik profil (v2_radnici, v2_ucenici, v2_dnevni, v2_posiljke)
  factory V2Putnik.v2FromProfil(Map<String, dynamic> map) {
    final grad = _v2GradIzProfila(map);
    final tipPutnika = tipIzTabele(map['_tabela']?.toString());
    final isDnevni = tipPutnika == 'dnevni' || tipPutnika == 'posiljka';

    return V2Putnik(
      id: map['id'],
      ime: map['ime'] as String? ?? '',
      polazak: '---',
      pokupljen: false,
      vremeDodavanja: map['created_at'] != null ? DateTime.tryParse(map['created_at'] as String)?.toLocal() : null,
      dan: '',
      status: map['status'] as String? ?? 'aktivan',
      statusVreme: map['updated_at'] as String?,
      grad: grad,
      adresa: _v2AdresaNaziv(map, grad),
      adresaId: _v2AdresaId(map, grad),
      obrisan: !V2RegistrovaniHelpers.isActiveFromMap(map),
      brojTelefona: map['telefon'] as String?,
      brojMesta: (map['broj_mesta'] as num?)?.toInt() ?? 1,
      tipPutnika: tipPutnika,
    );
  }

  final dynamic id; // UUID putnika iz v2_radnici/v2_ucenici/v2_dnevni/v2_posiljke
  final String ime;
  final String polazak;
  final bool? pokupljen;
  final DateTime? vremeDodavanja; // ? DateTime
  final String dan;
  final String? status;
  final String? statusVreme;
  final DateTime? vremePokupljenja; // ? DateTime
  final DateTime? vremePlacanja; // ? DateTime
  final bool? placeno;
  final double? cena; // standardna cena iz profila (za dialog i prikaz mjesta)
  final double? iznosUplate; // stvarni iznos placanja iz v2_polasci.placen_iznos
  double? get iznosPlacanja => iznosUplate;
  final String? naplatioVozac;
  final String? pokupioVozac;
  final String? dodeljenVozac;
  final String? vozac;
  final String grad;
  final String? otkazaoVozac;
  final DateTime? vremeOtkazivanja; // NOVO - vreme kada je otkazano
  final String? adresa; // NOVO - adresa putnika za optimizaciju rute
  final String? adresaId; // NOVO - UUID reference u tabelu adrese
  final bool obrisan; // NOVO - soft delete flag
  final String? brojTelefona; // NOVO - broj telefona putnika
  final String? datum; // ISO format
  final int brojMesta;
  final String? tipPutnika; // Tip putnika: radnik, ucenik, dnevni, posiljka
  final bool otkazanZaPolazak;
  final String? requestId; // ID konkretnog v2_polasci reda
  final String? pokupioVozacId; // UUID vozaca koji je pokupljanje izVrsio
  final String? naplatioVozacId; // UUID vozaca koji je naplatio
  final String? otkazaoVozacId; // UUID vozaca koji je otkazao

  factory V2Putnik.v2FromPolazak(Map<String, dynamic> req, {Map<String, dynamic>? profile}) {
    // 1. Prioritet: Denormalizovana polja iz v2_polasci (najbrže - 0 DB lookup)
    // Ako nema denormalizovanih polja, proveri profile (v3_putnici ili legacy)
    final ime =
        req['putnik_ime'] as String? ?? profile?['ime_prezime'] as String? ?? profile?['ime'] as String? ?? 'Putnik';

    final adresa = req['adresa_naziv'] as String? ?? profile?['adresa_naziv'] as String?;

    // NOVO: Denormalizovane adrese iz v2_polasci ako postoje u redovima
    final adresaBc = req['adresa_bc_naziv'] as String? ?? profile?['adresa_bc_naziv'] as String?;
    final adresaVs = req['adresa_vs_naziv'] as String? ?? profile?['adresa_vs_naziv'] as String?;

    return V2Putnik(
      id: req['putnik_id'],
      ime: ime,
      polazak: req['zeljeno_vreme'] ?? '---',
      pokupljen: req['status'] == V2Polazak.statusPokupljen,
      vremeDodavanja: req['created_at'] != null ? DateTime.tryParse(req['created_at'] as String)?.toLocal() : null,
      dan: (req['dan']?.toString() ?? '').toLowerCase(),
      status: req['status'] as String? ?? 'aktivan',
      statusVreme: req['updated_at'] as String?,
      grad: req['grad'] ?? 'BC',
      adresa: adresa ?? (req['grad'] == 'BC' ? adresaBc : adresaVs), // Koristi denormalizovanu adresu zavisno od smera
      tipPutnika: tipIzTabele(req['putnik_tabela']?.toString()),
    );
  }

  // Helper getter za proveru da li je dnevni tip (v2_dnevni ili v2_posiljke)
  bool get isDnevniTip => tipPutnika?.toLowerCase() == 'dnevni' || tipPutnika?.toLowerCase() == 'posiljka';

  // Getteri po konkretnom tipu
  bool get isRadnik => tipPutnika?.toLowerCase() == 'radnik';
  bool get isUcenik => tipPutnika?.toLowerCase() == 'ucenik';
  bool get isPosiljka => tipPutnika?.toLowerCase() == 'posiljka';
  bool get isDnevni => tipPutnika?.toLowerCase() == 'dnevni';

  // Getter-i za kompatibilnost
  String get destinacija => grad;
  String get vremePolaska => polazak;

  /// Izracunava efektivnu cenu po mestu za ovaj polazak
  double get effectivePrice {
    // Cena iskljucivo iz baze - admin postavlja manuelno
    if (cena != null && cena! > 0) {
      return cena!;
    }
    return 0.0;
  }

  // Getter-i za centralizovanu logiku statusa
  // jeOtkazan proverava otkazanZaPolazak (po gradu) umesto globalnog statusa
  bool get jeOtkazan =>
      !jeOdsustvo &&
      (obrisan ||
          otkazanZaPolazak ||
          status?.toLowerCase() == 'otkazano' ||
          status?.toLowerCase() == 'otkazan' ||
          status?.toLowerCase() == 'cancelled');

  bool get jeBolovanje => status != null && status!.toLowerCase() == 'bolovanje';

  bool get jeGodisnji => status != null && (status!.toLowerCase() == 'godišnji' || status!.toLowerCase() == 'godisnji');

  bool get jeOdsustvo => jeBolovanje || jeGodisnji;

  bool get jePokupljen {
    // 1. Ako je eksplicitno prosleden flag (iz v2_polasci srRow) - NAJVECI PRIORITET
    if (pokupljen == true) return true;

    // STATUS 'odobreno' NIJE POKUPLJEN (to je samo odobrena rezervacija)
    if (status?.toLowerCase() == 'odobreno') return false;

    // 2. Za v2_polasci: pokupljen je ako je status 'pokupljen'
    if (status?.toLowerCase() == 'pokupljen') {
      return true;
    }

    return false;
  }

  // Vozac UUID iz dodeljenVozac (via vreme_vozac)
  String? get vozacUuid => dodeljenVozac != null && dodeljenVozac!.isNotEmpty ? dodeljenVozac : null;

  // Ime vozaca
  String? get vozacIme => naplatioVozac ?? dodeljenVozac;

  // HELPER METODE za mapiranje
  static String _v2GradIzProfila(Map<String, dynamic> map) {
    // Odredi grad na osnovu AKTIVNOG polaska za danas
    final danKratica = V2DanUtils.odDatuma(DateTime.now());

    final bcPolazak = V2RegistrovaniHelpers.getPolazakForDay(map, danKratica, 'bc');
    final vsPolazak = V2RegistrovaniHelpers.getPolazakForDay(map, danKratica, 'vs');

    // Ako ima BC polazak danas, V2Putnik putuje IZ Bela Crkva (pokupljaš ga tamo)
    if (bcPolazak != null && bcPolazak.toString().isNotEmpty) {
      return 'BC';
    }

    // Ako ima VS polazak danas, V2Putnik putuje IZ Vrsac (pokupljaš ga tamo)
    if (vsPolazak != null && vsPolazak.toString().isNotEmpty) {
      return 'VS';
    }

    // Fallback: proveri da li ima VS adresu u JOIN-u
    final adresaVsObj = map['adresa_vs'] as Map<String, dynamic>?;
    if (adresaVsObj != null && adresaVsObj['naziv'] != null) {
      return 'VS';
    }

    return 'BC';
  }

  static String? _v2AdresaNaziv(Map<String, dynamic> map, String grad) {
    // 1. Prioritet: Denormalizovani naziv direktno iz kolone (adresa_bc_naziv / adresa_vs_naziv)
    if (grad == 'VS') {
      final denormalized = map['adresa_vs_naziv'] as String?;
      if (denormalized != null && denormalized.isNotEmpty) return denormalized;
      return (map['adresa_vs'] as Map<String, dynamic>?)?['naziv'] as String?;
    }
    final denormalizedBC = map['adresa_bc_naziv'] as String?;
    if (denormalizedBC != null && denormalizedBC.isNotEmpty) return denormalizedBC;
    return (map['adresa_bc'] as Map<String, dynamic>?)?['naziv'] as String?;
  }

  static String? _v2AdresaId(Map<String, dynamic> map, String grad) {
    if (grad == 'VS') return map['adresa_vs_id'] as String?;
    return map['adresa_bc_id'] as String?;
  }

  // -----------------------------------------------------------------------
  // COPY WITH - za azuriranje putnika sa novim podacima
  // -----------------------------------------------------------------------

  V2Putnik copyWith({
    String? id,
    String? ime,
    String? polazak,
    bool? pokupljen,
    DateTime? vremeDodavanja,
    String? dan,
    String? status,
    String? statusVreme,
    DateTime? vremePokupljenja,
    DateTime? vremePlacanja,
    bool? placeno,
    double? cena,
    double? iznosUplate,
    String? naplatioVozac,
    String? pokupioVozac,
    String? dodeljenVozac,
    String? vozac,
    String? grad,
    String? otkazaoVozac,
    DateTime? vremeOtkazivanja,
    String? adresa,
    String? adresaId,
    bool? obrisan,
    String? brojTelefona,
    String? datum,
    int? brojMesta,
    String? tipPutnika,
    bool? otkazanZaPolazak,
    String? requestId,
    String? pokupioVozacId,
    String? naplatioVozacId,
    String? otkazaoVozacId,
  }) {
    return V2Putnik(
      id: id ?? this.id,
      ime: ime ?? this.ime,
      polazak: polazak ?? this.polazak,
      pokupljen: pokupljen ?? this.pokupljen,
      vremeDodavanja: vremeDodavanja ?? this.vremeDodavanja,
      dan: dan ?? this.dan,
      status: status ?? this.status,
      statusVreme: statusVreme ?? this.statusVreme,
      vremePokupljenja: vremePokupljenja ?? this.vremePokupljenja,
      vremePlacanja: vremePlacanja ?? this.vremePlacanja,
      placeno: placeno ?? this.placeno,
      cena: cena ?? this.cena,
      iznosUplate: iznosUplate ?? this.iznosUplate,
      naplatioVozac: naplatioVozac ?? this.naplatioVozac,
      pokupioVozac: pokupioVozac ?? this.pokupioVozac,
      dodeljenVozac: dodeljenVozac ?? this.dodeljenVozac,
      vozac: vozac ?? this.vozac,
      grad: grad ?? this.grad,
      otkazaoVozac: otkazaoVozac ?? this.otkazaoVozac,
      vremeOtkazivanja: vremeOtkazivanja ?? this.vremeOtkazivanja,
      adresa: adresa ?? this.adresa,
      adresaId: adresaId ?? this.adresaId,
      obrisan: obrisan ?? this.obrisan,
      brojTelefona: brojTelefona ?? this.brojTelefona,
      datum: datum ?? this.datum,
      brojMesta: brojMesta ?? this.brojMesta,
      tipPutnika: tipPutnika ?? this.tipPutnika,
      otkazanZaPolazak: otkazanZaPolazak ?? this.otkazanZaPolazak,
      requestId: requestId ?? this.requestId,
      pokupioVozacId: pokupioVozacId ?? this.pokupioVozacId,
      naplatioVozacId: naplatioVozacId ?? this.naplatioVozacId,
      otkazaoVozacId: otkazaoVozacId ?? this.otkazaoVozacId,
    );
  }

  // -----------------------------------------------------------------------
  // EQUALITY OPERATORS - za stabilno mapiranje u Map<V2Putnik, Position>
  // Ukljuci SVE relevantne atribute za detekciju promena iz realtime-a
  // -----------------------------------------------------------------------

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! V2Putnik) return false;

    // Poredi SVE relevantne atribute, ne samo id
    // Ovo omogucava da didUpdateWidget detektuje promene iz realtime-a
    return id == other.id &&
        ime == other.ime &&
        grad == other.grad &&
        polazak == other.polazak &&
        status == other.status &&
        pokupljen == other.pokupljen &&
        placeno == other.placeno &&
        cena == other.cena &&
        vremePokupljenja == other.vremePokupljenja &&
        vremeOtkazivanja == other.vremeOtkazivanja &&
        otkazanZaPolazak == other.otkazanZaPolazak;
  }

  @override
  int get hashCode {
    // Koristi samo stabilne atribute za hash (id ili ime+grad+polazak)
    if (id != null) {
      return id.hashCode;
    }
    return Object.hash(ime, grad, polazak);
  }

  @override
  String toString() => 'V2Putnik(id: $id, ime: $ime, grad: $grad, status: $status, dan: $dan, polazak: $polazak)';

  // FALLBACK METODA: Ucitaj adresu iz rm cache-a ako je NULL
  String? getAdresaFallback() {
    // Ako vec imamo adresu, vrati je
    if (adresa != null && adresa!.isNotEmpty && adresa != 'Adresa nije definisana') {
      return adresa;
    }

    // Ako nemamo adresaId, ne možemo ucitati
    if (adresaId == null || adresaId!.isEmpty) {
      return adresa; // vrati šta god imamo (ili null)
    }

    // Čita direktno iz rm cache-a — sync
    final fetchedAdresa = V2AdresaSupabaseService.getNazivAdreseByUuid(adresaId);
    if (fetchedAdresa != null && fetchedAdresa.isNotEmpty) {
      return fetchedAdresa;
    }

    return adresa;
  }
}
