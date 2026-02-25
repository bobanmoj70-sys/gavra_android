import '../constants/day_constants.dart';
import '../services/adresa_supabase_service.dart'; // DODATO za fallback učitavanje adrese
import '../utils/registrovani_helpers.dart';

class Putnik {
  // NOVO - originalni datum za dnevne putnike (ISO yyyy-MM-dd)

  Putnik({
    this.id,
    required this.ime,
    required this.polazak,
    this.pokupljen,
    this.vremeDodavanja,
    this.mesecnaKarta,
    required this.dan,
    this.status,
    this.statusVreme,
    this.vremePokupljenja,
    this.vremePlacanja,
    this.placeno,
    this.cena, // ? STANDARDIZOVANO: cena umesto iznosPlacanja
    this.naplatioVozac,
    this.pokupioVozac,
    this.dodeljenVozac,
    this.vozac,
    required this.grad,
    this.otkazaoVozac,
    this.vremeOtkazivanja,
    this.adresa,
    this.adresaId, // NOVO - UUID reference u tabelu adrese
    this.obrisan = false, // default vrednost
    this.priority, // prioritet za optimizaciju ruta
    this.brojTelefona, // broj telefona putnika
    this.datum,
    this.brojMesta = 1, // ?? Broj rezervisanih mesta (default 1)
    this.tipPutnika, // ?? Tip putnika: radnik, ucenik, dnevni
    this.otkazanZaPolazak = false, // ?? Da li je otkazan za ovaj specificni polazak (grad)
    this.requestId, // 🆕 ID konkretnog seat_request zapisa
    this.pokupioVozacId, // UUID vozača koji je pokupljanje izVrsio
    this.naplatioVozacId, // UUID vozača koji je naplatio
    this.otkazaoVozacId, // UUID vozača koji je otkazao
  });

  factory Putnik.fromMap(Map<String, dynamic> map) {
    // Svi podaci dolaze iz registrovani_putnici tabele
    if (map.containsKey('putnik_ime')) {
      return Putnik.fromRegistrovaniPutnici(map);
    }

    // GREŠKA - Struktura tabele nije prepoznata
    throw Exception(
      'Struktura podataka nije prepoznata - ocekuje se putnik_ime kolona iz registrovani_putnici',
    );
  }

  // NOVI: Factory za registrovani_putnici tabelu (PROFIL PUTNIKA)
  factory Putnik.fromRegistrovaniPutnici(Map<String, dynamic> map) {
    final grad = _determineGradFromRegistrovani(map);

    // ⚠️ SSOT: Ne čitamo polazak iz profila, on mora doći iz seat_requests
    final tipPutnika = map['tip'] as String?;
    final isDnevni = tipPutnika == 'dnevni' || tipPutnika == 'posiljka';

    return Putnik(
      id: map['id'],
      ime: map['putnik_ime'] as String? ?? '',
      polazak: '---', // Nema polaska bez seat_request-a
      pokupljen: false,
      vremeDodavanja: map['created_at'] != null ? DateTime.parse(map['created_at'] as String).toLocal() : null,
      mesecnaKarta: !isDnevni,
      dan: '',
      status: map['status'] as String? ?? 'radi',
      statusVreme: map['updated_at'] as String?,
      grad: grad,
      adresa: _determineAdresaFromRegistrovani(map, grad),
      adresaId: _determineAdresaIdFromRegistrovani(map, grad),
      obrisan: !RegistrovaniHelpers.isActiveFromMap(map),
      brojTelefona: map['broj_telefona'] as String?,
      brojMesta: (map['broj_mesta'] as int?) ?? 1,
      tipPutnika: tipPutnika,
    );
  }

  final dynamic id; // UUID iz registrovani_putnici
  final String ime;
  final String polazak;
  final bool? pokupljen;
  final DateTime? vremeDodavanja; // ? DateTime
  final bool? mesecnaKarta;
  final String dan;
  final String? status;
  final String? statusVreme;
  final DateTime? vremePokupljenja; // ? DateTime
  final DateTime? vremePlacanja; // ? DateTime
  final bool? placeno;
  final double? cena; // ? STANDARDIZOVANO: cena umesto iznosPlacanja
  double? get iznosPlacanja => cena; // BACKWARD COMPATIBILITY
  final String? naplatioVozac;
  final String? pokupioVozac; // NOVO - vozac koji je pokupljanje izVrsio
  final String? dodeljenVozac;
  final String? vozac;
  final String grad;
  final String? otkazaoVozac;
  final DateTime? vremeOtkazivanja; // NOVO - vreme kada je otkazano
  final String? adresa; // NOVO - adresa putnika za optimizaciju rute
  final String? adresaId; // NOVO - UUID reference u tabelu adrese
  final bool obrisan; // NOVO - soft delete flag
  final int? priority; // NOVO - prioritet za optimizaciju ruta (1-5, gde je 1 najmanji)
  final String? brojTelefona; // NOVO - broj telefona putnika
  final String? datum; // ISO format
  final int brojMesta; // ?? Broj rezervisanih mesta
  final String? tipPutnika; // ?? Tip putnika: radnik, ucenik, dnevni
  final bool otkazanZaPolazak; // ?? Da li je otkazan za ovaj polazak
  final String? requestId; // 🆕 ID konkretnog seat_request-a
  final String? pokupioVozacId; // UUID vozača koji je pokupljanje izVrsio
  final String? naplatioVozacId; // UUID vozača koji je naplatio
  final String? otkazaoVozacId; // UUID vozača koji je otkazao

  factory Putnik.fromSeatRequest(Map<String, dynamic> req, {Map<String, dynamic>? profile}) {
    // Ako je profil join-ovan u samom requestu (Supabase .select('*, registrovani_putnici(...)'))
    final Map<String, dynamic> p = profile ?? (req['registrovani_putnici'] as Map<String, dynamic>? ?? {});

    final danStr = (req['dan']?.toString() ?? '').toLowerCase();
    // ✅ PRIORITET: datum iz RPC-a (p_datum = danas) — ne računaj iz dana jer ide u budućnost
    // Fallback: _getIsoDateForDan samo ako RPC nije vratio datum (direktni seat_requests query)
    final rpcDatum = req['datum']?.toString();
    final datumStr = (rpcDatum != null && rpcDatum.isNotEmpty)
        ? rpcDatum.split('T')[0] // ISO: "2026-02-23T00:00:00" → "2026-02-23"
        : _getIsoDateForDan(danStr);
    final gRaw = req['grad']?.toString().toLowerCase() ?? '';
    final grad = (gRaw == 'vs' || gRaw.contains('vrs') || gRaw.contains('vr')) ? 'VS' : 'BC';

    // ✅ PRIORITET: Dodeljeno vreme (ako je vozač pomerio termin), inače željeno
    final vremeRaw = (req['dodeljeno_vreme'] ?? req['zeljeno_vreme'])?.toString() ?? '';

    // Provera da li je pokupljen (iz voznje_log ili statusa)
    final bool isPickedUp = req['pokupljen_iz_loga'] == true || req['status']?.toString().toLowerCase() == 'pokupljen';

    // Provera da li je plaćeno (za dnevne putnike)
    // ✅ SAMO iz voznje_log (uplata/uplata_dnevna), ne iz statusa!
    final bool isPaid = req['placeno_iz_loga'] == true;

    // ✅ FIX: Koristi centralizovanu normalizaciju vremena
    final vreme = RegistrovaniHelpers.normalizeTime(vremeRaw) ?? '05:00';

    final tip = p['tip'] as String?;
    final isDnevni = tip == 'dnevni' || tip == 'posiljka';

    // Status: Prioritet ima status iz profila ako je na bolovanju/godišnjem,
    // inače koristimo status iz seat_request (approved, confirmed, cancelled...)
    final profileStatus = p['status']?.toString().toLowerCase();
    String? finalStatus = req['status']?.toString();

    if (profileStatus == 'bolovanje' || profileStatus == 'godisnji' || profileStatus == 'godišnji') {
      // Ako je globalno na odsustvu, to je primarni status za prikaz
      finalStatus = profileStatus;
    }

    // Dodeljeni vozač je uvek null (tabele vreme_vozac i putnik_vozac su uklonjene)
    String? dodeljenVozacFinal;

    return Putnik(
      id: p['id'] ?? req['putnik_id'],
      ime: p['putnik_ime'] ?? p['ime'] ?? '',
      polazak: vreme,
      dan: danStr.isNotEmpty ? danStr : _getDayNameFromIso(datumStr),
      grad: grad,
      status: finalStatus,
      pokupljen: isPickedUp, // ✅ Redizajnirano: Gleda status ili voznje_log flag
      placeno: isPaid, // ✅ Novo: Gleda status ili voznje_log flag
      datum: datumStr,
      tipPutnika: tip,
      mesecnaKarta: !isDnevni,
      brojMesta: req['broj_mesta'] ?? p['broj_mesta'] ?? 1,
      adresa: (req['adrese'] as Map?)?['naziv'] ??
          (grad == 'VS'
              ? (p['adresa_vs']?['naziv'] ?? p['adresa_vrsac_naziv'])
              : (p['adresa_bc']?['naziv'] ?? p['adresa_bela_crkva_naziv'])),
      adresaId: req['custom_adresa_id'] ?? (grad == 'VS' ? p['adresa_vrsac_id'] : p['adresa_bela_crkva_id']),
      brojTelefona: p['broj_telefona'],
      statusVreme: p['updated_at'],
      vremeDodavanja: p['created_at'] != null ? DateTime.parse(p['created_at']) : null,
      vremePokupljenja: req['processed_at'] != null ? DateTime.parse(req['processed_at']).toLocal() : null,
      pokupioVozac: req['pokupioVozac'],
      naplatioVozac: req['naplatioVozac'],
      otkazaoVozac: req['otkazaoVozac'],
      pokupioVozacId: req['pokupioVozacId'] as String?,
      naplatioVozacId: req['naplatioVozacId'] as String?,
      otkazaoVozacId: req['otkazaoVozacId'] as String?,
      cena: req['cena']?.toDouble(), // ✅ NOVO: Iznos plaćanja iz voznje_log
      obrisan: false,
      dodeljenVozac: dodeljenVozacFinal,
      requestId: req['id']?.toString(), // ✅ DODATO: ID seat_request-a
    );
  }

  static String _getDayNameFromIso(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      // ✅ FIX: Vrati KRATICU (pet) umesto punog imena (Petak) - zbog client-side filtera
      final index = DayConstants.weekdayToIndex(dt.weekday);
      return DayConstants.dayAbbreviations[index];
    } catch (_) {
      return '';
    }
  }

  /// Izračunava ISO datum (yyyy-MM-dd) za danu kraticu dana (pon, uto...)
  /// Traži od danas pa unaprijed (max 7 dana) sljedeći taj dan u sedmici
  static String _getIsoDateForDan(String danKratica) {
    if (danKratica.isEmpty) return '';
    try {
      final abbrs = DayConstants.dayAbbreviations;
      final idx = abbrs.indexWhere((a) => a.toLowerCase() == danKratica.toLowerCase());
      if (idx < 0) return '';
      // DayConstants: 0=pon(1), 1=uto(2), ... 4=pet(5), weekday je 1-7 (1=Mon)
      final targetWeekday = idx + 1; // 1=Monday...5=Friday
      final now = DateTime.now();
      for (int i = 0; i < 7; i++) {
        final d = now.add(Duration(days: i));
        if (d.weekday == targetWeekday) {
          return d.toIso8601String().split('T')[0];
        }
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  // ?? Helper getter za proveru da li je dnevni tip
  bool get isDnevniTip => tipPutnika?.toLowerCase() == 'dnevni' || mesecnaKarta == false;

  // ?? Helper getter za proveru da li je radnik ili ucenik (prikazuje MESECNA badge)
  // Fallback: ako tipPutnika nije poznat, koristi mesecnaKarta kao indikator
  bool get isMesecniTip =>
      tipPutnika?.toLowerCase() == 'radnik' ||
      tipPutnika?.toLowerCase() == 'ucenik' ||
      (tipPutnika == null && mesecnaKarta == true);

  // Getter-i za kompatibilnost
  String get destinacija => grad;
  String get vremePolaska => polazak;

  /// Izračunava efektivnu cenu po mestu za ovaj polazak
  double get effectivePrice {
    // 1. Custom cena iz baze (AKO JE POSTAVLJENA - NAJVEĆI PRIORITET)
    if (cena != null && cena! > 0) {
      return cena!;
    }

    final tipLower = tipPutnika?.toLowerCase() ?? '';
    final imeLower = ime.toLowerCase();

    // 2. Zubi (Specijalna cena - Fallback)
    if (tipLower == 'posiljka' && imeLower.contains('zubi')) {
      return 300.0;
    }

    // 3. Default cena za dnevne putnike (Fiksno 600 RSD)
    if (isDnevniTip) {
      return 600.0;
    }

    return 0.0;
  }

  // Getter-i za centralizovanu logiku statusa
  // ?? IZMENJENO: jeOtkazan sada proverava otkazanZaPolazak (po gradu) umesto globalnog statusa
  // Dodata provera za status 'otkazano' za kompatibilnost
  bool get jeOtkazan =>
      !jeOdsustvo &&
      (obrisan ||
          otkazanZaPolazak ||
          status?.toLowerCase() == 'otkazano' ||
          status?.toLowerCase() == 'otkazan' ||
          status?.toLowerCase() == 'cancelled');

  bool get jeBezPolaska => status?.toLowerCase() == 'bez_polaska';

  bool get jeBolovanje => status != null && status!.toLowerCase() == 'bolovanje';

  bool get jeGodisnji => status != null && (status!.toLowerCase() == 'godišnji' || status!.toLowerCase() == 'godisnji');

  bool get jeOdsustvo => jeBolovanje || jeGodisnji;

  bool get jePokupljen {
    // 1. Ako je eksplicitno prosleđen flag (iz voznje_log preko _enrichWithLogData) - NAJVEĆI PRIORITET
    if (pokupljen == true) return true;

    // 🛡️ STATUS 'confirmed' NIJE POKUPLJEN (to je samo potvrđena rezervacija)
    if (status?.toLowerCase() == 'confirmed') return false;

    // 2. Za seat_requests: pokupljen je ako je status 'pokupljen'
    if (status?.toLowerCase() == 'pokupljen') {
      return true;
    }

    return false;
  }

  // Vozac UUID iz dodeljenVozac (via vreme_vozac)
  String? get vozacUuid => dodeljenVozac != null && dodeljenVozac!.isNotEmpty ? dodeljenVozac : null;

  // Ime vozača
  String? get vozacIme => naplatioVozac ?? dodeljenVozac;

  // ⚠️ NAPOMENA: Sve metode koje su koristile polasci_po_danu su UKLONJENE.
  // Koristi se Putnik.fromSeatRequest za kreiranje objekata iz baze.

  // HELPER METODE za mapiranje
  static String _determineGradFromRegistrovani(Map<String, dynamic> map) {
    // Odredi grad na osnovu AKTIVNOG polaska za danas
    final index = DayConstants.weekdayToIndex(DateTime.now().weekday);
    final danKratica = DayConstants.dayAbbreviations[index];

    // Proveri koji polazak postoji za danas
    final bcPolazak = RegistrovaniHelpers.getPolazakForDay(map, danKratica, 'bc');
    final vsPolazak = RegistrovaniHelpers.getPolazakForDay(map, danKratica, 'vs');

    // Ako ima BC polazak danas, putnik putuje IZ Bela Crkva (pokupljaš ga tamo)
    if (bcPolazak != null && bcPolazak.toString().isNotEmpty) {
      return 'BC';
    }

    // Ako ima VS polazak danas, putnik putuje IZ Vrsac (pokupljaš ga tamo)
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

  static String? _determineAdresaFromRegistrovani(Map<String, dynamic> map, String grad) {
    // ? FIX: Koristi grad parametar za odredivanje adrese umesto ponovnog racunanja
    // Ovo osigurava konzistentnost izmedu grad i adresa polja

    // ? NOVO: Citaj adresu iz JOIN objekta (adresa_bc, adresa_vs)
    String? adresaBC;
    String? adresaVS;

    // Proveri da li postoji JOIN objekat za BC adresu
    final adresaBcObj = map['adresa_bc'] as Map<String, dynamic>?;
    if (adresaBcObj != null) {
      adresaBC = adresaBcObj['naziv'] as String? ?? '${adresaBcObj['ulica'] ?? ''} ${adresaBcObj['broj'] ?? ''}'.trim();
      if (adresaBC.isEmpty) adresaBC = null;
    }

    // Proveri da li postoji JOIN objekat za VS adresu
    final adresaVsObj = map['adresa_vs'] as Map<String, dynamic>?;
    if (adresaVsObj != null) {
      adresaVS = adresaVsObj['naziv'] as String? ?? '${adresaVsObj['ulica'] ?? ''} ${adresaVsObj['broj'] ?? ''}'.trim();
      if (adresaVS.isEmpty) adresaVS = null;
    }

    // ? FIX: Koristi grad parametar za odredivanje ispravne adrese
    // Ako je grad Bela Crkva, koristi BC adresu (gde pokupljaš putnika)
    // Ako je grad Vrsac, koristi VS adresu
    if (grad.toLowerCase().contains('bela') || grad.toLowerCase().contains('bc')) {
      return adresaBC ?? adresaVS ?? 'Adresa nije definisana';
    }

    // Za Vrsac ili bilo koji drugi grad, koristi VS adresu
    return adresaVS ?? adresaBC ?? 'Adresa nije definisana';
  }

  static String? _determineAdresaIdFromRegistrovani(Map<String, dynamic> map, String grad) {
    // Koristi UUID reference na osnovu grada
    if (grad.toLowerCase().contains('bela')) {
      return map['adresa_bela_crkva_id'] as String?;
    } else {
      return map['adresa_vrsac_id'] as String?;
    }
  }

  // ?? MAPIRANJE ZA registrovani_putnici TABELU
  Map<String, dynamic> toRegistrovaniPutniciMap() {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month);
    final endOfMonth = DateTime(now.year, now.month + 1, 0);

    return {
      // 'id': id, // Uklonjen - Supabase ce auto-generirati UUID
      'putnik_ime': ime,
      'tip': 'radnik', // ili 'ucenik' - treba logiku za odredivanje
      'tip_skole': null, // ? NOVA KOLONA - možda treba logika
      'broj_telefona': brojTelefona,
      'tip_prikazivanja': null,
      'aktivan': !obrisan,
      'status': status ?? 'radi',
      'datum_pocetka_meseca': startOfMonth.toIso8601String().split('T')[0],
      'datum_kraja_meseca': endOfMonth.toIso8601String().split('T')[0],
      // UUID validacija za vozac_id
      'vozac_id': (vozac?.isEmpty ?? true) ? null : vozac,
      'created_at': vremeDodavanja?.toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  // -----------------------------------------------------------------------
  // ?? COPY WITH - za ažuriranje putnika sa novim podacima
  // -----------------------------------------------------------------------

  Putnik copyWith({
    String? id,
    String? ime,
    String? polazak,
    bool? pokupljen,
    DateTime? vremeDodavanja,
    bool? mesecnaKarta,
    String? dan,
    String? status,
    String? statusVreme,
    DateTime? vremePokupljenja,
    DateTime? vremePlacanja,
    bool? placeno,
    double? cena,
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
    int? priority,
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
    return Putnik(
      id: id ?? this.id,
      ime: ime ?? this.ime,
      polazak: polazak ?? this.polazak,
      pokupljen: pokupljen ?? this.pokupljen,
      vremeDodavanja: vremeDodavanja ?? this.vremeDodavanja,
      mesecnaKarta: mesecnaKarta ?? this.mesecnaKarta,
      dan: dan ?? this.dan,
      status: status ?? this.status,
      statusVreme: statusVreme ?? this.statusVreme,
      vremePokupljenja: vremePokupljenja ?? this.vremePokupljenja,
      vremePlacanja: vremePlacanja ?? this.vremePlacanja,
      placeno: placeno ?? this.placeno,
      cena: cena ?? this.cena,
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
      priority: priority ?? this.priority,
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
  // ?? EQUALITY OPERATORS - za stabilno mapiranje u Map<Putnik, Position>
  // ?? FIX: Ukljuci SVE relevantne atribute za detekciju promena iz realtime-a
  // -----------------------------------------------------------------------

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Putnik) return false;

    // ?? FIX: Poredi SVE relevantne atribute, ne samo id
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

  // 🔄 FALLBACK METODA: Učitaj adresu ako je NULL (fallback za JOIN koji nije radio)
  Future<String?> getAdresaFallback() async {
    // Ako već imamo adresu, vrati je
    if (adresa != null && adresa!.isNotEmpty && adresa != 'Adresa nije definisana') {
      return adresa;
    }

    // Ako nemamo adresaId, ne možemo učitati
    if (adresaId == null || adresaId!.isEmpty) {
      return adresa; // vrati šta god imamo (ili null)
    }

    try {
      // Pokušaj da učitaš adresu direktno iz baze koristeći UUID
      final fetchedAdresa = await AdresaSupabaseService.getNazivAdreseByUuid(adresaId);
      if (fetchedAdresa != null && fetchedAdresa.isNotEmpty) {
        return fetchedAdresa;
      }
    } catch (_) {
      // Ignore error i vrati šta god imamo
    }

    return adresa;
  }

  // ?? Helper za parsiranje radnih dana (iz kolone ili JSON-a)
}
