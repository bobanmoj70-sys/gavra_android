import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/day_constants.dart';
import '../globals.dart';
import '../helpers/putnik_statistike_helper.dart'; // 📊 Zajednički dijalog za statistike
import '../models/registrovani_putnik.dart';
import '../services/cena_obracun_service.dart';
import '../services/putnik_push_service.dart'; // 📱 Push notifikacije za putnike
import '../services/putnik_service.dart'; // 🏖️ Za bolovanje/godišnji
import '../services/realtime/realtime_manager.dart';
import '../services/theme_manager.dart';
import '../services/weather_service.dart'; // 🌤️ Vremenska prognoza
import '../theme.dart';
import '../utils/app_snack_bar.dart';
import '../utils/date_utils.dart' as app_date_utils;
import '../utils/grad_adresa_validator.dart';
import '../utils/registrovani_helpers.dart';
import '../widgets/kombi_eta_widget.dart'; // 🆕 Jednostavan ETA widget
import '../widgets/shared/time_picker_cell.dart';

/// 📊 MESEČNI PUTNIK PROFIL SCREEN
/// Prikazuje podatke o mesečnom putniku: raspored, vožnje, dugovanja
class RegistrovaniPutnikProfilScreen extends StatefulWidget {
  final Map<String, dynamic> putnikData;

  const RegistrovaniPutnikProfilScreen({super.key, required this.putnikData});

  @override
  State<RegistrovaniPutnikProfilScreen> createState() => _RegistrovaniPutnikProfilScreenState();
}

class _RegistrovaniPutnikProfilScreenState extends State<RegistrovaniPutnikProfilScreen> with WidgetsBindingObserver {
  Map<String, dynamic> _putnikData = {};
  bool _isLoading = false;
  // 🔔 Status notifikacija
  PermissionStatus _notificationStatus = PermissionStatus.granted;

  int _brojVoznji = 0;
  int _brojOtkazivanja = 0;
  // ignore: unused_field
  double _dugovanje = 0.0;
  List<Map<String, dynamic>> _istorijaPl = [];

  // 📊 Statistike - detaljno po zapisima iz dnevnika
  final Map<String, List<Map<String, dynamic>>> _voznjeDetaljno = {}; // mesec -> lista zapisa vožnji
  final Map<String, List<Map<String, dynamic>>> _otkazivanjaDetaljno = {}; // mesec -> lista zapisa otkazivanja
  final Map<String, int> _brojMestaPoVoznji = {}; // datum -> broj_mesta (za tačan obračun)
  double _ukupnoZaduzenje = 0.0; // ukupno zaduženje za celu godinu
  double _cenaPoVoznji = 0.0; // 💰 Cena po vožnji/danu
  String? _adresaBC; // BC adresa
  String? _adresaVS; // VS adresa

  // 🚐 GPS Tracking - više se ne koristi direktno, ETA se čita iz KombiEtaWidget
  // ignore: unused_field
  double? _putnikLat;
  // ignore: unused_field
  double? _putnikLng;
  // ignore: unused_field
  // ignore: unused_field
  String _smerTure = 'BC_VS';
  String? _sledecaVoznjaInfo; // 🆕 Format: "Ponedeljak, 7:00 BC"

  // 🎯 Realtime subscription za status promene
  StreamSubscription? _statusSubscription;
  // 🆕 Realtime subscription za seat request approvals
  StreamSubscription? _seatRequestSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // 🕵️ Prati lifecycle aplikacije
    _checkNotificationPermission(); // 🔍 Proveri dozvolu za notifikacije

    // 🔔 Listen for season changes (auto/zimski/letnji)
    navBarTypeNotifier.addListener(_onSeasonChanged);

    _putnikData = Map<String, dynamic>.from(widget.putnikData);
    _refreshPutnikData(); // 🔄 Učitaj sveže podatke iz baze
    _loadStatistike();
    _registerPushToken(); // 📱 Registruj push token (retry ako nije uspelo pri login-u)
    // ❌ UKLONJENO: Client-side pending resolution - sada se radi putem Supabase cron jobs
    // _checkAndResolvePendingRequests();
    _cleanupOldSeatRequests(); // 🧹 Očisti stare seat_requests iz baze
    WeatherService.refreshAll(); // 🌤️ Učitaj vremensku prognozu
    _setupRealtimeListener(); // 🎯 Sluša promene statusa u realtime
    _loadActiveRequests();
  }

  /// ❄️ Reaguje na promenu sezone
  void _onSeasonChanged() {
    if (mounted) {
      setState(() {
        debugPrint('❄️ [Season] Sezona promenjena na: ${navBarTypeNotifier.value}. Osvežavam UI profil ekrana.');
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    navBarTypeNotifier.removeListener(_onSeasonChanged);
    _statusSubscription?.cancel(); // 🛑 Zatvori Realtime listener
    _seatRequestSubscription?.cancel(); // 🛑 Zatvori Seat Request listener
    RealtimeManager.instance.unsubscribe('registrovani_putnici');
    RealtimeManager.instance.unsubscribe('seat_requests');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 🔄 Kada se korisnik vrati u aplikaciju, proveri notifikacije ponovo
    if (state == AppLifecycleState.resumed) {
      _checkNotificationPermission();
    }
  }

  /// 🔍 Proverava status notifikacija
  Future<void> _checkNotificationPermission() async {
    final status = await Permission.notification.status;
    if (mounted) {
      setState(() {
        _notificationStatus = status;
      });
    }
  }

  /// 🔓 Traži dozvolu ili otvara podešavanja
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

  /// 📱 Registruje push token za notifikacije (retry mehanizam)
  Future<void> _registerPushToken() async {
    final putnikId = _putnikData['id'];
    if (putnikId != null) {
      await PutnikPushService.registerPutnikToken(putnikId);
    }
  }

  /// 🎯 Postavlja Realtime listener za status promene
  void _setupRealtimeListener() {
    final putnikId = _putnikData['id']?.toString();
    if (putnikId == null) return;

    // Koristi RealtimeManager za centralizovanu pretplatu
    _statusSubscription = RealtimeManager.instance.subscribe('registrovani_putnici').where((payload) {
      // Filtriraj samo ako je ažuriran ovaj putnik
      return payload.newRecord['id'].toString() == putnikId;
    }).listen((payload) {
      debugPrint('🎯 [Realtime] Status promena detektovana za putnika $putnikId');
      _handleStatusChange(payload);
    });

    // 🆕 Dodaj listener za seat_requests (sve promene za ovog putnika)
    _seatRequestSubscription = RealtimeManager.instance.subscribe('seat_requests').where((payload) {
      // Filtriraj samo za ovog putnika
      final record = payload.newRecord.isNotEmpty ? payload.newRecord : payload.oldRecord;
      return record['putnik_id'].toString() == putnikId;
    }).listen((payload) {
      debugPrint('🆕 [Realtime] Seat request promena detektovana: ${payload.eventType}');
      _loadActiveRequests(); // Osveži listu zahteva
    });

    debugPrint('🎯 [Realtime] Listener aktivan za putnika $putnikId');
  }

  List<Map<String, dynamic>> _activeSeatRequests = [];

  /// 📥 Učitava aktivne (pending/manual) zahteve iz seat_requests tabele
  Future<void> _loadActiveRequests() async {
    try {
      final putnikId = _putnikData['id']?.toString();
      if (putnikId == null) return;

      // seat_requests.datum je DROPOVAN — filtrira po dan kraticama (radni dani)
      const radniDani = ['pon', 'uto', 'sre', 'cet', 'pet'];

      final res = await supabase
          .from('seat_requests')
          .select()
          .eq('putnik_id', putnikId)
          .inFilter('dan', radniDani)
          .inFilter('status', ['pending', 'manual', 'approved', 'confirmed', 'otkazano', 'cancelled']);

      if (mounted) {
        setState(() {
          _activeSeatRequests = List<Map<String, dynamic>>.from(res);
          _sledecaVoznjaInfo = _izracunajSledecuVoznju(); // 🔄 Reračunaj nakon učitavanja
          debugPrint('📥 [ActiveRequests] Učitano: ${_activeSeatRequests.length} zahteva');
        });
      }
    } catch (e) {
      debugPrint('❌ [ActiveRequests] Greška: $e');
    }
  }

  /// 🔔 Hendluje promenu statusa (confirmed/null) - samo osvežava UI
  Future<void> _handleStatusChange(PostgresChangePayload payload) async {
    try {
      debugPrint('🔄 [Realtime] Osvežavam podatke putnika...');
      await _refreshPutnikData();
      await _loadActiveRequests();

      // ⚠️ FIX: Uklonjen snackbar odavde jer se aktivirao na svaku promenu profila
      // ako je globalni status putnika bio 'approved'
    } catch (e) {
      debugPrint('❌ [Realtime] Greška pri obradi: $e');
    }
  }

  Future<void> _refreshPutnikData() async {
    try {
      final putnikId = _putnikData['id']?.toString();
      if (putnikId == null) return;

      final response = await supabase.from('registrovani_putnici').select().eq('id', putnikId).maybeSingle();

      if (response != null && mounted) {
        setState(() {
          _putnikData = Map<String, dynamic>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ [_refreshPutnikData] Greška: $e');
    }
  }

  /// 🛡️ HELPER: Merge-uje nove promene sa postojećim markerima u bazi
  /// Čuva bc_pokupljeno, bc_placeno, vs_pokupljeno, vs_placeno i ostale markere
  // ❌ UKLONJENO: _checkAndResolvePendingRequests() funkcija
  // Razlog: Client-side pending resolution je konflikovao sa Supabase cron jobs
  // Sva pending logika se sada obrađuje server-side putem:
  // - Job #7: resolve-pending-main (svaki minut)
  // - Job #5: resolve-pending-20h-ucenici (u 20:00)
  // - Job #6: cleanup-expired-pending (svakih 5 minuta)

  /// 🧹 UKLONJENO: Brisanje seat_requests je zabranjeno iz klijentskog koda!
  /// Pravilo: seat_requests je operativna tabela — stari redovi ostaju kao istorija (cron uklonjen).
  /// Videti PRAVILA.md
  Future<void> _cleanupOldSeatRequests() async {
    // NE RADI NIŠTA — brisanje seat_requests nije dozvoljeno iz aplikacije
    debugPrint('⛔ [Cleanup] _cleanupOldSeatRequests je onemogućen - videti PRAVILA.md');
  }

  /// 🔧 Helperi za sigurno parsiranje brojeva iz Supabase-a (koji mogu biti String)
  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  int _toInt(dynamic v, {int defaultValue = 1}) {
    if (v == null) return defaultValue;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? defaultValue;
    return defaultValue;
  }

  /// 📊 Učitava statistike za profil (vožnje i otkazivanja)
  Future<void> _loadStatistike() async {
    final now = DateTime.now();
    final pocetakGodine = DateTime(now.year, 1, 1);
    final putnikId = _putnikData['id'];
    if (putnikId == null) return;

    try {
      final tipPutnikaRaw = (_putnikData['tip'] ?? 'radnik').toString().toLowerCase();
      bool isJeDnevni(String t) => t.contains('dnevni') || t.contains('posiljka') || t.contains('pošiljka');
      final jeDnevni = isJeDnevni(tipPutnikaRaw);

      // 1. Dohvati vožnje za TEKUĆI MESEC
      final datumPocetakMeseca = DateTime(now.year, now.month, 1).toIso8601String().split('T')[0];
      final datumKrajMeseca = DateTime(now.year, now.month + 1, 0).toIso8601String().split('T')[0];

      final voznjeResponse = await supabase
          .from('voznje_log')
          .select('datum, tip, broj_mesta')
          .eq('putnik_id', putnikId)
          .eq('tip', 'voznja')
          .gte('datum', datumPocetakMeseca)
          .lte('datum', datumKrajMeseca);

      // 2. Dohvati otkazivanja za TEKUĆI MESEC
      final otkazivanjaResponse = await supabase
          .from('voznje_log')
          .select('datum, tip, broj_mesta')
          .eq('putnik_id', putnikId)
          .eq('tip', 'otkazivanje')
          .gte('datum', datumPocetakMeseca)
          .lte('datum', datumKrajMeseca);

      // Broj vožnji ovog meseca
      int brojVoznjiTotal = 0;
      final Map<String, int> dailyMaxSeatsV = {};
      if (jeDnevni) {
        for (final v in voznjeResponse) {
          brojVoznjiTotal += _toInt(v['broj_mesta']);
        }
      } else {
        for (final v in voznjeResponse) {
          final d = v['datum'] as String?;
          if (d != null) {
            final bm = _toInt(v['broj_mesta']);
            if (bm > (dailyMaxSeatsV[d] ?? 0)) {
              dailyMaxSeatsV[d] = bm;
            }
          }
        }
        dailyMaxSeatsV.forEach((_, val) => brojVoznjiTotal += val);
      }

      // Broj otkazivanja ovog meseca
      int brojOtkazivanjaTotal = 0;
      if (jeDnevni) {
        for (final o in otkazivanjaResponse) {
          brojOtkazivanjaTotal += _toInt(o['broj_mesta']);
        }
      } else {
        final Map<String, int> dailyMaxSeatsO = {};
        for (final o in otkazivanjaResponse) {
          final d = o['datum'] as String?;
          if (d != null) {
            final bm = _toInt(o['broj_mesta']);
            if (bm > (dailyMaxSeatsO[d] ?? 0)) {
              dailyMaxSeatsO[d] = bm;
            }
          }
        }
        // Broji otkazivanje samo ako taj dan NEMA vožnje (isti dan = vožnja, ne otkazivanje)
        dailyMaxSeatsO.forEach((dan, val) {
          if (!dailyMaxSeatsV.containsKey(dan)) {
            brojOtkazivanjaTotal += val;
          }
        });
      }

      // 🏠 Učitaj obe adrese iz tabele adrese
      String? adresaBcNaziv;
      String? adresaVsNaziv;
      double? putnikLat;
      double? putnikLng;
      final adresaBcId = _putnikData['adresa_bela_crkva_id'] as String?;
      final adresaVsId = _putnikData['adresa_vrsac_id'] as String?;
      final grad = _putnikData['grad'] as String? ?? 'BC';

      try {
        if (adresaBcId != null && adresaBcId.isNotEmpty) {
          final bcResponse =
              await supabase.from('adrese').select('naziv, gps_lat, gps_lng').eq('id', adresaBcId).maybeSingle();
          if (bcResponse != null) {
            adresaBcNaziv = bcResponse['naziv'] as String?;
            if (GradAdresaValidator.isBelaCrkva(grad) &&
                bcResponse['gps_lat'] != null &&
                bcResponse['gps_lng'] != null) {
              putnikLat = _toDouble(bcResponse['gps_lat']);
              putnikLng = _toDouble(bcResponse['gps_lng']);
            }
          }
        }
        if (adresaVsId != null && adresaVsId.isNotEmpty) {
          final vsResponse =
              await supabase.from('adrese').select('naziv, gps_lat, gps_lng').eq('id', adresaVsId).maybeSingle();
          if (vsResponse != null) {
            adresaVsNaziv = vsResponse['naziv'] as String?;
            if (GradAdresaValidator.isVrsac(grad) && vsResponse['gps_lat'] != null && vsResponse['gps_lng'] != null) {
              putnikLat = _toDouble(vsResponse['gps_lat']);
              putnikLng = _toDouble(vsResponse['gps_lng']);
            }
          }
        }
      } catch (e) {
        debugPrint('❌ [Adrese] Greška: $e');
      }

      // 💰 Istorija plaćanja - poslednjih 6 meseci
      final istorija = await _loadIstorijuPlacanja(putnikId);

      // 📊 Vožnje po mesecima (cela godina)
      final sveVoznje = await supabase
          .from('voznje_log')
          .select('datum, tip, created_at')
          .eq('putnik_id', putnikId)
          .gte('datum', pocetakGodine.toIso8601String().split('T')[0])
          .order('datum', ascending: false);

      final Map<String, List<Map<String, dynamic>>> voznjeDetaljnoMap = {};
      final Map<String, List<Map<String, dynamic>>> otkazivanjaDetaljnoMap = {};

      for (final v in sveVoznje) {
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

      // 💰 Obračun dugovanja
      final putnikModel = RegistrovaniPutnik.fromMap(_putnikData);
      final cenaPoVoznji = CenaObracunService.getCenaPoDanu(putnikModel);

      double ukupnoZaplacanje = 0;
      final Map<String, int> brojMestaPoVoznji = {};
      try {
        final sveVoznjeZaDug =
            await supabase.from('voznje_log').select('datum, broj_mesta').eq('putnik_id', putnikId).eq('tip', 'voznja');

        if (jeDnevni) {
          for (final voznja in sveVoznjeZaDug) {
            final bm = _toInt(voznja['broj_mesta']);
            ukupnoZaplacanje += bm * cenaPoVoznji;
            final dStr = voznja['datum'] as String?;
            if (dStr != null) {
              brojMestaPoVoznji[dStr] = (brojMestaPoVoznji[dStr] ?? 0) + bm;
            }
          }
        } else {
          final Map<String, int> dnevniMaxMesta = {};
          for (final voznja in sveVoznjeZaDug) {
            final dStr = voznja['datum'] as String?;
            if (dStr == null) continue;
            final bm = _toInt(voznja['broj_mesta']);
            if (bm > (dnevniMaxMesta[dStr] ?? 0)) {
              dnevniMaxMesta[dStr] = bm;
            }
          }
          dnevniMaxMesta.forEach((datum, maxMesta) {
            ukupnoZaplacanje += maxMesta * cenaPoVoznji;
            brojMestaPoVoznji[datum] = maxMesta;
          });
        }
      } catch (e) {
        debugPrint('❌ [Obračun] Greška: $e');
      }

      double ukupnoUplaceno = 0;
      try {
        final uplateResponse = await supabase
            .from('voznje_log')
            .select('iznos')
            .eq('putnik_id', putnikId)
            .filter('tip', 'in', '("uplata","uplata_mesecna","uplata_dnevna")');

        for (final u in uplateResponse) {
          ukupnoUplaceno += _toDouble(u['iznos']);
        }
      } catch (e) {
        for (final p in istorija) {
          ukupnoUplaceno += _toDouble(p['iznos']);
        }
      }

      final pocetniDugRaw = _toDouble(_putnikData['dug']);
      final zaduzenje = pocetniDugRaw + (ukupnoZaplacanje - ukupnoUplaceno);

      if (mounted) {
        setState(() {
          _brojVoznji = brojVoznjiTotal;
          _brojOtkazivanja = brojOtkazivanjaTotal;
          _dugovanje = zaduzenje;
          _istorijaPl = istorija;
          _voznjeDetaljno.clear();
          _voznjeDetaljno.addAll(voznjeDetaljnoMap);
          _otkazivanjaDetaljno.clear();
          _otkazivanjaDetaljno.addAll(otkazivanjaDetaljnoMap);
          _brojMestaPoVoznji.clear();
          _brojMestaPoVoznji.addAll(brojMestaPoVoznji);
          _ukupnoZaduzenje = zaduzenje;
          _cenaPoVoznji = cenaPoVoznji;
          _adresaBC = adresaBcNaziv;
          _adresaVS = adresaVsNaziv;
          _putnikLat = putnikLat;
          _putnikLng = putnikLng;
          _smerTure = (grad == 'BC' || grad == 'Bela Crkva') ? 'BC_VS' : 'VS_BC';
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
  /// Vraća format: "Ponedeljak, 7:00 BC" ili null ako nema zakazanih vožnji
  String? _izracunajSledecuVoznju() {
    try {
      if (_activeSeatRequests.isEmpty) return null;

      final now = DateTime.now();
      final daniPuniNaziv = <String, String>{};
      for (int i = 0; i < DayConstants.dayAbbreviations.length; i++) {
        daniPuniNaziv[DayConstants.dayAbbreviations[i]] = DayConstants.dayNamesInternal[i];
      }

      // Sortiraj zahteve po redosledu dana u sedmici (od danas na dalje)
      final todayWd = now.weekday; // 1=pon...7=ned
      final daniOrder = ['pon', 'uto', 'sre', 'cet', 'pet'];
      // Redosled počevajući od dana koji sledi nakon danas
      final orderedDani = [
        ...daniOrder.where((d) => daniOrder.indexOf(d) + 1 >= todayWd),
        ...daniOrder.where((d) => daniOrder.indexOf(d) + 1 < todayWd),
      ];

      for (final danKratica in orderedDani) {
        final req = _activeSeatRequests
            .where((r) => (r['dan'] as String?)?.toLowerCase() == danKratica)
            .where((r) {
              final status = r['status'] as String?;
              return status != 'otkazano' && status != 'cancelled';
            })
            .firstOrNull;

        if (req == null) continue;

        final polazakRaw = (req['zeljeno_vreme'] ?? '').toString().trim();
        final polazakParts = polazakRaw.split(':');
        final polazakH = polazakParts.isNotEmpty ? (int.tryParse(polazakParts[0]) ?? 0) : 0;
        final polazakM = polazakParts.length > 1 ? (int.tryParse(polazakParts[1]) ?? 0) : 0;
        final polazak = '$polazakH:${polazakM.toString().padLeft(2, '0')}';
        if (polazak.isEmpty) continue;

        // Ako je danas, proveri da li je polazak prošao
        final danWd = daniOrder.indexOf(danKratica) + 1;
        if (danWd == todayWd) {
          if (polazakH * 60 + polazakM < now.hour * 60 + now.minute - 30) continue;
        }

        final gradRaw = (req['grad'] ?? '').toString();
        final grad = GradAdresaValidator.isVrsac(gradRaw) ? 'Vrsac' : 'Bela Crkva';
        final danNaziv = daniPuniNaziv[danKratica] ?? danKratica;
        return '$danNaziv $grad - $polazak';
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 💰 Učitaj istoriju plaćanja - od 1. januara tekuće godine
  /// 🔄 POJEDNOSTAVLJENO: Koristi voznje_log
  Future<List<Map<String, dynamic>>> _loadIstorijuPlacanja(String putnikId) async {
    try {
      final now = DateTime.now();
      final pocetakGodine = DateTime(now.year, 1, 1);

      // Koristi voznje_log za uplate
      final placanja = await supabase
          .from('voznje_log')
          .select('iznos, datum, created_at')
          .eq('putnik_id', putnikId)
          .filter('tip', 'in', '("uplata","uplata_mesecna","uplata_dnevna")')
          .gte('datum', pocetakGodine.toIso8601String().split('T')[0])
          .order('datum', ascending: false);

      // Grupiši po mesecima
      final Map<String, double> poMesecima = {};
      final Map<String, DateTime> poslednjeDatum = {};

      for (final p in placanja) {
        final datumStr = p['datum'] as String?;
        if (datumStr == null) continue;

        final datum = DateTime.tryParse(datumStr);
        if (datum == null) continue;

        final mesecKey = '${datum.year}-${datum.month.toString().padLeft(2, '0')}';
        final iznos = _toDouble(p['iznos']);

        poMesecima[mesecKey] = (poMesecima[mesecKey] ?? 0.0) + iznos;

        // Zapamti poslednji datum uplate za taj mesec
        if (!poslednjeDatum.containsKey(mesecKey) || datum.isAfter(poslednjeDatum[mesecKey]!)) {
          poslednjeDatum[mesecKey] = datum;
        }
      }

      // Konvertuj u listu sortiranu po datumu (najnoviji prvi)
      final result = poMesecima.entries.map((e) {
        final parts = e.key.split('-');
        final godina = int.parse(parts[0]);
        final mesec = int.parse(parts[1]);
        return {'mesec': mesec, 'godina': godina, 'iznos': e.value, 'datum': poslednjeDatum[e.key]};
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
        content: Text('Da li želiš da se odjaviš?', style: TextStyle(color: Colors.white.withOpacity(0.8))),
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('registrovani_putnik_telefon');

      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  /// 🏖️ Dugme za postavljanje bolovanja/godišnjeg - SAMO za radnike
  Widget _buildOdsustvoButton() {
    final status = _putnikData['status']?.toString().toLowerCase() ?? 'radi';
    final jeNaOdsustvu = status == 'bolovanje' || status == 'godisnji';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
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
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.white54),
          onTap: () => _pokaziOdsustvoDialog(jeNaOdsustvu),
        ),
      ),
    );
  }

  /// 🏖️ Dialog za odabir tipa odsustva ili vraćanje na posao
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
        await _postaviStatus('radi');
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

  /// 🔄 Postavi status putnika u bazu
  Future<void> _postaviStatus(String noviStatus) async {
    try {
      final putnikId = _putnikData['id']?.toString();
      if (putnikId == null) return;

      await PutnikService().oznaciBolovanjeGodisnji(
        putnikId,
        noviStatus,
        'self', // Radnik sam sebi menja status
      );

      // Ažuriraj lokalni state
      setState(() {
        _putnikData['status'] = noviStatus;
      });

      if (mounted) {
        final poruka = noviStatus == 'radi'
            ? 'Vraćeni ste na posao'
            : noviStatus == 'godisnji'
                ? 'Postavljeni ste na godišnji odmor'
                : 'Postavljeni ste na bolovanje';

        AppSnackBar.info(context, poruka);
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, 'Greška: $e');
      }
    }
  }

  // 🌤️ KOMPAKTAN PRIKAZ TEMPERATURE ZA GRAD (isti kao na danas_screen)
  Widget _buildWeatherCompact(String grad) {
    final stream = grad == 'BC' ? WeatherService.bcWeatherStream : WeatherService.vsWeatherStream;

    return StreamBuilder<WeatherData?>(
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
        if (WeatherData.isAssetIcon(icon)) {
          iconWidget = Image.asset(WeatherData.getAssetPath(icon), width: 32, height: 32);
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

  // 🌤️ DIJALOG ZA DETALJNU VREMENSKU PROGNOZU
  void _showWeatherDialog(String grad, WeatherData? data) {
    final gradPun = grad == 'BC' ? 'Bela Crkva' : 'Vrsac';

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
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, spreadRadius: 2)],
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
                        '🌤️ Vreme - $gradPun',
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
                                color: Colors.blue.withOpacity(0.3),
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
                                color: Colors.indigo.withOpacity(0.3),
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
                              if (WeatherData.isAssetIcon(data.icon))
                                Image.asset(WeatherData.getAssetPath(data.icon), width: 80, height: 80)
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

  String _getWeatherDescription(int code) {
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
    // ignore: unused_local_variable
    final grad = _putnikData['grad'] as String? ?? 'BC';
    final tip = _putnikData['tip'] as String? ?? 'radnik';
    final tipPrikazivanja = _putnikData['tip_prikazivanja'] as String? ?? 'standard';
    // ignore: unused_local_variable
    final aktivan = _putnikData['aktivan'] as bool? ?? true;

    return Container(
      decoration: BoxDecoration(gradient: ThemeManager().currentGradient),
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
                await ThemeManager().nextTheme();
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
                    // 🌤️ VREMENSKA PROGNOZA - BC levo, VS desno
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

                    // ⚠️ NOTIFIKACIJE UPOZORENJE (ako su ugašene)
                    if (_notificationStatus.isDenied || _notificationStatus.isPermanentlyDenied)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.9),
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
                              border: Border.all(color: Colors.white.withOpacity(0.4), width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: (tip == 'ucenik'
                                          ? Colors.blue
                                          : tip == 'posiljka'
                                              ? Colors.purple
                                              : Colors.orange)
                                      .withOpacity(0.4),
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
                                      ? Colors.blue.withOpacity(0.3)
                                      : (tip == 'dnevni' || tipPrikazivanja == 'DNEVNI')
                                          ? Colors.green.withOpacity(0.3)
                                          : tip == 'posiljka'
                                              ? Colors.purple.withOpacity(0.3)
                                              : Colors.orange.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white.withOpacity(0.3)),
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
                                                  : '👤 Putnik',
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
                                    color: Colors.white.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white.withOpacity(0.3)),
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
                                    style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13),
                                  ),
                                ],
                                if (_adresaBC != null && _adresaVS != null) const SizedBox(width: 16),
                                if (_adresaVS != null && _adresaVS!.isNotEmpty) ...[
                                  Icon(Icons.work, color: Colors.white70, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    _adresaVS!,
                                    style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13),
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
                      child: Divider(color: Colors.white.withOpacity(0.2), thickness: 1),
                    ),

                    // 🚐 ETA Widget sa fazama:
                    // 0. Nema dozvola: "Odobravanjem GPS i notifikacija ovde će vam biti prikazano vreme dolaska prevoza"
                    // 1. 30 min pre polaska: "Vozač će uskoro krenuti"
                    // 2. Vozač startovao rutu: Realtime ETA praćenje
                    // 3. Pokupljen: "Pokupljeni ste u HH:MM" (stoji 60 min) - ČITA IZ BAZE!
                    // 4. Nakon 60 min: "Vaša sledeća vožnja: dan, vreme"
                    KombiEtaWidget(
                      putnikIme: fullName,
                      grad: grad,
                      sledecaVoznja: _sledecaVoznjaInfo,
                      putnikId: _putnikData['id']?.toString(),
                    ),

                    // ─────────── Divider ───────────

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Divider(color: Colors.white.withOpacity(0.2), thickness: 1),
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

                    // 🏖️ Bolovanje/Godišnji dugme - SAMO za radnike
                    if (_putnikData['tip']?.toString().toLowerCase() == 'radnik') ...[
                      _buildOdsustvoButton(),
                      const SizedBox(height: 16),
                    ],

                    // 💰 TRENUTNO ZADUŽENJE
                    if (_putnikData['cena_po_danu'] != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _ukupnoZaduzenje > 0
                                ? [Colors.red.withOpacity(0.2), Colors.red.withOpacity(0.05)]
                                : [Colors.green.withOpacity(0.2), Colors.green.withOpacity(0.05)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _ukupnoZaduzenje > 0 ? Colors.red.withOpacity(0.3) : Colors.green.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'TRENUTNO STANJE',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
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
                                  color: Colors.white.withOpacity(0.5),
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

                    // 📊 Detaljne statistike - dugme za dijalog
                    _buildDetaljneStatistikeDugme(),
                    const SizedBox(height: 16),

                    // 📅 Raspored polazaka
                    _buildRasporedCard(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
      ),
    );
  }

  /// 📅 Widget za prikaz rasporeda polazaka po danima
  Widget _buildRasporedCard() {
    final tip = _putnikData['tip'] as String? ?? 'radnik';
    final tipPrikazivanja = _putnikData['tip_prikazivanja'] as String? ?? 'standard';

    // 🆕 Inicijalizuj polasci mapu sa praznim vrednostima za svih 7 dana
    Map<String, Map<String, dynamic>> polasci = {};
    for (final shortDay in DayConstants.dayAbbreviations) {
      polasci[shortDay] = {
        'bc': null,
        'vs': null,
        'bc_status': null,
        'vs_status': null,
      };
    }

    // 🆕 MERGE AKTIVNIH ZAHTEVA iz _activeSeatRequests
    final daniNedelje = ['pon', 'uto', 'sre', 'cet', 'pet'];
    final now = DateTime.now();

    // Sortiramo: aktivni (confirmed/approved/pending) ZADNJI da pregazе otkazane
    // Redosljed: otkazano/cancelled/bez_polaska → pending/manual/approved/confirmed
    const statusPrioritet = {
      'bez_polaska': 0,
      'cancelled': 1,
      'otkazano': 2,
      'pending': 3,
      'manual': 4,
      'approved': 5,
      'confirmed': 6,
    };
    final sortedRequests = List<Map<String, dynamic>>.from(_activeSeatRequests);
    sortedRequests.sort((a, b) {
      final datumCmp = (a['datum'] as String).compareTo(b['datum'] as String);
      if (datumCmp != 0) return datumCmp;
      final aPrio = statusPrioritet[a['status']] ?? 0;
      final bPrio = statusPrioritet[b['status']] ?? 0;
      return aPrio.compareTo(bPrio); // niži prioritet dolazi prvi, viši pobijedi
    });

    for (final req in sortedRequests) {
      try {
        final datumStr = req['datum'] as String?;
        if (datumStr == null) continue;

        final datum = DateTime.parse(datumStr);
        // Prikazujemo samo zahteve koji su u narednih 7 dana
        if (datum.isBefore(now.subtract(const Duration(days: 1))) || datum.isAfter(now.add(const Duration(days: 7)))) {
          continue;
        }

        final danIndex = datum.weekday - 1;
        if (danIndex < 0 || danIndex >= daniNedelje.length) continue;

        final danKratica = daniNedelje[danIndex];
        final gradRaw = (req['grad'] ?? '').toString().toLowerCase();
        // Normalizuj grad na 'bc' ili 'vs'
        final grad = (gradRaw == 'vs' || gradRaw.contains('vr')) ? 'vs' : 'bc';
        final status = req['status'] as String?;
        final vreme = (req['zeljeno_vreme'] ?? '').toString();

        final existing = polasci[danKratica]!;

        if (status == 'otkazano' || status == 'cancelled' || status == 'bez_polaska') {
          // Postavi otkazano SAMO ako još nema aktivnog zahtjeva za ovaj grad
          // (aktivni zahtjev dolazi zadnji zbog sortiranja pa će ga pregaziti)
          existing['${grad}_status'] = status == 'bez_polaska' ? 'bez_polaska' : 'otkazano';
          existing['${grad}_otkazano'] = status != 'bez_polaska';
          existing['${grad}_otkazano_vreme'] = vreme;
        } else {
          // Aktivan zahtjev — uvijek pregazuje otkazano
          existing[grad] = vreme;
          existing['${grad}_status'] = status;
          existing['${grad}_otkazano'] = false;
          existing['${grad}_otkazano_vreme'] = null;
        }
      } catch (e) {
        debugPrint('⚠️ [MergeRequests] Greška: $e');
      }
    }

    // Prikazujemo samo radne dane
    final dani = DayConstants.dayAbbreviations.where((d) => d != 'sub' && d != 'ned').toList();
    final daniLabels = <String, String>{};
    for (int i = 0; i < DayConstants.dayAbbreviations.length; i++) {
      final short = DayConstants.dayAbbreviations[i];
      if (short == 'sub' || short == 'ned') continue;
      final long = (i < DayConstants.dayNamesInternal.length) ? DayConstants.dayNamesInternal[i] : short;
      daniLabels[short] = long;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withOpacity(0.13)),
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
                              color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.bold, fontSize: 14)))),
              Expanded(
                  child: Center(
                      child: Text('VS',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.bold, fontSize: 14)))),
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
                      child: TimePickerCell(
                        value: bcDisplayVreme,
                        isBC: true,
                        status: bcStatus,
                        dayName: dan,
                        isCancelled: bcOtkazano,
                        tipPutnika: tip.toString(),
                        tipPrikazivanja: tipPrikazivanja,
                        onChanged: (newValue) => _updatePolazak(dan, 'bc', newValue),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: TimePickerCell(
                        value: vsDisplayVreme,
                        isBC: false,
                        status: vsStatus,
                        dayName: dan,
                        isCancelled: vsOtkazano,
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

  /// 🕐 Ažurira polazak
  Future<void> _updatePolazak(String dan, String tipGrad, String? novoVreme) async {
    final putnikId = _putnikData['id']?.toString();
    if (putnikId == null) return;

    final tipPutnika = (_putnikData['tip'] ?? '').toString().toLowerCase();
    final jeDnevni = tipPutnika.contains('dnevni') || tipPutnika.contains('posiljka');

    // 🚫 BEZ POLASKA od strane putnika → otkazana vožnja (upisuje se u voznje_log)
    if (novoVreme == null) {
      try {
        // Pronađi aktivan seat_request za ovaj dan i grad da dobijemo requestId i vreme
        final gradKey = tipGrad.startsWith('bc') ? 'BC' : 'VS';
        final datum = app_date_utils.DateUtils.getIsoDateForDay(dan);

        final existing = await supabase
            .from('seat_requests')
            .select('id, zeljeno_vreme')
            .eq('putnik_id', putnikId)
            .eq('dan', dan)
            .eq('grad', gradKey)
            .inFilter('status', ['pending', 'manual', 'approved', 'confirmed']).maybeSingle();

        await PutnikService().otkaziPutnika(
          putnikId,
          'Putnik', // putnik sam otkazuje - loguje se kao 'Putnik'
          grad: gradKey,
          vreme: existing?['zeljeno_vreme']?.toString(),
          selectedDan: dan,
          datum: datum,
          requestId: existing?['id']?.toString(),
          status: 'otkazano',
        );

        await _loadActiveRequests();
        await _refreshPutnikData();

        if (mounted) {
          AppSnackBar.warning(context, 'Vožnja otkazana. Evidentirano kao otkazivanje.');
        }
      } catch (e) {
        debugPrint('❌ Greška u _updatePolazak (otkazivanje): $e');
        if (mounted) {
          AppSnackBar.error(context, 'Greška pri otkazivanju.');
        }
      }
      return;
    }

    final String normalizedVreme = RegistrovaniHelpers.normalizeTime(novoVreme) ?? '';

    String? rpcStatus = 'pending';
    if (tipGrad.startsWith('bc') && jeDnevni) {
      rpcStatus = 'manual';
    }

    try {
      // 1. RPC poziv koji sada ažurira seat_requests
      await supabase.rpc('update_putnik_polazak_v2', params: {
        'p_id': putnikId,
        'p_dan': dan,
        'p_grad': tipGrad.startsWith('bc') ? 'BC' : 'VS',
        'p_vreme': normalizedVreme,
        'p_status': rpcStatus,
      });

      // 2. Osveži podatke
      await _loadActiveRequests();
      await _refreshPutnikData();

      if (mounted) {
        AppSnackBar.success(context, 'Vaš zahtev je uspešno primljen.');
      }
    } catch (e) {
      debugPrint('❌ Greška u _updatePolazak: $e');
      if (mounted) {
        AppSnackBar.error(context, 'Greška pri čuvanju promene.');
      }
    }
  }

  Widget _buildStatCard(String icon, String title, String value, Color color, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withOpacity(0.13)),
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
                  color: color.withOpacity(0.2),
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
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10),
          ),
        ],
      ),
    );
  }

  /// 📊 Dugme za otvaranje detaljnih statistika
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
          PutnikStatistikeHelper.prikaziDetaljneStatistike(
            context: context,
            putnikId: _putnikData['id'] ?? '',
            putnikIme: _putnikData['putnik_ime'] ?? 'Nepoznato',
            tip: _putnikData['tip'] ?? 'radnik',
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
              Icon(Icons.arrow_forward_ios, color: Colors.white.withOpacity(0.5), size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
