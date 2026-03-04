import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import 'realtime/v2_master_realtime_manager.dart';

/// Servis za računanje prihoda, troškova i neto zarade
class V2FinansijeService {
  static SupabaseClient get _supabase => supabase;

  /// Dohvati sve aktivne troškove za određeni mesec/godinu (čita iz cache-a)
  static Future<List<V2Trosak>> getTroskovi({int? mesec, int? godina}) async {
    try {
      final rm = V2MasterRealtimeManager.instance;
      var rows = rm.troskoviCache.values.where((r) => r['aktivan'] == true);
      if (mesec != null) rows = rows.where((r) => r['mesec'] == mesec);
      if (godina != null) rows = rows.where((r) => r['godina'] == godina);

      return rows.map((row) {
        // Resolviraj ime vozača iz vozaciCache (umjesto PostgREST join-a)
        String? vozacIme;
        final vozacId = row['vozac_id']?.toString();
        if (vozacId != null) {
          vozacIme = rm.vozaciCache[vozacId]?['ime'] as String?;
        }
        return V2Trosak.fromJson({
          ...row,
          if (vozacIme != null) 'v2_vozaci': {'ime': vozacIme}
        });
      }).toList()
        ..sort((a, b) => a.tip.compareTo(b.tip));
    } catch (e) {
      debugPrint('[Finansije] getTroskovi greška: $e');
      return [];
    }
  }

  /// Ažuriraj trošak
  static Future<bool> updateTrosak(String id, double noviIznos) async {
    try {
      await _supabase.from('v2_finansije_troskovi').update({'iznos': noviIznos}).eq('id', id);
      return true;
    } catch (e) {
      debugPrint('[Finansije] updateTrosak greška: $e');
      return false;
    }
  }

  /// Dodaj novi trošak za određeni mesec/godinu
  static Future<bool> addTrosak(String naziv, String tip, double iznos, {int? mesec, int? godina}) async {
    try {
      final now = DateTime.now();
      debugPrint('[Finansije] Dodajem trošak: $naziv ($tip) = $iznos za ${mesec ?? now.month}/${godina ?? now.year}');
      await _supabase.from('v2_finansije_troskovi').insert({
        'naziv': naziv,
        'tip': tip,
        'iznos': iznos,
        'mesecno': true,
        'aktivan': true,
        'mesec': mesec ?? now.month,
        'godina': godina ?? now.year,
      });
      debugPrint('[Finansije] Trošak dodat uspešno: $naziv');

      return true;
    } catch (e) {
      debugPrint('[Finansije] Greška pri dodavanju troška $naziv: $e');
      return false;
    }
  }

  /// Obriši trošak (soft delete)
  static Future<bool> deleteTrosak(String id) async {
    try {
      await _supabase.from('v2_finansije_troskovi').update({'aktivan': false}).eq('id', id);
      return true;
    } catch (e) {
      debugPrint('[Finansije] deleteTrosak greška: $e');
      return false;
    }
  }

  /// Dohvati ukupna potraživanja (putnici s vožnjama koji nisu platili u tekućem mesecu)
  static Future<double> getPotrazivanja() async {
    try {
      final now = DateTime.now();
      final mesec = now.month;
      final godina = now.year;
      final mesecOd = '$godina-${mesec.toString().padLeft(2, '0')}-01';
      final mesecDo = _fmtDate(DateTime(godina, mesec + 1, 0)); // zadnji dan meseca

      // Dohvati sve putnike koji su imali vožnje ovaj mesec
      final voznjeResp = await _supabase
          .from('v2_statistika_istorija')
          .select('putnik_id')
          .eq('tip', 'voznja')
          .filter('datum', 'gte', mesecOd)
          .filter('datum', 'lte', mesecDo);

      final putnikIds =
          (voznjeResp as List).map((r) => r['putnik_id'] as String?).where((id) => id != null).toSet().toList();

      if (putnikIds.isEmpty) return 0;

      // Od tih putnika, koji su platili ovaj mesec
      final uplateResp = await _supabase
          .from('v2_statistika_istorija')
          .select('putnik_id')
          .inFilter('tip', ['uplata'])
          .filter('datum', 'gte', mesecOd)
          .filter('datum', 'lte', mesecDo);

      final placeniIds = (uplateResp as List).map((r) => r['putnik_id'] as String?).where((id) => id != null).toSet();

      // Putnici s dugom = imaju vožnje ali nisu platili
      final duznici = putnikIds.where((id) => !placeniIds.contains(id)).whereType<String>().toList();

      if (duznici.isEmpty) return 0;

      // Čitaj podatke putnika iz V2MasterRealtimeManager cache-a (nema DB upita)
      // Odvoji mesečne od dnevnih — dnevni trebaju broj vožnji iz DB-a
      double ukupnoDug = 0;
      final List<String> dnevniDuznici = [];

      for (final id in duznici) {
        final p = V2MasterRealtimeManager.instance.getPutnikById(id);
        if (p == null) continue;
        final String tabela = (p['_tabela'] as String? ?? '');
        final tip = tabela == 'v2_radnici'
            ? 'radnik'
            : tabela == 'v2_ucenici'
                ? 'ucenik'
                : tabela == 'v2_dnevni'
                    ? 'dnevni'
                    : 'posiljka';
        final cenaPoDanu = (p['cena_po_danu'] as num?)?.toDouble() ?? (p['cena'] as num?)?.toDouble();

        if (tip == 'mesecni' || tip == 'radnik' || tip == 'ucenik') {
          // Mesečni - paušal 6000 ako nema cenu
          ukupnoDug += cenaPoDanu != null ? cenaPoDanu * 22 : 6000;
        } else {
          dnevniDuznici.add(id);
        }
      }

      // Jedan batch DB upit za sve dnevne dužnike
      if (dnevniDuznici.isNotEmpty) {
        final brojVoznjiResp = await _supabase
            .from('v2_statistika_istorija')
            .select('putnik_id')
            .inFilter('putnik_id', dnevniDuznici)
            .eq('tip', 'voznja')
            .filter('datum', 'gte', mesecOd)
            .filter('datum', 'lte', mesecDo);

        final Map<String, int> voznjePoId = {};
        for (final r in (brojVoznjiResp as List)) {
          final pid = r['putnik_id'] as String?;
          if (pid != null) voznjePoId[pid] = (voznjePoId[pid] ?? 0) + 1;
        }

        for (final id in dnevniDuznici) {
          final p = V2MasterRealtimeManager.instance.getPutnikById(id);
          if (p == null) continue;
          final cenaPoDanu = (p['cena_po_danu'] as num?)?.toDouble() ?? (p['cena'] as num?)?.toDouble();
          final brojVoznji = voznjePoId[id] ?? 0;
          ukupnoDug += brojVoznji * (cenaPoDanu ?? 300);
        }
      }

      return ukupnoDug;
    } catch (e) {
      debugPrint('[Finansije] Greška pri računanju potraživanja: $e');
      return 0;
    }
  }

  /// Dohvati kompletan finansijski izveštaj (direktni SQL upiti, bez RPC)
  static Future<V2FinansijskiIzvestaj> getIzvestaj() async {
    try {
      final now = DateTime.now();
      final weekday = now.weekday;
      final mondayThisWeek = now.subtract(Duration(days: weekday - 1));
      final sundayThisWeek = mondayThisWeek.add(const Duration(days: 6));

      // Datumi za filtre
      final nedFrom = _fmtDate(mondayThisWeek);
      final nedTo = _fmtDate(sundayThisWeek);
      final mesFrom = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
      final mesTo = _fmtDate(DateTime(now.year, now.month + 1, 0)); // zadnji dan meseca
      final godFrom = '${now.year}-01-01';
      final godTo = '${now.year}-12-31';
      final proslaFrom = '${now.year - 1}-01-01';
      final proslaTo = '${now.year - 1}-12-31';

      // Paralelni upiti iz v2_statistika_istorija (trošovi se čitaju iz troskoviCache)
      final results = await Future.wait([
        // 0: nedelja
        _supabase.from('v2_statistika_istorija').select('tip, iznos').gte('datum', nedFrom).lte('datum', nedTo),
        // 1: mesec
        _supabase.from('v2_statistika_istorija').select('tip, iznos').gte('datum', mesFrom).lte('datum', mesTo),
        // 2: godina
        _supabase.from('v2_statistika_istorija').select('tip, iznos').gte('datum', godFrom).lte('datum', godTo),
        // 3: prosla godina
        _supabase.from('v2_statistika_istorija').select('tip, iznos').gte('datum', proslaFrom).lte('datum', proslaTo),
      ]);

      final nedRows = (results[0] as List).cast<Map<String, dynamic>>();
      final mesRows = (results[1] as List).cast<Map<String, dynamic>>();
      final godRows = (results[2] as List).cast<Map<String, dynamic>>();
      final proslaRows = (results[3] as List).cast<Map<String, dynamic>>();

      // Troškovi iz troskoviCache (0 DB upita)
      final troskoviRows = V2MasterRealtimeManager.instance.troskoviCache.values.toList();
      final mesTroskRows = troskoviRows
          .where((r) => r['aktivan'] == true && r['mesec'] == now.month && r['godina'] == now.year)
          .toList();
      final godTroskRows = troskoviRows.where((r) => r['aktivan'] == true && r['godina'] == now.year).toList();
      final proslaTroskRows = troskoviRows.where((r) => r['aktivan'] == true && r['godina'] == now.year - 1).toList();

      // Agregati iz v2_statistika_istorija
      final prihodNedelja = _sumirajPrihode(nedRows);
      final voznjiNedelja = _broji(nedRows, 'voznja');
      final prihodMesec = _sumirajPrihode(mesRows);
      final voznjiMesec = _broji(mesRows, 'voznja');
      final prihodGodina = _sumirajPrihode(godRows);
      final voznjiGodina = _broji(godRows, 'voznja');
      final prihodProsla = _sumirajPrihode(proslaRows);
      final voznjiProsla = _broji(proslaRows, 'voznja');

      // Troškovi iz finansije_troskovi
      final troskoviNedelja = 0.0; // troškovi nemaju dnevnu granularnost
      final troskoviMesec = mesTroskRows.fold<double>(0, (s, r) => s + _toDouble(r['iznos']));
      final troskoviGodina = godTroskRows.fold<double>(0, (s, r) => s + _toDouble(r['iznos']));
      final troskoviProsla = proslaTroskRows.fold<double>(0, (s, r) => s + _toDouble(r['iznos']));

      // Troškovi po tipu (za tekući mesec)
      final Map<String, double> troskoviPoTipu = {};
      for (final r in mesTroskRows) {
        final tip = r['tip'] as String? ?? 'ostalo';
        troskoviPoTipu[tip] = (troskoviPoTipu[tip] ?? 0) + _toDouble(r['iznos']);
      }

      // Potraživanja (frontend calculation)
      final potrazivanja = await getPotrazivanja();

      return V2FinansijskiIzvestaj(
        prihodNedelja: prihodNedelja,
        troskoviNedelja: troskoviNedelja,
        netoNedelja: prihodNedelja - troskoviNedelja,
        voznjiNedelja: voznjiNedelja,
        prihodMesec: prihodMesec,
        troskoviMesec: troskoviMesec,
        netoMesec: prihodMesec - troskoviMesec,
        voznjiMesec: voznjiMesec,
        prihodGodina: prihodGodina,
        troskoviGodina: troskoviGodina,
        netoGodina: prihodGodina - troskoviGodina,
        voznjiGodina: voznjiGodina,
        prihodProslaGodina: prihodProsla,
        troskoviProslaGodina: troskoviProsla,
        netoProslaGodina: prihodProsla - troskoviProsla,
        voznjiProslaGodina: voznjiProsla,
        proslaGodina: now.year - 1,
        troskoviPoTipu: troskoviPoTipu,
        ukupnoMesecniTroskovi: troskoviMesec,
        potrazivanja: potrazivanja,
        startNedelja: mondayThisWeek,
        endNedelja: sundayThisWeek,
      );
    } catch (e) {
      debugPrint('[Finansije] Greška pri dohvatanju izveštaja: $e');
      return _getEmptyIzvestaj();
    }
  }

  /// Sumira iznose uplata (tip = 'uplata')
  static double _sumirajPrihode(List<Map<String, dynamic>> rows) {
    const prihodTipovi = {'uplata'};
    return rows
        .where((r) => prihodTipovi.contains(r['tip'] as String?))
        .fold<double>(0, (s, r) => s + _toDouble(r['iznos']));
  }

  /// Broji redove određenog tipa
  static int _broji(List<Map<String, dynamic>> rows, String tip) => rows.where((r) => r['tip'] == tip).length;

  /// Formatiraj datum kao YYYY-MM-DD
  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static double _toDouble(dynamic val) {
    if (val == null) return 0;
    return (val is num) ? val.toDouble() : double.tryParse(val.toString()) ?? 0;
  }

  static V2FinansijskiIzvestaj _getEmptyIzvestaj() {
    final now = DateTime.now();
    return V2FinansijskiIzvestaj(
      prihodNedelja: 0,
      troskoviNedelja: 0,
      netoNedelja: 0,
      voznjiNedelja: 0,
      prihodMesec: 0,
      troskoviMesec: 0,
      netoMesec: 0,
      voznjiMesec: 0,
      prihodGodina: 0,
      troskoviGodina: 0,
      netoGodina: 0,
      voznjiGodina: 0,
      prihodProslaGodina: 0,
      troskoviProslaGodina: 0,
      netoProslaGodina: 0,
      voznjiProslaGodina: 0,
      proslaGodina: now.year - 1,
      troskoviPoTipu: {},
      ukupnoMesecniTroskovi: 0,
      potrazivanja: 0,
      startNedelja: now,
      endNedelja: now,
    );
  }

  /// Dohvati izveštaj za specifičan period (Custom Range) — direktni SQL, bez RPC
  static Future<Map<String, dynamic>> getIzvestajZaPeriod(DateTime from, DateTime to) async {
    try {
      final fromStr = _fmtDate(from);
      final toStr = _fmtDate(to);

      final results = await Future.wait([
        // v2_statistika_istorija za period
        _supabase.from('v2_statistika_istorija').select('tip, iznos').gte('datum', fromStr).lte('datum', toStr),
      ]);

      final voznjeRows = (results[0] as List).cast<Map<String, dynamic>>();

      // Troškovi za period iz cache-a (aktivan=true, godina u opsegu from..to)
      final troskoviRows = V2MasterRealtimeManager.instance.troskoviCache.values
          .where((r) =>
              r['aktivan'] == true && (r['godina'] as int? ?? 0) >= from.year && (r['godina'] as int? ?? 0) <= to.year)
          .toList();

      final prihod = _sumirajPrihode(voznjeRows);
      final voznje = _broji(voznjeRows, 'voznja');
      final troskovi = troskoviRows.fold<double>(0, (s, r) => s + _toDouble(r['iznos']));

      return {
        'prihod': prihod,
        'voznje': voznje,
        'troskovi': troskovi,
        'neto': prihod - troskovi,
      };
    } catch (e) {
      debugPrint('[Finansije] Greška custom report: $e');
      return {'prihod': 0, 'voznje': 0, 'troskovi': 0, 'neto': 0};
    }
  }

  /// REALTIME STREAMati promene u relevantnim tabelama i osvežava izveštaj
  static Stream<V2FinansijskiIzvestaj> streamIzvestaj() async* {
    // Emituj inicijalne podatke
    yield await getIzvestaj();

    // Sluša promene u v2_statistika_istorija (troskovi se čitaju iz cache-a)
    final voznjeStream = supabase.from('v2_statistika_istorija').stream(primaryKey: ['id']);

    await for (final _ in voznjeStream) {
      yield await getIzvestaj();
    }
  }
}

/// Model za jedan trošak
class V2Trosak {
  final String id;
  final String naziv;
  final String tip;
  final double iznos;
  final bool mesecno;
  final bool aktivan;
  final String? vozacId;
  final String? vozacIme;
  final int? mesec;
  final int? godina;

  V2Trosak({
    required this.id,
    required this.naziv,
    required this.tip,
    required this.iznos,
    required this.mesecno,
    required this.aktivan,
    this.vozacId,
    this.vozacIme,
    this.mesec,
    this.godina,
  });

  factory V2Trosak.fromJson(Map<String, dynamic> json) {
    // Izvuci ime vozača iz join-a
    String? vozacIme;
    if (json['v2_vozaci'] != null && json['v2_vozaci'] is Map) {
      vozacIme = json['v2_vozaci']['ime'] as String?;
    }

    return V2Trosak(
      id: json['id']?.toString() ?? '',
      naziv: json['naziv'] as String? ?? '',
      tip: json['tip'] as String? ?? 'ostalo',
      iznos: (json['iznos'] is num)
          ? (json['iznos'] as num).toDouble()
          : double.tryParse(json['iznos']?.toString() ?? '0') ?? 0,
      mesecno: json['mesecno'] as bool? ?? true,
      aktivan: json['aktivan'] as bool? ?? true,
      vozacId: json['vozac_id']?.toString(),
      vozacIme: vozacIme,
      mesec: json['mesec'] as int?,
      godina: json['godina'] as int?,
    );
  }

  /// Prikaži naziv (koristi ime vozača za plate)
  String get displayNaziv {
    if (tip == 'plata' && vozacIme != null) {
      return 'Plata - $vozacIme';
    }
    return naziv;
  }

  @override
  bool operator ==(Object other) => identical(this, other) || (other is V2Trosak && other.id == id);

  @override
  int get hashCode => id.hashCode;

  /// Emoji za tip troška
  String get emoji {
    switch (tip) {
      case 'plata':
        return '👷';
      case 'kredit':
        return '🏦';
      case 'gorivo':
        return '⛽';
      case 'amortizacija':
        return '🔧';
      case 'registracija':
        return '🛠️';
      case 'yu_auto':
        return '🇷🇸';
      case 'majstori':
        return '👨‍🔧';
      case 'ostalo':
        return '📋';
      case 'porez':
        return '🏛️';
      case 'alimentacija':
        return '👶';
      case 'racuni':
        return '🧾';
      default:
        return '❓';
    }
  }
}

/// Model za finansijski izveštaj
class V2FinansijskiIzvestaj {
  // Nedelja
  final double prihodNedelja;
  final double troskoviNedelja;
  final double netoNedelja;
  final int voznjiNedelja;

  // Mesec
  final double prihodMesec;
  final double troskoviMesec;
  final double netoMesec;
  final int voznjiMesec;

  // Godina
  final double prihodGodina;
  final double troskoviGodina;
  final double netoGodina;
  final int voznjiGodina;

  // Prošla godina
  final double prihodProslaGodina;
  final double troskoviProslaGodina;
  final double netoProslaGodina;
  final int voznjiProslaGodina;
  final int proslaGodina;

  // Detalji
  final Map<String, double> troskoviPoTipu;
  final double ukupnoMesecniTroskovi;
  final double potrazivanja;

  // Datumi
  final DateTime startNedelja;
  final DateTime endNedelja;

  V2FinansijskiIzvestaj({
    required this.prihodNedelja,
    required this.troskoviNedelja,
    required this.netoNedelja,
    required this.voznjiNedelja,
    required this.prihodMesec,
    required this.troskoviMesec,
    required this.netoMesec,
    required this.voznjiMesec,
    required this.prihodGodina,
    required this.troskoviGodina,
    required this.netoGodina,
    required this.voznjiGodina,
    required this.prihodProslaGodina,
    required this.troskoviProslaGodina,
    required this.netoProslaGodina,
    required this.voznjiProslaGodina,
    required this.proslaGodina,
    required this.troskoviPoTipu,
    required this.ukupnoMesecniTroskovi,
    required this.potrazivanja,
    required this.startNedelja,
    required this.endNedelja,
  });

  /// Formatiran datum nedelje
  String get nedeljaPeriod {
    return '${startNedelja.day}.${startNedelja.month}. - ${endNedelja.day}.${endNedelja.month}.';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! V2FinansijskiIzvestaj) return false;
    return prihodMesec == other.prihodMesec &&
        troskoviMesec == other.troskoviMesec &&
        prihodGodina == other.prihodGodina &&
        potrazivanja == other.potrazivanja &&
        voznjiMesec == other.voznjiMesec;
  }

  @override
  int get hashCode => Object.hash(prihodMesec, troskoviMesec, prihodGodina, potrazivanja, voznjiMesec);
}
