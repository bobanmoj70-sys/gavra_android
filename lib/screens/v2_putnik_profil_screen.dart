import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../globals.dart';
import '../helpers/v2_putnik_statistike_helper.dart';
import '../models/v2_registrovani_putnik.dart';
import '../services/realtime/v2_master_realtime_manager.dart';
import '../services/v2_adresa_supabase_service.dart';
import '../services/v2_auth_manager.dart';
import '../services/v2_cena_obracun_service.dart';
import '../services/v2_polasci_service.dart';
import '../services/v2_push_token_service.dart'; // Push token + V2PutnikPushService
import '../services/v2_statistika_istorija_service.dart';
import '../services/v2_theme_manager.dart';
import '../services/v2_weather_service.dart'; // Vremenska prognoza
import '../theme.dart';
import '../utils/v2_app_snack_bar.dart';
import '../widgets/v2_kombi_eta_widget.dart'; // 🆕 Jednostavan ETA widget
import '../widgets/v2_time_picker_cell.dart';

/// MESEČNI V2Putnik PROFIL SCREEN
/// Prikazuje podatke o mesečnom putniku: raspored, vožnje, dugovanja
class V2PutnikProfilScreen extends StatefulWidget {
  final Map<String, dynamic> putnikData;

  const V2PutnikProfilScreen({super.key, required this.putnikData});

  @override
  State<V2PutnikProfilScreen> createState() => _V2PutnikProfilScreenState();
}

class _V2PutnikProfilScreenState extends State<V2PutnikProfilScreen> with WidgetsBindingObserver {
  Map<String, dynamic> _putnikData = {};
  bool _isLoading = false;
  PermissionStatus _notificationStatus = PermissionStatus.granted;

  int _brojVoznji = 0;
  int _brojOtkazivanja = 0;
  List<Map<String, dynamic>> _istorijaPl = [];

  // Statistike - detaljno po zapisima iz dnevnika
  final Map<String, List<Map<String, dynamic>>> _voznjeDetaljno = {}; // mesec -> lista zapisa vožnji
  final Map<String, List<Map<String, dynamic>>> _otkazivanjaDetaljno = {}; // mesec -> lista zapisa otkazivanja
  double _ukupnoZaduzenje = 0.0; // ukupno zaduženje za celu godinu
  double _cenaPoVoznji = 0.0; // Cena po vožnji/danu
  String? _adresaBC; // BC adresa
  String? _adresaVS; // VS adresa
  String? _sledecaVoznjaInfo; // Format: "Ponedeljak BC - 7:00" ili null

  late final Stream<void> _cacheStream;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Prati lifecycle aplikacije
    _checkNotificationPermission(); // Proveri dozvolu za notifikacije

    navBarTypeNotifier.addListener(_onSeasonChanged);

    _putnikData = Map<String, dynamic>.from(widget.putnikData);
    _cacheStream = V2MasterRealtimeManager.instance.v2StreamFromCache(
      tables: ['v2_polasci'],
      build: () {},
    );
    _refreshPutnikData();
    _registerPushToken();
    V2WeatherService.refreshAll();
  }

  /// Reaguje na promenu sezone
  void _onSeasonChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    navBarTypeNotifier.removeListener(_onSeasonChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Kada se korisnik vrati u aplikaciju, proveri notifikacije ponovo
    if (state == AppLifecycleState.resumed) {
      _checkNotificationPermission();
    }
  }

  /// Proverava status notifikacija
  Future<void> _checkNotificationPermission() async {
    final status = await Permission.notification.status;
    if (mounted) {
      setState(() {
        _notificationStatus = status;
      });
    }
  }

  /// Traži dozvolu ili otvara podešavanja
  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.request();
    if (mounted) {
      setState(() {
        _notificationStatus = status;
      });
    }

    // Ako je trajno odbijeno, otvori podešavanja
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
  }

  /// Registruje push token za notifikacije (retry mehanizam)
  Future<void> _registerPushToken() async {
    final putnikId = _putnikData['id'];
    if (putnikId != null) {
      final tabela = _putnikData['_tabela'] as String? ?? _putnikData['putnik_tabela'] as String?;
      await V2PutnikPushService.registerPutnikToken(putnikId, putnikTabela: tabela);
    }
  }

  Future<void> _refreshPutnikData() async {
    try {
      final putnikId = _putnikData['id']?.toString();
      if (putnikId == null) return;

      // Prvo pokušaj iz v2 cache-a
      final cached = V2MasterRealtimeManager.instance.v2GetPutnikById(putnikId);
      if (cached != null && mounted) {
        setState(() {
          _putnikData = Map<String, dynamic>.from(cached);
          _isLoading = false;
        });
        _loadStatistike();
        return;
      }

      // Fallback: pretraži sve v2 tabele
      final response = await V2MasterRealtimeManager.instance.v2FindPutnikById(putnikId);

      if (response != null && mounted) {
        setState(() {
          _putnikData = Map<String, dynamic>.from(response);
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
      // Uvijek učitaj statistike (sa svežim ili postojećim podacima)
      _loadStatistike();
    } catch (e) {
      debugPrint('❌ [_refreshPutnikData] Greška: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// HELPER: Merge-uje nove promene sa postojećim markerima u bazi
  /// Čuva bc_pokupljeno, bc_placeno, vs_pokupljeno, vs_placeno i ostale markere
  // UKLONJENO: _checkAndResolvePendingRequests() funkcija
  // Razlog: Client-side pending resolution je konflikovao sa Supabase cron jobs
  // Sva pending logika se sada obrađuje server-side putem:
  // - Job #7: resolve-pending-main (svaki minut)
  // - Job #5: resolve-pending-20h-ucenici (u 20:00)
  // - Job #6: cleanup-expired-pending (svakih 5 minuta)

  // _cleanupOldSeatRequests() uklonjen — metoda je bila prazan stub.
  // Brisanje v2_polasci redova nije dozvoljeno iz klijentskog koda (videti PRAVILA.md).
  // Cleanup se radi server-side putem Supabase cron job-ova.

  /// Helperi za sigurno parsiranje brojeva iz Supabase-a (koji mogu biti String)
  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  /// Učitava statistike za profil (vožnje i otkazivanja)
  Future<void> _loadStatistike() async {
    final now = DateTime.now();
    final pocetakGodine = DateTime(now.year, 1, 1);
    final putnikId = _putnikData['id'];
    if (putnikId == null) return;

    try {
      final tipPutnikaRaw = _v2TipIzTabele(_putnikData);
      bool isJeDnevni(String t) => t.contains('dnevni') || t.contains('posiljka') || t.contains('pošiljka');
      final jeDnevni = isJeDnevni(tipPutnikaRaw);

      // 1+2. Jedan upit za SVE zapise od poč. godine (obuhvata tekući mesec i istoriju)
      // Filtriramo client-side po mesecu — izbegavamo 2 odvojena upita
      final datumPocetakMeseca = DateTime(now.year, now.month, 1).toIso8601String().split('T')[0];
      final datumKrajMeseca = DateTime(now.year, now.month + 1, 0).toIso8601String().split('T')[0];

      // Jedan upit: sve voznje+otkazivanja+uplate od poč. godine
      final sveZapisiGodina = await V2StatistikaIstorijaService.getSveZapisiGodina(
        putnikId: putnikId,
        pocetakGodineIso: pocetakGodine.toIso8601String().split('T')[0],
      );

      // Filtriraj vožnje i otkazivanja ovog meseca iz već dohvaćenih podataka
      final voznjeResponse = sveZapisiGodina.where((r) {
        final d = r['datum'] as String?;
        return r['tip'] == 'voznja' &&
            d != null &&
            d.compareTo(datumPocetakMeseca) >= 0 &&
            d.compareTo(datumKrajMeseca) <= 0;
      }).toList();
      final otkazivanjaResponse = sveZapisiGodina.where((r) {
        final d = r['datum'] as String?;
        return r['tip'] == 'otkazivanje' &&
            d != null &&
            d.compareTo(datumPocetakMeseca) >= 0 &&
            d.compareTo(datumKrajMeseca) <= 0;
      }).toList();

      // Broj vožnji ovog meseca — 1 red = 1 vožnja
      final Set<String> daniSaVoznjom = {};
      for (final v in voznjeResponse) {
        final d = v['datum'] as String?;
        if (d != null) daniSaVoznjom.add(d);
      }
      final int brojVoznjiTotal = jeDnevni ? voznjeResponse.length : daniSaVoznjom.length;

      // Broj otkazivanja ovog meseca — 1 red = 1 otkazivanje
      final Set<String> daniSaOtkazivanjem = {};
      for (final o in otkazivanjaResponse) {
        final d = o['datum'] as String?;
        if (d != null && !daniSaVoznjom.contains(d)) daniSaOtkazivanjem.add(d);
      }
      final int brojOtkazivanjaTotal = jeDnevni ? otkazivanjaResponse.length : daniSaOtkazivanjem.length;

      // Učitaj obe adrese iz cache-a (nula DB upita)
      String? adresaBcNaziv;
      String? adresaVsNaziv;
      final adresaBcId = _putnikData['adresa_bela_crkva_id'] as String?;
      final adresaVsId = _putnikData['adresa_vrsac_id'] as String?;

      try {
        if (adresaBcId != null && adresaBcId.isNotEmpty) {
          adresaBcNaziv = V2AdresaSupabaseService.getAdresaByUuid(adresaBcId)?.naziv;
        }
        if (adresaVsId != null && adresaVsId.isNotEmpty) {
          adresaVsNaziv = V2AdresaSupabaseService.getAdresaByUuid(adresaVsId)?.naziv;
        }
      } catch (e) {
        debugPrint('❌ [Adrese] Greška: $e');
      }

      // Vožnje po mesecima iz već dohvaćenih sveZapisiGodina (nula dodatnih upita)
      // Istorija plaćanja - grupiše uplate iz iste kolekcije
      final Map<String, List<Map<String, dynamic>>> voznjeDetaljnoMap = {};
      final Map<String, List<Map<String, dynamic>>> otkazivanjaDetaljnoMap = {};

      for (final v in sveZapisiGodina) {
        final datumStr = v['datum'] as String?;
        if (datumStr == null) continue;
        final datum = DateTime.tryParse(datumStr);
        if (datum == null) continue;

        final mesecKey = '${datum.year}-${datum.month.toString().padLeft(2, '0')}';
        final tip = v['tip'] as String?;

        if (tip == 'otkazivanje') {
          otkazivanjaDetaljnoMap[mesecKey] = [...(otkazivanjaDetaljnoMap[mesecKey] ?? []), v];
        } else if (tip == 'voznja') {
          voznjeDetaljnoMap[mesecKey] = [...(voznjeDetaljnoMap[mesecKey] ?? []), v];
        }
      }

      // Obračun dugovanja — iz sveZapisiGodina (nema dodatnih DB upita)
      final putnikModel = V2RegistrovaniPutnik.fromMap(_putnikData);
      final cenaPoVoznji = V2CenaObracunService.getCenaPoDanu(putnikModel);

      final sveVoznjeGodina = sveZapisiGodina.where((r) => r['tip'] == 'voznja').toList();
      double ukupnoZaplacanje = 0;
      if (jeDnevni) {
        ukupnoZaplacanje = sveVoznjeGodina.length * cenaPoVoznji;
      } else {
        final Set<String> daniSet = {};
        for (final v in sveVoznjeGodina) {
          final d = v['datum'] as String?;
          if (d != null) daniSet.add(d);
        }
        ukupnoZaplacanje = daniSet.length * cenaPoVoznji;
      }

      final uplateGodina = sveZapisiGodina.where((r) => r['tip'] == 'uplata');
      double ukupnoUplaceno = 0;
      for (final u in uplateGodina) {
        ukupnoUplaceno += _toDouble(u['iznos']);
      }

      // Istorija plaćanja za UI prikaz (iz iste kolekcije — nema DB upita)
      final istorija = _izracunajIstorijuIzKolekcije(sveZapisiGodina);

      final pocetniDugRaw = _toDouble(_putnikData['dug']);
      final zaduzenje = pocetniDugRaw + (ukupnoZaplacanje - ukupnoUplaceno);

      if (mounted) {
        setState(() {
          _brojVoznji = brojVoznjiTotal;
          _brojOtkazivanja = brojOtkazivanjaTotal;
          _istorijaPl = istorija;
          _voznjeDetaljno.clear();
          _voznjeDetaljno.addAll(voznjeDetaljnoMap);
          _otkazivanjaDetaljno.clear();
          _otkazivanjaDetaljno.addAll(otkazivanjaDetaljnoMap);
          _ukupnoZaduzenje = zaduzenje;
          _cenaPoVoznji = cenaPoVoznji;
          _adresaBC = adresaBcNaziv;
          _adresaVS = adresaVsNaziv;
          _sledecaVoznjaInfo = _izracunajSledecuVoznju();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ [_loadStatistike] Finalna greška: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 🆕 Izračunaj sledeću zakazanu vožnju putnika
  /// Vraća format: "Ponedeljak BC - 7:00" ili null ako nema zakazanih vožnji
  String? _izracunajSledecuVoznju() {
    try {
      final putnikId = _putnikData['id']?.toString();
      if (putnikId == null) return null;
      const aktivniStatusi = ['obrada', 'odobreno', 'pokupljen'];
      final polasci = V2MasterRealtimeManager.instance.polasciCache.values
          .where((r) => r['putnik_id']?.toString() == putnikId && aktivniStatusi.contains(r['status'] as String?))
          .toList();
      if (polasci.isEmpty) return null;

      final now = DateTime.now();
      final daniPuniNaziv = <String, String>{};
      for (int i = 0; i < _abbrs.length; i++) {
        daniPuniNaziv[_abbrs[i]] = _names2[i];
      }

      // Sortiraj zahteve po redosledu dana u sedmici (od danas na dalje)
      // Vikend (sub=6, ned=7) → počni od ponedeljka (sve radne dane prikaži)
      // todayWd=0 vikendom jer 0 < 1 (pon), pa orderedDani = [pon, uto, sre, cet, pet]
      final todayWd = now.weekday >= 6 ? 0 : now.weekday; // 1=pon...5=pet, 0=vikend
      final daniOrder = ['pon', 'uto', 'sre', 'cet', 'pet'];
      final orderedDani = [
        ...daniOrder.where((d) => daniOrder.indexOf(d) + 1 >= todayWd),
        ...daniOrder.where((d) => daniOrder.indexOf(d) + 1 < todayWd),
      ];

      for (final danKratica in orderedDani) {
        final req = polasci.where((r) => (r['dan'] as String?)?.toLowerCase() == danKratica).where((r) {
          final status = r['status'] as String?;
          return status != 'otkazano';
        }).firstOrNull;

        if (req == null) continue;

        final polazakRaw = (req['dodeljeno_vreme'] ?? '').toString().trim();
        final polazakParts = polazakRaw.split(':');
        final polazakH = polazakParts.isNotEmpty ? (int.tryParse(polazakParts[0]) ?? 0) : 0;
        final polazakM = polazakParts.length > 1 ? (int.tryParse(polazakParts[1]) ?? 0) : 0;
        final polazak = '$polazakH:${polazakM.toString().padLeft(2, '0')}';
        if (polazak.isEmpty) continue;

        // Ako je danas radni dan, proveri da li je polazak prošao
        final danWd = daniOrder.indexOf(danKratica) + 1;
        if (danWd == todayWd) {
          if (polazakH * 60 + polazakM < now.hour * 60 + now.minute - 30) continue;
        }

        final gradRaw = (req['grad'] ?? '').toString();
        final grad = gradRaw.isEmpty ? 'BC' : gradRaw;
        final danNaziv = daniPuniNaziv[danKratica] ?? danKratica;
        return '$danNaziv $grad - $polazak';
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Vraća vreme polaska za DANAS (npr. '7:00') iz aktivnih zahteva, ili null
  String? _getVremeZaDanas() {
    try {
      final putnikId = _putnikData['id']?.toString();
      if (putnikId == null) return null;
      const daniOrder = ['pon', 'uto', 'sre', 'cet', 'pet'];
      final now = DateTime.now();
      if (now.weekday > 5) return null; // vikend
      final danasKratica = daniOrder[now.weekday - 1];
      final polasci = V2MasterRealtimeManager.instance.polasciCache.values
          .where((r) => r['putnik_id']?.toString() == putnikId)
          .toList();
      final req = polasci.where((r) {
        if ((r['dan'] as String?)?.toLowerCase() != danasKratica) return false;
        final status = r['status'] as String?;
        return status != 'otkazano' && status != 'odbijeno';
      }).firstOrNull;
      if (req == null) return null;
      return (req['dodeljeno_vreme'] ?? '').toString().trim();
    } catch (e) {
      return null;
    }
  }

  /// Izračunaj istoriju plaćanja iz već učitane kolekcije zapisa (nema DB upita)
  static List<Map<String, dynamic>> _izracunajIstorijuIzKolekcije(List<dynamic> sviZapisi) {
    try {
      final Map<String, double> poMesecima = {};
      final Map<String, DateTime> poslednjeDatum = {};
      for (final p in sviZapisi) {
        final tip = p['tip'] as String?;
        if (tip != 'uplata') continue;
        final datumStr = p['datum'] as String?;
        if (datumStr == null) continue;
        final datum = DateTime.tryParse(datumStr);
        if (datum == null) continue;
        final mesecKey = '${datum.year}-${datum.month.toString().padLeft(2, '0')}';
        poMesecima[mesecKey] = (poMesecima[mesecKey] ?? 0.0) + _toDouble(p['iznos']);
        if (!poslednjeDatum.containsKey(mesecKey) || datum.isAfter(poslednjeDatum[mesecKey]!)) {
          poslednjeDatum[mesecKey] = datum;
        }
      }
      final result = poMesecima.entries.map((e) {
        final parts = e.key.split('-');
        return {
          'mesec': int.parse(parts[1]),
          'godina': int.parse(parts[0]),
          'iznos': e.value,
          'datum': poslednjeDatum[e.key]
        };
      }).toList();
      result.sort((a, b) {
        final dateA = DateTime(a['godina'] as int, a['mesec'] as int);
        final dateB = DateTime(b['godina'] as int, b['mesec'] as int);
        return dateB.compareTo(dateA);
      });
      return result;
    } catch (e) {
      return [];
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Odjava?', style: TextStyle(color: Colors.white)),
        content: Text('Da li želiš da se odjaviš?', style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ne')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Da, odjavi me'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final putnikId = _putnikData['id']?.toString();
      if (putnikId != null) {
        try {
          await V2PushTokenService.clearToken(putnikId: putnikId);
        } catch (e) {}
      }
      if (mounted) {
        await V2AuthManager.logout(context);
      }
    }
  }

  /// Dugme za postavljanje bolovanja/godišnjeg - SAMO za radnike
  Widget _buildOdsustvoButton() {
    final status = _putnikData['status']?.toString().toLowerCase() ?? 'aktivan';
    final jeNaOdsustvu = status == 'bolovanje' || status == 'godisnji';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: ListTile(
          leading: Icon(
            jeNaOdsustvu ? Icons.work : Icons.beach_access,
            color: jeNaOdsustvu ? Colors.green : Colors.orange,
          ),
          title: Text(
            jeNaOdsustvu ? 'Vratite se na posao' : 'Godišnji / Bolovanje',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            jeNaOdsustvu
                ? 'Trenutno ste na ${status == "godisnji" ? "godišnjem odmoru" : "bolovanju"}'
                : 'Postavite se na odsustvo',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.white54),
          onTap: () => _pokaziOdsustvoDialog(jeNaOdsustvu),
        ),
      ),
    );
  }

  /// Dialog za odabir tipa odsustva ili vraćanje na posao
  Future<void> _pokaziOdsustvoDialog(bool jeNaOdsustvu) async {
    if (jeNaOdsustvu) {
      // Vraćanje na posao
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: const Row(
            children: [
              Icon(Icons.work, color: Colors.green),
              SizedBox(width: 8),
              Expanded(child: Text('Povratak na posao')),
            ],
          ),
          content: const Text('Da li želite da se vratite na posao?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ne')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Da, vraćam se'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        await _postaviStatus('aktivan');
      }
    } else {
      // Odabir tipa odsustva
      final odabraniStatus = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: const Row(
            children: [
              Icon(Icons.beach_access, color: Colors.orange),
              SizedBox(width: 8),
              Text('Odsustvo'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Izaberite tip odsustva:'),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'godisnji'),
                  icon: const Icon(Icons.beach_access),
                  label: const Text('🏖️ Godišnji odmor'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'bolovanje'),
                  icon: const Icon(Icons.sick),
                  label: const Text('🤒 Bolovanje'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Odustani'))],
        ),
      );

      if (odabraniStatus != null) {
        await _postaviStatus(odabraniStatus);
      }
    }
  }

  /// Postavi status putnika u bazu
  Future<void> _postaviStatus(String noviStatus) async {
    try {
      final putnikId = _putnikData['id']?.toString();
      if (putnikId == null) return;

      final tabela = _putnikData['_tabela'] as String? ?? 'v2_radnici';
      await V2MasterRealtimeManager.instance.v2UpdatePutnik(
        putnikId,
        {'status': noviStatus},
        tabela,
      );

      setState(() {
        _putnikData['status'] = noviStatus;
      });

      if (mounted) {
        final poruka = noviStatus == 'aktivan'
            ? 'Vraćeni ste na posao'
            : noviStatus == 'godisnji'
                ? 'Postavljeni ste na godišnji odmor'
                : 'Postavljeni ste na bolovanje';

        V2AppSnackBar.info(context, poruka);
      }
    } catch (e) {
      if (mounted) {
        V2AppSnackBar.error(context, 'Greška: $e');
      }
    }
  }

  // KOMPAKTAN PRIKAZ TEMPERATURE ZA GRAD (isti kao na danas_screen)
  Widget _buildWeatherCompact(String grad) {
    final stream = grad == 'BC' ? V2WeatherService.bcWeatherStream : V2WeatherService.vsWeatherStream;

    return StreamBuilder<V2WeatherData?>(
      stream: stream,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final temp = data?.temperature;
        final icon = data?.icon ?? '🌡️';
        final tempStr = temp != null ? '${temp.round()}°' : '--';
        final tempColor = temp != null
            ? (temp < 0
                ? Colors.lightBlue
                : temp < 15
                    ? Colors.cyan
                    : temp < 25
                        ? Colors.green
                        : Colors.orange)
            : Colors.grey;

        // Widget za ikonu - slika ili emoji (usklađene veličine)
        Widget iconWidget;
        if (V2WeatherData.isAssetIcon(icon)) {
          iconWidget = Image.asset(V2WeatherData.getAssetPath(icon), width: 32, height: 32);
        } else {
          iconWidget = Text(icon, style: const TextStyle(fontSize: 14));
        }

        return GestureDetector(
          onTap: () => _showWeatherDialog(grad, data),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconWidget,
              const SizedBox(width: 2),
              Text(
                '$grad $tempStr',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: tempColor,
                  shadows: const [Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black54)],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // DIJALOG ZA DETALJNU VREMENSKU PROGNOZU
  void _showWeatherDialog(String grad, V2WeatherData? data) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.9),
          decoration: BoxDecoration(
            gradient: Theme.of(context).backgroundGradient,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 2)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).glassContainer,
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '🌤️ Vreme - $grad',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(20),
                child: data != null
                    ? Column(
                        children: [
                          // Upozorenje za kišu/sneg
                          if (data.willSnow)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('❄️', style: TextStyle(fontSize: 20)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'SNEG ${data.precipitationStartTime ?? 'SADA'}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (data.willRain)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.indigo.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.indigo.shade200),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('🌧️', style: TextStyle(fontSize: 20)),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'KIŠA ${data.precipitationStartTime ?? 'SADA'}${data.precipitationProbability != null ? " (${data.precipitationProbability}%)" : ''}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // Velika ikona i temperatura
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (V2WeatherData.isAssetIcon(data.icon))
                                Image.asset(V2WeatherData.getAssetPath(data.icon), width: 80, height: 80)
                              else
                                Text(data.icon, style: const TextStyle(fontSize: 60)),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${data.temperature.round()}°C',
                                    style: TextStyle(
                                      fontSize: 42,
                                      fontWeight: FontWeight.bold,
                                      color: data.temperature < 0
                                          ? Colors.lightBlue
                                          : data.temperature < 15
                                              ? Colors.cyan
                                              : data.temperature < 25
                                                  ? Colors.white
                                                  : Colors.orange,
                                      shadows: const [
                                        Shadow(offset: Offset(2, 2), blurRadius: 4, color: Colors.black54),
                                      ],
                                    ),
                                  ),
                                  if (data.tempMin != null && data.tempMax != null)
                                    Text(
                                      '${data.tempMin!.round()}° / ${data.tempMax!.round()}°',
                                      style: const TextStyle(fontSize: 16, color: Colors.white70),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Opis baziran na weather code
                          Text(
                            _getWeatherDescription(data.dailyWeatherCode ?? data.weatherCode),
                            style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w500),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      )
                    : const Center(
                        child: Text('Podaci nisu dostupni', style: TextStyle(color: Colors.white70, fontSize: 16)),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _getWeatherDescription(int code) {
    if (code == 0) return 'Vedro nebo';
    if (code == 1) return 'Pretežno vedro';
    if (code == 2) return 'Delimično oblačno';
    if (code == 3) return 'Oblačno';
    if (code >= 45 && code <= 48) return 'Magla';
    if (code >= 51 && code <= 55) return 'Sitna kiša';
    if (code >= 56 && code <= 57) return 'Ledena kiša';
    if (code >= 61 && code <= 65) return 'Kiša';
    if (code >= 66 && code <= 67) return 'Ledena kiša';
    if (code >= 71 && code <= 77) return 'Sneg';
    if (code >= 80 && code <= 82) return 'Pljuskovi';
    if (code >= 85 && code <= 86) return 'Snežni pljuskovi';
    if (code >= 95 && code <= 99) return 'Grmljavina';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    // Ime može biti u 'putnik_ime' ili odvojeno 'ime'/'prezime'
    final putnikIme = _putnikData['putnik_ime'] as String? ?? '';
    final ime = _putnikData['ime'] as String? ?? '';
    final prezime = _putnikData['prezime'] as String? ?? '';
    final fullName = putnikIme.isNotEmpty ? putnikIme : '$ime $prezime'.trim();

    // Razdvoji ime i prezime za avatar
    final nameParts = fullName.split(' ');
    final firstName = nameParts.isNotEmpty ? nameParts.first : '';
    final lastName = nameParts.length > 1 ? nameParts.last : '';

    final telefon = _putnikData['broj_telefona'] as String? ?? '-';
    final grad = _putnikData['grad'] as String? ?? 'BC';
    final tip = _v2TipIzTabele(_putnikData);
    final tipPrikazivanja = _putnikData['tip_prikazivanja'] as String? ?? 'standard';

    return StreamBuilder<void>(
      stream: _cacheStream,
      builder: (context, __) {
        return Container(
          decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: const Text(
                'Moj profil',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.palette, color: Colors.white),
                  tooltip: 'Tema',
                  onPressed: () async {
                    await V2ThemeManager().nextTheme();
                    if (mounted) setState(() {});
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.red),
                  onPressed: _logout,
                ),
              ],
            ),
            body: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.amber))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // VREMENSKA PROGNOZA - BC levo, VS desno
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: Center(child: _buildWeatherCompact('BC'))),
                              const SizedBox(width: 16),
                              Expanded(child: Center(child: _buildWeatherCompact('VS'))),
                            ],
                          ),
                        ),

                        // NOTIFIKACIJE UPOZORENJE (ako su ugašene)
                        if (_notificationStatus.isDenied || _notificationStatus.isPermanentlyDenied)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.redAccent),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.notifications_off, color: Colors.white),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Notifikacije isključene!',
                                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        'Nećete videti potvrde vožnji.',
                                        style: TextStyle(color: Colors.white70, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: _requestNotificationPermission,
                                  style: TextButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.red,
                                  ),
                                  child: const Text('UKLJUČI'),
                                ),
                              ],
                            ),
                          ),

                        // Ime i status - Flow dizajn bez Card okvira
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              // Avatar - glassmorphism stil
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: tip == 'ucenik'
                                        ? [Colors.blue.shade400, Colors.indigo.shade600]
                                        : tip == 'posiljka'
                                            ? [Colors.purple.shade400, Colors.deepPurple.shade600]
                                            : [Colors.orange.shade400, Colors.deepOrange.shade600],
                                  ),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (tip == 'ucenik'
                                              ? Colors.blue
                                              : tip == 'posiljka'
                                                  ? Colors.purple
                                                  : Colors.orange)
                                          .withValues(alpha: 0.4),
                                      blurRadius: 20,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    '${firstName.isNotEmpty ? firstName[0].toUpperCase() : ''}${lastName.isNotEmpty ? lastName[0].toUpperCase() : ''}',
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 2,
                                      shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black38)],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Ime
                              Text(
                                fullName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Tip i grad
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: tip == 'ucenik'
                                          ? Colors.blue.withValues(alpha: 0.3)
                                          : (tip == 'dnevni' || tipPrikazivanja == 'DNEVNI')
                                              ? Colors.green.withValues(alpha: 0.3)
                                              : tip == 'posiljka'
                                                  ? Colors.purple.withValues(alpha: 0.3)
                                                  : Colors.orange.withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                                    ),
                                    child: Text(
                                      tip == 'ucenik'
                                          ? '🎓 Učenik'
                                          : tip == 'posiljka'
                                              ? '📦 Pošiljka'
                                              : tip == 'radnik'
                                                  ? '💼 Radnik'
                                                  : tip == 'dnevni'
                                                      ? '📅 Dnevni'
                                                      : '👤 V2Putnik',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  if (telefon.isNotEmpty && telefon != '-') ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.phone, color: Colors.white70, size: 14),
                                          const SizedBox(width: 4),
                                          Text(
                                            telefon,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Adrese - BC levo, VS desno
                              if (_adresaBC != null || _adresaVS != null)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (_adresaBC != null && _adresaBC!.isNotEmpty) ...[
                                      Icon(Icons.home, color: Colors.white70, size: 16),
                                      const SizedBox(width: 4),
                                      Text(
                                        _adresaBC!,
                                        style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
                                      ),
                                    ],
                                    if (_adresaBC != null && _adresaVS != null) const SizedBox(width: 16),
                                    if (_adresaVS != null && _adresaVS!.isNotEmpty) ...[
                                      Icon(Icons.work, color: Colors.white70, size: 16),
                                      const SizedBox(width: 4),
                                      Text(
                                        _adresaVS!,
                                        style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
                                      ),
                                    ],
                                  ],
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ─────────── Divider ───────────
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Divider(color: Colors.white.withValues(alpha: 0.2), thickness: 1),
                        ),

                        // ETA Widget sa fazama:
                        // 0. Nema dozvola: "Odobravanjem GPS i notifikacija ovde će vam biti prikazano vreme dolaska prevoza"
                        // 1. 30 min pre polaska: "Vozač će uskoro krenuti"
                        // 2. Vozač startovao rutu: Realtime ETA praćenje
                        // 3. Pokupljen: "Pokupljeni ste u HH:MM" (stoji 60 min) - ČITA IZ BAZE!
                        // 4. Nakon 60 min: "Vaša sledeća vožnja: dan, vreme"
                        V2KombiEtaWidget(
                          putnikIme: fullName,
                          grad: grad,
                          sledecaVoznja: _sledecaVoznjaInfo,
                          putnikId: _putnikData['id']?.toString(),
                          vreme: _getVremeZaDanas(), // 🆕 Filter po terminu polaska
                        ),

                        // ─────────── Divider ───────────

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Divider(color: Colors.white.withValues(alpha: 0.2), thickness: 1),
                        ),
                        const SizedBox(height: 8),

                        // Statistike - Prikazano za sve, ali dnevni/pošiljka broje svako pokupljenje
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard('🚌', 'Vožnje', _brojVoznji.toString(), Colors.blue, 'ovaj mesec'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildStatCard(
                                '❌',
                                'Otkazano',
                                _brojOtkazivanja.toString(),
                                Colors.orange,
                                'ovaj mesec',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Bolovanje/Godišnji dugme - SAMO za radnike
                        if ((_putnikData['_tabela'] ?? _putnikData['putnik_tabela'] ?? '').toString() ==
                            'v2_radnici') ...[
                          _buildOdsustvoButton(),
                          const SizedBox(height: 16),
                        ],

                        // TRENUTNO ZADUŽENJE
                        if (_putnikData['cena_po_danu'] != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: _ukupnoZaduzenje > 0
                                    ? [Colors.red.withValues(alpha: 0.2), Colors.red.withValues(alpha: 0.05)]
                                    : [Colors.green.withValues(alpha: 0.2), Colors.green.withValues(alpha: 0.05)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _ukupnoZaduzenje > 0
                                    ? Colors.red.withValues(alpha: 0.3)
                                    : Colors.green.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'TRENUTNO STANJE',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 11,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _ukupnoZaduzenje > 0 ? '${_ukupnoZaduzenje.toStringAsFixed(0)} RSD' : 'IZMIRENO OK',
                                  style: TextStyle(
                                    color: _ukupnoZaduzenje > 0 ? Colors.red.shade200 : Colors.green.shade200,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (_cenaPoVoznji > 0) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Cena: ${_cenaPoVoznji.toStringAsFixed(0)} RSD / ${tip.toLowerCase() == 'radnik' || tip.toLowerCase() == 'ucenik' ? 'dan' : 'vožnja'}',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.5),
                                      fontSize: 10,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Detaljne statistike - dugme za dijalog
                        _buildDetaljneStatistikeDugme(),
                        const SizedBox(height: 16),

                        // Raspored polazaka
                        _buildRasporedCard(),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }

  static const _abbrs = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
  static const _names2 = ['Ponedeljak', 'Utorak', 'Sreda', 'Četvrtak', 'Petak', 'Subota', 'Nedelja'];
  static const _statusPrioritet = {
    'bez_polaska': 0,
    'odbijeno': 1,
    'otkazano': 2,
    'obrada': 3,
    'odobreno': 4,
    'pokupljen': 5,
  };
  static const _daniRedosled = {'pon': 0, 'uto': 1, 'sre': 2, 'cet': 3, 'pet': 4};

  /// Widget za prikaz rasporeda polazaka po danima
  Widget _buildRasporedCard() {
    final tip = _v2TipIzTabele(_putnikData);
    final tipPrikazivanja = _putnikData['tip_prikazivanja'] as String? ?? 'standard';

    // 🆕 Inicijalizuj polasci mapu sa praznim vrednostima za svih 7 dana
    Map<String, Map<String, dynamic>> polasci = {};
    for (final shortDay in _abbrs) {
      polasci[shortDay] = {
        'bc': null,
        'vs': null,
        'bc_status': null,
        'vs_status': null,
      };
    }

    // MERGE v2_polasci redova po danima
    final daniNedelje = ['pon', 'uto', 'sre', 'cet', 'pet'];
    final now = DateTime.now();

    // Sortiramo: aktivni (odobreno/obrada) ZADNJI da pregaze otkazane
    // Redosljed: otkazano/bez_polaska/odbijeno → obrada → odobreno → pokupljen
    final putnikId = _putnikData['id']?.toString();
    const aktivniStatusi = ['obrada', 'odobreno', 'otkazano', 'odbijeno', 'bez_polaska', 'pokupljen'];
    final sortedRequests = V2MasterRealtimeManager.instance.polasciCache.values
        .where((r) => r['putnik_id']?.toString() == putnikId && aktivniStatusi.contains(r['status'] as String?))
        .toList();
    // Sortiraj po dan kratica redosledu (pon→pet), pa po statusu prioritetu
    sortedRequests.sort((a, b) {
      final aDan = _daniRedosled[(a['dan'] as String?)?.toLowerCase() ?? ''] ?? 9;
      final bDan = _daniRedosled[(b['dan'] as String?)?.toLowerCase() ?? ''] ?? 9;
      final danCmp = aDan.compareTo(bDan);
      if (danCmp != 0) return danCmp;
      final aPrio = _statusPrioritet[a['status']] ?? 0;
      final bPrio = _statusPrioritet[b['status']] ?? 0;
      return aPrio.compareTo(bPrio);
    });

    for (final req in sortedRequests) {
      try {
        final danKratica = (req['dan'] as String?)?.toLowerCase();
        if (danKratica == null || !daniNedelje.contains(danKratica)) continue;

        final gradRaw = (req['grad'] ?? '').toString().toLowerCase();
        // Normalizuj grad na 'bc' ili 'vs'
        final grad = (gradRaw == 'vs' || gradRaw.contains('vr')) ? 'vs' : 'bc';
        final status = req['status'] as String?;
        // Normalizuj na HH:MM (baza vraća '12:00:00', TimePickerCell očekuje '12:00')
        final vremeRaw = (req['dodeljeno_vreme'] ?? req['zeljeno_vreme'] ?? '').toString();
        final vreme = vremeRaw.length >= 5 ? vremeRaw.substring(0, 5) : vremeRaw;

        final existing = polasci[danKratica]!;

        if (status == 'otkazano' || status == 'bez_polaska' || status == 'odbijeno') {
          // Postavi otkazano SAMO ako još nema aktivnog zahtjeva za ovaj grad
          // (aktivni zahtjev dolazi zadnji zbog sortiranja pa će ga pregaziti)
          existing['${grad}_status'] = status;
          existing['${grad}_otkazano'] = status != 'bez_polaska';
          existing['${grad}_otkazano_vreme'] = vreme;
          // bez_polaska: čuvamo vreme u grad ključu da TimePickerCell može prikazati
          // dugme "Bez polaska" kao aktivan izbor (value != null → onChanged se može pozvati)
          if (status == 'bez_polaska' && vreme.isNotEmpty) {
            existing[grad] = vreme;
          }
        } else {
          // Aktivan zahtjev — uvijek pregazuje otkazano
          existing[grad] = vreme;
          existing['${grad}_status'] = status;
          existing['${grad}_otkazano'] = false;
          existing['${grad}_otkazano_vreme'] = null;
        }
      } catch (e) {}
    }

    // Prikazujemo samo radne dane
    final dani = _abbrs.where((d) => d != 'sub' && d != 'ned').toList();
    final daniLabels = <String, String>{};
    for (int i = 0; i < _abbrs.length; i++) {
      final short = _abbrs[i];
      if (short == 'sub' || short == 'ned') continue;
      final long = (i < _names2.length) ? _names2[i] : short;
      daniLabels[short] = long;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              '🕐 Vremena polaska',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const SizedBox(width: 100),
              Expanded(
                  child: Center(
                      child: Text('BC',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.bold, fontSize: 14)))),
              Expanded(
                  child: Center(
                      child: Text('VS',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.bold, fontSize: 14)))),
            ],
          ),
          const SizedBox(height: 8),
          ...dani.map((dan) {
            final danPolasci = polasci[dan]!;
            final bcVreme = danPolasci['bc']?.toString();
            final vsVreme = danPolasci['vs']?.toString();
            final bcStatus = danPolasci['bc_status']?.toString();
            final vsStatus = danPolasci['vs_status']?.toString();
            final bcOtkazano = (danPolasci['bc_otkazano'] == true);
            final vsOtkazano = (danPolasci['vs_otkazano'] == true);
            final bcOtkazanoVreme = danPolasci['bc_otkazano_vreme'];
            final vsOtkazanoVreme = danPolasci['vs_otkazano_vreme'];
            final bcDisplayVreme = bcOtkazano ? bcOtkazanoVreme : bcVreme;
            final vsDisplayVreme = vsOtkazano ? vsOtkazanoVreme : vsVreme;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                      width: 100,
                      child: Text(daniLabels[dan] ?? dan, style: const TextStyle(color: Colors.white, fontSize: 14))),
                  Expanded(
                    child: Center(
                      child: V2TimePickerCell(
                        value: bcDisplayVreme,
                        isBC: true,
                        status: bcStatus,
                        dayName: dan,
                        tipPutnika: tip.toString(),
                        tipPrikazivanja: tipPrikazivanja,
                        onChanged: (newValue) => _updatePolazak(dan, 'bc', newValue),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: V2TimePickerCell(
                        value: vsDisplayVreme,
                        isBC: false,
                        status: vsStatus,
                        dayName: dan,
                        tipPutnika: tip.toString(),
                        tipPrikazivanja: tipPrikazivanja,
                        onChanged: (newValue) => _updatePolazak(dan, 'vs', newValue),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// Ažurira polazak
  Future<void> _updatePolazak(String dan, String tipGrad, String? novoVreme) async {
    final putnikId = _putnikData['id']?.toString();
    if (putnikId == null) return;

    final gradKey = tipGrad.startsWith('bc') ? 'BC' : 'VS';

    // null → bez_polaska (ukloni polazak)
    if (novoVreme == null) {
      try {
        await V2PolasciService.v2OtkaziPutnika(
          putnikId: putnikId,
          grad: gradKey,
          selectedDan: dan,
          status: 'bez_polaska',
        );
      } catch (e) {
        debugPrint('❌ _updatePolazak (bez_polaska): $e');
        if (mounted) V2AppSnackBar.error(context, 'Greška pri uklanjanju polaska.');
        return;
      }
    } else {
      // dan + grad + zeljeno_vreme → pending (V2Putnik šalje zahtev)
      try {
        final rpRow = V2MasterRealtimeManager.instance.v2GetPutnikById(putnikId);
        final brojMesta = (rpRow?['broj_mesta'] as int?) ?? 1;
        // _tabela iz cache-a → npr. 'v2_radnici'
        final putnikTabela = (_putnikData['_tabela'] as String?) ??
            (_putnikData['putnik_tabela'] as String?) ??
            rpRow?['_tabela']?.toString();
        await V2PolasciService.v2PoSaljiZahtev(
          putnikId: putnikId,
          dan: dan,
          grad: gradKey,
          vreme: novoVreme,
          brojMesta: brojMesta,
          isAdmin: false,
          putnikTabela: putnikTabela,
        );
      } catch (e) {
        debugPrint('❌ _updatePolazak: $e');
        if (mounted) V2AppSnackBar.error(context, 'Greška pri čuvanju promene.');
        return;
      }
    }

    await _refreshPutnikData();
    if (mounted) {
      V2AppSnackBar.success(
          context, 'Polazak ažuriran: $dan $gradKey${novoVreme != null ? " $novoVreme" : " uklonjen"}.');
    }
  }

  static Widget _buildStatCard(String icon, String title, String value, Color color, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(icon, style: const TextStyle(fontSize: 18)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  title,
                  style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(
            subtitle,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10),
          ),
        ],
      ),
    );
  }

  /// Dugme za otvaranje detaljnih statistika
  Widget _buildDetaljneStatistikeDugme() {
    return Card(
      color: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).glassBorder, width: 1.5),
      ),
      child: InkWell(
        onTap: () {
          V2PutnikStatistikeHelper.prikaziDetaljneStatistike(
            context: context,
            putnikId: _putnikData['id'] ?? '',
            putnikIme: _putnikData['putnik_ime'] ?? 'Nepoznato',
            tip: _v2TipIzTabele(_putnikData),
            tipSkole: _putnikData['tip_skole'],
            brojTelefona: _putnikData['broj_telefona'],
            createdAt:
                _putnikData['created_at'] != null ? DateTime.tryParse(_putnikData['created_at'].toString()) : null,
            updatedAt:
                _putnikData['updated_at'] != null ? DateTime.tryParse(_putnikData['updated_at'].toString()) : null,
            aktivan: _putnikData['aktivan'] ?? true,
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.analytics_outlined, color: Colors.blue.shade300, size: 24),
              const SizedBox(width: 12),
              const Text(
                'Detaljne statistike',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_ios, color: Colors.white.withValues(alpha: 0.5), size: 16),
            ],
          ),
        ),
      ),
    );
  }

  /// v2 helper: čita tip putnika iz '_tabela' ključa (v2 sistem)
  /// Fallback na stari 'tip' ključ radi kompatibilnosti
  static String _v2TipIzTabele(Map<String, dynamic> data) {
    final tabela = data['_tabela'] as String?;
    if (tabela != null) {
      return switch (tabela) {
        'v2_radnici' => 'radnik',
        'v2_ucenici' => 'ucenik',
        'v2_dnevni' => 'dnevni',
        'v2_posiljke' => 'posiljka',
        _ => 'radnik',
      };
    }
    return (data['tip'] as String? ?? 'radnik').toLowerCase();
  }
}
