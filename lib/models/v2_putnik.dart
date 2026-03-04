import 'package:flutter/foundation.dart';

import '../services/realtime/v2_master_realtime_manager.dart';
import '../services/v2_adresa_supabase_service.dart'; // DODATO za fallback ucitavanje adrese
import '../utils/v2_registrovani_helpers.dart';
import '../utils/v2_vozac_cache.dart';

class V2Putnik {
  // NOVO - originalni datum za dnevne putnike (ISO yyyy-MM-dd)

  V2Putnik({
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
    this.cena, // STANDARDIZOVANO: cena umesto iznosPlacanja
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

  // Factory za v2 putnik profil (v2_radnici, v2_ucenici, v2_dnevni, v2_posiljke)
  factory V2Putnik.v2FromProfil(Map<String, dynamic> map) {
    final grad = _v2GradIzProfila(map);
    final tipPutnika = map['_tabela'] != null
        ? (map['_tabela'] == 'v2_radnici'
            ? 'radnik'
            : map['_tabela'] == 'v2_ucenici'
                ? 'ucenik'
                : map['_tabela'] == 'v2_dnevni'
                    ? 'dnevni'
                    : 'posiljka')
        : map['tip'] as String?;
    final isDnevni = tipPutnika == 'dnevni' || tipPutnika == 'posiljka';

    return V2Putnik(
      id: map['id'],
      ime: map['ime'] as String? ?? '',
      polazak: '---',
      pokupljen: false,
      vremeDodavanja: map['created_at'] != null ? DateTime.parse(map['created_at'] as String).toLocal() : null,
      mesecnaKarta: !isDnevni,
      dan: '',
      status: map['status'] as String? ?? 'aktivan',
      statusVreme: map['updated_at'] as String?,
      grad: grad,
      adresa: _v2AdresaNaziv(map, grad),
      adresaId: _v2AdresaId(map, grad),
      obrisan: !V2RegistrovaniHelpers.isActiveFromMap(map),
      brojTelefona: map['telefon'] as String?,
      brojMesta: (map['broj_mesta'] as int?) ?? 1,
      tipPutnika: tipPutnika,
    );
  }

  final dynamic id; // UUID putnika iz v2_radnici/v2_ucenici/v2_dnevni/v2_posiljke
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
  final double? cena; // STANDARDIZOVANO: cena umesto iznosPlacanja
  double? get iznosPlacanja => cena; // backward compatibility
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
    // Profil je prosleđen direktno ili ugnezden u mapi pod kljucem 'registrovani_putnici'
    // (taj ključ stavlja _buildPutnik iz v2_putnik_stream_service.dart)
    final Map<String, dynamic> p = profile ?? (req['registrovani_putnici'] as Map<String, dynamic>? ?? {});

    final danStr = (req['dan']?.toString() ?? '').toLowerCase();
    // PRIORITET: datum iz RPC-a (p_datum = danas) — ne racunaj iz dana jer ide u buducnost
    // Fallback: _getIsoDateForDan samo ako RPC nije vratio datum (direktni v2_polasci query)
    final rpcDatum = req['datum']?.toString();
    final datumStr = (rpcDatum != null && rpcDatum.isNotEmpty)
        ? rpcDatum.split('T')[0] // ISO: "2026-02-23T00:00:00" -> "2026-02-23"
        : _getIsoDateForDan(danStr);
    final gRaw = req['grad']?.toString().toLowerCase() ?? '';
    final grad = (gRaw == 'vs' || gRaw.contains('vrs') || gRaw.contains('vr')) ? 'VS' : 'BC';

    // PRIORITET: Dodeljeno vreme (ako je vozac pomerio termin), inace zeljeno
    final vremeRaw = (req['dodeljeno_vreme'] ?? req['zeljeno_vreme'])?.toString() ?? '';

    // Provera da li je pokupljen (iz v2_polasci srRow ili statusa)
    final bool isPickedUp = req['pokupljen_iz_loga'] == true || req['status']?.toString().toLowerCase() == 'pokupljen';

    // Provera da li je placeno (za dnevne putnike)
    // Čita se iz v2_polasci srRow (placen kolona), ne iz statusa
    final bool isPaid = req['placeno_iz_loga'] == true;

    // Koristi centralizovanu normalizaciju vremena
    final vreme = V2RegistrovaniHelpers.normalizeTime(vremeRaw) ?? '05:00';

    final tip = p['tip'] as String?;
    final isDnevni = tip == 'dnevni' || tip == 'posiljka';

    // Status: Prioritet ima status iz profila ako je na bolovanju/godišnjem,
    // inace koristimo status iz v2_polasci (odobreno, obrada, otkazano...)
    final profileStatus = p['status']?.toString().toLowerCase();
    String? finalStatus = req['status']?.toString();

    if (profileStatus == 'bolovanje' || profileStatus == 'godisnji' || profileStatus == 'godišnji') {
      // Ako je globalno na odsustvu, to je primarni status za prikaz
      finalStatus = profileStatus;
    }

    // Dodeljeni vozac — traži individualnu dodjelu (v2_vozac_putnik), pa termin-raspored (v2_vozac_raspored)
    String? dodeljenVozacFinal;
    try {
      final rm = V2MasterRealtimeManager.instance;
      final putnikIdStr = (p['id'] ?? req['putnik_id'])?.toString() ?? '';
      final gradNorm = grad.toUpperCase(); // već je 'BC' ili 'VS'
      final vremeNorm = V2RegistrovaniHelpers.normalizeTime(vreme) ?? '';

      // 1. Individualna dodjela za ovaj dan+grad+vreme
      final indDodjela = rm.vozacPutnikCache.values.where((vp) {
        return vp['putnik_id']?.toString() == putnikIdStr &&
            vp['dan']?.toString().toLowerCase() == danStr &&
            vp['grad']?.toString().toUpperCase() == gradNorm &&
            (V2RegistrovaniHelpers.normalizeTime(vp['vreme']?.toString()) ?? '') == vremeNorm;
      }).firstOrNull;

      if (indDodjela != null) {
        dodeljenVozacFinal = V2VozacCache.getImeByUuid(indDodjela['vozac_id']?.toString() ?? '');
      } else {
        // 2. Termin-raspored (v2_vozac_raspored) za ovaj dan+grad+vreme
        final terminRaspored = rm.rasporedCache.values.where((vr) {
          return vr['dan']?.toString().toLowerCase() == danStr &&
              vr['grad']?.toString().toUpperCase() == gradNorm &&
              (V2RegistrovaniHelpers.normalizeTime(vr['vreme']?.toString()) ?? '') == vremeNorm;
        }).firstOrNull;

        if (terminRaspored != null) {
          dodeljenVozacFinal = V2VozacCache.getImeByUuid(terminRaspored['vozac_id']?.toString() ?? '');
        }
      }
    } catch (e) {
      debugPrint('[V2Putnik.v2FromPolazak] dodeljenVozac lookup failed: $e');
    }

    return V2Putnik(
      id: p['id'] ?? req['putnik_id'],
      ime: p['ime'] as String? ?? '',
      polazak: vreme,
      dan: danStr.isNotEmpty ? danStr : _getDayNameFromIso(datumStr),
      grad: grad,
      status: finalStatus,
      pokupljen: isPickedUp,
      placeno: isPaid,
      datum: datumStr,
      tipPutnika: tip,
      mesecnaKarta: !isDnevni,
      brojMesta: req['broj_mesta'] ?? p['broj_mesta'] ?? 1,
      adresa: ((req['adrese'] as Map?)?['naziv'] as String?) ??
          (grad == 'VS'
              ? ((p['adresa_vs'] as Map<String, dynamic>?)?['naziv'] as String?)
              : ((p['adresa_bc'] as Map<String, dynamic>?)?['naziv'] as String?)),
      adresaId: req['custom_adresa_id'] as String? ??
          (grad == 'VS' ? p['adresa_vs_id'] as String? : p['adresa_bc_id'] as String?),
      brojTelefona: p['telefon'] as String?,
      statusVreme: p['updated_at'],
      vremeDodavanja: p['created_at'] != null ? DateTime.parse(p['created_at']) : null,
      vremePokupljenja: req['processed_at'] != null ? DateTime.parse(req['processed_at']).toLocal() : null,
      pokupioVozac: req['pokupioVozac'],
      naplatioVozac: req['naplatioVozac'],
      otkazaoVozac: req['otkazaoVozac'],
      pokupioVozacId: req['pokupioVozacId'] as String?,
      naplatioVozacId: req['naplatioVozacId'] as String?,
      otkazaoVozacId: req['otkazaoVozacId'] as String?,
      cena: req['cena']?.toDouble(),
      vremePlacanja: req['vreme_placanja'] != null ? DateTime.parse(req['vreme_placanja']).toLocal() : null,
      vremeOtkazivanja: req['vreme_otkazivanja'] != null ? DateTime.parse(req['vreme_otkazivanja']).toLocal() : null,
      obrisan: false,
      dodeljenVozac: dodeljenVozacFinal,
      requestId: req['id']?.toString(), // ID v2_polasci reda
    );
  }

  static const _dayAbbreviations = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];

  static String _getDayNameFromIso(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      return _dayAbbreviations[dt.weekday - 1];
    } catch (e) {
      debugPrint('[V2Putnik] _getDayNameFromIso failed for "$isoDate": $e');
      return '';
    }
  }

  /// Izracunava ISO datum (yyyy-MM-dd) za danu kraticu dana (pon, uto...)
  /// Traži od danas pa unaprijed (max 7 dana) sljedeci taj dan u sedmici
  static String _getIsoDateForDan(String danKratica) {
    if (danKratica.isEmpty) return '';
    try {
      final idx = _dayAbbreviations.indexWhere((a) => a.toLowerCase() == danKratica.toLowerCase());
      if (idx < 0) return '';
      final targetWeekday = idx + 1; // 1=Monday...7=Sunday
      final now = DateTime.now();
      for (int i = 0; i < 7; i++) {
        final d = now.add(Duration(days: i));
        if (d.weekday == targetWeekday) {
          return d.toIso8601String().split('T')[0];
        }
      }
      return '';
    } catch (e) {
      debugPrint('[V2Putnik] _getIsoDateForDan failed for "$danKratica": $e');
      return '';
    }
  }

  // Helper getter za proveru da li je dnevni tip
  bool get isDnevniTip => tipPutnika?.toLowerCase() == 'dnevni' || mesecnaKarta == false;

  // Helper getter za proveru da li je radnik ili ucenik (prikazuje MESECNA badge)
  // Fallback: ako tipPutnika nije poznat, koristi mesecnaKarta kao indikator
  bool get isMesecniTip =>
      tipPutnika?.toLowerCase() == 'radnik' ||
      tipPutnika?.toLowerCase() == 'ucenik' ||
      (tipPutnika == null && mesecnaKarta == true);

  // Getter-i za kompatibilnost
  String get destinacija => grad;
  String get vremePolaska => polazak;

  /// Izracunava efektivnu cenu po mestu za ovaj polazak
  double get effectivePrice {
    // 1. Custom cena iz baze (AKO JE POSTAVLJENA - NAJVECI PRIORITET)
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
  // jeOtkazan proverava otkazanZaPolazak (po gradu) umesto globalnog statusa
  bool get jeOtkazan =>
      !jeOdsustvo &&
      (obrisan ||
          otkazanZaPolazak ||
          status?.toLowerCase() == 'otkazano' ||
          status?.toLowerCase() == 'otkazan' ||
          status?.toLowerCase() == 'cancelled'); // legacy backward compat

  bool get jeBezPolaska => status?.toLowerCase() == 'bez_polaska';

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
    final danKratica = _dayAbbreviations[DateTime.now().weekday - 1];

    // Proveri koji polazak postoji za danas
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
    if (grad == 'VS') {
      return (map['adresa_vs'] as Map<String, dynamic>?)?['naziv'] as String?;
    }
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

  // ?? Helper za parsiranje radnih dana (iz kolone ili JSON-a)
}
