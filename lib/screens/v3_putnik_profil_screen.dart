import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../globals.dart';
import '../models/v3_putnik.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_adresa_service.dart';
import '../services/v3/v3_closed_auth_service.dart';
import '../services/v3/v3_device_identity_service.dart';
import '../services/v3/v3_push_token_edge_service.dart';
import '../services/v3/v3_putnik_service.dart';
import '../services/v3/v3_putnik_statistika_service.dart';
import '../services/v3/v3_weather_service.dart';
import '../services/v3/v3_zahtev_service.dart';
import '../services/v3_biometric_service.dart';
import '../services/v3_locale_manager.dart';
import '../services/v3_theme_manager.dart';
import '../theme.dart';
import '../utils/v3_app_messages.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dialog_helper.dart';
import '../utils/v3_error_utils.dart';
import '../utils/v3_input_utils.dart';
import '../utils/v3_phone_utils.dart';
import '../utils/v3_state_utils.dart';
import '../utils/v3_status_policy.dart';
import '../utils/v3_stream_utils.dart';
import '../utils/v3_string_utils.dart';
import '../utils/v3_style_helper.dart';
import '../utils/v3_uuid_utils.dart';
import '../widgets/v3_info_banner.dart';
import '../widgets/v3_update_banner.dart';
import '../widgets/v3_vreme_dolaska_widget.dart';
import 'v3_help_screen.dart';
import 'v3_putnik_statistika_screen.dart';
import 'v3_welcome_screen.dart';

// Prevodi za dijaloge izmene profila / promene PIN-a (SR/EN/RU/DE).
const Map<String, Map<String, String>> _profileDialogT = {
  'izmeniProfilTitle': {
    'sr': 'Izmeni profil',
    'en': 'Edit profile',
    'ru': 'Изменить профиль',
    'de': 'Profil bearbeiten',
  },
  'azurirajImeTel': {
    'sr': 'Ažuriraj ime i broj telefona',
    'en': 'Update name and phone number',
    'ru': 'Обновите имя и номер телефона',
    'de': 'Name und Telefonnummer aktualisieren',
  },
  'imePrezime': {'sr': 'Ime i prezime', 'en': 'Full name', 'ru': 'Имя и фамилия', 'de': 'Vor- und Nachname'},
  'telefon1': {'sr': 'Telefon 1', 'en': 'Phone 1', 'ru': 'Телефон 1', 'de': 'Telefon 1'},
  'telefon2': {'sr': 'Telefon 2', 'en': 'Phone 2', 'ru': 'Телефон 2', 'de': 'Telefon 2'},
  'promeniPin': {'sr': 'Promeni PIN', 'en': 'Change PIN', 'ru': 'Изменить PIN', 'de': 'PIN ändern'},
  'otkazi': {'sr': 'Otkaži', 'en': 'Cancel', 'ru': 'Отмена', 'de': 'Abbrechen'},
  'sacuvaj': {'sr': 'Sačuvaj', 'en': 'Save', 'ru': 'Сохранить', 'de': 'Speichern'},
  'dodaj': {'sr': '➕ dodaj', 'en': '➕ add', 'ru': '➕ добавить', 'de': '➕ hinzufügen'},
  'imeNeSmeBitiPrazno': {
    'sr': '⚠️ Ime i prezime ne sme biti prazno',
    'en': '⚠️ Full name must not be empty',
    'ru': '⚠️ Имя и фамилия не должны быть пустыми',
    'de': '⚠️ Vor- und Nachname dürfen nicht leer sein',
  },
  'profilSacuvan': {
    'sr': '✅ Profil sačuvan',
    'en': '✅ Profile saved',
    'ru': '✅ Профиль сохранён',
    'de': '✅ Profil gespeichert',
  },
  'greska': {'sr': 'Greška', 'en': 'Error', 'ru': 'Ошибка', 'de': 'Fehler'},
  'promeniPinTitle': {'sr': 'Promeni PIN', 'en': 'Change PIN', 'ru': 'Изменить PIN', 'de': 'PIN ändern'},
  'unesiPinSubtitle': {
    'sr': 'Unesi trenutni i novi PIN (6 cifara)',
    'en': 'Enter current and new PIN (6 digits)',
    'ru': 'Введите текущий и новый PIN (6 цифр)',
    'de': 'Aktuelle und neue PIN eingeben (6 Ziffern)',
  },
  'trenutniPin': {'sr': 'Trenutni PIN', 'en': 'Current PIN', 'ru': 'Текущий PIN', 'de': 'Aktuelle PIN'},
  'noviPin': {'sr': 'Novi PIN', 'en': 'New PIN', 'ru': 'Новый PIN', 'de': 'Neue PIN'},
  'ponoviNoviPin': {
    'sr': 'Ponovi novi PIN',
    'en': 'Repeat new PIN',
    'ru': 'Повторите новый PIN',
    'de': 'Neue PIN wiederholen',
  },
  'trenutniPinMora6Cifara': {
    'sr': 'Trenutni PIN mora imati tačno 6 cifara.',
    'en': 'Current PIN must have exactly 6 digits.',
    'ru': 'Текущий PIN должен содержать ровно 6 цифр.',
    'de': 'Die aktuelle PIN muss genau 6 Ziffern haben.',
  },
  'noviPinMora6Cifara': {
    'sr': 'Novi PIN mora imati tačno 6 cifara.',
    'en': 'New PIN must have exactly 6 digits.',
    'ru': 'Новый PIN должен содержать ровно 6 цифр.',
    'de': 'Die neue PIN muss genau 6 Ziffern haben.',
  },
  'noviPinoviSeNePoklapaju': {
    'sr': 'Novi PIN-ovi se ne poklapaju.',
    'en': 'New PINs do not match.',
    'ru': 'Новые PIN-коды не совпадают.',
    'de': 'Die neuen PINs stimmen nicht überein.',
  },
  'noviPinMoraBitiRazlicit': {
    'sr': 'Novi PIN mora biti različit od trenutnog.',
    'en': 'New PIN must be different from the current one.',
    'ru': 'Новый PIN должен отличаться от текущего.',
    'de': 'Die neue PIN muss sich von der aktuellen unterscheiden.',
  },
  'trenutniPinNijeIspravan': {
    'sr': 'Trenutni PIN nije ispravan.',
    'en': 'Current PIN is incorrect.',
    'ru': 'Текущий PIN неверен.',
    'de': 'Die aktuelle PIN ist falsch.',
  },
  'nalogNemaPin': {
    'sr': 'Nalog nema podešen PIN.',
    'en': 'Account has no PIN set.',
    'ru': 'У аккаунта не установлен PIN.',
    'de': 'Für das Konto ist keine PIN festgelegt.',
  },
  'greskaPromenaPin': {
    'sr': 'Greška pri promeni PIN-a. Pokušaj ponovo.',
    'en': 'Error changing PIN. Please try again.',
    'ru': 'Ошибка при смене PIN. Попробуйте снова.',
    'de': 'Fehler beim Ändern der PIN. Bitte versuche es erneut.',
  },
  'pinPromenjen': {
    'sr': '✅ PIN je uspešno promenjen.',
    'en': '✅ PIN has been changed successfully.',
    'ru': '✅ PIN успешно изменён.',
    'de': '✅ PIN wurde erfolgreich geändert.',
  },
};

String _trProfileDialog(String key) {
  final code = V3LocaleManager().currentLocale.languageCode;
  return _profileDialogT[key]?[code] ?? _profileDialogT[key]?['sr'] ?? key;
}

class V3PutnikProfilScreen extends StatefulWidget {
  final Map<String, dynamic> putnikData;
  const V3PutnikProfilScreen({super.key, required this.putnikData});
  @override
  State<V3PutnikProfilScreen> createState() => _V3PutnikProfilScreenState();
}

class _V3PutnikProfilScreenState extends State<V3PutnikProfilScreen> with WidgetsBindingObserver {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _biometricPromptChoicePrefix = 'v3_biometric_prompt_choice_';

  late Map<String, dynamic> _putnikData;
  // Operativni termini po danu
  // key = dan kratica npr 'pon', value = lista termina (BC i VS)
  final Map<String, List<_ZahtevInfo>> _rasporedMap = {};
  Map<String, V3WeatherSnapshot> _weatherByGrad = const {};
  Timer? _weatherTimer;

  static final RegExp _timeFormat = RegExp(r'^\d{2}:\d{2}$');

  /// Debounce ključ za akcije otkazivanja/sačuvaj u profilu.
  String get _actionDebounceKey {
    final putnikId = _putnikData['id']?.toString() ?? 'unknown';
    return 'putnik_profil_${putnikId}_action_debounce';
  }

  // Prevodi za profil ekran (SR/EN/RU/DE) — isti obrazac kao welcome screen.
  static const Map<String, Map<String, String>> _t = {
    'tema': {'sr': 'Tema', 'en': 'Theme', 'ru': 'Тема', 'de': 'Thema'},
    'izmeniProfil': {'sr': 'Izmeni profil', 'en': 'Edit profile', 'ru': 'Изменить профиль', 'de': 'Profil bearbeiten'},
    'odjava': {'sr': 'Odjava', 'en': 'Log out', 'ru': 'Выйти', 'de': 'Abmelden'},
    'tipUcenik': {'sr': '🎓 Učenik', 'en': '🎓 Student', 'ru': '🎓 Ученик', 'de': '🎓 Schüler'},
    'tipPosiljka': {'sr': '📦 Pošiljka', 'en': '📦 Parcel', 'ru': '📦 Посылка', 'de': '📦 Paket'},
    'tipDnevni': {'sr': '📅 Dnevni', 'en': '📅 Daily', 'ru': '📅 Ежедневно', 'de': '📅 Täglich'},
    'tipRadnik': {'sr': '💼 Radnik', 'en': '💼 Worker', 'ru': '💼 Рабочий', 'de': '💼 Arbeiter'},
    'tipPutnik': {'sr': '👤 Putnik', 'en': '👤 Passenger', 'ru': '👤 Пассажир', 'de': '👤 Fahrgast'},
    'uputstvo': {
      'sr': 'Uputstvo za korišćenje',
      'en': 'Usage instructions',
      'ru': 'Инструкция по использованию',
      'de': 'Gebrauchsanweisung'
    },
    'cenaPoVoznji': {'sr': 'Cena po vožnji', 'en': 'Price per ride', 'ru': 'Цена за поездку', 'de': 'Preis pro Fahrt'},
    'cenaPoDanu': {'sr': 'Cena po danu', 'en': 'Price per day', 'ru': 'Цена за день', 'de': 'Preis pro Tag'},
    'operativnaNedelja': {
      'sr': 'Operativna nedelja',
      'en': 'Operating week',
      'ru': 'Рабочая неделя',
      'de': 'Betriebswoche'
    },
    'stanjeVoznji': {
      'sr': 'Stanje vožnji i naplate',
      'en': 'Ride and payment status',
      'ru': 'Состояние поездок и оплаты',
      'de': 'Status der Fahrten und Zahlungen',
    },
    'voznji': {'sr': 'Vožnji', 'en': 'Rides', 'ru': 'Поездок', 'de': 'Fahrten'},
    'otkazano': {'sr': 'Otkazano', 'en': 'Canceled', 'ru': 'Отменено', 'de': 'Storniert'},
    'placeno': {'sr': 'Plaćeno', 'en': 'Paid', 'ru': 'Оплачено', 'de': 'Bezahlt'},
    'dug': {'sr': 'Dug', 'en': 'Debt', 'ru': 'Долг', 'de': 'Schuld'},
    'ukupanDug': {'sr': 'Ukupan dug', 'en': 'Total debt', 'ru': 'Общий долг', 'de': 'Gesamtschuld'},
    'poslednjaUplata': {
      'sr': 'Poslednja uplata',
      'en': 'Last payment',
      'ru': 'Последний платеж',
      'de': 'Letzte Zahlung'
    },
    'modelCenaPoDanu': {
      'sr': 'Model: cena po danu (jedna cena za jednu ili vise voznji u toku dana).',
      'en': 'Model: price per day (one price for one or more rides per day).',
      'ru': 'Модель: цена за день (одна цена за одну или несколько поездок в течение дня).',
      'de': 'Modell: Preis pro Tag (ein Preis für eine oder mehrere Fahrten pro Tag).',
    },
    'modelCenaPoVoznji': {
      'sr': 'Model: cena po voznji (svaka voznja se naplaćuje).',
      'en': 'Model: price per ride (every ride is charged).',
      'ru': 'Модель: цена за поездку (каждая поездка оплачивается).',
      'de': 'Modell: Preis pro Fahrt (jede Fahrt wird berechnet).',
    },
    'detaljneStatistike': {
      'sr': 'Detaljne statistike',
      'en': 'Detailed statistics',
      'ru': 'Подробная статистика',
      'de': 'Detaillierte Statistiken'
    },
    'pregledPoMesecima': {
      'sr': 'Pregled po mesecima',
      'en': 'Monthly overview',
      'ru': 'Обзор по месяцам',
      'de': 'Monatsübersicht'
    },
    'otvoriDetaljneStatistike': {
      'sr': 'Otvori detaljne statistike',
      'en': 'Open detailed statistics',
      'ru': 'Открыть подробную статистику',
      'de': 'Detaillierte Statistiken öffnen',
    },
    'rasporedTermina': {'sr': '🕐 Raspored termina', 'en': '🕐 Schedule', 'ru': '🕐 Расписание', 'de': '🕐 Zeitplan'},
    'belaCrkva': {'sr': 'Bela Crkva', 'en': 'Bela Crkva', 'ru': 'Бела Црква', 'de': 'Bela Crkva'},
    'vrsac': {'sr': 'Vrsac', 'en': 'Vrsac', 'ru': 'Вршац', 'de': 'Vrsac'},
    'glavnaAdresa': {'sr': 'Glavna adresa', 'en': 'Main address', 'ru': 'Основной адрес', 'de': 'Hauptadresse'},
    'drugaAdresa': {'sr': 'Druga adresa', 'en': 'Second address', 'ru': 'Второй адрес', 'de': 'Zweite Adresse'},
    'primarnaAdresa': {
      'sr': 'Primarna adresa',
      'en': 'Primary address',
      'ru': 'Основной адрес',
      'de': 'Primäre Adresse'
    },
    'bcPolazak': {'sr': '🏙️ BC polazak', 'en': '🏙️ BC departure', 'ru': '🏙️ Отправление БC', 'de': '🏙️ BC Abfahrt'},
    'vsPolazak': {'sr': '🌆 VS polazak', 'en': '🌆 VS departure', 'ru': '🌆 Отправление VS', 'de': '🌆 VS Abfahrt'},
    'otkaziTermin': {
      'sr': 'Otkaži termin',
      'en': 'Cancel appointment',
      'ru': 'Отменить запись',
      'de': 'Termin stornieren'
    },
    'zatvori': {'sr': 'Zatvori', 'en': 'Close', 'ru': 'Закрыть', 'de': 'Schließen'},
    'odjavaTitle': {'sr': 'Odjava', 'en': 'Log out', 'ru': 'Выход', 'de': 'Abmelden'},
    'odjavaMessage': {
      'sr': 'Da li ste sigurni da želite da se odjavite?',
      'en': 'Are you sure you want to log out?',
      'ru': 'Вы уверены, что хотите выйти?',
      'de': 'Möchten Sie sich wirklich abmelden?',
    },
    'odjaviSe': {'sr': 'Odjavi se', 'en': 'Log out', 'ru': 'Выйти', 'de': 'Abmelden'},
    'otkaziBtn': {'sr': 'Otkaži', 'en': 'Cancel', 'ru': 'Отмена', 'de': 'Abbrechen'},
    'danas': {'sr': 'danas', 'en': 'today', 'ru': 'сегодня', 'de': 'heute'},
    'sutra': {'sr': 'sutra', 'en': 'tomorrow', 'ru': 'завтра', 'de': 'morgen'},
    'danPonedeljak': {'sr': 'Ponedeljak', 'en': 'Monday', 'ru': 'Понедельник', 'de': 'Montag'},
    'danUtorak': {'sr': 'Utorak', 'en': 'Tuesday', 'ru': 'Вторник', 'de': 'Dienstag'},
    'danSreda': {'sr': 'Sreda', 'en': 'Wednesday', 'ru': 'Среда', 'de': 'Mittwoch'},
    'danCetvrtak': {'sr': 'Četvrtak', 'en': 'Thursday', 'ru': 'Четверг', 'de': 'Donnerstag'},
    'danPetak': {'sr': 'Petak', 'en': 'Friday', 'ru': 'Пятница', 'de': 'Freitag'},
    'danSubota': {'sr': 'Subota', 'en': 'Saturday', 'ru': 'Суббота', 'de': 'Samstag'},
    'danNedelja': {'sr': 'Nedelja', 'en': 'Sunday', 'ru': 'Воскресенье', 'de': 'Sonntag'},
    'jezik': {'sr': 'Jezik', 'en': 'Language', 'ru': 'Язык', 'de': 'Sprache'},
  };

  String _tr(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    return _t[key]?[code] ?? _t[key]?['sr'] ?? key;
  }

  /// Prevodi puni srpski naziv dana (npr. 'Ponedeljak') u naziv na trenutnom jeziku, samo za prikaz.
  /// Interna logika (matchovanje rasporeda) i dalje koristi V3DanHelper.fullName na srpskom.
  String _trDanFullName(String srDanFullName) {
    const map = {
      'Ponedeljak': 'danPonedeljak',
      'Utorak': 'danUtorak',
      'Sreda': 'danSreda',
      'Cetvrtak': 'danCetvrtak',
      'Petak': 'danPetak',
      'Subota': 'danSubota',
      'Nedelja': 'danNedelja',
    };
    final key = map[srDanFullName];
    return key != null ? _tr(key) : srDanFullName;
  }

  String? _normalizeValidTime(String? value) {
    if (value == null) return null;
    final normalized = V3StringUtils.trimTimeToHhMm(value).trim();
    if (normalized.isEmpty) return null;
    if (!_timeFormat.hasMatch(normalized)) return null;
    return normalized;
  }

  String _formatNedeljaOpsegLabel() {
    final weekRange = V3DanHelper.schedulingWeekRange();
    final ponedeljak = weekRange.start;
    final petak = weekRange.end;
    final od = '${ponedeljak.day.toString().padLeft(2, '0')}.${ponedeljak.month.toString().padLeft(2, '0')}.';
    final doDatuma = '${petak.day.toString().padLeft(2, '0')}.${petak.month.toString().padLeft(2, '0')}.';
    return '$od - $doDatuma';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _putnikData = Map<String, dynamic>.from(widget.putnikData);
    _refresh();
    _refreshWeather(forceRefresh: true);
    _weatherTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      if (mounted) _refreshWeather();
    });
    // Pratimo promjene cache-a
    V3StreamUtils.subscribe<int>(
      key: 'putnik_profil_cache',
      stream: V3MasterRealtimeManager.instance.tablesRevisionStream(const [
        'v3_auth',
        'v3_zahtevi',
        'v3_operativna_nedelja',
        'v3_app_settings',
      ]),
      onData: (_) {
        if (mounted) _refresh();
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    V3StreamUtils.cancelSubscription('putnik_profil_cache');
    V3StreamUtils.cancelTimer(_actionDebounceKey);
    _weatherTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshWeather();
    }
  }

  Future<void> _refreshWeather({bool forceRefresh = false}) async {
    final snapshots = await V3WeatherService.fetchBcVs(forceRefresh: forceRefresh);
    if (!mounted || snapshots.isEmpty) return;
    V3StateUtils.safeSetState(this, () => _weatherByGrad = snapshots);
  }

  void _refresh() {
    final putnikId = _putnikData['id']?.toString();
    if (putnikId == null) return;
    // Osvježi putnik iz cache-a
    final cached = V3MasterRealtimeManager.instance.putniciCache[putnikId];
    if (cached != null) _putnikData = Map<String, dynamic>.from(cached);
    // Raspored po danima iz v3_operativna_nedelja kao jedinog izvora istine za READ
    final dani = V3DanHelper.workdayAbbrs.toList(); // pon-pet (radni dani)
    final anchor = V3DanHelper.schedulingWeekAnchor();
    final rm = V3MasterRealtimeManager.instance;
    final newMap = <String, List<_ZahtevInfo>>{};
    for (final dan in dani) {
      final datumIso = V3DanHelper.datumIsoZaDanAbbrUTekucojSedmici(dan, anchor: anchor);
      final infos = <_ZahtevInfo>[];

      for (final grad in const ['BC', 'VS']) {
        final opRows = rm.operativnaNedeljaCache.values.where((e) {
          return (e['created_by']?.toString() ?? '') == putnikId &&
              (e['datum'] as String? ?? '').startsWith(datumIso) &&
              (e['grad']?.toString().toUpperCase() ?? '') == grad;
        }).toList();

        final zahtevRows = rm.zahteviCache.values.where((z) {
          final status = V3StatusPolicy.normalizeStatus(z['status']?.toString());
          return (z['created_by']?.toString() ?? '') == putnikId &&
              (z['datum'] as String? ?? '').startsWith(datumIso) &&
              (z['grad']?.toString().toUpperCase() ?? '') == grad &&
              (V3StatusPolicy.isPending(status) || V3StatusPolicy.isOfferLike(status));
        }).toList();

        _ZahtevInfo? bestZahtevInfo;
        int bestZahtevPriority = -1;
        DateTime bestZahtevTs = DateTime.fromMillisecondsSinceEpoch(0);

        for (final zahtev in zahtevRows) {
          final status = V3StatusPolicy.normalizeStatus(zahtev['status']?.toString());
          final priority = V3StatusPolicy.displayPriority(status: status, pokupljen: false);
          final zahtevTs = DateTime.tryParse(zahtev['updated_at']?.toString() ?? '') ??
              DateTime.tryParse(zahtev['created_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);

          final trazeniVreme = _normalizeValidTime(zahtev['trazeni_polazak_at']?.toString()) ??
              _normalizeValidTime(zahtev['polazak_at']?.toString()) ??
              _normalizeValidTime(zahtev['alternativa_pre_at']?.toString()) ??
              _normalizeValidTime(zahtev['alternativa_posle_at']?.toString()) ??
              '—';

          final info = _ZahtevInfo(
            grad: grad,
            vreme: trazeniVreme,
            status: status,
            pokupljen: false,
            koristiSekundarnu: zahtev['koristi_sekundarnu'] as bool? ?? false,
          );

          if (priority > bestZahtevPriority || (priority == bestZahtevPriority && zahtevTs.isAfter(bestZahtevTs))) {
            bestZahtevInfo = info;
            bestZahtevPriority = priority;
            bestZahtevTs = zahtevTs;
          }
        }

        Map<String, dynamic>? selected;
        int selectedRank = -1;
        for (final row in opRows) {
          final status = V3StatusPolicy.normalizeStatus(
            V3StatusPolicy.deriveOperativnaStatus(
              otkazanoAt: row['otkazano_at'],
              polazakAt: row['polazak_at'],
            ),
          );
          final rank = V3StatusPolicy.displayPriority(
            status: status,
            pokupljen: V3StatusPolicy.isTimestampSet(row['pokupljen_at']),
          );
          if (rank > selectedRank) {
            selected = row;
            selectedRank = rank;
          }
        }

        _ZahtevInfo? bestOperativnaInfo;
        if (selected != null) {
          final status = V3StatusPolicy.normalizeStatus(
            V3StatusPolicy.deriveOperativnaStatus(
              otkazanoAt: selected['otkazano_at'],
              polazakAt: selected['polazak_at'],
            ),
          );
          final opPolazakAt = _normalizeValidTime(selected['polazak_at']?.toString());
          final displayVreme = opPolazakAt ?? '—';

          bestOperativnaInfo = _ZahtevInfo(
            grad: grad,
            vreme: displayVreme,
            status: status,
            pokupljen: V3StatusPolicy.isTimestampSet(selected['pokupljen_at']),
            koristiSekundarnu: selected['koristi_sekundarnu'] as bool? ?? false,
          );
        }

        if (bestOperativnaInfo == null && bestZahtevInfo == null) continue;

        if (bestOperativnaInfo == null) {
          infos.add(bestZahtevInfo!);
          continue;
        }

        if (bestZahtevInfo == null) {
          infos.add(bestOperativnaInfo);
          continue;
        }

        final operativnaPriority = V3StatusPolicy.displayPriority(
          status: bestOperativnaInfo.status,
          pokupljen: bestOperativnaInfo.pokupljen,
        );
        final zahtevPriority = V3StatusPolicy.displayPriority(
          status: bestZahtevInfo.status,
          pokupljen: bestZahtevInfo.pokupljen,
        );

        infos.add(zahtevPriority > operativnaPriority ? bestZahtevInfo : bestOperativnaInfo);
      }

      final bestByGrad = <String, _ZahtevInfo>{};
      for (final info in infos) {
        final current = bestByGrad[info.grad];
        final infoPriority = V3StatusPolicy.displayPriority(
          status: info.status,
          pokupljen: info.pokupljen,
        );
        final currentPriority = current == null
            ? -1
            : V3StatusPolicy.displayPriority(
                status: current.status,
                pokupljen: current.pokupljen,
              );
        if (current == null || infoPriority > currentPriority) {
          bestByGrad[info.grad] = info;
        }
      }
      newMap[dan] = bestByGrad.values.toList();
    }
    if (mounted) {
      setState(() {
        _rasporedMap
          ..clear()
          ..addAll(newMap);
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // TIME PICKER
  // ─────────────────────────────────────────────────────────────────
  /// Vraća datum za dati dan abbr u tekućoj sedmici.
  Future<void> _updatePolazak(String dan, String grad, String? novoVreme,
      {_ZahtevInfo? trenutniInfo, bool koristiSekundarnu = false}) async {
    final putnikId = _putnikData['id']?.toString();
    if (putnikId == null) return;

    // Debounce: ignoriši dvostruki klik u roku od 500 ms
    if (V3StreamUtils.isTimerActive(_actionDebounceKey)) return;
    V3StreamUtils.createTimer(
      key: _actionDebounceKey,
      duration: const Duration(milliseconds: 500),
      callback: () => V3StreamUtils.cancelTimer(_actionDebounceKey),
    );

    final validNovoVreme = _normalizeValidTime(novoVreme);
    final datumPolaska = V3DanHelper.datumZaDanAbbrUTekucojSedmici(
      dan,
      anchor: V3DanHelper.schedulingWeekAnchor(),
    );

    if (novoVreme != null && validNovoVreme == null) {
      if (mounted) V3AppSnackBar.warning(context, V3PutnikProfilMessages.invalidTermTime);
      return;
    }

    final tipPutnika = (_putnikData['tip_putnika'] as String? ?? '').toLowerCase();
    if (validNovoVreme != null && tipPutnika == 'dnevni' && !_isDnevniDatumAllowed(datumPolaska)) {
      final allowedLabel = _allowedDnevniDateLabel(grad: grad);
      if (mounted) {
        V3AppSnackBar.info(context, V3PutnikProfilMessages.dnevniDateWindowLocked(allowedLabel));
      }
      return;
    }

    try {
      if (validNovoVreme == null) {
        // Otkaži postojeći zahtev
        if (trenutniInfo == null) return;
        await V3ZahtevService.otkaziPolazakPutnikaPoKontekstu(
          putnikId: putnikId,
          datum: datumPolaska,
          grad: grad,
          otkazaoPutnikId: putnikId,
        );
        if (mounted) V3AppSnackBar.success(context, V3PutnikProfilMessages.tripCanceled(dan, grad));
      } else {
        // Sačuvaj izmenu po kontekstu (putnik + dan + grad)
        await V3ZahtevService.sacuvajPolazakPutnikaPoKontekstu(
          putnikId: putnikId,
          datum: datumPolaska,
          grad: grad,
          novoVreme: validNovoVreme,
          koristiSekundarnu: koristiSekundarnu,
          updatedBy: V3UuidUtils.normalizeUuid(putnikId),
        );
        if (mounted) {
          V3AppSnackBar.success(context, V3PutnikProfilMessages.requestReceived);
        }
      }
    } catch (e) {
      V3ErrorUtils.asyncError(this, context, e);
    }
  }

  Future<void> _showTimePicker(BuildContext ctx, String dan, String grad, _ZahtevInfo? info) async {
    final tipPutnika = (_putnikData['tip_putnika'] as String? ?? '').toLowerCase();
    final datumPolaska = V3DanHelper.datumZaDanAbbrUTekucojSedmici(
      dan,
      anchor: V3DanHelper.schedulingWeekAnchor(),
    );

    if (tipPutnika == 'dnevni' && !_isDnevniDatumAllowed(datumPolaska)) {
      final allowedLabel = _allowedDnevniDateLabel(grad: grad);
      if (mounted) {
        V3AppSnackBar.info(ctx, V3PutnikProfilMessages.dnevniDateWindowLocked(allowedLabel));
      }
      return;
    }

    // Scenario 2: zahtev u obradi — blokirati sve akcije
    if (V3StatusPolicy.isPending(info?.status)) {
      if (mounted) V3AppSnackBar.info(ctx, V3PutnikProfilMessages.requestPendingDispatcher);
      return;
    }
    // Scenario 6: putnik je već pokupljen — ne može da otkazuje
    if (V3StatusPolicy.isActionLocked(status: info?.status, pokupljen: info?.pokupljen ?? false)) {
      if (mounted) V3AppSnackBar.info(ctx, V3PutnikProfilMessages.alreadyPickedUp);
      return;
    }
    // Scenario 5: zaključavanje 15 min pre polaska
    final datumIso = V3DanHelper.toIsoDate(datumPolaska);
    final neradanRazlog = getNeradanDanRazlog(datumIso: datumIso, grad: grad.toLowerCase());
    if (neradanRazlog != null) {
      if (mounted) {
        V3AppSnackBar.info(ctx, V3PutnikProfilMessages.nonWorkingDay(datumIso, neradanRazlog));
      }
      return;
    }

    final now = DateTime.now();
    final dayFullName = V3DanHelper.fullName(datumPolaska);
    final vremena = getRasporedVremena(grad.toLowerCase(), navBarTypeNotifier.value, day: dayFullName)
        .where((v) => _normalizeValidTime(v) != null)
        .toList();
    final currentVreme = info?.vreme;
    final hasActive =
        info != null && !V3StatusPolicy.isCanceledOrRejected(info.status) && !V3StatusPolicy.isOfferLike(info.status);
    // Provera da li putnik ima drugu adresu za ovaj grad
    final putnikId = _putnikData['id']?.toString();
    final putnikCache = V3MasterRealtimeManager.instance.putniciCache[putnikId];
    final hasSecondary =
        grad == 'BC' ? (putnikCache?['adresa_bc_id_2'] != null) : (putnikCache?['adresa_vs_id_2'] != null);
    String? secondaryId;
    if (grad == 'BC') {
      secondaryId = putnikCache?['adresa_bc_id_2'] as String?;
    } else {
      secondaryId = putnikCache?['adresa_vs_id_2'] as String?;
    }
    final secondaryNaziv = V3AdresaService.getAdresaById(secondaryId)?.naziv ?? _tr('drugaAdresa');
    bool koristiSekundarnu = info?.koristiSekundarnu ?? false;
    await V3DialogHelper.showDialogBuilder<void>(
      context: ctx,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          child: SizedBox.expand(
            child: V3ContainerUtils.gradientContainer(
              gradient: V3ThemeManager().currentGradient,
              borderRadius: BorderRadius.zero,
              child: SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Title
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Column(
                          children: [
                            Text(
                              grad == 'BC' ? _tr('bcPolazak') : _tr('vsPolazak'),
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _getDanLabel(dan),
                              style: TextStyle(color: V3StyleHelper.whiteAlpha5, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const Divider(color: Colors.white12, height: 1),
                      // Address Selector (Prikazuje se samo ako postoji druga adresa)
                      if (hasSecondary)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                          child: InkWell(
                            onTap: () => setDialogState(() => koristiSekundarnu = !koristiSekundarnu),
                            borderRadius: BorderRadius.circular(8),
                            child: V3ContainerUtils.styledContainer(
                              padding: const EdgeInsets.all(10),
                              backgroundColor: V3StyleHelper.whiteAlpha05,
                              border: Border.all(
                                color: Colors.white12,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              child: Row(
                                children: [
                                  Icon(
                                    koristiSekundarnu ? Icons.location_on : Icons.location_on_outlined,
                                    color: Colors.white54,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          koristiSekundarnu ? _tr('drugaAdresa') : _tr('primarnaAdresa'),
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                          ),
                                        ),
                                        Text(
                                          koristiSekundarnu
                                              ? secondaryNaziv
                                              : (grad == 'BC'
                                                  ? (V3AdresaService.getAdresaById(
                                                              putnikCache?['adresa_bc_id'] as String?)
                                                          ?.naziv ??
                                                      _tr('glavnaAdresa'))
                                                  : (V3AdresaService.getAdresaById(
                                                              putnikCache?['adresa_vs_id'] as String?)
                                                          ?.naziv ??
                                                      _tr('glavnaAdresa'))),
                                          style: TextStyle(
                                            color: koristiSekundarnu ? Colors.greenAccent : Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: koristiSekundarnu,
                                    onChanged: (val) => setDialogState(() => koristiSekundarnu = val),
                                    activeColor: Colors.orange,
                                    activeTrackColor: Colors.orange.withValues(alpha: 0.3),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      // Grid vremena
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Otkaži dugme
                            if (hasActive)
                              SizedBox(
                                width: double.infinity,
                                child: V3ButtonUtils.outlinedButton(
                                  onPressed: () async {
                                    Navigator.of(dialogCtx).pop();
                                    await _updatePolazak(dan, grad, null, trenutniInfo: info);
                                  },
                                  text: _tr('otkaziTermin'),
                                  icon: Icons.cancel_outlined,
                                  borderColor: Colors.redAccent,
                                  foregroundColor: Colors.redAccent,
                                  fontSize: 14,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            if (hasActive) const SizedBox(height: 10),
                            if (hasActive) const Divider(color: Colors.white24, height: 1),
                            if (hasActive) const SizedBox(height: 10),
                            // Grid 2 kolone
                            GridView.count(
                              crossAxisCount: 2,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: 3.2,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              children: vremena.map((vreme) {
                                final isSelected =
                                    currentVreme != null && V3StringUtils.trimTimeToHhMm(currentVreme) == vreme;
                                // Scenario 5: zaključaj dugme 15 min pre polaska
                                final parts = vreme.split(':');
                                final polazak = DateTime(
                                  datumPolaska.year,
                                  datumPolaska.month,
                                  datumPolaska.day,
                                  int.parse(parts[0]),
                                  int.parse(parts[1]),
                                );
                                final isLocked = now.isAfter(polazak.subtract(const Duration(minutes: 15)));
                                return OutlinedButton(
                                  onPressed: isLocked
                                      ? () async {
                                          Navigator.of(dialogCtx).pop();
                                          final unlockAt = V3DanHelper.nextSchedulingUnlock(now: now);
                                          final unlockStr =
                                              '${unlockAt.day}.${unlockAt.month}.${unlockAt.year}. ${unlockAt.hour.toString().padLeft(2, '0')}:${unlockAt.minute.toString().padLeft(2, '0')}';
                                          await Future<void>.delayed(const Duration(milliseconds: 120));
                                          if (!mounted) return;
                                          V3AppSnackBar.info(
                                              ctx, V3PutnikProfilMessages.schedulingLocked(vreme, unlockStr));
                                        }
                                      : () async {
                                          Navigator.of(dialogCtx).pop();
                                          await _updatePolazak(dan, grad, vreme,
                                              trenutniInfo: info, koristiSekundarnu: koristiSekundarnu);
                                        },
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: isLocked
                                        ? V3StyleHelper.whiteAlpha05
                                        : isSelected
                                            ? Colors.green.withValues(alpha: 0.45)
                                            : V3StyleHelper.whiteAlpha15,
                                    side: BorderSide(
                                      color: isLocked
                                          ? Colors.white12
                                          : isSelected
                                              ? Colors.greenAccent
                                              : Colors.white60,
                                      width: isSelected ? 2.5 : 1.5,
                                    ),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: EdgeInsets.symmetric(vertical: isSelected ? 4 : 10),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isSelected)
                                        const Icon(Icons.check_circle, color: Colors.greenAccent, size: 12),
                                      Text(
                                        vreme,
                                        style: TextStyle(
                                          color: isLocked ? Colors.white24 : Colors.white,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      // Zatvori
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: V3ButtonUtils.textButton(
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                          text: _tr('zatvori'),
                          foregroundColor: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _isDnevniDatumAllowed(DateTime datumPolaska, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final today = DateTime(current.year, current.month, current.day);
    final tomorrow = today.add(const Duration(days: 1));
    final target = DateTime(datumPolaska.year, datumPolaska.month, datumPolaska.day);

    if (current.hour < 16) {
      return target == today;
    }
    return target == tomorrow;
  }

  bool _isWorkingDateForGrad(DateTime date, String grad) {
    if (date.weekday < DateTime.monday || date.weekday > DateTime.friday) {
      return false;
    }
    final datumIso = V3DanHelper.toIsoDate(date);
    return getNeradanDanRazlog(datumIso: datumIso, grad: grad.toLowerCase()) == null;
  }

  DateTime _nextWorkingDateForGrad(DateTime startDate, String grad) {
    var candidate = DateTime(startDate.year, startDate.month, startDate.day);
    for (var i = 0; i < 14; i++) {
      if (_isWorkingDateForGrad(candidate, grad)) {
        return candidate;
      }
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  String _allowedDnevniDateLabel({DateTime? now, required String grad}) {
    final current = now ?? DateTime.now();
    final today = DateTime(current.year, current.month, current.day);
    final baseDate = current.hour < 16 ? today : today.add(const Duration(days: 1));
    final allowedDate = _nextWorkingDateForGrad(baseDate, grad);
    final tomorrow = today.add(const Duration(days: 1));
    final dateLabel = V3DanHelper.formatDatumPuni(allowedDate);

    if (allowedDate == today) {
      return '${_tr('danas')} ($dateLabel)';
    }
    if (allowedDate == tomorrow) {
      return '${_tr('sutra')} ($dateLabel)';
    }

    return '${_trDanFullName(V3DanHelper.fullName(allowedDate))}, $dateLabel';
  }

  /// Helper za konverziju kratice dana u puni naziv koristeći V3DanHelper.
  String _getDanLabel(String danAbbr) {
    try {
      final datum = V3DanHelper.datumZaDanAbbrUTekucojSedmici(
        danAbbr,
        anchor: V3DanHelper.schedulingWeekAnchor(),
      );
      return _trDanFullName(V3DanHelper.fullName(datum));
    } catch (e) {
      // Fallback ako kratica nije validna
      return danAbbr;
    }
  }

  Widget _buildLanguageFlag() {
    return ValueListenableBuilder<Locale>(
      valueListenable: V3LocaleManager().localeNotifier,
      builder: (context, locale, _) {
        final code = locale.languageCode;
        final currentFlag = code == 'en'
            ? '🇬🇧'
            : code == 'ru'
                ? '🇷🇺'
                : code == 'de'
                    ? '🇩🇪'
                    : '🇷🇸';
        return PopupMenuButton<String>(
          tooltip: _tr('jezik'),
          offset: const Offset(0, 44),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: Colors.black.withValues(alpha: 0.85),
          onSelected: (newCode) => V3LocaleManager().changeLocale(Locale(newCode)),
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              value: 'sr',
              child: Row(
                children: [
                  const Text('🇷🇸', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Text(
                    'Srpski',
                    style: TextStyle(color: Colors.white.withValues(alpha: code == 'sr' ? 1 : 0.6)),
                  ),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'en',
              child: Row(
                children: [
                  const Text('🇬🇧', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Text(
                    'English',
                    style: TextStyle(color: Colors.white.withValues(alpha: code == 'en' ? 1 : 0.6)),
                  ),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'ru',
              child: Row(
                children: [
                  const Text('🇷🇺', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Text(
                    'Русский',
                    style: TextStyle(color: Colors.white.withValues(alpha: code == 'ru' ? 1 : 0.6)),
                  ),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'de',
              child: Row(
                children: [
                  const Text('🇩🇪', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Text(
                    'Deutsch',
                    style: TextStyle(color: Colors.white.withValues(alpha: code == 'de' ? 1 : 0.6)),
                  ),
                ],
              ),
            ),
          ],
          child: Text(currentFlag, style: const TextStyle(fontSize: 18)),
        );
      },
    );
  }

  Future<void> _logout() async {
    final ok = await V3DialogHelper.showConfirmDialog(
      context,
      title: _tr('odjavaTitle'),
      message: _tr('odjavaMessage'),
      confirmText: _tr('odjaviSe'),
      cancelText: _tr('otkaziBtn'),
      isDangerous: true,
    );
    if (ok != true || !mounted) return;
    // Otkaži stream subscription pre brisanja sesije
    V3StreamUtils.cancelSubscription('putnik_profil_cache');
    // Obrisi sesiju i kredencijale
    V3PutnikService.currentPutnik = null;

    final phoneRaw = (_putnikData['telefon_1'] ?? _putnikData['telefon'] ?? '').toString();
    final normalizedPhone = V3ClosedAuthService.normalizePhone(phoneRaw);
    if (normalizedPhone.isNotEmpty) {
      await _secureStorage.delete(key: '$_biometricPromptChoicePrefix$normalizedPhone');
    }

    // Oslobodi uređaj slot u bazi pre brisanja lokalne sesije
    final putnikId = (_putnikData['id'] ?? '').toString().trim();
    if (putnikId.isNotEmpty) {
      final deviceId = await V3DeviceIdentityService.getStableDeviceId();
      await V3PushTokenEdgeService.releaseDeviceSlot(
        v3AuthId: putnikId,
        installationId: deviceId,
      );
    }

    await V3BiometricService().clearCredentials();
    await V3ClosedAuthService.clearManualSmsPutnikPhone();
    await V3ClosedAuthService.clearManualSmsVozacPhone();
    if (!mounted) return;
    V3AppSnackBar.success(context, V3PutnikProfilMessages.logoutSuccess);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const V3WelcomeScreen()),
      (r) => false,
    );
  }

  Future<void> _showEditProfilDialog() async {
    await V3DialogHelper.showDialogBuilder<void>(
      context: context,
      builder: (ctx) => _EditProfilDialog(
        putnikData: _putnikData,
        onSaved: (updated) {
          V3StateUtils.safeSetState(this, () => _putnikData = updated);
        },
      ),
    );
  }

  // _showAlternativaDialog obrisan jer alternativa ide samo preko push notifikacije.
  // ─── STATUS WIDGET ───────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final putnikId = _putnikData['id']?.toString();
    final tip = _putnikData['tip_putnika'] as String? ?? 'radnik';
    final cenaPoDanu = (_putnikData['cena_po_danu'] as num?)?.toDouble() ?? 0.0;
    final cenaPoPokupljenju = (_putnikData['cena_po_pokupljenju'] as num?)?.toDouble() ?? 0.0;
    final koristiCenuPoPokupljenju = tip == 'dnevni' || tip == 'posiljka';
    final efektivnaCena = koristiCenuPoPokupljenju ? cenaPoPokupljenju : cenaPoDanu;
    final cenaInfo = efektivnaCena > 0
        ? '${koristiCenuPoPokupljenju ? _tr('cenaPoVoznji') : _tr('cenaPoDanu')}: ${efektivnaCena.toStringAsFixed(0)} RSD'
        : null;
    final imePrezime = _putnikData['ime_prezime'] as String? ?? '';
    final telefon = _putnikData['telefon_1'] as String? ?? '';
    final telefon2 = _putnikData['telefon_2'] as String? ?? '';
    final adresaBcId = _putnikData['adresa_bc_id'] as String?;
    final adresaVsId = _putnikData['adresa_vs_id'] as String?;
    final adresaBcId2 = _putnikData['adresa_bc_id_2'] as String?;
    final adresaVsId2 = _putnikData['adresa_vs_id_2'] as String?;
    final adresaBcNaziv = V3AdresaService.getNazivAdreseById(adresaBcId);
    final adresaVsNaziv = V3AdresaService.getNazivAdreseById(adresaVsId);
    final adresaBcNaziv2 = V3AdresaService.getNazivAdreseById(adresaBcId2);
    final adresaVsNaziv2 = V3AdresaService.getNazivAdreseById(adresaVsId2);
    final stats = V3PutnikStatistikaService.getTekuciMesec(putnikId ?? '');
    final ukupanDug = V3PutnikStatistikaService.getUkupanDugZaSveMesece(putnikId ?? '');
    final nedeljaOpseg = _formatNedeljaOpsegLabel();
    final nedeljaInfo = '${_tr('operativnaNedelja')}: $nedeljaOpseg';
    return ValueListenableBuilder<Locale>(
      valueListenable: V3LocaleManager().localeNotifier,
      builder: (context, __, ___) => ValueListenableBuilder<ThemeData>(
        valueListenable: V3ThemeManager().themeNotifier,
        builder: (context, _, __) => V3ContainerUtils.backgroundContainer(
          gradient: V3ThemeManager().currentGradient,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: Stack(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Forced update gate
                        const V3UpdateBanner(),
                        // ── HEADER CARD ──────────────────────────────────────
                        _buildHeaderCard(
                          tip: tip,
                          imePrezime: imePrezime,
                          telefon: telefon,
                          telefon2: telefon2,
                          adresaBcNaziv: adresaBcNaziv,
                          adresaVsNaziv: adresaVsNaziv,
                          adresaBcNaziv2: adresaBcNaziv2,
                          adresaVsNaziv2: adresaVsNaziv2,
                        ),
                        if (putnikId != null && putnikId.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          V3VremeDolaskaWidget(putnikId: putnikId),
                        ],
                        const SizedBox(height: 16),
                        _buildStatistikaCard(
                          tip: tip,
                          stats: stats,
                          cenaInfo: cenaInfo,
                          ukupanDug: ukupanDug,
                        ),
                        const SizedBox(height: 10),
                        _buildDetaljneStatistikeSection(
                          putnikId: putnikId,
                          imePrezime: imePrezime,
                          tipPutnika: tip,
                        ),
                        const SizedBox(height: 16),
                        // ── RASPORED TERMINA ─────────────────────────────────
                        _buildRasporedCard(nedeljaInfo: nedeljaInfo),
                        const SizedBox(height: 16),
                        // ── UPUTSTVO ZA KORIŠĆENJE ───────────────────────────
                        GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const V3HelpScreen()),
                          ),
                          child: V3ContainerUtils.styledContainer(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            backgroundColor: V3StyleHelper.whiteAlpha06,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: V3StyleHelper.whiteAlpha13),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.help_outline, color: Colors.white70, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  _tr('uputstvo'),
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 16,
                    right: 16,
                    child: const V3InfoBanner(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // WIDGETS
  // ─────────────────────────────────────────────────────────────────
  Widget _buildHeaderCard({
    required String tip,
    required String imePrezime,
    required String telefon,
    String telefon2 = '',
    required String? adresaBcNaziv,
    required String? adresaVsNaziv,
    String? adresaBcNaziv2,
    String? adresaVsNaziv2,
  }) {
    final avatarColors = _avatarColors(tip);
    final tipLabel = _tipLabel(tip);
    return V3ContainerUtils.styledContainer(
      padding: const EdgeInsets.all(20),
      backgroundColor: V3StyleHelper.whiteAlpha06,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: V3StyleHelper.whiteAlpha13),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Text('🎨', style: TextStyle(fontSize: 18)),
                tooltip: _tr('tema'),
                onPressed: () async {
                  await V3ThemeManager().nextTheme();
                  V3StateUtils.safeSetState(this, () {});
                  if (!mounted) return;
                  V3AppSnackBar.info(context, V3PutnikProfilMessages.themeChanged);
                },
              ),
              const Spacer(),
              _buildLanguageFlag(),
              const Spacer(),
              IconButton(
                icon: const Text('✏️', style: TextStyle(fontSize: 18)),
                tooltip: _tr('izmeniProfil'),
                onPressed: _showEditProfilDialog,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.red),
                tooltip: _tr('odjava'),
                onPressed: _logout,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _WeatherMiniCell(snapshot: _weatherByGrad['BC'], grad: 'BC'),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _WeatherMiniCell(snapshot: _weatherByGrad['VS'], grad: 'VS'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  imePrezime,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (telefon.isNotEmpty || telefon2.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.phone, color: Colors.white54, size: 13),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    [if (telefon.isNotEmpty) telefon, if (telefon2.isNotEmpty) telefon2].join('  •  '),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: V3StyleHelper.whiteAlpha9,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          // Adrese
          if (adresaBcNaziv != null || adresaVsNaziv != null) ...[
            const SizedBox(height: 12),
            Divider(color: V3StyleHelper.whiteAlpha15),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // BC kolona
                if (adresaBcNaziv != null && adresaBcNaziv.isNotEmpty)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.location_city, color: Colors.white38, size: 12),
                          const SizedBox(width: 4),
                          Text(_tr('belaCrkva'),
                              style: TextStyle(
                                  color: V3StyleHelper.whiteAlpha45, fontSize: 14, fontWeight: FontWeight.bold)),
                        ]),
                        const SizedBox(height: 3),
                        Row(children: [
                          const Icon(Icons.home, color: Colors.white60, size: 14),
                          const SizedBox(width: 4),
                          Expanded(
                              child: Text(adresaBcNaziv,
                                  style: TextStyle(color: V3StyleHelper.whiteAlpha9, fontSize: 14),
                                  overflow: TextOverflow.ellipsis)),
                        ]),
                        if (adresaBcNaziv2 != null && adresaBcNaziv2.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.home_outlined, color: Colors.white60, size: 14),
                            const SizedBox(width: 4),
                            Expanded(
                                child: Text(adresaBcNaziv2,
                                    style: TextStyle(color: V3StyleHelper.whiteAlpha9, fontSize: 14),
                                    overflow: TextOverflow.ellipsis)),
                          ]),
                        ],
                      ],
                    ),
                  ),
                if (adresaBcNaziv != null && adresaVsNaziv != null)
                  Container(
                      width: 1,
                      height: V3ContainerUtils.responsiveHeight(context, 40),
                      color: Colors.white12,
                      margin: const EdgeInsets.symmetric(horizontal: 10)),
                // VS kolona
                if (adresaVsNaziv != null && adresaVsNaziv.isNotEmpty)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.location_city, color: Colors.white38, size: 12),
                          const SizedBox(width: 4),
                          Text(_tr('vrsac'),
                              style: TextStyle(
                                  color: V3StyleHelper.whiteAlpha45, fontSize: 14, fontWeight: FontWeight.bold)),
                        ]),
                        const SizedBox(height: 3),
                        Row(children: [
                          const Icon(Icons.work, color: Colors.white60, size: 14),
                          const SizedBox(width: 4),
                          Expanded(
                              child: Text(adresaVsNaziv,
                                  style: TextStyle(color: V3StyleHelper.whiteAlpha9, fontSize: 14),
                                  overflow: TextOverflow.ellipsis)),
                        ]),
                        if (adresaVsNaziv2 != null && adresaVsNaziv2.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.work_outline, color: Colors.white60, size: 14),
                            const SizedBox(width: 4),
                            Expanded(
                                child: Text(adresaVsNaziv2,
                                    style: TextStyle(color: V3StyleHelper.whiteAlpha9, fontSize: 14),
                                    overflow: TextOverflow.ellipsis)),
                          ]),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatistikaCard({
    required String tip,
    required V3PutnikMesecnaStatistika stats,
    String? cenaInfo,
    required double ukupanDug,
  }) {
    return V3ContainerUtils.styledContainer(
      padding: const EdgeInsets.all(16),
      backgroundColor: V3StyleHelper.whiteAlpha06,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: V3StyleHelper.whiteAlpha13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              stats.mesecNaziv,
              style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              _tr('stanjeVoznji'),
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          if (cenaInfo != null) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                cenaInfo,
                textAlign: TextAlign.center,
                style: TextStyle(color: V3StyleHelper.whiteAlpha9, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            _modelNaplataLabel(tip),
            style: TextStyle(color: V3StyleHelper.whiteAlpha65, fontSize: 12, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _kpiTile(_tr('voznji'), '${stats.ukupnoVoznji}', Colors.greenAccent),
                const SizedBox(width: 12),
                _kpiTile(_tr('otkazano'), '${stats.otkazano}', Colors.redAccent),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Divider(color: V3StyleHelper.whiteAlpha15),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_tr('placeno'), style: TextStyle(color: V3StyleHelper.whiteAlpha75, fontSize: 13)),
              Text(
                '${stats.naplacenoIznos.toStringAsFixed(0)} RSD',
                style: const TextStyle(color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_tr('dug'), style: TextStyle(color: V3StyleHelper.whiteAlpha75, fontSize: 13)),
              Text(
                '${stats.dugIznos.toStringAsFixed(0)} RSD',
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_tr('ukupanDug'), style: TextStyle(color: V3StyleHelper.whiteAlpha75, fontSize: 13)),
              Text(
                '${ukupanDug.toStringAsFixed(0)} RSD',
                style: const TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (stats.poslednjaUplata != null) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_tr('poslednjaUplata'), style: TextStyle(color: V3StyleHelper.whiteAlpha75, fontSize: 13)),
                Text(
                  '${stats.poslednjaUplata!.day.toString().padLeft(2, '0')}.${stats.poslednjaUplata!.month.toString().padLeft(2, '0')}.',
                  style: const TextStyle(color: Colors.blueAccent, fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
          if (stats.otkazano > 0) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_tr('otkazano'), style: TextStyle(color: V3StyleHelper.whiteAlpha75, fontSize: 13)),
                Text(
                  '${stats.otkazano}',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _kpiTile(String label, String value, Color color) {
    return V3ContainerUtils.styledContainer(
      width: 90,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      backgroundColor: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      child: Column(
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(color: V3StyleHelper.whiteAlpha65, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  String _modelNaplataLabel(String tip) {
    final normalized = tip.toLowerCase();
    if (normalized == 'radnik' || normalized == 'ucenik') {
      return _tr('modelCenaPoDanu');
    }
    return _tr('modelCenaPoVoznji');
  }

  Widget _buildDetaljneStatistikeSection({
    required String? putnikId,
    required String imePrezime,
    required String tipPutnika,
  }) {
    return V3ContainerUtils.styledContainer(
      padding: const EdgeInsets.all(12),
      backgroundColor: V3StyleHelper.whiteAlpha06,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: V3StyleHelper.whiteAlpha13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _tr('detaljneStatistike'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            _tr('pregledPoMesecima'),
            textAlign: TextAlign.center,
            style: TextStyle(color: V3StyleHelper.whiteAlpha65, fontSize: 12),
          ),
          const SizedBox(height: 10),
          V3ButtonUtils.outlinedButton(
            onPressed: (putnikId == null || putnikId.isEmpty)
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => V3PutnikStatistikaScreen(
                          putnikId: putnikId,
                          imePrezime: imePrezime,
                          tipPutnika: tipPutnika,
                        ),
                      ),
                    );
                  },
            text: _tr('otvoriDetaljneStatistike'),
            icon: Icons.analytics_outlined,
            borderColor: Colors.white30,
            foregroundColor: Colors.white,
            borderRadius: BorderRadius.circular(10),
            fontSize: 13,
          ),
        ],
      ),
    );
  }

  Widget _buildRasporedCard({required String nedeljaInfo}) {
    final dani = V3DanHelper.workdayAbbrs.toList(); // pon-pet (radni dani)
    return V3ContainerUtils.styledContainer(
      padding: const EdgeInsets.all(16),
      backgroundColor: V3StyleHelper.whiteAlpha06,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: V3StyleHelper.whiteAlpha13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              nedeljaInfo,
              style: TextStyle(
                color: V3StyleHelper.whiteAlpha75,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              _tr('rasporedTermina'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Header
          Row(
            children: [
              const SizedBox(width: 96),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'BC',
                        style: TextStyle(
                          color: V3StyleHelper.whiteAlpha65,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '(${_tr('belaCrkva')})',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'VS',
                        style: TextStyle(
                          color: V3StyleHelper.whiteAlpha65,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '(${_tr('vrsac')})',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: V3StyleHelper.whiteAlpha1),
          ...dani.map((dan) {
            final infos = _rasporedMap[dan] ?? [];
            final bcInfo = infos.where((i) => i.grad == 'BC').firstOrNull;
            final vsInfo = infos.where((i) => i.grad == 'VS').firstOrNull;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      _getDanLabel(dan),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: _ZahtevCell(
                        info: bcInfo,
                        onTap: () => _showTimePicker(context, dan, 'BC', bcInfo),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: _ZahtevCell(
                        info: vsInfo,
                        onTap: () => _showTimePicker(context, dan, 'VS', vsInfo),
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

  // ─────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────
  List<Color> _avatarColors(String tip) {
    switch (tip.toLowerCase()) {
      case 'ucenik':
        return [Colors.blue.shade400, Colors.indigo.shade600];
      case 'posiljka':
        return [Colors.purple.shade400, Colors.deepPurple.shade600];
      case 'dnevni':
        return [Colors.green.shade400, Colors.teal.shade600];
      default:
        return [Colors.orange.shade400, Colors.deepOrange.shade600];
    }
  }

  String _tipLabel(String tip) {
    switch (tip.toLowerCase()) {
      case 'ucenik':
        return _tr('tipUcenik');
      case 'posiljka':
        return _tr('tipPosiljka');
      case 'dnevni':
        return _tr('tipDnevni');
      case 'radnik':
        return _tr('tipRadnik');
      default:
        return _tr('tipPutnik');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────
// Helper data class
// ─────────────────────────────────────────────────────────────────────
class _ZahtevInfo {
  final String grad;
  final String vreme;
  final String status;
  final bool pokupljen;
  final bool koristiSekundarnu;
  const _ZahtevInfo({
    required this.grad,
    required this.vreme,
    required this.status,
    this.pokupljen = false,
    this.koristiSekundarnu = false,
  });
}

// ─────────────────────────────────────────────────────────────────────
// Small widgets
// ─────────────────────────────────────────────────────────────────────
class _WeatherMiniCell extends StatelessWidget {
  final V3WeatherSnapshot? snapshot;
  final String grad;

  const _WeatherMiniCell({required this.snapshot, required this.grad});

  @override
  Widget build(BuildContext context) {
    final data = snapshot;
    final labelStyle = TextStyle(
      color: V3StyleHelper.whiteAlpha5,
      fontSize: 18,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
    );

    if (data == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(grad, style: labelStyle),
          const SizedBox(width: 4),
          Text(
            '—',
            style: TextStyle(
              color: V3StyleHelper.whiteAlpha5,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    final temp = '${data.temperatureC.round()}°';
    final rain = data.precipitationProbability != null ? ' · ${data.precipitationProbability}%' : '';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(grad, style: labelStyle),
        const SizedBox(width: 4),
        Text(
          data.icon,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$temp$rain',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ZahtevCell extends StatelessWidget {
  final _ZahtevInfo? info;
  final VoidCallback? onTap;
  const _ZahtevCell({this.info, this.onTap});
  @override
  Widget build(BuildContext context) {
    if (info == null) {
      return GestureDetector(
        onTap: onTap,
        child: V3ContainerUtils.styledContainer(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          backgroundColor: V3StyleHelper.whiteAlpha25,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: V3StyleHelper.whiteAlpha5),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(
                child: Text(
                  _trProfileDialog('dodaj'),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final badgeStyle = V3StatusPolicy.badgeForCell(
      status: info!.status,
      pokupljen: info!.pokupljen,
    );
    final statusColor = badgeStyle.color;
    final statusIcon = badgeStyle.icon;
    final vreme = V3StringUtils.trimTimeToHhMm(info!.vreme);
    final statusPrefix = '$statusIcon ';
    return GestureDetector(
      onTap: onTap,
      child: V3ContainerUtils.styledContainer(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        backgroundColor: statusColor.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.90),
          width: 1.2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
              child: Text(
                '$statusPrefix$vreme',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: V3StyleHelper.whiteAlpha9,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── EDIT PROFIL DIALOG ─────────────────────────────────────────────────────
class _EditProfilDialog extends StatefulWidget {
  final Map<String, dynamic> putnikData;
  final ValueChanged<Map<String, dynamic>> onSaved;

  const _EditProfilDialog({required this.putnikData, required this.onSaved});

  @override
  State<_EditProfilDialog> createState() => _EditProfilDialogState();
}

class _EditProfilDialogState extends State<_EditProfilDialog> {
  late final TextEditingController _ime = TextEditingController(
    text: widget.putnikData['ime_prezime']?.toString() ?? '',
  );
  late final TextEditingController _tel1 = TextEditingController(
    text: widget.putnikData['telefon_1']?.toString() ?? '',
  );
  late final TextEditingController _tel2 = TextEditingController(
    text: widget.putnikData['telefon_2']?.toString() ?? '',
  );

  bool _saving = false;

  @override
  void dispose() {
    _ime.dispose();
    _tel1.dispose();
    _tel2.dispose();
    super.dispose();
  }

  Future<void> _sacuvaj() async {
    final imeVal = _ime.text.trim();
    final tel1Val = V3PhoneUtils.normalizeOrNull(_tel1.text);
    final tel2Val = V3PhoneUtils.normalizeOrNull(_tel2.text);

    if (imeVal.isEmpty) {
      V3AppSnackBar.error(context, _trProfileDialog('imeNeSmeBitiPrazno'));
      return;
    }

    V3StateUtils.safeSetState(this, () => _saving = true);
    try {
      final updated = Map<String, dynamic>.from(widget.putnikData)
        ..['ime_prezime'] = imeVal
        ..['telefon_1'] = tel1Val
        ..['telefon_2'] = tel2Val;

      final putnik = V3Putnik.fromJson(updated);
      await V3PutnikService.addUpdatePutnik(
        putnik,
        updatedBy: putnik.id,
      );

      if (!mounted) return;
      V3AppSnackBar.success(context, _trProfileDialog('profilSacuvan'));
      widget.onSaved(updated);
      Navigator.pop(context);
    } catch (e) {
      V3AppSnackBar.error(context, '${_trProfileDialog('greska')}: $e');
    } finally {
      V3StateUtils.safeSetState(this, () => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gradient = theme.backgroundGradient;

    return Dialog(
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: BoxDecoration(gradient: gradient),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.18),
                  border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.edit_note_rounded, color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _trProfileDialog('izmeniProfilTitle'),
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            _trProfileDialog('azurirajImeTel'),
                            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      V3InputUtils.textField(
                        controller: _ime,
                        label: _trProfileDialog('imePrezime'),
                        icon: Icons.person_outline,
                        keyboardType: TextInputType.name,
                      ),
                      const SizedBox(height: 12),
                      V3InputUtils.textField(
                        controller: _tel1,
                        label: _trProfileDialog('telefon1'),
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      V3InputUtils.textField(
                        controller: _tel2,
                        label: _trProfileDialog('telefon2'),
                        icon: Icons.phone_iphone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () async {
                                  final authId = widget.putnikData['id']?.toString().trim() ?? '';
                                  if (authId.isEmpty) return;
                                  await V3DialogHelper.showDialogBuilder<void>(
                                    context: context,
                                    builder: (ctx) => _ChangePinDialog(v3AuthId: authId),
                                  );
                                },
                          icon: const Icon(Icons.lock_reset_outlined, color: Colors.white),
                          label: Text(_trProfileDialog('promeniPin'), style: const TextStyle(color: Colors.white)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white54),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: V3ButtonUtils.outlinedButton(
                              onPressed: _saving ? null : () => Navigator.pop(context),
                              text: _trProfileDialog('otkazi'),
                              borderColor: Colors.white54,
                              foregroundColor: Colors.white70,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: V3ButtonUtils.primaryButton(
                              onPressed: _saving ? null : _sacuvaj,
                              text: _trProfileDialog('sacuvaj'),
                              icon: Icons.check,
                              isLoading: _saving,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── CHANGE PIN DIALOG ──────────────────────────────────────────────────────
class _ChangePinDialog extends StatefulWidget {
  final String v3AuthId;

  const _ChangePinDialog({required this.v3AuthId});

  @override
  State<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends State<_ChangePinDialog> {
  final _oldPinController = TextEditingController();
  final _newPinController = TextEditingController();
  final _newPinConfirmController = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _oldPinController.dispose();
    _newPinController.dispose();
    _newPinConfirmController.dispose();
    super.dispose();
  }

  Future<void> _sacuvaj() async {
    final oldPin = _oldPinController.text.trim();
    final newPin = _newPinController.text.trim();
    final newPinConfirm = _newPinConfirmController.text.trim();

    if (!V3ClosedAuthService.isValidPin(oldPin)) {
      setState(() => _error = _trProfileDialog('trenutniPinMora6Cifara'));
      return;
    }
    if (!V3ClosedAuthService.isValidPin(newPin)) {
      setState(() => _error = _trProfileDialog('noviPinMora6Cifara'));
      return;
    }
    if (newPin != newPinConfirm) {
      setState(() => _error = _trProfileDialog('noviPinoviSeNePoklapaju'));
      return;
    }
    if (newPin == oldPin) {
      setState(() => _error = _trProfileDialog('noviPinMoraBitiRazlicit'));
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final result = await V3ClosedAuthService.changePin(
      v3AuthId: widget.v3AuthId,
      oldPin: oldPin,
      newPin: newPin,
    );

    if (!mounted) return;

    if (!result.ok) {
      final message = switch (result.reason) {
        'old_pin_mismatch' => _trProfileDialog('trenutniPinNijeIspravan'),
        'pin_not_set' => _trProfileDialog('nalogNemaPin'),
        _ => _trProfileDialog('greskaPromenaPin'),
      };
      setState(() {
        _saving = false;
        _error = message;
      });
      return;
    }

    V3AppSnackBar.success(context, _trProfileDialog('pinPromenjen'));
    Navigator.of(context, rootNavigator: true).pop();
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gradient = theme.backgroundGradient;

    return Dialog(
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: BoxDecoration(gradient: gradient),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.18),
                  border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_reset_outlined, color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _trProfileDialog('promeniPinTitle'),
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            _trProfileDialog('unesiPinSubtitle'),
                            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      V3InputUtils.textField(
                        controller: _oldPinController,
                        label: _trProfileDialog('trenutniPin'),
                        icon: Icons.lock_outline,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                      ),
                      const SizedBox(height: 12),
                      V3InputUtils.textField(
                        controller: _newPinController,
                        label: _trProfileDialog('noviPin'),
                        icon: Icons.lock_open_outlined,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                      ),
                      const SizedBox(height: 12),
                      V3InputUtils.textField(
                        controller: _newPinConfirmController,
                        label: _trProfileDialog('ponoviNoviPin'),
                        icon: Icons.lock_open_outlined,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: V3ButtonUtils.outlinedButton(
                              onPressed: _saving ? null : () => Navigator.of(context, rootNavigator: true).pop(),
                              text: _trProfileDialog('otkazi'),
                              borderColor: Colors.white54,
                              foregroundColor: Colors.white70,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: V3ButtonUtils.primaryButton(
                              onPressed: _saving ? null : _sacuvaj,
                              text: _trProfileDialog('sacuvaj'),
                              icon: Icons.check,
                              isLoading: _saving,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
