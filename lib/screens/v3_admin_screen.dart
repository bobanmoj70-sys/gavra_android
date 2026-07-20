import 'package:flutter/material.dart';

import '../globals.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_app_settings_service.dart';
import '../services/v3/v3_finansije_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../services/v3_locale_manager.dart';
import '../services/v3_theme_manager.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dialog_helper.dart';
import '../utils/v3_navigation_utils.dart';
import '../utils/v3_safe_text.dart';
import '../utils/v3_status_policy.dart';
import 'v3_admin_raspored_screen.dart';
import 'v3_adrese_screen.dart';
import 'v3_dnevnik_vozaca_screen.dart';
import 'v3_dugovi_screen.dart';
import 'v3_finansije_screen.dart';
import 'v3_gorivo_screen.dart';
import 'v3_kapacitet_screen.dart';
import 'v3_odrzavanje_screen.dart';
import 'v3_posiljke_zahtevi_screen.dart';
import 'v3_putnici_screen.dart';
import 'v3_radnici_zahtevi_screen.dart';
import 'v3_ucenici_zahtevi_screen.dart';
import 'v3_uplata_pazara_screen.dart';
import 'v3_zahtevi_dnevni_screen.dart';

class V3AdminScreen extends StatefulWidget {
  const V3AdminScreen({super.key});

  @override
  State<V3AdminScreen> createState() => _V3AdminScreenState();
}

class _V3AdminScreenState extends State<V3AdminScreen> {
  static const Map<String, Map<String, String>> _t = {
    'neradniDani': {'sr': 'Neradni dani', 'en': 'Non-working days', 'ru': 'Нерабочие дни', 'de': 'Arbeitsfreie Tage'},
    'datumBiraSeIzKalendara': {
      'sr': 'Datum se bira iz kalendara.',
      'en': 'The date is chosen from the calendar.',
      'ru': 'Дата выбирается из календаря.',
      'de': 'Das Datum wird aus dem Kalender ausgewählt.',
    },
    'datum': {'sr': 'Datum', 'en': 'Date', 'ru': 'Дата', 'de': 'Datum'},
    'izaberiDatum': {'sr': 'Izaberi datum', 'en': 'Select date', 'ru': 'Выберите дату', 'de': 'Datum auswählen'},
    'scope': {'sr': 'Scope', 'en': 'Scope', 'ru': 'Область', 'de': 'Bereich'},
    'sviAll': {'sr': 'Svi (ALL)', 'en': 'All (ALL)', 'ru': 'Все (ALL)', 'de': 'Alle (ALL)'},
    'razlog': {'sr': 'Razlog', 'en': 'Reason', 'ru': 'Причина', 'de': 'Grund'},
    'drzavniPraznik': {
      'sr': 'Državni praznik',
      'en': 'Public holiday',
      'ru': 'Государственный праздник',
      'de': 'Feiertag'
    },
    'dodajZameni': {
      'sr': 'Dodaj / Zameni',
      'en': 'Add / Replace',
      'ru': 'Добавить / Заменить',
      'de': 'Hinzufügen / Ersetzen'
    },
    'aktivnaPravila': {'sr': 'Aktivna pravila', 'en': 'Active rules', 'ru': 'Активные правила', 'de': 'Aktive Regeln'},
    'nemaUnosa': {'sr': 'Nema unosa', 'en': 'No entries', 'ru': 'Нет записей', 'de': 'Keine Einträge'},
    'otkazi': {'sr': 'Otkaži', 'en': 'Cancel', 'ru': 'Отмена', 'de': 'Abbrechen'},
    'sacuvaj': {'sr': 'Sačuvaj', 'en': 'Save', 'ru': 'Сохранить', 'de': 'Speichern'},
    'cuvam': {'sr': 'Čuvam...', 'en': 'Saving...', 'ru': 'Сохранение...', 'de': 'Speichern...'},
    'izaberiDatumIzKalendara': {
      'sr': 'Izaberi datum iz kalendara.',
      'en': 'Select a date from the calendar.',
      'ru': 'Выберите дату из календаря.',
      'de': 'Datum aus dem Kalender auswählen.',
    },
    'datumNijeValidan': {
      'sr': 'Datum nije validan kalendarski.',
      'en': 'The date is not a valid calendar date.',
      'ru': 'Дата не является допустимой календарной датой.',
      'de': 'Das Datum ist kein gültiges Kalenderdatum.',
    },
    'dodajBarJedanNeradanDan': {
      'sr': 'Dodaj bar jedan neradan dan pre čuvanja.',
      'en': 'Add at least one non-working day before saving.',
      'ru': 'Добавьте хотя бы один нерабочий день перед сохранением.',
      'de': 'Fügen Sie mindestens einen arbeitsfreien Tag hinzu, bevor Sie speichern.',
    },
    'neradniDaniSacuvani': {
      'sr': '✅ Neradni dani sačuvani',
      'en': '✅ Non-working days saved',
      'ru': '✅ Нерабочие дни сохранены',
      'de': '✅ Arbeitsfreie Tage gespeichert',
    },
    'greskaPriCuvanju': {
      'sr': 'Greška pri čuvanju:',
      'en': 'Error while saving:',
      'ru': 'Ошибка при сохранении:',
      'de': 'Fehler beim Speichern:'
    },
    'greskaPriUcitavanjuNeradnih': {
      'sr': 'Greška pri učitavanju neradnih dana:',
      'en': 'Error loading non-working days:',
      'ru': 'Ошибка при загрузке нерабочих дней:',
      'de': 'Fehler beim Laden der arbeitsfreien Tage:',
    },
    'customVremenaPolazaka': {
      'sr': 'Custom vremena polazaka',
      'en': 'Custom departure times',
      'ru': 'Пользовательское время отправления',
      'de': 'Benutzerdefinierte Abfahrtszeiten',
    },
    'unosFormataHint': {
      'sr': 'Unos formata HH:mm, razdvojeno zarezom.',
      'en': 'Enter in HH:mm format, comma-separated.',
      'ru': 'Введите в формате ЧЧ:мм, через запятую.',
      'de': 'Eingabe im Format HH:mm, durch Komma getrennt.',
    },
    'neispravnoVreme': {
      'sr': 'Neispravno vreme:',
      'en': 'Invalid time:',
      'ru': 'Неверное время:',
      'de': 'Ungültige Zeit:'
    },
    'customVremenaSacuvana': {
      'sr': '✅ Custom vremena sačuvana',
      'en': '✅ Custom times saved',
      'ru': '✅ Пользовательское время сохранено',
      'de': '✅ Benutzerdefinierte Zeiten gespeichert',
    },
    'greskaPriUcitavanjuCustom': {
      'sr': 'Greška pri učitavanju custom vremena:',
      'en': 'Error loading custom times:',
      'ru': 'Ошибка при загрузке пользовательского времени:',
      'de': 'Fehler beim Laden der benutzerdefinierten Zeiten:',
    },
    'infoBaner': {
      'sr': '📢 Info baner',
      'en': '📢 Info banner',
      'ru': '📢 Информационный баннер',
      'de': '📢 Info-Banner'
    },
    'infoBanerHint': {
      'sr': 'Jedna poruka prikazana odabranoj grupi korisnika. Isključi kada ne treba da se prikazuje.',
      'en': 'A single message shown to the selected group of users. Turn off when it should not be shown.',
      'ru': 'Одно сообщение, показываемое выбранной группе пользователей. Отключите, если не нужно показывать.',
      'de':
          'Eine einzelne Nachricht für die ausgewählte Nutzergruppe. Deaktivieren, wenn sie nicht angezeigt werden soll.',
    },
    'prikaziBaner': {'sr': 'Prikaži baner', 'en': 'Show banner', 'ru': 'Показать баннер', 'de': 'Banner anzeigen'},
    'naslov': {'sr': 'Naslov', 'en': 'Title', 'ru': 'Заголовок', 'de': 'Titel'},
    'obavestenje': {'sr': 'Obaveštenje', 'en': 'Notice', 'ru': 'Уведомление', 'de': 'Hinweis'},
    'poruka': {'sr': 'Poruka', 'en': 'Message', 'ru': 'Сообщение', 'de': 'Nachricht'},
    'unesiTekstObavestenja': {
      'sr': 'Unesi tekst obaveštenja...',
      'en': 'Enter notice text...',
      'ru': 'Введите текст уведомления...',
      'de': 'Hinweistext eingeben...',
    },
    'bojaBanera': {'sr': 'Boja banera', 'en': 'Banner color', 'ru': 'Цвет баннера', 'de': 'Bannerfarbe'},
    'prikaziKorisnicima': {
      'sr': 'Prikaži korisnicima',
      'en': 'Show to users',
      'ru': 'Показать пользователям',
      'de': 'Nutzern anzeigen'
    },
    'bakerUkljucenValidacija': {
      'sr': 'Ako je baner uključen, moraš uneti i naslov i poruku.',
      'en': 'If the banner is enabled, you must enter both a title and a message.',
      'ru': 'Если баннер включен, необходимо ввести заголовок и сообщение.',
      'de': 'Wenn der Banner aktiviert ist, müssen Titel und Nachricht eingegeben werden.',
    },
    'infoBanerSacuvan': {
      'sr': '✅ Info baner sačuvan',
      'en': '✅ Info banner saved',
      'ru': '✅ Информационный баннер сохранен',
      'de': '✅ Info-Banner gespeichert',
    },
    'greskaPriUcitavanjuBanera': {
      'sr': 'Greška pri učitavanju info banera:',
      'en': 'Error loading info banner:',
      'ru': 'Ошибка при загрузке информационного баннера:',
      'de': 'Fehler beim Laden des Info-Banners:',
    },
    'audSvi': {'sr': 'Svi', 'en': 'All', 'ru': 'Все', 'de': 'Alle'},
    'audPutnici': {'sr': 'Putnici', 'en': 'Passengers', 'ru': 'Пассажиры', 'de': 'Passagiere'},
    'audVozaci': {'sr': 'Vozači', 'en': 'Drivers', 'ru': 'Водители', 'de': 'Fahrer'},
    'audRadnici': {'sr': 'Radnici', 'en': 'Workers', 'ru': 'Рабочие', 'de': 'Arbeiter'},
    'audUcenici': {'sr': 'Učenici', 'en': 'Students', 'ru': 'Ученики', 'de': 'Schüler'},
    'updateVerzije': {
      'sr': 'Update verzije',
      'en': 'Update versions',
      'ru': 'Версии обновления',
      'de': 'Update-Versionen'
    },
    'androidLatest': {
      'sr': 'Android latest',
      'en': 'Android latest',
      'ru': 'Android последняя',
      'de': 'Android neueste'
    },
    'androidMin': {'sr': 'Android min', 'en': 'Android min', 'ru': 'Android минимальная', 'de': 'Android min'},
    'iosLatest': {'sr': 'iOS latest', 'en': 'iOS latest', 'ru': 'iOS последняя', 'de': 'iOS neueste'},
    'iosMin': {'sr': 'iOS min', 'en': 'iOS min', 'ru': 'iOS минимальная', 'de': 'iOS min'},
    'forceAndroid': {
      'sr': 'Force Android',
      'en': 'Force Android',
      'ru': 'Принудительно Android',
      'de': 'Android erzwingen'
    },
    'forceIos': {'sr': 'Force iOS', 'en': 'Force iOS', 'ru': 'Принудительно iOS', 'de': 'iOS erzwingen'},
    'maintenanceAndroid': {
      'sr': 'Maintenance Android',
      'en': 'Maintenance Android',
      'ru': 'Обслуживание Android',
      'de': 'Wartung Android'
    },
    'maintenanceIos': {'sr': 'Maintenance iOS', 'en': 'Maintenance iOS', 'ru': 'Обслуживание iOS', 'de': 'Wartung iOS'},
    'androidVerzijaFormat': {
      'sr': 'Android verzija mora biti u formatu npr. 6.0.192',
      'en': 'Android version must be in format e.g. 6.0.192',
      'ru': 'Версия Android должна быть в формате, например, 6.0.192',
      'de': 'Die Android-Version muss z. B. im Format 6.0.192 vorliegen',
    },
    'iosVerzijaFormat': {
      'sr': 'iOS verzija mora biti u formatu npr. 6.0.192',
      'en': 'iOS version must be in format e.g. 6.0.192',
      'ru': 'Версия iOS должна быть в формате, например, 6.0.192',
      'de': 'Die iOS-Version muss z. B. im Format 6.0.192 vorliegen',
    },
    'updateVerzijeSacuvane': {
      'sr': '✅ Update verzije sačuvane',
      'en': '✅ Update versions saved',
      'ru': '✅ Версии обновления сохранены',
      'de': '✅ Update-Versionen gespeichert',
    },
    'uceniciBezVsTermina': {
      'sr': 'Učenici bez VS termina',
      'en': 'Students without VS slot',
      'ru': 'Ученики без слота VS',
      'de': 'Schüler ohne VS-Termin',
    },
    'bezVs': {'sr': 'Bez VS', 'en': 'Without VS', 'ru': 'Без VS', 'de': 'Ohne VS'},
    'sviImajuVsTermin': {
      'sr': '— svi imaju VS termin —',
      'en': '— everyone has a VS slot —',
      'ru': '— у всех есть слот VS —',
      'de': '— alle haben einen VS-Termin —',
    },
    'zatvori': {'sr': 'Zatvori', 'en': 'Close', 'ru': 'Закрыть', 'de': 'Schließen'},
    'tipRasporeda': {'sr': 'Tip rasporeda', 'en': 'Schedule type', 'ru': 'Тип расписания', 'de': 'Zeitplantyp'},
    'custom': {'sr': '🛠️  Custom', 'en': '🛠️  Custom', 'ru': '🛠️  Настраиваемый', 'de': '🛠️  Benutzerdefiniert'},
    'urediCustomVremena': {
      'sr': '⏱️  Uredi custom vremena',
      'en': '⏱️  Edit custom times',
      'ru': '⏱️  Изменить пользовательское время',
      'de': '⏱️  Benutzerdefinierte Zeiten bearbeiten',
    },
    'urediNeradneDane': {
      'sr': '📅  Uredi neradne dane',
      'en': '📅  Edit non-working days',
      'ru': '📅  Изменить нерабочие дни',
      'de': '📅  Arbeitsfreie Tage bearbeiten',
    },
    'urediInfoBaner': {
      'sr': '📢  Uredi info baner',
      'en': '📢  Edit info banner',
      'ru': '📢  Изменить информационный баннер',
      'de': '📢  Info-Banner bearbeiten',
    },
    'duznici': {'sr': 'Dužnici', 'en': 'Debtors', 'ru': 'Должники', 'de': 'Schuldner'},
    'ukupanPazar': {'sr': 'UKUPAN PAZAR', 'en': 'TOTAL EARNINGS', 'ru': 'ОБЩАЯ ВЫРУЧКА', 'de': 'GESAMTEINNAHMEN'},
  };

  String _tr(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    return _t[key]?[code] ?? _t[key]?['sr'] ?? key;
  }

  late final V3ThemeManager _themeManager;
  static final RegExp _versionPattern = RegExp(r'^\d+(\.\d+){1,3}$');
  static final RegExp _timePattern = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');
  static final RegExp _dateIsoPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  void _runAfterMenuClose(Future<void> Function() action) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await action();
    });
  }

  @override
  void initState() {
    super.initState();
    _themeManager = V3ThemeManager();
  }

  bool _isValidVersion(String value) {
    return _versionPattern.hasMatch(value.trim());
  }

  Future<Map<String, dynamic>> _loadUpdateSettings() async {
    try {
      return await V3AppSettingsService.loadGlobal(
        selectColumns:
            'latest_version_android, min_supported_version_android, force_update_android, store_url_android, maintenance_mode_android, maintenance_title_android, maintenance_message_android, '
            'latest_version_ios, min_supported_version_ios, force_update_ios, store_url_ios, maintenance_mode_ios, maintenance_title_ios, maintenance_message_ios',
      );
    } catch (e) {
      debugPrint('[AdminScreen] Greška pri učitavanju update settings: $e');
      return <String, dynamic>{};
    }
  }

  List<String> _normalizeTimes(List<String> input) {
    final unique = <String>{};
    for (final raw in input) {
      final t = raw.trim();
      if (_timePattern.hasMatch(t)) unique.add(t);
    }
    final times = unique.toList();
    times.sort();
    return times;
  }

  List<String> _parseTimesCsv(String value) {
    if (value.trim().isEmpty) return [];
    return value.split(RegExp(r'[,\n; ]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  List<Map<String, String>> _parseNeradniDani(dynamic raw) {
    if (raw is! List) return <Map<String, String>>[];

    final out = <Map<String, String>>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final date = (item['date'] ?? '').toString().trim();
      if (!_dateIsoPattern.hasMatch(date)) continue;

      final scopeRaw = (item['scope'] ?? 'all').toString().trim().toLowerCase();
      final scope = (scopeRaw == 'bc' || scopeRaw == 'vs') ? scopeRaw : 'all';
      final reason = (item['reason'] ?? '').toString().trim();

      out.add({'date': date, 'scope': scope, 'reason': reason});
    }

    out.sort((a, b) => (a['date'] ?? '').compareTo(b['date'] ?? ''));
    return out;
  }

  Future<void> _openNeradniDaniEditor() async {
    try {
      final row = await V3AppSettingsService.loadGlobal(selectColumns: 'neradni_dani');
      if (!mounted) return;

      final items = _parseNeradniDani(row['neradni_dani']);

      await V3DialogHelper.showDialogBuilder<void>(
        context: context,
        builder: (dialogContext) {
          var isSaving = false;
          final dateCtrl = TextEditingController();
          final reasonCtrl = TextEditingController();
          var scope = 'all';

          return StatefulBuilder(
            builder: (context, setModalState) => AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.primary,
              title: Text(_tr('neradniDani'), style: const TextStyle(color: Colors.white)),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _tr('datumBiraSeIzKalendara'),
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: dateCtrl,
                        readOnly: true,
                        onTap: () async {
                          final now = DateTime.now();
                          final parsed = DateTime.tryParse(dateCtrl.text.trim());
                          final initial = parsed ?? DateTime(now.year, now.month, now.day);
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: initial,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            final iso =
                                '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                            setModalState(() => dateCtrl.text = iso);
                          }
                        },
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: _tr('datum'),
                          hintText: _tr('izaberiDatum'),
                          prefixIcon: const Icon(Icons.calendar_today, color: Colors.white70),
                          labelStyle: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: scope,
                        dropdownColor: Theme.of(context).colorScheme.primary,
                        decoration: InputDecoration(
                          labelText: _tr('scope'),
                          labelStyle: const TextStyle(color: Colors.white70),
                        ),
                        style: const TextStyle(color: Colors.white),
                        items: [
                          DropdownMenuItem(value: 'all', child: Text(_tr('sviAll'))),
                          const DropdownMenuItem(value: 'bc', child: Text('BC')),
                          const DropdownMenuItem(value: 'vs', child: Text('VS')),
                        ],
                        onChanged: (val) => setModalState(() => scope = val ?? 'all'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: reasonCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: _tr('razlog'),
                          hintText: _tr('drzavniPraznik'),
                          labelStyle: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: isSaving
                                  ? null
                                  : () {
                                      final date = dateCtrl.text.trim();
                                      if (!_dateIsoPattern.hasMatch(date)) {
                                        V3AppSnackBar.warning(context, _tr('izaberiDatumIzKalendara'));
                                        return;
                                      }

                                      final normalized = DateTime.tryParse(date);
                                      if (normalized == null) {
                                        V3AppSnackBar.warning(context, _tr('datumNijeValidan'));
                                        return;
                                      }

                                      final normalizedDate =
                                          '${normalized.year.toString().padLeft(4, '0')}-${normalized.month.toString().padLeft(2, '0')}-${normalized.day.toString().padLeft(2, '0')}';

                                      setModalState(() {
                                        items.removeWhere((e) => e['date'] == normalizedDate && e['scope'] == scope);
                                        items.add({
                                          'date': normalizedDate,
                                          'scope': scope,
                                          'reason': reasonCtrl.text.trim(),
                                        });
                                        items.sort((a, b) => (a['date'] ?? '').compareTo(b['date'] ?? ''));
                                        dateCtrl.clear();
                                        reasonCtrl.clear();
                                        scope = 'all';
                                      });
                                    },
                              icon: const Icon(Icons.add),
                              label: Text(_tr('dodajZameni')),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 8),
                      Text(_tr('aktivnaPravila'),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      if (items.isEmpty)
                        Text(_tr('nemaUnosa'), style: const TextStyle(color: Colors.white60))
                      else
                        ...items.map(
                          (entry) => Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${entry['date']} [${(entry['scope'] ?? 'all').toUpperCase()}] — ${entry['reason'] ?? ''}',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                IconButton(
                                  onPressed: isSaving
                                      ? null
                                      : () => setModalState(() {
                                            items.remove(entry);
                                          }),
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
                  child: Text(_tr('otkazi')),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setModalState(() => isSaving = true);
                          try {
                            final draftDate = dateCtrl.text.trim();
                            if (draftDate.isNotEmpty) {
                              if (!_dateIsoPattern.hasMatch(draftDate)) {
                                setModalState(() => isSaving = false);
                                V3AppSnackBar.warning(context, _tr('izaberiDatumIzKalendara'));
                                return;
                              }

                              final normalized = DateTime.tryParse(draftDate);
                              if (normalized == null) {
                                setModalState(() => isSaving = false);
                                V3AppSnackBar.warning(context, _tr('datumNijeValidan'));
                                return;
                              }

                              final normalizedDate =
                                  '${normalized.year.toString().padLeft(4, '0')}-${normalized.month.toString().padLeft(2, '0')}-${normalized.day.toString().padLeft(2, '0')}';

                              items.removeWhere((e) => e['date'] == normalizedDate && e['scope'] == scope);
                              items.add({
                                'date': normalizedDate,
                                'scope': scope,
                                'reason': reasonCtrl.text.trim(),
                              });
                              items.sort((a, b) => (a['date'] ?? '').compareTo(b['date'] ?? ''));
                            }

                            if (items.isEmpty) {
                              setModalState(() => isSaving = false);
                              V3AppSnackBar.warning(context, _tr('dodajBarJedanNeradanDan'));
                              return;
                            }

                            await V3AppSettingsService.updateGlobal({'neradni_dani': items});
                            if (!mounted) return;
                            Navigator.of(dialogContext).pop();
                            V3AppSnackBar.success(this.context, _tr('neradniDaniSacuvani'));
                          } catch (e) {
                            if (!mounted) return;
                            setModalState(() => isSaving = false);
                            V3AppSnackBar.error(context, '${_tr('greskaPriCuvanju')} $e');
                          }
                        },
                  child: Text(_tr('sacuvaj')),
                ),
              ],
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      V3AppSnackBar.error(context, '${_tr('greskaPriUcitavanjuNeradnih')} $e');
    }
  }

  Map<String, List<String>> _parseByDaySchedule(dynamic raw) {
    final result = {
      for (final day in V3DanHelper.workdayNames) day: <String>[],
    };

    if (raw is! Map) return result;

    for (final entry in raw.entries) {
      final normalizedDay = V3DanHelper.normalizeToWorkdayFull(entry.key.toString());
      if (normalizedDay.isEmpty) continue;
      if (entry.value is List) {
        result[normalizedDay] = _normalizeTimes((entry.value as List).map((e) => e.toString()).toList());
      }
    }

    return result;
  }

  Future<void> _openCustomScheduleEditor() async {
    try {
      final row = await V3AppSettingsService.loadGlobal(
        selectColumns: 'bc_custom_by_day, vs_custom_by_day',
      );
      if (!mounted) return;

      final bcByDayCurrent = _parseByDaySchedule(row['bc_custom_by_day']);
      final vsByDayCurrent = _parseByDaySchedule(row['vs_custom_by_day']);

      final bcInputs = {
        for (final day in V3DanHelper.workdayNames) day: (bcByDayCurrent[day] ?? const <String>[]).join(', '),
      };
      final vsInputs = {
        for (final day in V3DanHelper.workdayNames) day: (vsByDayCurrent[day] ?? const <String>[]).join(', '),
      };

      await V3DialogHelper.showDialogBuilder<void>(
        context: context,
        builder: (dialogContext) {
          var isSaving = false;
          return StatefulBuilder(
            builder: (context, setModalState) => AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.primary,
              title: Text(_tr('customVremenaPolazaka'), style: const TextStyle(color: Colors.white)),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_tr('unosFormataHint'), style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 10),
                      for (final day in V3DanHelper.workdayNames) ...[
                        Text(day, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: bcInputs[day] ?? '',
                          style: const TextStyle(color: Colors.white),
                          onChanged: (value) => bcInputs[day] = value,
                          decoration: InputDecoration(
                            labelText: 'BC custom - $day',
                            labelStyle: const TextStyle(color: Colors.white70),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: vsInputs[day] ?? '',
                          style: const TextStyle(color: Colors.white),
                          onChanged: (value) => vsInputs[day] = value,
                          decoration: InputDecoration(
                            labelText: 'VS custom - $day',
                            labelStyle: const TextStyle(color: Colors.white70),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
                  child: Text(_tr('otkazi')),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final bcByDayNorm = <String, List<String>>{};
                          final vsByDayNorm = <String, List<String>>{};
                          final invalidTokens = <String>[];

                          for (final day in V3DanHelper.workdayNames) {
                            final bcRaw = _parseTimesCsv(bcInputs[day] ?? '');
                            final vsRaw = _parseTimesCsv(vsInputs[day] ?? '');

                            invalidTokens
                                .addAll(bcRaw.where((t) => !_timePattern.hasMatch(t)).map((t) => '$day BC:$t'));
                            invalidTokens
                                .addAll(vsRaw.where((t) => !_timePattern.hasMatch(t)).map((t) => '$day VS:$t'));

                            bcByDayNorm[day] = _normalizeTimes(bcRaw);
                            vsByDayNorm[day] = _normalizeTimes(vsRaw);
                          }

                          if (invalidTokens.isNotEmpty) {
                            V3AppSnackBar.warning(context, '${_tr('neispravnoVreme')} ${invalidTokens.join(', ')}');
                            return;
                          }

                          setModalState(() => isSaving = true);
                          try {
                            await V3AppSettingsService.updateGlobal({
                              'bc_custom_by_day': bcByDayNorm,
                              'vs_custom_by_day': vsByDayNorm,
                            });
                            if (!mounted) return;
                            Navigator.of(dialogContext).pop();
                            V3AppSnackBar.success(this.context, _tr('customVremenaSacuvana'));
                          } catch (e) {
                            if (!mounted) return;
                            setModalState(() => isSaving = false);
                            V3AppSnackBar.error(context, '${_tr('greskaPriCuvanju')} $e');
                          }
                        },
                  child: Text(_tr('sacuvaj')),
                ),
              ],
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      V3AppSnackBar.error(context, '${_tr('greskaPriUcitavanjuCustom')} $e');
    }
  }

  Future<void> _openInfoBannerEditor() async {
    try {
      final row = await V3AppSettingsService.loadGlobal(selectColumns: 'info_banner');
      if (!mounted) return;

      final raw = row['info_banner'];
      final initial = raw is Map ? raw : <String, dynamic>{};

      final titleCtrl = TextEditingController(text: (initial['title'] ?? '').toString());
      final messageCtrl = TextEditingController(text: (initial['message'] ?? '').toString());
      var enabled = initial['enabled'] == true;
      var color = (initial['color'] ?? 'amber').toString().trim().toLowerCase();
      if (color.isEmpty) color = 'amber';
      var audience = _parseInfoBannerAudienceForEditor(initial['audience']);

      const colors = ['amber', 'blue', 'red', 'green'];
      const audiences = ['svi', 'putnici', 'vozaci', 'radnici', 'ucenici'];
      const audienceLabels = {
        'svi': 'Svi',
        'putnici': 'Putnici',
        'vozaci': 'Vozači',
        'radnici': 'Radnici',
        'ucenici': 'Učenici',
      };

      await V3DialogHelper.showDialogBuilder<void>(
        context: context,
        builder: (dialogContext) {
          var isSaving = false;
          return StatefulBuilder(
            builder: (context, setModalState) => AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.primary,
              title: Text(_tr('infoBaner'), style: const TextStyle(color: Colors.white)),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _tr('infoBanerHint'),
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        activeColor: Colors.amber,
                        title: Text(_tr('prikaziBaner'),
                            style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                        value: enabled,
                        onChanged: (val) => setModalState(() => enabled = val),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: titleCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: _tr('naslov'),
                          hintText: _tr('obavestenje'),
                          labelStyle: const TextStyle(color: Colors.white70),
                          prefixIcon: const Icon(Icons.title, color: Colors.white70),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: messageCtrl,
                        minLines: 3,
                        maxLines: 6,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: _tr('poruka'),
                          hintText: _tr('unesiTekstObavestenja'),
                          labelStyle: const TextStyle(color: Colors.white70),
                          prefixIcon: const Icon(Icons.message_outlined, color: Colors.white70),
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(_tr('bojaBanera'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: colors
                            .map(
                              (c) => ChoiceChip(
                                label: Text(
                                  c.toUpperCase(),
                                  style: TextStyle(
                                    color: color == c ? Colors.black : Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                selected: color == c,
                                selectedColor: _chipColor(c),
                                backgroundColor: Colors.white.withValues(alpha: 0.1),
                                onSelected: (_) => setModalState(() => color = c),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                      Text(_tr('prikaziKorisnicima'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: audiences
                            .map(
                              (a) => ChoiceChip(
                                label: Text(
                                  audienceLabels[a]!,
                                  style: TextStyle(
                                    color: audience.contains(a) ? Colors.black : Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                selected: audience.contains(a),
                                selectedColor: Colors.amber,
                                backgroundColor: Colors.white.withValues(alpha: 0.1),
                                onSelected: (selected) => setModalState(() {
                                  if (a == 'svi') {
                                    audience = selected ? ['svi'] : [];
                                  } else {
                                    audience = [
                                      ...audience.where((x) => x != 'svi'),
                                      if (selected) a,
                                    ];
                                  }
                                }),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
                  child: Text(_tr('otkazi')),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final title = titleCtrl.text.trim();
                          final message = messageCtrl.text.trim();

                          if (enabled && (title.isEmpty || message.isEmpty)) {
                            V3AppSnackBar.warning(context, _tr('bakerUkljucenValidacija'));
                            return;
                          }

                          setModalState(() => isSaving = true);
                          try {
                            await V3AppSettingsService.updateGlobal({
                              'info_banner': {
                                'enabled': enabled,
                                'title': title,
                                'message': message,
                                'color': color,
                                'audience': audience,
                              },
                            });
                            if (!mounted) return;
                            Navigator.of(dialogContext).pop();
                            V3AppSnackBar.success(this.context, _tr('infoBanerSacuvan'));
                          } catch (e) {
                            if (!mounted) return;
                            setModalState(() => isSaving = false);
                            V3AppSnackBar.error(context, '${_tr('greskaPriCuvanju')} $e');
                          }
                        },
                  child: Text(_tr('sacuvaj')),
                ),
              ],
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      V3AppSnackBar.error(context, '${_tr('greskaPriUcitavanjuBanera')} $e');
    }
  }

  List<String> _parseInfoBannerAudienceForEditor(dynamic raw) {
    if (raw == null) return const ['svi'];
    if (raw is List) {
      final list = raw.map((e) => e.toString().trim().toLowerCase()).where((s) => s.isNotEmpty).toList();
      return list.isEmpty ? const ['svi'] : list;
    }
    final single = raw.toString().trim().toLowerCase();
    return single.isEmpty ? const ['svi'] : [single];
  }

  Color _chipColor(String color) {
    switch (color) {
      case 'blue':
        return Colors.blue;
      case 'red':
        return Colors.red;
      case 'green':
        return Colors.green;
      case 'amber':
      default:
        return Colors.amber;
    }
  }

  Future<void> _openUpdateVersionsEditor() async {
    final row = await _loadUpdateSettings();
    if (!mounted) return;

    final latestAndroidCtrl = TextEditingController(text: (row['latest_version_android'] ?? '').toString());
    final minAndroidCtrl = TextEditingController(text: (row['min_supported_version_android'] ?? '').toString());
    final latestIosCtrl = TextEditingController(text: (row['latest_version_ios'] ?? '').toString());
    final minIosCtrl = TextEditingController(text: (row['min_supported_version_ios'] ?? '').toString());

    var forceAndroid = row['force_update_android'] == true;
    var forceIos = row['force_update_ios'] == true;
    var maintenanceAndroid = row['maintenance_mode_android'] == true;
    var maintenanceIos = row['maintenance_mode_ios'] == true;
    var isSaving = false;

    Future<void> save(StateSetter setModalState, BuildContext dialogContext) async {
      final latestAndroid = latestAndroidCtrl.text.trim();
      final latestIos = latestIosCtrl.text.trim();
      final minAndroid = minAndroidCtrl.text.trim().isEmpty ? latestAndroid : minAndroidCtrl.text.trim();
      final minIos = minIosCtrl.text.trim().isEmpty ? latestIos : minIosCtrl.text.trim();

      if (!_isValidVersion(latestAndroid) || !_isValidVersion(minAndroid)) {
        V3AppSnackBar.warning(dialogContext, _tr('androidVerzijaFormat'));
        return;
      }

      if (!_isValidVersion(latestIos) || !_isValidVersion(minIos)) {
        V3AppSnackBar.warning(dialogContext, _tr('iosVerzijaFormat'));
        return;
      }

      setModalState(() => isSaving = true);
      try {
        await V3AppSettingsService.upsertGlobal({
          'latest_version_android': latestAndroid,
          'min_supported_version_android': minAndroid,
          'force_update_android': forceAndroid,
          'maintenance_mode_android': maintenanceAndroid,
          'latest_version_ios': latestIos,
          'min_supported_version_ios': minIos,
          'force_update_ios': forceIos,
          'maintenance_mode_ios': maintenanceIos,
        });

        if (!mounted) return;
        Navigator.of(dialogContext).pop();
        V3AppSnackBar.success(context, _tr('updateVerzijeSacuvane'));
      } catch (e) {
        if (!mounted) return;
        V3AppSnackBar.error(dialogContext, '${_tr('greskaPriCuvanju')} $e');
      } finally {
        if (mounted) {
          setModalState(() => isSaving = false);
        }
      }
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (builderContext, setModalState) {
            return AlertDialog(
              title: Text(_tr('updateVerzije')),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: latestAndroidCtrl,
                        decoration: InputDecoration(labelText: _tr('androidLatest')),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: minAndroidCtrl,
                        decoration: InputDecoration(labelText: _tr('androidMin')),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: latestIosCtrl,
                        decoration: InputDecoration(labelText: _tr('iosLatest')),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: minIosCtrl,
                        decoration: InputDecoration(labelText: _tr('iosMin')),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_tr('forceAndroid')),
                        value: forceAndroid,
                        onChanged: (value) => setModalState(() => forceAndroid = value),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_tr('forceIos')),
                        value: forceIos,
                        onChanged: (value) => setModalState(() => forceIos = value),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_tr('maintenanceAndroid')),
                        value: maintenanceAndroid,
                        onChanged: (value) => setModalState(() => maintenanceAndroid = value),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_tr('maintenanceIos')),
                        value: maintenanceIos,
                        onChanged: (value) => setModalState(() => maintenanceIos = value),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(_tr('otkazi')),
                ),
                ElevatedButton(
                  onPressed: isSaving ? null : () => save(setModalState, dialogContext),
                  child: Text(isSaving ? _tr('cuvam') : _tr('sacuvaj')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Map<String, double> _getPazarPoVozacu() {
    return V3FinansijeService.getPazarPoVozacuZaDan(DateTime.now());
  }

  Color _bojaVozaca(String vozacId) {
    final hex = V3MasterRealtimeManager.instance.vozaciCache[vozacId]?['boja']?.toString();
    if (hex == null || hex.isEmpty) return Colors.blueGrey;
    try {
      final clean = hex.replaceFirst('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return Colors.blueGrey;
    }
  }

  Map<String, int> _getUceniciBcVsSummary() {
    final grouped = _getUceniciSaDodeljenimVremenomDanasPoGradu();
    final bcIds = grouped['BC'] ?? const <String>[];
    final vsSet = (grouped['VS'] ?? const <String>[]).toSet();
    // bcSaVs = učenici koji imaju i BC i VS zakazano danas
    final bcSaVs = bcIds.where((id) => vsSet.contains(id)).length;

    return {
      'bcTotal': bcIds.length,
      'bcSaVs': bcSaVs,
      'preostalo': bcIds.length - bcSaVs,
    };
  }

  // Vraca Map sa listama putnikId-eva (ne imena!) za BC i VS.
  Map<String, List<String>> _getUceniciSaDodeljenimVremenomDanasPoGradu() {
    final rm = V3MasterRealtimeManager.instance;
    final now = DateTime.now();

    final uceniciIds = rm.putniciCache.values
        .where((p) => (p['tip_putnika'] as String? ?? '').toLowerCase() == 'ucenik')
        .map((p) => p['id'] as String)
        .toSet();

    final bcIds = <String>{};
    final vsIds = <String>{};

    for (final r in rm.operativnaNedeljaCache.values) {
      final putnikId = r['created_by']?.toString();
      if (putnikId == null || !uceniciIds.contains(putnikId)) continue;

      final datumRaw = r['datum']?.toString();
      if (datumRaw == null || datumRaw.isEmpty) continue;
      final datum = DateTime.tryParse(datumRaw);
      if (datum == null) continue;
      if (datum.year != now.year || datum.month != now.month || datum.day != now.day) continue;

      final status = V3StatusPolicy.deriveOperativnaStatus(
        otkazanoAt: r['otkazano_at'],
        polazakAt: r['polazak_at'],
      );
      if (!V3StatusPolicy.isApproved(status)) continue;

      final polazakAt = (r['polazak_at']?.toString() ?? '').trim();
      if (polazakAt.isEmpty) continue;

      final grad = (r['grad']?.toString() ?? '').toUpperCase();
      if (grad == 'BC') {
        bcIds.add(putnikId);
      } else if (grad == 'VS') {
        vsIds.add(putnikId);
      }
    }

    return {
      'BC': bcIds.toList(),
      'VS': vsIds.toList(),
    };
  }

  void _showUceniciDanasPopup(BuildContext context) {
    final rm = V3MasterRealtimeManager.instance;
    final grouped = _getUceniciSaDodeljenimVremenomDanasPoGradu();
    final bcIds = grouped['BC'] ?? const <String>[];
    final vsSet = (grouped['VS'] ?? const <String>[]).toSet();
    // bezVs = ID-evi koji su u BC ali nisu u VS
    final bezVsIds = bcIds.where((id) => !vsSet.contains(id)).toList();
    // za prikaz - lookup imena po ID-u
    String idToIme(String id) => (rm.putniciCache[id]?['ime_prezime']?.toString() ?? id).trim();
    final bezVs = bezVsIds.map(idToIme).toList()..sort();

    V3DialogHelper.showDialogBuilder<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colorScheme = theme.colorScheme;
        final onSurface = colorScheme.onSurface;

        return AlertDialog(
          backgroundColor: theme.dialogTheme.backgroundColor ?? colorScheme.surface,
          title: Text(
            _tr('uceniciBezVsTermina'),
            style: theme.textTheme.titleMedium?.copyWith(
              color: onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_tr('bezVs')} (${bezVs.length})',
                    style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    bezVs.isEmpty ? _tr('sviImajuVsTermin') : bezVs.join('\n'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: onSurface.withValues(alpha: 0.82),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(_tr('zatvori')),
            ),
          ],
        );
      },
    );
  }

  /// Broj zahteva učenika na čekanju koje su učenici sami poslali
  int _getUceniciZahteviCount() {
    final rm = V3MasterRealtimeManager.instance;
    final uceniciIds = rm.putniciCache.values
        .where((p) => (p['tip_putnika'] as String? ?? '').toLowerCase() == 'ucenik')
        .map((p) => p['id'] as String)
        .toSet();

    return rm.zahteviCache.values.where((row) {
      if (!V3StatusPolicy.isPending(row['status']?.toString())) return false;

      final putnikId = row['created_by']?.toString();
      if (putnikId == null || putnikId.isEmpty) return false;
      if (!uceniciIds.contains(putnikId)) return false;

      final createdBy = (row['created_by']?.toString() ?? '').trim();
      return createdBy == putnikId;
    }).length;
  }

  int _getRadniciZahteviCount() {
    final rm = V3MasterRealtimeManager.instance;
    final radniciIds = rm.putniciCache.values
        .where((p) => (p['tip_putnika'] as String? ?? '').toLowerCase() == 'radnik')
        .map((p) => p['id'] as String)
        .toSet();

    return rm.zahteviCache.values.where((row) {
      if (!V3StatusPolicy.isPending(row['status']?.toString())) return false;

      final putnikId = row['created_by']?.toString();
      if (putnikId == null || putnikId.isEmpty) return false;
      if (!radniciIds.contains(putnikId)) return false;

      final createdBy = (row['created_by']?.toString() ?? '').trim();
      return createdBy == putnikId;
    }).length;
  }

  int _getZahteviCount() {
    final rm = V3MasterRealtimeManager.instance;
    return rm.zahteviCache.values.where((row) {
      if (!V3StatusPolicy.isPending(row['status']?.toString())) return false;
      final putnikId = row['created_by']?.toString();
      if (putnikId == null || putnikId.isEmpty) return false;

      final putnik = rm.putniciCache[putnikId];
      final tip = (putnik?['tip_putnika'] as String? ?? '').toLowerCase();
      if (tip != 'dnevni') return false;

      final createdBy = (row['created_by']?.toString() ?? '').trim();
      return createdBy == putnikId;
    }).length;
  }

  int _getPosiljkeZahteviCount() {
    final rm = V3MasterRealtimeManager.instance;
    final posiljkaPutnici = rm.putniciCache.values
        .where((p) => (p['tip_putnika'] as String? ?? '').toLowerCase() == 'posiljka')
        .map((p) => p['id'] as String)
        .toSet();
    return rm.zahteviCache.values.where((r) {
      if (!V3StatusPolicy.isPending(r['status']?.toString())) return false;
      final putnikId = r['created_by']?.toString();
      if (putnikId == null || putnikId.isEmpty) return false;
      if (!posiljkaPutnici.contains(putnikId)) return false;

      final createdBy = (r['created_by']?.toString() ?? '').trim();
      return createdBy == putnikId;
    }).length;
  }

  /// Učenici brojač: BC učenika danas / preostalo bez VS termina.
  Widget _buildSaVsWidget(BuildContext context) {
    final stats = _getUceniciBcVsSummary();
    final bcTotal = stats['bcTotal'] ?? 0;
    final preostalo = stats['preostalo'] ?? 0;

    return GestureDetector(
      onTap: () => _showUceniciDanasPopup(context),
      child: Container(
        height: V3ContainerUtils.responsiveHeight(context, 50),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.7), width: 1.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$bcTotal/$preostalo',
              style: const TextStyle(
                color: Colors.orange,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: V3MasterRealtimeManager.instance.tablesRevisionStream(const [
        'v3_operativna_nedelja',
        'v3_auth',
        'v3_zahtevi',
        'v3_finansije',
      ]),
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final vozac = V3VozacService.currentVozac;
    final ime = vozac?.imePrezime ?? 'Admin';
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: _themeManager.currentGradient),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 10),

              // ─── RED 1: Kompaktni emoji gumbi (h=40) ───
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                child: Row(
                  children: [
                    // 📍 Adrese
                    Expanded(
                      child: _NavBtn(
                        color: Colors.teal,
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3AdreseScreen(),
                        ),
                        child: const Text('📍', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 💺 Kapacitet termina
                    Expanded(
                      child: _NavBtn(
                        color: Colors.green,
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3KapacitetScreen(),
                        ),
                        child: const Text('💺', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 💹 Finasnije
                    Expanded(
                      child: _NavBtn(
                        color: Colors.indigo,
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3FinansijeScreen(),
                        ),
                        child: const Text('💹', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 🔧 Kolska knjga
                    Expanded(
                      child: _NavBtn(
                        color: Colors.brown,
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3OdrzavanjeScreen(),
                        ),
                        child: const Text('🔧', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 🔧 Raspored + dodatne opcije
                    Expanded(
                      child: ValueListenableBuilder<String>(
                        valueListenable: navBarTypeNotifier,
                        builder: (context, __, ___) {
                          return _NavBtn(
                            color: Colors.blueGrey,
                            onTap: () async {
                              final RenderBox button = context.findRenderObject()! as RenderBox;
                              final RenderBox overlay =
                                  Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
                              final RelativeRect position = RelativeRect.fromRect(
                                Rect.fromPoints(
                                  button.localToGlobal(Offset.zero, ancestor: overlay),
                                  button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
                                ),
                                Offset.zero & overlay.size,
                              );
                              final val = await showMenu<String>(
                                context: context,
                                position: position,
                                color: Theme.of(context).colorScheme.primary,
                                items: [
                                  PopupMenuItem(
                                    enabled: false,
                                    height: V3ContainerUtils.responsiveHeight(context, 28),
                                    child: Text(_tr('tipRasporeda'),
                                        style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                  ),
                                  PopupMenuItem(
                                      value: 'custom',
                                      child: Text(_tr('custom'), style: const TextStyle(color: Colors.white))),
                                  const PopupMenuDivider(),
                                  PopupMenuItem(
                                      value: '__custom_times__',
                                      child:
                                          Text(_tr('urediCustomVremena'), style: const TextStyle(color: Colors.white))),
                                  PopupMenuItem(
                                      value: '__non_working_days__',
                                      child:
                                          Text(_tr('urediNeradneDane'), style: const TextStyle(color: Colors.white))),
                                  PopupMenuItem(
                                      value: '__info_banner__',
                                      child: Text(_tr('urediInfoBaner'), style: const TextStyle(color: Colors.white))),
                                ],
                              );
                              if (val == null) return;
                              if (val == '__custom_times__') {
                                _runAfterMenuClose(_openCustomScheduleEditor);
                                return;
                              }
                              if (val == '__non_working_days__') {
                                _runAfterMenuClose(_openNeradniDaniEditor);
                                return;
                              }
                              if (val == '__info_banner__') {
                                _runAfterMenuClose(_openInfoBannerEditor);
                                return;
                              }
                            },
                            child: const Text('🛠️', style: TextStyle(fontSize: 20)),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // ─── RED 2: Brojač učenika bez VS + Putnici ───
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Row(
                  children: [
                    Expanded(child: _buildSaVsWidget(context)),
                    const SizedBox(width: 6),
                    _NavBtn(
                      color: Colors.green,
                      height: V3ContainerUtils.responsiveHeight(context, 50),
                      width: V3ContainerUtils.responsiveHeight(context, 50),
                      onTap: () => V3NavigationUtils.pushScreen<void>(
                        context,
                        const V3PutniciScreen(),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '🧑‍🤝‍🧑',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                            color: Colors.white,
                            shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ─── RED 3: Kalendar, Dnevnik vozača, Putnici, Gorivo ───
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Row(
                  children: [
                    // 📅 Raspored
                    Expanded(
                      flex: 1,
                      child: _NavBtn(
                        color: Colors.blue,
                        height: V3ContainerUtils.responsiveHeight(context, 50),
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3AdminRasporedScreen(),
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '📅',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Colors.white,
                              shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Dnevnik vozača
                    Expanded(
                      flex: 1,
                      child: _NavBtn(
                        color: Colors.indigo,
                        height: V3ContainerUtils.responsiveHeight(context, 50),
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3DnevnikVozacaScreen(),
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '📒',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Colors.white,
                              shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Uplata pazara
                    Expanded(
                      flex: 1,
                      child: _NavBtn(
                        color: Colors.teal,
                        height: V3ContainerUtils.responsiveHeight(context, 50),
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3UplataPazaraScreen(),
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '💰',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Colors.white,
                              shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // ⛽ Gorivo
                    Expanded(
                      flex: 1,
                      child: _NavBtn(
                        color: Colors.orange,
                        height: V3ContainerUtils.responsiveHeight(context, 50),
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3GorivoScreen(),
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '⛽',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Colors.white,
                              shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 1,
                      child: _NavBtn(
                        color: Colors.purple,
                        height: V3ContainerUtils.responsiveHeight(context, 50),
                        onTap: _openUpdateVersionsEditor,
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '🔄',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Colors.white,
                              shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ─── RED 4: Badge gumbi — Učenici, Radnici, Pošiljke, Zahtevi, Šifre ───
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Row(
                  children: [
                    // 🔔 Zahtevi (polasci)
                    Expanded(
                      child: _BadgeBtn(
                        emoji: '🔔',
                        color: Colors.deepOrange,
                        badgeCount: _getZahteviCount(),
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3ZahteviDnevniScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 🎓 Učenici zahtevi
                    Expanded(
                      child: _BadgeBtn(
                        emoji: '🎓',
                        color: Colors.lightBlue,
                        badgeCount: _getUceniciZahteviCount(),
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3UceniciZahteviScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 👷 Radnici zahtevi
                    Expanded(
                      child: _BadgeBtn(
                        emoji: '👷',
                        color: Colors.green,
                        badgeCount: _getRadniciZahteviCount(),
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3RadniciZahteviScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 📦 Pošiljke zahtevi
                    Expanded(
                      child: _BadgeBtn(
                        emoji: '📦',
                        color: Colors.deepOrangeAccent,
                        badgeCount: _getPosiljkeZahteviCount(),
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3PosiljkeZahteviScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // ─── DONJI DIO: Vozači s pazarom + Dužnici + Ukupno ───
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + MediaQuery.of(context).padding.bottom),
                  child: _buildPazarSection(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPazarSection(BuildContext context) {
    final vozaci = V3VozacService.getAllVozaci();
    final pazarPoVozacu = _getPazarPoVozacu();
    final sveDugovi = V3FinansijeService.getDugovi();
    // Dužnici = dnevni + pošiljke (naplata po pokupljenju)
    final dugovi = sveDugovi.where((d) => d.tipPutnika == 'dnevni' || d.tipPutnika == 'posiljka').toList();
    final dugoviIznos = dugovi.fold(0.0, (s, d) => s + d.iznos);
    final ukupnoPazar = pazarPoVozacu.values.fold(0.0, (s, v) => s + v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Lista vozača sa pazarom
        ...vozaci.map((v) {
          final boja = _bojaVozaca(v.id);
          final pazar = pazarPoVozacu[v.id] ?? 0.0;
          return Container(
            height: V3ContainerUtils.responsiveHeight(context, 56),
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: boja.withValues(alpha: 60 / 255),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: boja.withValues(alpha: 120 / 255)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: boja,
                  radius: 15,
                  child: Text(
                    v.imePrezime.isNotEmpty ? v.imePrezime[0] : '?',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: V3SafeText.userName(
                    v.imePrezime,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: boja),
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.monetization_on, color: boja, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '${pazar.toStringAsFixed(0)} RSD',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: boja),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),

        const SizedBox(height: 6),

        // Dužnici dugme
        InkWell(
          onTap: () => V3NavigationUtils.pushScreen<void>(
            context,
            const V3DugoviScreen(),
          ),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: V3ContainerUtils.responsiveHeight(context, 52),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _tr('duznici'),
                    style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                Text(
                  '${dugoviIznos.toStringAsFixed(0)} RSD',
                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.monetization_on, color: Colors.redAccent, size: 16),
              ],
            ),
          ),
        ),

        const SizedBox(height: 6),

        // Ukupan pazar
        V3ContainerUtils.styledContainer(
          height: V3ContainerUtils.responsiveHeight(context, 72),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          backgroundColor: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green.withValues(alpha: 0.5), width: 1.5),
          boxShadow: [
            BoxShadow(color: Colors.green.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4)),
          ],
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.account_balance_wallet, color: Colors.green[700], size: 22),
              const SizedBox(width: 10),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _tr('ukupanPazar'),
                    style: TextStyle(
                      color: Colors.green[800],
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    '${ukupnoPazar.toStringAsFixed(0)} RSD',
                    style: TextStyle(
                      color: Colors.green[900],
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Helper widget: kompaktni nav dugme h=40 (samo emoji)
// ─────────────────────────────────────────────
class _NavBtn extends StatelessWidget {
  const _NavBtn({
    required this.onTap,
    required this.child,
    this.color = Colors.blueGrey,
    this.height,
    this.width,
  });

  final VoidCallback onTap;
  final Widget child;
  final Color color;
  final double? height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: height ?? V3ContainerUtils.responsiveHeight(context, 50),
        width: width,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
        ),
        child: Center(child: child),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Helper widget: dugme s badge brojevima
// ─────────────────────────────────────────────
class _BadgeBtn extends StatelessWidget {
  const _BadgeBtn({
    required this.onTap,
    required this.emoji,
    required this.color,
    required this.badgeCount,
  });

  final VoidCallback onTap;
  final String emoji;
  final Color color;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: V3ContainerUtils.responsiveHeight(context, 50),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: color.withValues(alpha: badgeCount > 0 ? 0.9 : 0.6),
                width: 1.5,
              ),
            ),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
          ),
        ),
        if (badgeCount > 0)
          Positioned(
            right: 4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle),
              constraints: BoxConstraints(
                minWidth: V3ContainerUtils.responsiveHeight(context, 20),
                minHeight: V3ContainerUtils.responsiveHeight(context, 20),
              ),
              child: Text(
                '$badgeCount',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
