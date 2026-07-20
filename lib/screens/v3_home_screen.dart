import 'dart:async';

import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../globals.dart';
import '../models/v3_adresa.dart';
import '../models/v3_putnik.dart';
import '../models/v3_vozac.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_adresa_service.dart';
import '../services/v3/v3_app_update_service.dart';
import '../services/v3/v3_dodela_resolver_service.dart';
import '../services/v3/v3_finansije_service.dart';
import '../services/v3/v3_operativna_nedelja_service.dart';
import '../services/v3/v3_printing_service.dart';
import '../services/v3/v3_putnik_service.dart';
import '../services/v3/v3_racun_service.dart';
import '../services/v3/v3_trenutna_dodela_service.dart';
import '../services/v3/v3_trenutna_dodela_slot_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../services/v3_locale_manager.dart';
import '../services/v3_theme_manager.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_card_color_policy.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_date_utils.dart';
import '../utils/v3_dialog_helper.dart';
import '../utils/v3_input_utils.dart';
import '../utils/v3_navigation_utils.dart';
import '../utils/v3_safe_text.dart';
import '../utils/v3_status_policy.dart';
import '../utils/v3_string_utils.dart';
import '../utils/v3_text_utils.dart';
import '../utils/v3_time_utils.dart';
import '../utils/v3_uuid_utils.dart';
import '../widgets/v3_bottom_nav_bar_slotovi.dart';
import '../widgets/v3_info_banner.dart';
import '../widgets/v3_live_clock_text.dart';
import '../widgets/v3_neradni_dani_banner.dart';
import '../widgets/v3_putnik_card.dart';
import '../widgets/v3_update_banner.dart';
import 'v3_admin_screen.dart';
import 'v3_vozac_screen.dart';
import 'v3_welcome_screen.dart';

// ─── Helpers za izbor meseca u dijalozima za račune ─────────────────────────

/// Generiše listu meseci za račun (januar–decembar tekuće godine).
List<DateTime> _racunMesecOptions() {
  final now = DateTime.now();
  return List.generate(12, (i) => DateTime(now.year, i + 1, 1));
}

/// Formatira mesec za prikaz u dijalogu (npr. "Januar 2026.").
String _formatMesecRacuna(DateTime mesec) {
  final raw = DateFormat('MMMM yyyy.', 'sr').format(mesec);
  if (raw.isEmpty) return '';
  return '${raw[0].toUpperCase()}${raw.substring(1)}';
}

/// Vraća poslednji dan u mesecu (koristi se kao datum prometa na računu).
DateTime _lastDayOfMonth(DateTime mesec) {
  return DateTime(mesec.year, mesec.month + 1, 0);
}

/// Računa predlog broja radnih dana/vožnji i cene za račun na osnovu putnika i meseca.
({int brojDana, double cenaPoDanu}) _racunPredlogZaPutnik(
  Map<String, dynamic>? putnik,
  DateTime mesec,
) {
  if (putnik == null) return (brojDana: 0, cenaPoDanu: 0.0);

  final putnikId = putnik['id']?.toString() ?? '';
  final tip = (putnik['tip_putnika']?.toString() ?? '').trim().toLowerCase();
  final isPoDanu = tip == 'radnik' || tip == 'ucenik';
  final cenaPoDanu = (putnik['cena_po_danu'] as num?)?.toDouble() ?? 0.0;
  final cenaPoPokupljenju = (putnik['cena_po_pokupljenju'] as num?)?.toDouble() ?? 0.0;
  final cena = isPoDanu ? cenaPoDanu : cenaPoPokupljenju;

  if (putnikId.isEmpty) return (brojDana: 0, cenaPoDanu: cena);

  final summary = V3FinansijeService.getNaplataSummaryForPutnik(
    putnikId: putnikId,
    mesec: mesec.month,
    godina: mesec.year,
  );

  return (brojDana: summary.brojVoznji, cenaPoDanu: cena);
}

class V3HomeScreen extends StatefulWidget {
  const V3HomeScreen({super.key});

  @override
  State<V3HomeScreen> createState() => _V3HomeScreenState();
}

class _V3HomeScreenState extends State<V3HomeScreen> with TickerProviderStateMixin {
  static const Set<String> _adminUserIds = <String>{
    V3AppUpdateService.bojanUserId,
  };

  // Prevodi za dijalog "Dodaj rezervaciju" (SR/EN/RU/DE).
  static const Map<String, Map<String, String>> _t = {
    'dodajRezervaciju': {
      'sr': 'Dodaj Rezervaciju',
      'en': 'Add Reservation',
      'ru': 'Добавить резервацию',
      'de': 'Reservierung hinzufügen',
    },
    'termin': {'sr': 'Termin', 'en': 'Appointment', 'ru': 'Время', 'de': 'Termin'},
    'vreme': {'sr': '⏰ Vreme:', 'en': '⏰ Time:', 'ru': '⏰ Время:', 'de': '⏰ Zeit:'},
    'grad': {'sr': '📍 Grad:', 'en': '📍 City:', 'ru': '📍 Город:', 'de': '📍 Stadt:'},
    'dan': {'sr': '📅 Dan:', 'en': '📅 Day:', 'ru': '📅 День:', 'de': '📅 Tag:'},
    'izaberiPutnika': {
      'sr': 'Izaberi putnika',
      'en': 'Select passenger',
      'ru': 'Выберите пассажира',
      'de': 'Fahrgast auswählen',
    },
    'pretrazi': {'sr': 'Pretraži...', 'en': 'Search...', 'ru': 'Поиск...', 'de': 'Suchen...'},
    'otkazi': {'sr': 'Otkaži', 'en': 'Cancel', 'ru': 'Отмена', 'de': 'Abbrechen'},
    'izaberitePutnika': {
      'sr': '⚠️ Izaberite putnika',
      'en': '⚠️ Select a passenger',
      'ru': '⚠️ Выберите пассажира',
      'de': '⚠️ Bitte Fahrgast auswählen',
    },
    'putnikNemaId': {
      'sr': '⚠️ Putnik nema validan ID',
      'en': '⚠️ Passenger has no valid ID',
      'ru': '⚠️ У пассажира нет действительного ID',
      'de': '⚠️ Fahrgast hat keine gültige ID',
    },
    'rezervacijaDodana': {
      'sr': '✅ Rezervacija dodana',
      'en': '✅ Reservation added',
      'ru': '✅ Резервация добавлена',
      'de': '✅ Reservierung hinzugefügt',
    },
    'greskaPrefix': {'sr': '❌ Greška:', 'en': '❌ Error:', 'ru': '❌ Ошибка:', 'de': '❌ Fehler:'},
    'dodaje': {'sr': 'Dodaje...', 'en': 'Adding...', 'ru': 'Добавление...', 'de': 'Wird hinzugefügt...'},
    'dodaj': {'sr': 'Dodaj', 'en': 'Add', 'ru': 'Добавить', 'de': 'Hinzufügen'},
    'noviRacun': {'sr': 'Novi račun', 'en': 'New invoice', 'ru': 'Новый счет', 'de': 'Neue Rechnung'},
    'imePrezimeKupca': {
      'sr': 'Ime i prezime kupca',
      'en': 'Customer full name',
      'ru': 'ФИО покупателя',
      'de': 'Name des Kunden',
    },
    'adresaKupca': {
      'sr': 'Adresa kupca',
      'en': 'Customer address',
      'ru': 'Адрес покупателя',
      'de': 'Adresse des Kunden'
    },
    'opisUsluge': {
      'sr': 'Opis usluge',
      'en': 'Service description',
      'ru': 'Описание услуги',
      'de': 'Leistungsbeschreibung'
    },
    'cena': {'sr': 'Cena', 'en': 'Price', 'ru': 'Цена', 'de': 'Preis'},
    'kolicina': {'sr': 'Količina', 'en': 'Quantity', 'ru': 'Количество', 'de': 'Menge'},
    'jedinicaMere': {'sr': 'Jedinica mere', 'en': 'Unit of measure', 'ru': 'Единица измерения', 'de': 'Maßeinheit'},
    'jmUsluga': {'sr': 'usluga', 'en': 'service', 'ru': 'услуга', 'de': 'Leistung'},
    'jmDan': {'sr': 'dan', 'en': 'day', 'ru': 'день', 'de': 'Tag'},
    'jmKom': {'sr': 'kom', 'en': 'pcs', 'ru': 'шт', 'de': 'Stk'},
    'jmSat': {'sr': 'sat', 'en': 'hour', 'ru': 'час', 'de': 'Stunde'},
    'jmKm': {'sr': 'km', 'en': 'km', 'ru': 'км', 'de': 'km'},
    'mesecIzdavanja': {
      'sr': 'Mesec izdavanja:',
      'en': 'Issue month:',
      'ru': 'Месяц выставления:',
      'de': 'Ausstellungsmonat:'
    },
    'izaberiMesec': {'sr': 'Izaberi mesec', 'en': 'Select month', 'ru': 'Выберите месяц', 'de': 'Monat auswählen'},
    'datumIzdavanja': {
      'sr': 'Datum izdavanja:',
      'en': 'Issue date:',
      'ru': 'Дата выставления:',
      'de': 'Ausstellungsdatum:'
    },
    'popuniteImeOpis': {
      'sr': '⚠️ Popunite ime i opis',
      'en': '⚠️ Fill in name and description',
      'ru': '⚠️ Заполните имя и описание',
      'de': '⚠️ Name und Beschreibung ausfüllen',
    },
    'uneseiteIspravnuCenu': {
      'sr': '⚠️ Unesite ispravnu cenu',
      'en': '⚠️ Enter a valid price',
      'ru': '⚠️ Введите правильную цену',
      'de': '⚠️ Gültigen Preis eingeben',
    },
    'stampaj': {'sr': 'Štampaj', 'en': 'Print', 'ru': 'Печать', 'de': 'Drucken'},
    'stampajSpisak': {
      'sr': 'Štampaj spisak',
      'en': 'Print list',
      'ru': 'Печать списка',
      'de': 'Liste drucken',
    },
    'racunPostojeci': {
      'sr': 'Račun - postojeći',
      'en': 'Invoice - existing',
      'ru': 'Счёт - существующий',
      'de': 'Rechnung - vorhanden',
    },
    'racunNovi': {
      'sr': 'Račun - novi',
      'en': 'Invoice - new',
      'ru': 'Счёт - новый',
      'de': 'Rechnung - neu',
    },
    'racunFirma': {'sr': 'Račun — firma', 'en': 'Invoice — company', 'ru': 'Счёт — компания', 'de': 'Rechnung — Firma'},
    'novaFirma': {'sr': 'Nova firma?', 'en': 'New company?', 'ru': 'Новая компания?', 'de': 'Neue Firma?'},
    'nemaRezultata': {'sr': 'Nema rezultata', 'en': 'No results', 'ru': 'Нет результатов', 'de': 'Keine Ergebnisse'},
    'adresaOpciono': {
      'sr': 'Adresa (opciono)',
      'en': 'Address (optional)',
      'ru': 'Адрес (необязательно)',
      'de': 'Adresse (optional)',
    },
    'nemaFirmiUBazi': {
      'sr': '⚠️ Nema firmi u bazi (v3_racuni je prazan)',
      'en': '⚠️ No companies in database (v3_racuni is empty)',
      'ru': '⚠️ Нет компаний в базе (v3_racuni пуст)',
      'de': '⚠️ Keine Firmen in der Datenbank (v3_racuni ist leer)',
    },
    'odaberitePutnika': {
      'sr': '⚠️ Odaberite putnika',
      'en': '⚠️ Select a passenger',
      'ru': '⚠️ Выберите пассажира',
      'de': '⚠️ Fahrgast auswählen',
    },
    'sekcijaFirma': {'sr': 'FIRMA', 'en': 'COMPANY', 'ru': 'КОМПАНИЯ', 'de': 'FIRMA'},
    'sekcijaPutnik': {'sr': 'PUTNIK', 'en': 'PASSENGER', 'ru': 'ПАССАЖИР', 'de': 'FAHRGAST'},
    'sekcijaMesecIDatumi': {
      'sr': 'MESEC I DATUMI',
      'en': 'MONTH AND DATES',
      'ru': 'МЕСЯЦ И ДАТЫ',
      'de': 'MONAT UND DATEN'
    },
    'sekcijaIznos': {'sr': 'IZNOS', 'en': 'AMOUNT', 'ru': 'СУММА', 'de': 'BETRAG'},
    'dodajNovuFirmu': {
      'sr': 'Dodaj novu firmu',
      'en': 'Add new company',
      'ru': 'Добавить новую компанию',
      'de': 'Neue Firma hinzufügen',
    },
  };

  String _tr(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    return _t[key]?[code] ?? _t[key]?['sr'] ?? key;
  }

  bool _isLoading = true;
  String _selectedDay = 'Ponedeljak';
  String _selectedGrad = 'BC';
  String _selectedVreme = '05:00';
  late Stream<List<V3OperativnaNedeljaEntry>> _operativnaStream;
  Map<String, String> _activeVozacByTerminId = const {};
  Map<String, String> _activeVozacBySlotKey = const {};
  StreamSubscription<int>? _trenutnaDodelaRevisionSub;

  void _handleActiveWeekChanged() {
    if (!mounted) return;
    setState(() {
      _syncSelectedSlotForDatum(_selectedDatumIso);
      _operativnaStream = _buildOperativnaStream(_selectedDatumIso);
    });
  }

  /// Vraća ISO datum (yyyy-MM-dd) za izabrani dan u aktivnoj sedmici.
  String get _selectedDatumIso =>
      V3DanHelper.datumIsoZaDanPuniUTekucojSedmici(_selectedDay, anchor: V3DanHelper.schedulingWeekAnchor());

  String? get _neradanDanRazlog => getNeradanDanRazlog(datumIso: _selectedDatumIso, grad: _selectedGrad);

  Stream<List<V3OperativnaNedeljaEntry>> _buildOperativnaStream(String datumIso) {
    return V3MasterRealtimeManager.instance.v3StreamFromRevisions<List<V3OperativnaNedeljaEntry>>(
      tables: const [
        'v3_operativna_nedelja',
        'v3_auth',
        'v3_adrese',
        'v3_kapacitet_slots',
        'v3_app_settings',
      ],
      build: () => V3OperativnaNedeljaService.getOperativnaNedeljaByDatum(datumIso),
    );
  }

  // Dinamična vremena prema tipu nav bara (iz baze)
  List<String> get _bcVremena => getRasporedVremena('bc', navBarTypeNotifier.value, day: _selectedDay);
  List<String> get _vsVremena => getRasporedVremena('vs', navBarTypeNotifier.value, day: _selectedDay);

  int _timeToMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return -1;
    final hour = int.tryParse(parts[0]) ?? -1;
    final minute = int.tryParse(parts[1]) ?? -1;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return -1;
    return hour * 60 + minute;
  }

  bool _isVisibleOperativnaRow(Map<String, dynamic> row) {
    return V3StatusPolicy.canAssign(
      status: row['status']?.toString(),
      otkazanoAt: row['otkazano_at'],
      pokupljenAt: row['pokupljen_at'],
    );
  }

  Future<void> _reloadTrenutnaDodelaMap() async {
    try {
      final byTerminId = await V3TrenutnaDodelaService.loadActiveVozacByTerminId();
      final bySlotKey = await V3TrenutnaDodelaSlotService.loadAllVozacBySlotKey(
        datumIso: _selectedDatumIso,
      );
      _activeVozacByTerminId = byTerminId;
      _activeVozacBySlotKey = bySlotKey;
    } catch (e) {
      debugPrint('[V3HomeScreen] _reloadTrenutnaDodelaMap error: $e');
      _activeVozacByTerminId = const {};
      _activeVozacBySlotKey = const {};
    }
  }

  String _vozacIdForOperativnaRow(Map<String, dynamic> row) {
    return V3DodelaResolverService.resolveVozacIdForOperativnaRow(
      row: row,
      activeVozacByTerminId: _activeVozacByTerminId,
      activeVozacBySlotKey: _activeVozacBySlotKey,
      vremeKolona: 'polazak_at',
    );
  }

  void _startTrenutnaDodelaRealtime() {
    _trenutnaDodelaRevisionSub?.cancel();
    _trenutnaDodelaRevisionSub = V3MasterRealtimeManager.instance.tablesRevisionStream(const [
      V3TrenutnaDodelaService.tableName,
      V3TrenutnaDodelaSlotService.tableName,
    ]).listen((_) {
      unawaited(_refreshDodelaFromRealtime());
    });
  }

  Future<void> _refreshDodelaFromRealtime() async {
    if (!mounted) return;
    await _reloadTrenutnaDodelaMap();
    if (!mounted) return;
    setState(() {});
  }

  void _syncSelectedSlotForDatum(String datumIso) {
    final entries = V3OperativnaNedeljaService.getOperativnaNedeljaByDatum(datumIso);
    final uniqueSlots = <String, Map<String, String>>{};

    for (final entry in entries) {
      final grad = (entry.grad ?? '').trim().toUpperCase();
      final vreme = V3TimeUtils.normalizeToHHmm(entry.polazakAt);
      if (grad.isEmpty || vreme.isEmpty) continue;
      uniqueSlots.putIfAbsent('$grad|$vreme', () => {'grad': grad, 'vreme': vreme});
    }

    if (uniqueSlots.isEmpty) return;

    final currentVremeNorm = V3TimeUtils.normalizeToHHmm(_selectedVreme);
    final hasCurrentSelection = uniqueSlots.values.any(
      (slot) => (slot['grad'] ?? '') == _selectedGrad && (slot['vreme'] ?? '') == currentVremeNorm,
    );
    if (hasCurrentSelection) return;

    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;
    final validSlots = uniqueSlots.values.toList();
    validSlots.sort((a, b) {
      final aVreme = a['vreme'] ?? '';
      final bVreme = b['vreme'] ?? '';
      final aMinutes = _timeToMinutes(aVreme);
      final bMinutes = _timeToMinutes(bVreme);
      final aDiff = aMinutes < 0 ? 99999 : (aMinutes - currentMinutes).abs();
      final bDiff = bMinutes < 0 ? 99999 : (bMinutes - currentMinutes).abs();
      if (aDiff != bDiff) return aDiff.compareTo(bDiff);
      final ga = (a['grad'] ?? '').toUpperCase();
      final gb = (b['grad'] ?? '').toUpperCase();
      if (ga != gb) return ga.compareTo(gb);
      return aVreme.compareTo(bVreme);
    });

    final first = validSlots.first;
    _selectedGrad = first['grad'] ?? _selectedGrad;
    _selectedVreme = first['vreme'] ?? _selectedVreme;
  }

  @override
  void initState() {
    super.initState();
    _selectedDay = V3DanHelper.defaultWorkdayFullName();
    _operativnaStream = _buildOperativnaStream(_selectedDatumIso);
    appSettingsActiveWeekStartNotifier.addListener(_handleActiveWeekChanged);
    appSettingsActiveWeekEndNotifier.addListener(_handleActiveWeekChanged);
    _startTrenutnaDodelaRealtime();
    _initData();
  }

  @override
  void dispose() {
    appSettingsActiveWeekStartNotifier.removeListener(_handleActiveWeekChanged);
    appSettingsActiveWeekEndNotifier.removeListener(_handleActiveWeekChanged);
    unawaited(_trenutnaDodelaRevisionSub?.cancel());
    _trenutnaDodelaRevisionSub = null;
    super.dispose();
  }

  Future<void> _initData() async {
    if (V3VozacService.currentVozac == null) {
      if (mounted) {
        V3NavigationUtils.pushAndRemoveUntil<void>(
          context,
          const V3WelcomeScreen(),
        );
      }
      return;
    }
    if (mounted) {
      await _reloadTrenutnaDodelaMap();
      _syncSelectedSlotForDatum(_selectedDatumIso);
      setState(() => _isLoading = false);
    }
  }

  bool get _isAdmin {
    final vozac = V3VozacService.currentVozac;
    final vozacId = vozac?.id.trim() ?? '';
    if (vozacId.isNotEmpty && _adminUserIds.contains(vozacId)) return true;
    return false;
  }

  List<Color> getVozacColors(String grad, String vreme) {
    final rm = V3MasterRealtimeManager.instance;
    final boje = <Color>[];

    // Proveri slot dodelu
    final slotVozacId = V3DodelaResolverService.resolveVozacIdForSlot(
      datumIso: _selectedDatumIso,
      grad: grad,
      vreme: vreme,
      activeVozacBySlotKey: _activeVozacBySlotKey,
    );
    if (slotVozacId.isNotEmpty) {
      final slotVozac = V3VozacService.getVozacById(slotVozacId);
      if (slotVozac != null) {
        boje.add(V3CardColorPolicy.vozacColorOr(slotVozac.boja));
      }
    }

    // Proveri individualne dodele za slot
    for (final dodela in rm.trenutnaDodelaCache.values) {
      final terminId = dodela['termin_id']?.toString();
      if (terminId == null || terminId.isEmpty) continue;

      final operativnaRow = rm.operativnaNedeljaCache[terminId];
      if (operativnaRow == null) continue;

      final rowDatum = V3DateUtils.parseIsoDatePart(operativnaRow['datum'] as String? ?? '');
      final rowGrad = (operativnaRow['grad']?.toString() ?? '').trim().toUpperCase();
      final rowVreme = V3StringUtils.trimTimeToHhMm(operativnaRow['polazak_at']?.toString() ?? '');

      if (rowDatum == _selectedDatumIso && rowGrad == grad && rowVreme == vreme) {
        final vozacId = dodela['vozac_v3_auth_id']?.toString();
        if (vozacId != null && vozacId.isNotEmpty) {
          final vozac = V3VozacService.getVozacById(vozacId);
          if (vozac != null) {
            final boja = V3CardColorPolicy.vozacColorOr(vozac.boja);
            if (!boje.contains(boja)) {
              boje.add(boja);
            }
          }
        }
      }
    }

    return boje;
  }

  // ─── Dodela vozača putniku (admin only) ──────────────────────

  V3Vozac? _getVozacZaPutnika(String putnikId, String grad, String vreme, String datum) {
    final rm = V3MasterRealtimeManager.instance;
    final vozacId = V3StatusPolicy.assignedVozacIdForPutnik(
      operativnaRows: rm.operativnaNedeljaCache.values,
      putnikId: putnikId,
      grad: grad,
      vreme: vreme,
      datumIso: datum,
      vozacIdForRow: _vozacIdForOperativnaRow,
      isVisibleRow: _isVisibleOperativnaRow,
      vremeKolona: 'polazak_at',
    );
    if ((vozacId ?? '').isNotEmpty) {
      return V3VozacService.getVozacById(vozacId!);
    }
    return null;
  }

  /// Dijalog za dodavanje novog operativnog termina (rezervacije)
  void _showDodajTerminDialog() {
    V3Putnik? selectedPutnik;
    V3Adresa? selectedAdresa; // override adresa (null = koristi putnikovu)
    bool isLoading = false;

    // Spoji sve tipove putnika iz V3
    final aktivniPutnici = [
      ...V3PutnikService.getPutniciByTip('radnik'),
      ...V3PutnikService.getPutniciByTip('dnevni'),
      ...V3PutnikService.getPutniciByTip('ucenik'),
      ...V3PutnikService.getPutniciByTip('posiljka'),
    ].toList()
      ..sort((a, b) => a.imePrezime.compareTo(b.imePrezime));

    V3DialogHelper.showDialogBuilder<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setS) {
          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.75,
                maxWidth: MediaQuery.of(ctx).size.width * 0.9,
              ),
              decoration: BoxDecoration(
                gradient: Theme.of(ctx).backgroundGradient,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Theme.of(ctx).glassBorder, width: 0.8),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 15, offset: const Offset(0, 8))
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  V3ContainerUtils.iconContainer(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Theme.of(ctx).glassContainer,
                    borderRadiusGeometry:
                        const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
                    border: Border(bottom: BorderSide(color: Theme.of(ctx).glassBorder)),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(_tr('dodajRezervaciju'),
                              style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(dialogCtx),
                          child: V3ContainerUtils.iconContainer(
                            padding: const EdgeInsets.all(8),
                            backgroundColor: Colors.red.withValues(alpha: 0.2),
                            borderRadiusGeometry: BorderRadius.circular(15),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                            child: const Icon(Icons.close, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Info o ruti
                          V3ContainerUtils.iconContainer(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            backgroundColor: Theme.of(ctx).glassContainer,
                            borderRadiusGeometry: BorderRadius.circular(12),
                            border: Border.all(color: Theme.of(ctx).glassBorder),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_tr('termin'),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                _buildStatRow(_tr('vreme'), _selectedVreme),
                                _buildStatRow(_tr('grad'), _selectedGrad),
                                _buildStatRow(_tr('dan'), _selectedDay),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Dropdown putnika
                          DropdownButtonFormField2<V3Putnik>(
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: _tr('izaberiPutnika'),
                              prefixIcon: const Icon(Icons.person_search),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            dropdownStyleData: DropdownStyleData(
                              maxHeight: V3ContainerUtils.responsiveHeight(ctx, 280),
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.white),
                            ),
                            dropdownSearchData: DropdownSearchData(
                              searchController: V3TextUtils.homeSearchController,
                              searchInnerWidgetHeight: V3ContainerUtils.responsiveHeight(ctx, 50),
                              searchInnerWidget: V3ContainerUtils.iconContainer(
                                height: V3ContainerUtils.responsiveHeight(ctx, 50),
                                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                                child: TextFormField(
                                  controller: V3TextUtils.homeSearchController,
                                  expands: true,
                                  maxLines: null,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    hintText: _tr('pretrazi'),
                                    prefixIcon: const Icon(Icons.search, size: 20),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                              searchMatchFn: (item, val) =>
                                  V3StringUtils.containsSearch(item.value?.imePrezime ?? '', val),
                            ),
                            items: aktivniPutnici
                                .map((p) => DropdownMenuItem(
                                      value: p,
                                      child: V3SafeText.userName(p.imePrezime),
                                    ))
                                .toList(),
                            onChanged: (p) => setS(() {
                              selectedPutnik = p;
                              selectedAdresa = null; // reset adrese kad se promijeni putnik
                            }),
                          ),
                          const SizedBox(height: 12),
                          // Adresa override — samo kad je putnik odabran
                          if (selectedPutnik != null) ...[
                            const SizedBox(height: 12),
                            _buildAdresaOverride(
                              putnik: selectedPutnik!,
                              grad: _selectedGrad,
                              selected: selectedAdresa,
                              onChanged: (a) => setS(() => selectedAdresa = a),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // Actions
                  V3ContainerUtils.iconContainer(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Theme.of(ctx).glassContainer,
                    borderRadiusGeometry:
                        const BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
                    border: Border(top: BorderSide(color: Theme.of(ctx).glassBorder)),
                    child: Row(
                      children: [
                        Expanded(
                          child: V3ButtonUtils.outlinedButton(
                            onPressed: () => Navigator.pop(dialogCtx),
                            text: _tr('otkazi'),
                            borderColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: V3ButtonUtils.elevatedButton(
                            onPressed: isLoading
                                ? null
                                : () async {
                                    if (selectedPutnik == null) {
                                      V3AppSnackBar.error(ctx, _tr('izaberitePutnika'));
                                      return;
                                    }
                                    if (selectedPutnik!.id.isEmpty) {
                                      V3AppSnackBar.error(ctx, _tr('putnikNemaId'));
                                      return;
                                    }
                                    setS(() => isLoading = true);
                                    try {
                                      final isoDate = V3DanHelper.datumIsoZaDanPuniUTekucojSedmici(
                                        _selectedDay,
                                        anchor: V3DanHelper.schedulingWeekAnchor(),
                                      );
                                      final vozacId = V3VozacService.currentVozac?.id ?? 'nepoznat';

                                      // Odredi koristiSekundarnu i adresaIdOverride
                                      bool? koristiSekundarnu;
                                      String? adresaIdOverride;
                                      if (selectedAdresa != null) {
                                        final isBC = _selectedGrad.toUpperCase() == 'BC';
                                        final id1 = isBC ? selectedPutnik!.adresaBcId : selectedPutnik!.adresaVsId;
                                        final id2 = isBC ? selectedPutnik!.adresaBcId2 : selectedPutnik!.adresaVsId2;
                                        if (selectedAdresa!.id == id2) {
                                          koristiSekundarnu = true;
                                        } else if (selectedAdresa!.id == id1) {
                                          koristiSekundarnu = false;
                                        } else {
                                          // "Ostala" adresa — čuvamo ID direktno
                                          adresaIdOverride = selectedAdresa!.id;
                                          koristiSekundarnu = false;
                                        }
                                      }

                                      // Direktan INSERT u v3_operativna_nedelja — bez upisa u v3_zahtevi
                                      await V3OperativnaNedeljaService.createOrUpdateByVozac(
                                        putnikId: selectedPutnik!.id,
                                        datum: isoDate,
                                        grad: _selectedGrad,
                                        polazakAt: _selectedVreme,
                                        createdBy: V3UuidUtils.normalizeUuid(vozacId),
                                        koristiSekundarnu: koristiSekundarnu,
                                        adresaIdOverride: adresaIdOverride,
                                      );

                                      if (!dialogCtx.mounted) return;
                                      Navigator.pop(dialogCtx);
                                      if (mounted) V3AppSnackBar.success(context, _tr('rezervacijaDodana'));
                                    } catch (e) {
                                      setS(() => isLoading = false);
                                      if (ctx.mounted) V3AppSnackBar.error(ctx, '${_tr('greskaPrefix')} $e');
                                    }
                                  },
                            text: isLoading ? _tr('dodaje') : _tr('dodaj'),
                            icon: Icons.add,
                            backgroundColor: Colors.green.withValues(alpha: 0.7),
                            foregroundColor: Colors.white,
                            isLoading: isLoading,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) => V3TextUtils.disposeController('home_search'));
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  /// Dropdown za override adrese u dijalogu rezervacije.
  /// Putnikove 2 adrese za grad su na vrhu liste (označene ★), zatim sve ostale.
  Widget _buildAdresaOverride({
    required V3Putnik putnik,
    required String grad,
    required V3Adresa? selected,
    required ValueChanged<V3Adresa?> onChanged,
  }) {
    final isBC = grad.toUpperCase() == 'BC';
    final id1 = isBC ? putnik.adresaBcId : putnik.adresaVsId;
    final id2 = isBC ? putnik.adresaBcId2 : putnik.adresaVsId2;
    final adresa1 = V3AdresaService.getAdresaById(id1);
    final adresa2 = V3AdresaService.getAdresaById(id2);

    // Sve adrese za grad, bez duplikata
    final sve = V3AdresaService.getAdreseZaGrad(grad);
    final putnikoviIds = {if (adresa1 != null) adresa1.id, if (adresa2 != null) adresa2.id};
    final ostale = sve.where((a) => !putnikoviIds.contains(a.id)).toList();

    // Izgradnja stavki: putnikove adrese prve (★), pa separator, pa ostale
    final items = <DropdownMenuItem<V3Adresa?>>[];

    // "default" opcija — bez override
    items.add(const DropdownMenuItem<V3Adresa?>(
      value: null,
      child: Text('— putnikova adresa —', style: TextStyle(fontSize: 13, color: Colors.grey)),
    ));

    if (adresa1 != null) {
      items.add(DropdownMenuItem<V3Adresa?>(
        value: adresa1,
        child: Text('★ ${adresa1.naziv}',
            overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ));
    }
    if (adresa2 != null) {
      items.add(DropdownMenuItem<V3Adresa?>(
        value: adresa2,
        child: Text('★ ${adresa2.naziv}',
            overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ));
    }

    for (final a in ostale) {
      items.add(DropdownMenuItem<V3Adresa?>(
        value: a,
        child: V3SafeText.userAddress(a.naziv, style: const TextStyle(fontSize: 13)),
      ));
    }

    return V3ContainerUtils.iconContainer(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      backgroundColor: Colors.white,
      borderRadiusGeometry: BorderRadius.circular(12),
      border: Border.all(color: selected != null ? Colors.blue.shade400 : Colors.grey.shade400),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: Colors.blueAccent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<V3Adresa?>(
                value: selected,
                isExpanded: true,
                isDense: true,
                hint: Text(_tr('adresaOpciono'), style: const TextStyle(fontSize: 13, color: Colors.grey)),
                items: items,
                onChanged: onChanged,
              ),
            ),
          ),
          if (selected != null)
            GestureDetector(
              onTap: () => onChanged(null),
              child: const Icon(Icons.clear, size: 18, color: Colors.grey),
            ),
        ],
      ),
    );
  }

  void _openDialogAfterMenuClose(VoidCallback openDialog) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      openDialog();
    });
  }

  // ─── Dialog: Račun za postojeću firmu (B2B) ──────────────────────
  void _showRacunZaFirmeDialog() {
    // v3_racuni sadrži jedan red po računu, pa se ista firma ponavlja.
    // Deduplikujemo po nazivu firme da dropdown prikaže samo jedinstvene firme.
    final seenFirme = <String>{};
    final firme = V3MasterRealtimeManager.instance.racuniCache.values.where((r) {
      final naziv = (r['firma_naziv'] ?? '').toString().trim();
      if (naziv.isEmpty) return false;
      final key = naziv.toLowerCase();
      if (seenFirme.contains(key)) return false;
      seenFirme.add(key);
      return true;
    }).toList()
      ..sort((a, b) => (a['firma_naziv'] ?? '').toString().compareTo((b['firma_naziv'] ?? '').toString()));

    if (firme.isEmpty) {
      V3AppSnackBar.warning(context, _tr('nemaFirmiUBazi'));
      return;
    }

    final putnici = V3MasterRealtimeManager.instance.putniciCache.values.toList()
      ..sort((a, b) => (a['ime_prezime'] ?? '').toString().compareTo((b['ime_prezime'] ?? '').toString()));

    V3DialogHelper.showDialogBuilder<void>(
      context: context,
      builder: (ctx) => _RacunFirmeDialogContent(
        firme: firme,
        putnici: putnici,
        parentContext: context,
      ),
    );
  }

  // ─── Dialog: Novi račun za fizičko lice ───────────────────────────
  void _showNoviRacunDialog() {
    final imeCtrl = TextEditingController();
    final adresaCtrl = TextEditingController();
    final opisCtrl = TextEditingController();
    final iznosCtrl = TextEditingController();
    final kolicinaCtrl = TextEditingController(text: '1');
    String jedMera = 'usluga';
    DateTime selectedMesec = DateTime(DateTime.now().year, DateTime.now().month, 1);
    DateTime datumPrometa = _lastDayOfMonth(selectedMesec);
    DateTime datumIzdavanja = DateTime.now();

    V3DialogHelper.showDialogBuilder<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFF1A2035),
          title: Text(_tr('noviRacun'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogField(imeCtrl, _tr('imePrezimeKupca')),
                const SizedBox(height: 8),
                _dialogField(adresaCtrl, _tr('adresaKupca')),
                const SizedBox(height: 8),
                _dialogField(opisCtrl, _tr('opisUsluge')),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _dialogField(iznosCtrl, _tr('cena'), numeric: true)),
                  const SizedBox(width: 8),
                  Expanded(child: _dialogField(kolicinaCtrl, _tr('kolicina'), numeric: true)),
                ]),
                const SizedBox(height: 8),
                // Jedinica mjere
                DropdownButtonFormField<String>(
                  value: jedMera,
                  dropdownColor: const Color(0xFF1A2035),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: _tr('jedinicaMere'),
                    labelStyle: const TextStyle(color: Colors.white54),
                    enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white30),
                    ),
                  ),
                  items: [
                    DropdownMenuItem(value: 'usluga', child: Text(_tr('jmUsluga'))),
                    DropdownMenuItem(value: 'dan', child: Text(_tr('jmDan'))),
                    DropdownMenuItem(value: 'kom', child: Text(_tr('jmKom'))),
                    DropdownMenuItem(value: 'sat', child: Text(_tr('jmSat'))),
                    DropdownMenuItem(value: 'km', child: Text(_tr('jmKm'))),
                  ],
                  onChanged: (v) => setS(() => jedMera = v ?? 'usluga'),
                ),
                const SizedBox(height: 8),
                // Mesec izdavanja
                Row(children: [
                  Text(_tr('mesecIzdavanja'), style: const TextStyle(color: Colors.white70)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: V3ButtonUtils.textButton(
                      onPressed: () async {
                        final meseci = _racunMesecOptions();
                        final initialDate = selectedMesec;
                        final currentYear = DateTime.now().year;
                        final currentMonth = DateTime.now().month;

                        // Prikazivanje dijaloga za izbor meseca
                        final izabraniMesec = await showDialog<DateTime>(
                          context: ctx,
                          builder: (dialogCtx) {
                            DateTime? privremeniIzbor = initialDate;
                            return AlertDialog(
                              backgroundColor: const Color(0xFF1A2035),
                              title: Text(_tr('izaberiMesec'), style: const TextStyle(color: Colors.white)),
                              content: SizedBox(
                                width: double.maxFinite,
                                child: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (final mesec in meseci)
                                        ListTile(
                                          title: Text(
                                            _formatMesecRacuna(mesec),
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          trailing: privremeniIzbor != null &&
                                                  mesec.year == privremeniIzbor!.year &&
                                                  mesec.month == privremeniIzbor!.month
                                              ? const Icon(Icons.check, color: Colors.green, size: 20)
                                              : null,
                                          onTap: () {
                                            privremeniIzbor = mesec;
                                            Navigator.pop(dialogCtx, mesec);
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );

                        if (izabraniMesec != null) {
                          setState(() {
                            selectedMesec = izabraniMesec;
                            datumPrometa = _lastDayOfMonth(izabraniMesec);
                          });
                        }
                      },
                      text: _formatMesecRacuna(selectedMesec),
                      foregroundColor: Colors.amber,
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                // Datum izdavanja
                Row(children: [
                  Text(_tr('datumIzdavanja'), style: const TextStyle(color: Colors.white70)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: V3ButtonUtils.textButton(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: datumIzdavanja,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (d != null) setState(() => datumIzdavanja = d);
                      },
                      text: '${datumIzdavanja.day}.${datumIzdavanja.month}.${datumIzdavanja.year}',
                      foregroundColor: Colors.amber,
                    ),
                  ),
                ]),
              ],
            ),
          ),
          actions: [
            V3ButtonUtils.textButton(
              onPressed: () => Navigator.pop(ctx),
              text: _tr('otkazi'),
              foregroundColor: Colors.red,
            ),
            V3ButtonUtils.successButton(
              onPressed: () async {
                if (imeCtrl.text.trim().isEmpty || opisCtrl.text.trim().isEmpty) {
                  V3AppSnackBar.error(ctx, _tr('popuniteImeOpis'));
                  return;
                }
                final cena = double.tryParse(iznosCtrl.text.trim()) ?? 0;
                final kolicina = double.tryParse(kolicinaCtrl.text.trim()) ?? 1;
                if (cena <= 0) {
                  V3AppSnackBar.error(ctx, _tr('uneseiteIspravnuCenu'));
                  return;
                }

                final broj = await V3RacunService.getNextBrojRacuna();
                if (!ctx.mounted) return;
                await V3RacunService.stampajRacun(
                  brojRacuna: broj,
                  imePrezimeKupca: imeCtrl.text.trim(),
                  adresaKupca: adresaCtrl.text.trim(),
                  opisUsluge: opisCtrl.text.trim(),
                  cena: cena,
                  kolicina: kolicina,
                  jedinicaMere: jedMera,
                  datumPrometa: datumPrometa,
                  datumIzdavanja: datumIzdavanja,
                  context: ctx,
                );

                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
              },
              text: _tr('stampaj'),
            ),
          ],
        ),
      ),
    ).then((_) {
      imeCtrl.dispose();
      adresaCtrl.dispose();
      opisCtrl.dispose();
      iznosCtrl.dispose();
      kolicinaCtrl.dispose();
    });
  }

  Widget _dialogField(TextEditingController ctrl, String label, {bool numeric = false}) {
    return numeric
        ? V3InputUtils.numberField(
            controller: ctrl,
            label: label,
          )
        : V3InputUtils.textField(
            controller: ctrl,
            label: label,
          );
  }

  @override
  Widget build(BuildContext context) {
    final vozac = V3VozacService.currentVozac;

    if (_isLoading) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: V3ContainerUtils.gradientContainer(
            gradient: V3ThemeManager().currentGradient,
            child: const Center(child: CircularProgressIndicator(color: Colors.white)),
          ),
        ),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Stack(
        children: [
          StreamBuilder<List<V3OperativnaNedeljaEntry>>(
            stream: _operativnaStream,
            builder: (context, snapshot) {
              final sviZapisi = snapshot.data ?? [];

              String slotVreme(V3OperativnaNedeljaEntry z) => z.polazakAt ?? '';

              final rm = V3MasterRealtimeManager.instance;

              V3Putnik? _resolvePutnik(V3OperativnaNedeljaEntry z) {
                final fromPutnici = V3PutnikService.getPutnikById(z.putnikId);
                if (fromPutnici != null) return fromPutnici;

                final putnikCacheRow = rm.putniciCache[z.putnikId];
                if (putnikCacheRow != null) return V3Putnik.fromJson(putnikCacheRow);

                return null;
              }

              // Lista: datum dolazi iz stream-a; prikazujemo redove samo za izabrani grad + slot vreme
              final currentVozacId = V3VozacService.currentVozac?.id;
              final prikazaniZapisi = sviZapisi.where((z) {
                return V3StatusPolicy.matchesSelectedSlot(
                  entryGrad: z.grad,
                  entryVreme: z.polazakAt,
                  grad: _selectedGrad,
                  vreme: _selectedVreme,
                );
              }).toList()
                ..sort((a, b) {
                  return V3StatusPolicy.compareEntriesForDisplay<V3OperativnaNedeljaEntry>(
                    a: a,
                    b: b,
                    currentVozacId: currentVozacId,
                    otkazanoAtOf: (entry) => entry.otkazanoAt,
                    pokupljenAtOf: (entry) => entry.pokupljenAt,
                    putnikIdOf: (entry) => entry.putnikId,
                    assignedVozacIdForEntry: (entry) {
                      final indiv = _getVozacZaPutnika(
                        entry.putnikId,
                        entry.grad ?? '',
                        slotVreme(entry),
                        _selectedDatumIso,
                      );
                      return indiv?.id;
                    },
                    putnikNameById: (putnikId) => V3PutnikService.getPutnikById(putnikId)?.imePrezime ?? '',
                  );
                });

              final resolvedZapisi = prikazaniZapisi.map((z) {
                final p = _resolvePutnik(z);
                final putnik = p ??
                    V3Putnik(
                      id: z.putnikId,
                      imePrezime: 'Nepoznat putnik',
                      tipPutnika: 'dnevni',
                    );
                return (entry: z, putnik: putnik);
              }).toList();

              // Brojač po gradu/vremenu za bottom nav bar (nav bar prikazuje oba grada)
              int getPutnikCount(String grad, String vreme) {
                return V3StatusPolicy.countOccupiedSeatsForSlot<V3OperativnaNedeljaEntry>(
                  items: sviZapisi,
                  grad: grad,
                  vreme: vreme,
                  includeItem: (entry) {
                    final tip =
                        (V3MasterRealtimeManager.instance.putniciCache[entry.putnikId]?['tip_putnika'] as String?)
                            ?.toLowerCase()
                            .trim();
                    return tip != 'posiljka';
                  },
                  gradOf: (entry) => entry.grad,
                  vremeOf: (entry) => entry.polazakAt,
                  statusOf: (entry) => entry.statusFinal,
                  otkazanoAtOf: (entry) => entry.otkazanoAt,
                );
              }

              // Kapacitet
              int? getKapacitet(String grad, String vreme) {
                final datum = DateTime.tryParse(_selectedDatumIso) ?? DateTime.now();
                return V3OperativnaNedeljaService.getKapacitetVozila(grad, vreme, datum);
              }

              Color? getVozacColor(String grad, String vreme) {
                final rm = V3MasterRealtimeManager.instance;
                final vozacId = V3StatusPolicy.sharedVozacIdForTermin(
                  operativnaRows: rm.operativnaNedeljaCache.values,
                  grad: grad,
                  vreme: vreme,
                  datumIso: _selectedDatumIso,
                  vozacIdForRow: _vozacIdForOperativnaRow,
                  isVisibleRow: _isVisibleOperativnaRow,
                  vremeKolona: 'polazak_at',
                );
                final resolvedVozacId = (vozacId ?? '').trim().isNotEmpty
                    ? vozacId!.trim()
                    : V3DodelaResolverService.resolveVozacIdForSlot(
                        datumIso: _selectedDatumIso,
                        grad: grad,
                        vreme: vreme,
                        activeVozacBySlotKey: _activeVozacBySlotKey,
                      );
                if (resolvedVozacId.isNotEmpty) {
                  final vozac = V3VozacService.getVozacById(resolvedVozacId);
                  if (vozac != null) return V3CardColorPolicy.vozacColorOr(vozac.boja);
                }

                return null;
              }

              final textScaleFactor = MediaQuery.textScalerOf(context).scale(1.0);
              final headerScaleExtra = (textScaleFactor - 1.0).clamp(0.0, 0.6).toDouble();
              final appBarHeight = 106 + (headerScaleExtra * 20);
              final headerControlHeight = 33 + (headerScaleExtra * 8);
              final weekRange = V3DanHelper.schedulingWeekRange();
              final ponedeljak = weekRange.start;
              final petak = weekRange.end;
              final aktivnaNedelja =
                  'Operativna nedelja: ${ponedeljak.day.toString().padLeft(2, '0')}.${ponedeljak.month.toString().padLeft(2, '0')} - ${petak.day.toString().padLeft(2, '0')}.${petak.month.toString().padLeft(2, '0')}';

              return V3ContainerUtils.gradientContainer(
                gradient: V3ThemeManager().currentGradient,
                child: Stack(
                  children: [
                    Scaffold(
                      backgroundColor: Colors.transparent,
                      appBar: PreferredSize(
                        preferredSize: Size.fromHeight(appBarHeight),
                        child: V3ContainerUtils.iconContainer(
                          backgroundColor: Theme.of(context).glassContainer,
                          border: Border.all(color: Theme.of(context).glassBorder, width: 0.8),
                          borderRadiusGeometry: const BorderRadius.only(
                            bottomLeft: Radius.circular(25),
                            bottomRight: Radius.circular(25),
                          ),
                          child: SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  // Red 1 - naslov
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Center(
                                          child: Text(
                                            'R E Z E R V A C I J E',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800,
                                              color: Theme.of(context).colorScheme.onPrimary,
                                              letterSpacing: 1.4,
                                              shadows: const [
                                                Shadow(blurRadius: 12, color: Colors.black87),
                                                Shadow(offset: Offset(2, 2), blurRadius: 6, color: Colors.black54),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    aktivnaNedelja,
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.85),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 4),
                                  // Red 2 - dan
                                  Row(
                                    children: [
                                      // Sat sa sekundama
                                      Expanded(
                                        child: V3ContainerUtils.iconContainer(
                                          height: headerControlHeight,
                                          padding: const EdgeInsets.all(6),
                                          backgroundColor: Theme.of(context).glassContainer,
                                          borderRadiusGeometry: BorderRadius.circular(14),
                                          border: Border.all(color: Theme.of(context).glassBorder, width: 0.8),
                                          child: Center(
                                            child: V3LiveClockText(
                                              style: TextStyle(
                                                color: Theme.of(context).colorScheme.onPrimary,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      // Dan dropdown
                                      Expanded(
                                        child: V3ContainerUtils.iconContainer(
                                          height: headerControlHeight,
                                          padding: const EdgeInsets.all(6),
                                          backgroundColor: Theme.of(context).glassContainer,
                                          borderRadiusGeometry: BorderRadius.circular(14),
                                          border: Border.all(color: Theme.of(context).glassBorder, width: 0.8),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton2<String>(
                                              value: _selectedDay,
                                              customButton: Center(
                                                child: Text(
                                                  _selectedDay,
                                                  style: TextStyle(
                                                    color: Theme.of(context).colorScheme.onPrimary,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 14,
                                                  ),
                                                  maxLines: 1,
                                                  softWrap: false,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              dropdownStyleData: DropdownStyleData(
                                                width: 170,
                                                maxHeight: 320,
                                                decoration: BoxDecoration(
                                                  gradient: Theme.of(context).backgroundGradient,
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: Theme.of(context).glassBorder, width: 0.8),
                                                ),
                                                elevation: 8,
                                              ),
                                              menuItemStyleData: const MenuItemStyleData(
                                                height: 44,
                                              ),
                                              items: V3DanHelper.workdayNames
                                                  .map((d) => DropdownMenuItem(
                                                        value: d,
                                                        child: Center(
                                                          child: Text(
                                                            d,
                                                            style: TextStyle(
                                                              color: Theme.of(context).colorScheme.onPrimary,
                                                              fontWeight: FontWeight.w700,
                                                            ),
                                                            maxLines: 1,
                                                            softWrap: false,
                                                            overflow: TextOverflow.ellipsis,
                                                            textAlign: TextAlign.center,
                                                          ),
                                                        ),
                                                      ))
                                                  .toList(),
                                              onChanged: (val) {
                                                setState(() {
                                                  _selectedDay = V3DanHelper.normalizeToWorkdayFull(val!);
                                                  _syncSelectedSlotForDatum(_selectedDatumIso);
                                                  _operativnaStream = _buildOperativnaStream(_selectedDatumIso);
                                                });
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      body: Column(
                        children: [
                          // Forced update gate
                          const V3UpdateBanner(),
                          const V3NeradniDaniBanner(
                            margin: EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 4),
                          ),
                          const V3InfoBanner(
                            margin: EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 4),
                          ),
                          // Action buttons
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _V3HomeButton(
                                    label: 'Dodaj',
                                    icon: Icons.person_add,
                                    onTap: _showDodajTerminDialog,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                if (!_isAdmin) ...[
                                  Expanded(
                                    child: _V3HomeButton(
                                      label: 'Ja',
                                      icon: Icons.person,
                                      onTap: () => V3NavigationUtils.pushScreen(
                                        context,
                                        const V3VozacScreen(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                if (_isAdmin) ...[
                                  Expanded(
                                    child: _V3HomeButton(
                                      label: 'Admin',
                                      icon: Icons.admin_panel_settings,
                                      onTap: () => V3NavigationUtils.pushScreen(
                                        context,
                                        const V3AdminScreen(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: _V3HomeButton(
                                      label: 'Ja',
                                      icon: Icons.person,
                                      onTap: () => V3NavigationUtils.pushScreen(
                                        context,
                                        const V3VozacScreen(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: PopupMenuButton<String>(
                                      tooltip: _tr('stampaj'),
                                      offset: const Offset(0, -150),
                                      onSelected: (val) {
                                        if (val == 'spisak') {
                                          V3PrintingService.printPutniksList(
                                            datumIso: _selectedDatumIso,
                                            dan: _selectedDay,
                                            vreme: _selectedVreme,
                                            grad: _selectedGrad,
                                            context: context,
                                          );
                                        } else if (val == 'racun_postojeci') {
                                          _openDialogAfterMenuClose(_showRacunZaFirmeDialog);
                                        } else if (val == 'racun_novi') {
                                          _openDialogAfterMenuClose(_showNoviRacunDialog);
                                        }
                                      },
                                      child: V3ContainerUtils.iconContainer(
                                        padding: const EdgeInsets.all(6),
                                        backgroundColor: Theme.of(context).glassContainer,
                                        border: Border.all(color: Theme.of(context).glassBorder, width: 0.8),
                                        borderRadiusGeometry: BorderRadius.circular(12),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.print, color: Theme.of(context).colorScheme.onPrimary, size: 18),
                                            const SizedBox(height: 4),
                                            SizedBox(
                                              height: V3ContainerUtils.responsiveHeight(context, 16),
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(_tr('stampaj'),
                                                    style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w600)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      itemBuilder: (_) => [
                                        PopupMenuItem(
                                          value: 'spisak',
                                          child: Row(children: [
                                            const Icon(Icons.list_alt, color: Colors.blue),
                                            const SizedBox(width: 8),
                                            Text(_tr('stampajSpisak')),
                                          ]),
                                        ),
                                        const PopupMenuDivider(),
                                        PopupMenuItem(
                                          value: 'racun_postojeci',
                                          child: Row(children: [
                                            const Icon(Icons.people, color: Colors.green),
                                            const SizedBox(width: 8),
                                            Text(_tr('racunPostojeci')),
                                          ]),
                                        ),
                                        PopupMenuItem(
                                          value: 'racun_novi',
                                          child: Row(children: [
                                            const Icon(Icons.person_add, color: Colors.orange),
                                            const SizedBox(width: 8),
                                            Text(_tr('racunNovi')),
                                          ]),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // Lista putnika/termina + floating neradan-banер
                          Expanded(
                            child: ValueListenableBuilder<List<Map<String, String>>>(
                              valueListenable: neradniDaniNotifier,
                              builder: (context, rules, _) {
                                int redniCounter = 0;
                                final redniBrojevi = <int?>[];
                                for (final row in resolvedZapisi) {
                                  final tip = row.putnik.tipPutnika.toLowerCase().trim();
                                  if (tip == 'posiljka') {
                                    redniBrojevi.add(null);
                                  } else {
                                    redniCounter += 1;
                                    redniBrojevi.add(redniCounter);
                                  }
                                }

                                return resolvedZapisi.isEmpty
                                    ? Center(
                                        child: Container(
                                          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                          child: V3ContainerUtils.iconContainer(
                                            padding: const EdgeInsets.all(16),
                                            backgroundColor: Theme.of(context).glassContainer,
                                            border: Border.all(color: Theme.of(context).glassBorder, width: 0.8),
                                            borderRadiusGeometry: BorderRadius.circular(12),
                                            child: const Text(
                                              'Nema planiranih putnika.',
                                              style: TextStyle(
                                                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                                            ),
                                          ),
                                        ),
                                      )
                                    : ListView.builder(
                                        padding: const EdgeInsets.only(top: 4, bottom: 16),
                                        itemCount: resolvedZapisi.length,
                                        itemBuilder: (ctx, i) {
                                          final row = resolvedZapisi[i];
                                          final z = row.entry;
                                          final p = row.putnik;

                                          final grad = z.grad ?? '';
                                          final vreme = slotVreme(z);
                                          final indivVozac =
                                              _getVozacZaPutnika(z.putnikId, grad, vreme, _selectedDatumIso);
                                          final vozacBoja = indivVozac != null
                                              ? V3CardColorPolicy.vozacColorOr(indivVozac.boja)
                                              : getVozacColor(grad, vreme);
                                          final redniBroj = redniBrojevi[i];

                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 8),
                                            child: V3PutnikCard(
                                              putnik: p,
                                              entry: z,
                                              redniBroj: redniBroj,
                                              vozacBoja: vozacBoja,
                                            ),
                                          );
                                        },
                                      );
                              },
                            ),
                          ),
                        ],
                      ),
                      // Bottom nav bar
                      bottomNavigationBar: ValueListenableBuilder<String>(
                        valueListenable: navBarTypeNotifier,
                        builder: (ctx, navType, _) {
                          return _buildBottomNavBar(getPutnikCount, getKapacitet, getVozacColor);
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar(
    int Function(String, String) getPutnikCount,
    int? Function(String, String) getKapacitet,
    Color? Function(String, String) getVozacColor,
  ) {
    return ValueListenableBuilder<String>(
      valueListenable: navBarTypeNotifier,
      builder: (context, navType, _) {
        final neradanRazlog = _neradanDanRazlog;
        if (neradanRazlog != null) {
          return SafeArea(
            child: Container(
              margin: const EdgeInsets.fromLTRB(10, 4, 10, 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.7)),
              ),
              child: Text(
                '⛔ Slotovi su zaključani za $_selectedDay. Razlog: $neradanRazlog',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        // Aktivni custom raspored se prosleđuje jedinstvenom layout widgetu
        return V3BottomNavBarSlotovi(
          selectedGrad: _selectedGrad,
          selectedVreme: _selectedVreme,
          onPolazakChanged: (grad, vreme) {
            setState(() {
              _selectedGrad = grad;
              _selectedVreme = vreme;
            });
          },
          getPutnikCount: getPutnikCount,
          getKapacitet: getKapacitet,
          showVozacBoja: true,
          getVozacColor: getVozacColor,
          getVozacColors: getVozacColors,
          bcVremena: _bcVremena,
          vsVremena: _vsVremena,
        );
      },
    );
  }
}

// ─── Dijalog: Račun za firmu — sadržaj ────────────────────────────────────────
class _RacunFirmeDialogContent extends StatefulWidget {
  const _RacunFirmeDialogContent({
    required this.firme,
    required this.putnici,
    required this.parentContext,
  });

  final List<Map<String, dynamic>> firme;
  final List<Map<String, dynamic>> putnici;
  final BuildContext parentContext;

  @override
  State<_RacunFirmeDialogContent> createState() => _RacunFirmeDialogContentState();
}

class _RacunFirmeDialogContentState extends State<_RacunFirmeDialogContent> {
  String _tr(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    return _V3HomeScreenState._t[key]?[code] ?? _V3HomeScreenState._t[key]?['sr'] ?? key;
  }

  late Map<String, dynamic>? selectedFirma;
  late Map<String, dynamic>? selectedPutnik;
  late final TextEditingController pretragaCtrl;
  late final TextEditingController cenaCtrl;
  late final TextEditingController danaCtrl;
  DateTime selectedMesec = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime datumPrometa = _lastDayOfMonth(DateTime(DateTime.now().year, DateTime.now().month, 1));
  DateTime datumIzdavanja = DateTime.now();
  bool _autoPredlogEnabled = true;

  @override
  void initState() {
    super.initState();
    selectedFirma = widget.firme.first;
    selectedPutnik = widget.putnici.isNotEmpty ? widget.putnici.first : null;
    pretragaCtrl = TextEditingController();
    cenaCtrl = TextEditingController();
    danaCtrl = TextEditingController();
    _applyPredlog();

    cenaCtrl.addListener(_onRucnaIzmena);
    danaCtrl.addListener(_onRucnaIzmena);
  }

  void _onRucnaIzmena() {
    _autoPredlogEnabled = false;
  }

  void _applyPredlog() {
    final predlog = _racunPredlogZaPutnik(selectedPutnik, selectedMesec);
    danaCtrl.text = predlog.brojDana > 0 ? predlog.brojDana.toString() : '';
    cenaCtrl.text = predlog.cenaPoDanu > 0 ? predlog.cenaPoDanu.toStringAsFixed(0) : '';
  }

  @override
  void dispose() {
    pretragaCtrl.dispose();
    cenaCtrl.dispose();
    danaCtrl.dispose();
    super.dispose();
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 0.5)),
      );

  Widget _divider() => const Divider(color: Color(0xFF666666), height: 20);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = const Color(0xFF1A1A1A);
    final sectionBg = const Color(0xFF2A2A2A);
    final borderColor = Colors.grey.withOpacity(0.4);

    final filtrirani = pretragaCtrl.text.trim().isEmpty
        ? widget.putnici
        : widget.putnici
            .where((p) =>
                (p['ime_prezime'] ?? '').toString().toLowerCase().contains(pretragaCtrl.text.trim().toLowerCase()))
            .toList();

    final ukupno = (double.tryParse(cenaCtrl.text) ?? 0) * (double.tryParse(danaCtrl.text) ?? 0);
    final predlog = _racunPredlogZaPutnik(selectedPutnik, selectedMesec);

    return AlertDialog(
      backgroundColor: bg,
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      title: Row(children: [
        const Icon(Icons.receipt_long, color: Colors.green, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(_tr('racunFirma'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
        ),
      ]),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _showDodajNovuFirmuDialog,
                  icon: const Icon(Icons.add_business, size: 16, color: Colors.green),
                  label: Text(_tr('novaFirma'), style: const TextStyle(color: Colors.green, fontSize: 12)),
                ),
              ),

              // ── FIRMA ──
              _sectionLabel(_tr('sekcijaFirma')),
              Container(
                decoration: BoxDecoration(
                  color: sectionBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedFirma?['id']?.toString(),
                    dropdownColor: sectionBg,
                    isExpanded: true,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    iconEnabledColor: Colors.white54,
                    items: widget.firme
                        .map((f) => DropdownMenuItem<String>(
                              value: f['id']?.toString(),
                              child: Text(f['firma_naziv']?.toString() ?? '---'),
                            ))
                        .toList(),
                    onChanged: (id) =>
                        setState(() => selectedFirma = widget.firme.firstWhere((f) => f['id']?.toString() == id)),
                  ),
                ),
              ),
              if (selectedFirma != null) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1525),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: borderColor),
                  ),
                  child: DefaultTextStyle(
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(selectedFirma!['firma_adresa']?.toString() ?? ''),
                        const SizedBox(height: 2),
                        Text('PIB: ${selectedFirma!['firma_pib'] ?? ''}   MB: ${selectedFirma!['firma_mb'] ?? ''}'),
                        if ((selectedFirma!['firma_ziro'] ?? '').toString().isNotEmpty)
                          Text('Žiro: ${selectedFirma!['firma_ziro']}'),
                      ],
                    ),
                  ),
                ),
              ],

              _divider(),

              // ── PUTNIK ──
              _sectionLabel(_tr('sekcijaPutnik')),
              TextField(
                controller: pretragaCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: _tr('pretrazi'),
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                  suffixIcon: pretragaCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.white38, size: 16),
                          onPressed: () => setState(() => pretragaCtrl.clear()),
                        )
                      : null,
                  filled: true,
                  fillColor: sectionBg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.green),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  color: sectionBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor),
                ),
                child: filtrirani.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(_tr('nemaRezultata'), style: const TextStyle(color: Colors.white38)),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtrirani.length,
                        itemBuilder: (_, i) {
                          final p = filtrirani[i];
                          final isSelected = p['id']?.toString() == selectedPutnik?['id']?.toString();
                          return InkWell(
                            onTap: () => setState(() {
                              selectedPutnik = p;
                              if (_autoPredlogEnabled) _applyPredlog();
                            }),
                            child: Container(
                              color: isSelected ? Colors.green.withOpacity(0.15) : Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Row(children: [
                                Icon(
                                  isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                  color: isSelected ? Colors.green : Colors.white30,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    p['ime_prezime']?.toString() ?? '---',
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.white70,
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                Text(
                                  p['tip_putnika']?.toString() ?? '',
                                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                                ),
                              ]),
                            ),
                          );
                        },
                      ),
              ),

              _divider(),

              // ── MESEC I DATUMI ──
              _sectionLabel(_tr('sekcijaMesecIDatumi')),
              InkWell(
                onTap: () async {
                  final meseci = _racunMesecOptions();
                  final initialDate = selectedMesec;
                  final izabraniMesec = await showDialog<DateTime>(
                    context: context,
                    builder: (dialogCtx) {
                      return AlertDialog(
                        backgroundColor: bg,
                        title: Text(_tr('izaberiMesec'), style: const TextStyle(color: Colors.white)),
                        content: SizedBox(
                          width: double.maxFinite,
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final mesec in meseci)
                                  ListTile(
                                    title: Text(
                                      _formatMesecRacuna(mesec),
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                                    ),
                                    trailing: mesec.year == initialDate.year && mesec.month == initialDate.month
                                        ? const Icon(Icons.check, color: Colors.green, size: 20)
                                        : null,
                                    onTap: () => Navigator.pop(dialogCtx, mesec),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                  if (izabraniMesec != null) {
                    setState(() {
                      selectedMesec = izabraniMesec;
                      datumPrometa = _lastDayOfMonth(izabraniMesec);
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: sectionBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(children: [
                    const Icon(Icons.calendar_month, color: Colors.amber, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Mesec: ${_formatMesecRacuna(selectedMesec)}',
                      style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: datumIzdavanja,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (d != null) setState(() => datumIzdavanja = d);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: sectionBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(children: [
                        const Icon(Icons.edit_calendar, color: Colors.amber, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Izdavanje: ${datumIzdavanja.day.toString().padLeft(2, '0')}.${datumIzdavanja.month.toString().padLeft(2, '0')}.${datumIzdavanja.year}.',
                            style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w600, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: datumPrometa,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (d != null) setState(() => datumPrometa = d);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: sectionBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(children: [
                        const Icon(Icons.calendar_today, color: Colors.amber, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Promet: ${datumPrometa.day.toString().padLeft(2, '0')}.${datumPrometa.month.toString().padLeft(2, '0')}.${datumPrometa.year}.',
                            style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w600, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ]),

              _divider(),

              // ── IZNOS ──
              _sectionLabel(_tr('sekcijaIznos')),
              Row(children: [
                Expanded(
                    child: V3InputUtils.numberField(
                  controller: danaCtrl,
                  label: 'Dana',
                  onChanged: (_) => setState(() {}),
                )),
                const SizedBox(width: 8),
                Expanded(
                    child: V3InputUtils.numberField(
                  controller: cenaCtrl,
                  label: 'Cena/dan',
                  onChanged: (_) => setState(() {}),
                )),
              ]),

              // ── SUMMARY ──
              if (selectedPutnik != null && ukupno > 0) ...[
                _divider(),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedFirma?['firma_naziv']?.toString() ?? '',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      Text(
                        selectedPutnik!['ime_prezime']?.toString() ?? '',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ukupno: ${ukupno.toStringAsFixed(2)} RSD',
                        style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actions: [
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.pop(context),
          text: _tr('otkazi'),
          foregroundColor: Colors.red,
        ),
        V3ButtonUtils.successButton(
          onPressed: () async {
            final ime = (selectedPutnik?['ime_prezime']?.toString() ?? '').trim();
            if (ime.isEmpty) {
              V3AppSnackBar.warning(context, _tr('odaberitePutnika'));
              return;
            }
            final cena = double.tryParse(cenaCtrl.text.trim()) ?? 0;
            final dana = double.tryParse(danaCtrl.text.trim()) ?? 1;
            if (cena <= 0) {
              V3AppSnackBar.warning(context, _tr('uneseiteIspravnuCenu'));
              return;
            }

            final ctx = context;
            final broj = await V3RacunService.getNextBrojRacuna();
            if (!ctx.mounted) return;

            await V3RacunService.stampajRacuneZaFirme(
              racuniPodaci: [
                {
                  'putnik_id': selectedPutnik?['id']?.toString() ?? '',
                  'ime_prezime': ime,
                  'cena_po_voznji': cena,
                  'broj_voznji': dana,
                  'broj_racuna': broj,
                  'firma_naziv': selectedFirma?['firma_naziv'],
                  'firma_adresa': selectedFirma?['firma_adresa'],
                  'firma_pib': selectedFirma?['firma_pib'],
                  'firma_ziro': selectedFirma?['firma_ziro'],
                }
              ],
              context: widget.parentContext,
              datumPrometa: datumPrometa,
              datumIzdavanja: datumIzdavanja,
            );

            if (ctx.mounted) {
              Navigator.pop(ctx);
            }
          },
          text: 'Štampaj',
        ),
      ],
    );
  }

  /// Dijalog za brzi unos nove firme u v3_racuni tabelu
  void _showDodajNovuFirmuDialog() {
    final nazivCtrl = TextEditingController();
    final adresaCtrl = TextEditingController();
    final pibCtrl = TextEditingController();
    final mbCtrl = TextEditingController();
    final ziroCtrl = TextEditingController();

    V3DialogHelper.showDialogBuilder<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(_tr('dodajNovuFirmu'),
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _localField(nazivCtrl, 'Naziv firme'),
              const SizedBox(height: 8),
              _localField(adresaCtrl, 'Adresa'),
              const SizedBox(height: 8),
              _localField(pibCtrl, 'PIB', numeric: true),
              const SizedBox(height: 8),
              _localField(mbCtrl, 'Matični broj', numeric: true),
              const SizedBox(height: 8),
              _localField(ziroCtrl, 'Žiro račun'),
            ],
          ),
        ),
        actions: [
          V3ButtonUtils.textButton(
            onPressed: () => Navigator.pop(ctx),
            text: 'Otkaži',
            foregroundColor: Colors.red,
          ),
          V3ButtonUtils.successButton(
            onPressed: () async {
              final naziv = nazivCtrl.text.trim();
              if (naziv.isEmpty) {
                V3AppSnackBar.error(ctx, '⚠️ Unesite naziv firme');
                return;
              }
              try {
                await supabase.from('v3_racuni').insert({
                  'firma_naziv': naziv,
                  'firma_adresa': adresaCtrl.text.trim(),
                  'firma_pib': pibCtrl.text.trim(),
                  'firma_mb': mbCtrl.text.trim(),
                  'firma_ziro': ziroCtrl.text.trim(),
                });
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) V3AppSnackBar.error(ctx, '❌ Greška pri upisu: $e');
              }
            },
            text: 'Sačuvaj',
          ),
        ],
      ),
    ).then((_) {
      nazivCtrl.dispose();
      adresaCtrl.dispose();
      pibCtrl.dispose();
      mbCtrl.dispose();
      ziroCtrl.dispose();
    });
  }

  Widget _localField(TextEditingController ctrl, String label, {bool numeric = false}) {
    return numeric
        ? V3InputUtils.numberField(controller: ctrl, label: label)
        : V3InputUtils.textField(controller: ctrl, label: label);
  }
}

class _V3HomeButton extends StatelessWidget {
  const _V3HomeButton({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: V3ContainerUtils.iconContainer(
        padding: const EdgeInsets.all(6),
        backgroundColor: Theme.of(context).glassContainer,
        border: Border.all(color: Theme.of(context).glassBorder, width: 0.8),
        borderRadiusGeometry: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.onPrimary, size: 18),
            const SizedBox(height: 4),
            SizedBox(
              height: V3ContainerUtils.responsiveHeight(context, 16),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    shadows: const [
                      Shadow(blurRadius: 8, color: Colors.black87),
                      Shadow(offset: Offset(1, 1), blurRadius: 4, color: Colors.black54),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
