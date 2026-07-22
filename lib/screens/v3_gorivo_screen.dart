import 'package:flutter/material.dart';
import 'package:gavra_android/models/v3_gorivo.dart';
import 'package:gavra_android/services/realtime/v3_master_realtime_manager.dart';
import 'package:gavra_android/services/v3/v3_gorivo_service.dart';
import 'package:gavra_android/theme.dart';

import '../services/v3_locale_manager.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_format_utils.dart';

class _GorTr {
  static const Map<String, Map<String, String>> _t = {
    'gorivo': {'sr': 'Gorivo', 'en': 'Fuel', 'ru': 'Топливо', 'de': 'Kraftstoff'},
    'nemaRedaZaDopunu': {
      'sr': 'Nema reda za dopunu. Prvo dodaj početne podatke.',
      'en': 'No record to refill. First add initial data.',
      'ru': 'Нет записи для заправки. Сначала добавьте начальные данные.',
      'de': 'Kein Eintrag zum Auffüllen. Zuerst Anfangsdaten hinzufügen.',
    },
    'dodajGorivo': {'sr': 'Dodaj gorivo', 'en': 'Add fuel', 'ru': 'Добавить топливо', 'de': 'Kraftstoff hinzufügen'},
    'trenutnoKapacitet': {
      'sr': 'Trenutno',
      'en': 'Current',
      'ru': 'Текущее',
      'de': 'Aktuell',
    },
    'kapacitet': {'sr': 'kapacitet', 'en': 'capacity', 'ru': 'ёмкость', 'de': 'Kapazität'},
    'kolikoLitaraJeDopunjeno': {
      'sr': 'Koliko litara je dopunjeno (L)',
      'en': 'How many liters were refilled (L)',
      'ru': 'Сколько литров было заправлено (л)',
      'de': 'Wie viele Liter wurden nachgefüllt (L)',
    },
    'otkazi': {'sr': 'Otkaži', 'en': 'Cancel', 'ru': 'Отмена', 'de': 'Abbrechen'},
    'unesiPozitivanBrojLitara': {
      'sr': 'Unesi pozitivan broj litara.',
      'en': 'Enter a positive number of liters.',
      'ru': 'Введите положительное число литров.',
      'de': 'Geben Sie eine positive Literzahl ein.',
    },
    'prekoracenjeKapaciteta': {
      'sr': 'Prekoračenje kapaciteta',
      'en': 'Capacity exceeded',
      'ru': 'Превышение ёмкости',
      'de': 'Kapazität überschritten',
    },
    'novoStanjeQPremasujeKapacitet': {
      'sr': 'Novo stanje %NOVO% L premašuje kapacitet %KAP% L.\n\nIpak dodati?',
      'en': 'New level %NOVO% L exceeds capacity %KAP% L.\n\nAdd anyway?',
      'ru': 'Новый уровень %NOVO% л превышает ёмкость %KAP% л.\n\nВсё равно добавить?',
      'de': 'Neuer Stand %NOVO% L überschreitet die Kapazität %KAP% L.\n\nTrotzdem hinzufügen?',
    },
    'ne': {'sr': 'Ne', 'en': 'No', 'ru': 'Нет', 'de': 'Nein'},
    'da': {'sr': 'Da', 'en': 'Yes', 'ru': 'Да', 'de': 'Ja'},
    'dodaj': {'sr': 'Dodaj', 'en': 'Add', 'ru': 'Добавить', 'de': 'Hinzufügen'},
    'gorivoDodatoNovoStanje': {
      'sr': 'Gorivo dodato. Novo stanje: %NOVO% L',
      'en': 'Fuel added. New level: %NOVO% L',
      'ru': 'Топливо добавлено. Новый уровень: %NOVO% л',
      'de': 'Kraftstoff hinzugefügt. Neuer Stand: %NOVO% L',
    },
    'greskaPriDodavanjuGoriva': {
      'sr': 'Greška pri dodavanju goriva.',
      'en': 'Error adding fuel.',
      'ru': 'Ошибка при добавлении топлива.',
      'de': 'Fehler beim Hinzufügen von Kraftstoff.',
    },
    'nemaRedaZaIzmenu': {
      'sr': 'Nema reda za izmenu. Prvo dodaj početne podatke.',
      'en': 'No record to edit. First add initial data.',
      'ru': 'Нет записи для изменения. Сначала добавьте начальные данные.',
      'de': 'Kein Eintrag zum Bearbeiten. Zuerst Anfangsdaten hinzufügen.',
    },
    'urediGorivo': {'sr': 'Uredi gorivo', 'en': 'Edit fuel', 'ru': 'Изменить топливо', 'de': 'Kraftstoff bearbeiten'},
    'kapacitetRezervoaraL': {
      'sr': 'Kapacitet rezervoara (L)',
      'en': 'Tank capacity (L)',
      'ru': 'Ёмкость бака (л)',
      'de': 'Tankkapazität (L)',
    },
    'alarmNivoL': {
      'sr': 'Alarm nivo (L)',
      'en': 'Alarm level (L)',
      'ru': 'Уровень тревоги (л)',
      'de': 'Alarmstand (L)'
    },
    'brojacPistoljaL': {
      'sr': 'Brojač pištolja (L)',
      'en': 'Nozzle counter (L)',
      'ru': 'Счётчик пистолета (л)',
      'de': 'Zapfpistolenzähler (L)',
    },
    'trenutnoStanjeSeRacunaAutomatski': {
      'sr': 'Upiši novo (rastuće) očitanje sa pištolja. Trenutno stanje se automatski umanjuje za razliku (potrošnju).',
      'en': 'Enter the new (increasing) nozzle reading. Current level is automatically reduced by the difference (consumption).',
      'ru': 'Введите новое (возрастающее) показание пистолета. Текущий уровень автоматически уменьшается на разницу (расход).',
      'de': 'Neuen (steigenden) Zapfpistolenstand eingeben. Der aktuelle Stand wird automatisch um die Differenz (Verbrauch) verringert.',
    },
    'cenaPoLitru': {
      'sr': 'Cena po litru (RSD)',
      'en': 'Price per liter (RSD)',
      'ru': 'Цена за литр (RSD)',
      'de': 'Preis pro Liter (RSD)'
    },
    'dugRsd': {'sr': 'Dug (RSD)', 'en': 'Debt (RSD)', 'ru': 'Долг (RSD)', 'de': 'Schulden (RSD)'},
    'vrednostiNeMoguBitiNegativne': {
      'sr': 'Vrednosti ne mogu biti negativne.',
      'en': 'Values cannot be negative.',
      'ru': 'Значения не могут быть отрицательными.',
      'de': 'Werte dürfen nicht negativ sein.',
    },
    'podaciOGorivuSuSacuvani': {
      'sr': 'Podaci o gorivu su sačuvani.',
      'en': 'Fuel data saved.',
      'ru': 'Данные о топливе сохранены.',
      'de': 'Kraftstoffdaten gespeichert.',
    },
    'greskaPriCuvanjuPodataka': {
      'sr': 'Greška pri čuvanju podataka.',
      'en': 'Error saving data.',
      'ru': 'Ошибка при сохранении данных.',
      'de': 'Fehler beim Speichern der Daten.',
    },
    'sacuvaj': {'sr': 'Sačuvaj', 'en': 'Save', 'ru': 'Сохранить', 'de': 'Speichern'},
    'obaveznoPolje': {'sr': 'Obavezno polje', 'en': 'Required field', 'ru': 'Обязательное поле', 'de': 'Pflichtfeld'},
    'unesiBroj': {'sr': 'Unesi broj', 'en': 'Enter a number', 'ru': 'Введите число', 'de': 'Zahl eingeben'},
    'pocetniPodaciZaGorivoSuKreirani': {
      'sr': 'Početni podaci za gorivo su kreirani.',
      'en': 'Initial fuel data has been created.',
      'ru': 'Начальные данные о топливе созданы.',
      'de': 'Anfängliche Kraftstoffdaten wurden erstellt.',
    },
    'neuspesnoKreiranjePocetnihPodataka': {
      'sr': 'Neuspešno kreiranje početnih podataka.',
      'en': 'Failed to create initial data.',
      'ru': 'Не удалось создать начальные данные.',
      'de': 'Erstellen der Anfangsdaten fehlgeschlagen.',
    },
    'dodavanjeDots': {'sr': 'Dodavanje...', 'en': 'Adding...', 'ru': 'Добавление...', 'de': 'Wird hinzugefügt...'},
    'nemaPodatakaOGorivuUBazi': {
      'sr': 'Nema podataka o gorivu u bazi',
      'en': 'No fuel data in the database',
      'ru': 'Нет данных о топливе в базе',
      'de': 'Keine Kraftstoffdaten in der Datenbank',
    },
    'kreiranjeDots': {'sr': 'Kreiranje...', 'en': 'Creating...', 'ru': 'Создание...', 'de': 'Wird erstellt...'},
    'dodajPocetnePodatke': {
      'sr': 'Dodaj početne podatke',
      'en': 'Add initial data',
      'ru': 'Добавить начальные данные',
      'de': 'Anfangsdaten hinzufügen',
    },
    'alarmNivoRezervoara': {
      'sr': '🔔 Alarm nivo rezervoara',
      'en': '🔔 Tank alarm level',
      'ru': '🔔 Уровень тревоги бака',
      'de': '🔔 Tank-Alarmstand',
    },
    'stanjeBrojacaPistolja': {
      'sr': '🔫 Stanje brojača pištolja',
      'en': '🔫 Nozzle counter state',
      'ru': '🔫 Состояние счётчика пистолета',
      'de': '🔫 Zapfpistolenzählerstand',
    },
    'cenaPoLitruEmoji': {
      'sr': '💰 Cena po litru',
      'en': '💰 Price per liter',
      'ru': '💰 Цена за литр',
      'de': '💰 Preis pro Liter',
    },
    'dugIznos': {
      'sr': '💳 Dug (iznos)',
      'en': '💳 Debt (amount)',
      'ru': '💳 Долг (сумма)',
      'de': '💳 Schulden (Betrag)'
    },
    'uneziIzmeniPodatke': {
      'sr': 'Unesi / izmeni podatke',
      'en': 'Enter / edit data',
      'ru': 'Ввести / изменить данные',
      'de': 'Daten eingeben / bearbeiten',
    },
    'maloGoriva': {'sr': '⚠️ MALO GORIVA', 'en': '⚠️ LOW FUEL', 'ru': '⚠️ МАЛО ТОПЛИВА', 'de': '⚠️ WENIG KRAFTSTOFF'},
    'odKapaciteta': {'sr': 'od', 'en': 'of', 'ru': 'из', 'de': 'von'},
    'kapacitetaL': {'sr': 'kapaciteta', 'en': 'capacity', 'ru': 'ёмкости', 'de': 'Kapazität'},
  };

  static String tr(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    return _t[key]?[code] ?? _t[key]?['sr'] ?? key;
  }
}

class V3GorivoScreen extends StatefulWidget {
  const V3GorivoScreen({super.key});

  @override
  State<V3GorivoScreen> createState() => _V3GorivoScreenState();
}

class _V3GorivoScreenState extends State<V3GorivoScreen> {
  static const Color _accent = Color(0xFFFF9800);
  bool _isCreatingInitialData = false;
  bool _isSavingFuelData = false;
  bool _isDodavanjeGoriva = false;

  double? _toDoubleOrNull(String input) {
    final normalized = input.trim().replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  Future<void> _openDopunaSheet({required V3PumpaRezervoar? rezervoar, required V3PumpaStanje? stanje}) async {
    final String? id =
        stanje?.id.isNotEmpty == true ? stanje!.id : (rezervoar?.id.isNotEmpty == true ? rezervoar!.id : null);
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_GorTr.tr('nemaRedaZaDopunu'))),
      );
      return;
    }

    final trenutno = stanje?.trenutnoStanje ?? rezervoar?.trenutnoLitara ?? 0;
    final kapacitet = stanje?.kapacitetLitri ?? rezervoar?.kapacitetMax ?? 0;
    final dodatoCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: V3ContainerUtils.styledContainer(
            backgroundColor: const Color(0xFF1D1D1D),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: Theme.of(context).glassBorder),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _GorTr.tr('dodajGorivo'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_GorTr.tr('trenutnoKapacitet')}: ${V3FormatUtils.formatGorivo(trenutno)} L / ${_GorTr.tr('kapacitet')} ${V3FormatUtils.formatGorivo(kapacitet)} L',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      _fuelField(controller: dodatoCtrl, label: _GorTr.tr('kolikoLitaraJeDopunjeno')),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isDodavanjeGoriva ? null : () => Navigator.of(context).pop(),
                              child: Text(_GorTr.tr('otkazi')),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isDodavanjeGoriva
                                  ? null
                                  : () async {
                                      if (formKey.currentState?.validate() != true) return;

                                      final dodato = _toDoubleOrNull(dodatoCtrl.text)!;
                                      if (dodato <= 0) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text(_GorTr.tr('unesiPozitivanBrojLitara'))),
                                        );
                                        return;
                                      }

                                      final novoStanje = trenutno + dodato;
                                      if (novoStanje > kapacitet) {
                                        final potvrda = await showDialog<bool>(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            backgroundColor: const Color(0xFF1D1D1D),
                                            title: Text(_GorTr.tr('prekoracenjeKapaciteta'),
                                                style: const TextStyle(color: Colors.white)),
                                            content: Text(
                                              _GorTr.tr('novoStanjeQPremasujeKapacitet')
                                                  .replaceAll('%NOVO%', V3FormatUtils.formatGorivo(novoStanje))
                                                  .replaceAll('%KAP%', V3FormatUtils.formatGorivo(kapacitet)),
                                              style: const TextStyle(color: Colors.white70),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(context, false),
                                                child: Text(_GorTr.tr('ne')),
                                              ),
                                              ElevatedButton(
                                                onPressed: () => Navigator.pop(context, true),
                                                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                                                child: Text(_GorTr.tr('da')),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (potvrda != true) return;
                                      }

                                      setState(() => _isDodavanjeGoriva = true);
                                      final success = await V3GorivoService.updateRezervoar(id, novoStanje);
                                      if (!mounted) return;

                                      setState(() => _isDodavanjeGoriva = false);
                                      Navigator.of(context).pop();
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            success
                                                ? _GorTr.tr('gorivoDodatoNovoStanje')
                                                    .replaceAll('%NOVO%', V3FormatUtils.formatGorivo(novoStanje))
                                                : _GorTr.tr('greskaPriDodavanjuGoriva'),
                                          ),
                                        ),
                                      );
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              child: _isDodavanjeGoriva
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : Text(_GorTr.tr('dodaj')),
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
        );
      },
    );
  }

  Future<void> _openEditFuelDataSheet({required V3PumpaRezervoar? rezervoar, required V3PumpaStanje? stanje}) async {
    final String? id =
        stanje?.id.isNotEmpty == true ? stanje!.id : (rezervoar?.id.isNotEmpty == true ? rezervoar!.id : null);
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_GorTr.tr('nemaRedaZaIzmenu'))),
      );
      return;
    }

    final kapacitetCtrl = TextEditingController(
      text: (stanje?.kapacitetLitri ?? rezervoar?.kapacitetMax ?? 3000).toStringAsFixed(1),
    );
    final alarmCtrl = TextEditingController(
      text: (stanje?.alarmNivoLitri ?? rezervoar?.alarmNivo ?? 500).toStringAsFixed(1),
    );
    final brojacCtrl = TextEditingController(
      text: (stanje?.stanjeBrojacPistolj ?? 0).toStringAsFixed(1),
    );
    final cenaCtrl = TextEditingController(
      text: (stanje?.cenaPoLitru ?? 0).toStringAsFixed(2),
    );
    final dugCtrl = TextEditingController(
      text: (stanje?.dugIznos ?? 0).toStringAsFixed(2),
    );
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: V3ContainerUtils.styledContainer(
            backgroundColor: const Color(0xFF1D1D1D),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: Theme.of(context).glassBorder),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _GorTr.tr('urediGorivo'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 12),
                      _fuelField(controller: kapacitetCtrl, label: _GorTr.tr('kapacitetRezervoaraL')),
                      _fuelField(controller: alarmCtrl, label: _GorTr.tr('alarmNivoL')),
                      _fuelField(controller: brojacCtrl, label: _GorTr.tr('brojacPistoljaL')),
                      Text(
                        _GorTr.tr('trenutnoStanjeSeRacunaAutomatski'),
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      _fuelField(controller: cenaCtrl, label: _GorTr.tr('cenaPoLitru')),
                      _fuelField(controller: dugCtrl, label: _GorTr.tr('dugRsd')),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isSavingFuelData ? null : () => Navigator.of(context).pop(),
                              child: Text(_GorTr.tr('otkazi')),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isSavingFuelData
                                  ? null
                                  : () async {
                                      if (formKey.currentState?.validate() != true) return;

                                      final kapacitet = _toDoubleOrNull(kapacitetCtrl.text)!;
                                      final alarm = _toDoubleOrNull(alarmCtrl.text)!;
                                      final brojac = _toDoubleOrNull(brojacCtrl.text)!;
                                      final cena = _toDoubleOrNull(cenaCtrl.text)!;
                                      final dug = _toDoubleOrNull(dugCtrl.text)!;

                                      if (kapacitet < 0 || alarm < 0 || brojac < 0 || cena < 0 || dug < 0) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text(_GorTr.tr('vrednostiNeMoguBitiNegativne'))),
                                        );
                                        return;
                                      }

                                      setState(() => _isSavingFuelData = true);
                                      final success = await V3GorivoService.updateAllFields(
                                        id: id,
                                        kapacitetLitri: kapacitet,
                                        alarmNivoLitri: alarm,
                                        brojacPistoljLitri: brojac,
                                        cenaPoLitru: cena,
                                        dugIznos: dug,
                                      );
                                      if (!mounted) return;

                                      setState(() => _isSavingFuelData = false);
                                      Navigator.of(context).pop();
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            success
                                                ? _GorTr.tr('podaciOGorivuSuSacuvani')
                                                : _GorTr.tr('greskaPriCuvanjuPodataka'),
                                          ),
                                        ),
                                      );
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _accent,
                                foregroundColor: Colors.black,
                              ),
                              child: _isSavingFuelData
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Text(_GorTr.tr('sacuvaj')),
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
        );
      },
    );
  }

  Widget _fuelField({required TextEditingController controller, required String label}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return _GorTr.tr('obaveznoPolje');
          }
          if (_toDoubleOrNull(value) == null) {
            return _GorTr.tr('unesiBroj');
          }
          return null;
        },
      ),
    );
  }

  Future<void> _createInitialData() async {
    if (_isCreatingInitialData) return;

    setState(() => _isCreatingInitialData = true);
    final success = await V3GorivoService.ensureInitialData();
    if (!mounted) return;

    setState(() => _isCreatingInitialData = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? _GorTr.tr('pocetniPodaciZaGorivoSuKreirani') : _GorTr.tr('neuspesnoKreiranjePocetnihPodataka'),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<_GorivoData>(
      stream: V3MasterRealtimeManager.instance.v3StreamFromRevisions<_GorivoData>(
        tables: ['v3_gorivo'],
        build: () => _GorivoData(
          stanje: V3GorivoService.getStanjeSync(),
          rezervoar: V3GorivoService.getRezervoarSync(),
        ),
      ),
      builder: (context, snapshot) {
        final data = snapshot.data ??
            _GorivoData(
              stanje: V3GorivoService.getStanjeSync(),
              rezervoar: V3GorivoService.getRezervoarSync(),
            );
        return _buildScaffold(context, data);
      },
    );
  }

  Widget _buildScaffold(BuildContext context, _GorivoData data) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: Theme.of(context).backgroundGradient,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).glassBorder),
            ),
          ),
        ),
        title: Text(
          _GorTr.tr('gorivo'),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
          ),
        ),
      ),
      body: V3ContainerUtils.backgroundContainer(
        gradient: Theme.of(context).backgroundGradient,
        child: _buildBody(data.rezervoar, data.stanje),
      ),
    );
  }

  Widget _buildBody(V3PumpaRezervoar? r, V3PumpaStanje? stanje) {
    final media = MediaQuery.of(context);
    final bool isCompact = media.size.width < 360;
    final double? kapacitet = stanje?.kapacitetLitri ?? r?.kapacitetMax;
    final double? trenutno = stanje?.trenutnoStanje ?? r?.trenutnoLitara;
    final double? alarmNivo = stanje?.alarmNivoLitri ?? r?.alarmNivo;
    final bool hasFuelData = kapacitet != null && trenutno != null && alarmNivo != null;
    final bool ispodAlarma = hasFuelData ? (trenutno <= alarmNivo) : false;
    final double procenat = hasFuelData && kapacitet > 0 ? ((trenutno / kapacitet).clamp(0.0, 1.0)) : 0.0;

    final topPad = media.padding.top + kToolbarHeight + (isCompact ? 12 : 16);
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(isCompact ? 12 : 16, topPad, isCompact ? 12 : 16, isCompact ? 12 : 16),
      child: Column(
        children: [
          if (hasFuelData) ...[
            _V3BrojcanikCard(
              trenutno: trenutno,
              kapacitet: kapacitet,
              procenat: procenat,
              ispodAlarma: ispodAlarma,
            ),
            SizedBox(height: isCompact ? 10 : 12),
            Align(
              alignment: Alignment.center,
              child: ElevatedButton.icon(
                onPressed: _isDodavanjeGoriva ? null : () => _openDopunaSheet(rezervoar: r, stanje: stanje),
                icon: _isDodavanjeGoriva
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.add_circle_outline),
                label: Text(_isDodavanjeGoriva ? _GorTr.tr('dodavanjeDots') : _GorTr.tr('dodajGorivo')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            SizedBox(height: isCompact ? 12 : 16),
          ] else ...[
            Padding(
              padding: EdgeInsets.symmetric(vertical: isCompact ? 16 : 24),
              child: Column(
                children: [
                  Text(_GorTr.tr('nemaPodatakaOGorivuUBazi'), style: const TextStyle(color: Colors.white70)),
                  SizedBox(height: isCompact ? 8 : 12),
                  ElevatedButton.icon(
                    onPressed: _isCreatingInitialData ? null : _createInitialData,
                    icon: _isCreatingInitialData
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                    label: Text(_isCreatingInitialData ? _GorTr.tr('kreiranjeDots') : _GorTr.tr('dodajPocetnePodatke')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ],
          _V3DetaljiCard(
            children: [
              _gorivoDetaljiRow(
                _GorTr.tr('alarmNivoRezervoara'),
                hasFuelData ? '${V3FormatUtils.formatGorivo(alarmNivo)} L' : '-',
                hasFuelData ? (ispodAlarma ? Colors.redAccent : Colors.white54) : Colors.white70,
              ),
              if (stanje != null) ...[
                _gorivoDetaljiRow(
                  _GorTr.tr('stanjeBrojacaPistolja'),
                  '${V3FormatUtils.formatGorivo(stanje.stanjeBrojacPistolj)} L',
                  Colors.white70,
                ),
                _gorivoDetaljiRow(
                  _GorTr.tr('cenaPoLitruEmoji'),
                  '${stanje.cenaPoLitru.toStringAsFixed(2)} RSD',
                  Colors.amberAccent,
                ),
                _gorivoDetaljiRow(
                  _GorTr.tr('dugIznos'),
                  '${stanje.dugIznos.toStringAsFixed(2)} RSD',
                  stanje.dugIznos > 0 ? Colors.redAccent : Colors.greenAccent,
                ),
              ] else ...[
                _gorivoDetaljiRow(_GorTr.tr('stanjeBrojacaPistolja'), '-', Colors.white70),
                _gorivoDetaljiRow(_GorTr.tr('cenaPoLitruEmoji'), '-', Colors.white70),
                _gorivoDetaljiRow(_GorTr.tr('dugIznos'), '-', Colors.white70),
              ],
            ],
          ),
          if (stanje != null || r != null) ...[
            SizedBox(height: isCompact ? 10 : 12),
            Align(
              alignment: Alignment.center,
              child: ElevatedButton.icon(
                onPressed: _isSavingFuelData ? null : () => _openEditFuelDataSheet(rezervoar: r, stanje: stanje),
                icon: const Icon(Icons.edit),
                label: Text(_GorTr.tr('uneziIzmeniPodatke')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.black,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── helper ─────────────────────────────────────────────────────────────────

Widget _gorivoDetaljiRow(String label, String value, Color valueColor) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, color: valueColor, fontSize: 13),
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

// ─── Kartice ────────────────────────────────────────────────────────────────

class _V3BrojcanikCard extends StatelessWidget {
  const _V3BrojcanikCard({
    required this.trenutno,
    required this.kapacitet,
    required this.procenat,
    required this.ispodAlarma,
  });

  final double trenutno;
  final double kapacitet;
  final double procenat;
  final bool ispodAlarma;

  static const Color _accent = Color(0xFFFF9800);

  @override
  Widget build(BuildContext context) {
    final bool isCompact = MediaQuery.of(context).size.width < 360;
    final Color barColor = ispodAlarma
        ? Colors.red
        : procenat > 0.6
            ? Colors.green
            : Colors.orange;

    return V3ContainerUtils.styledContainer(
      backgroundColor: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: barColor.withValues(alpha: 0.5), width: 2),
      boxShadow: [
        BoxShadow(color: barColor.withValues(alpha: 0.15), blurRadius: 16, spreadRadius: 1),
      ],
      child: Padding(
        padding: EdgeInsets.all(isCompact ? 14 : 20),
        child: Column(
          children: [
            if (ispodAlarma) ...[
              Align(
                alignment: Alignment.centerRight,
                child: V3ContainerUtils.iconContainer(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  backgroundColor: Colors.red.withValues(alpha: 0.15),
                  borderRadiusGeometry: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red),
                  child: Text(
                    _GorTr.tr('maloGoriva'),
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              SizedBox(height: isCompact ? 8 : 12),
            ],
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${V3FormatUtils.formatGorivo(trenutno)} L',
                style: TextStyle(fontSize: isCompact ? 40 : 48, fontWeight: FontWeight.bold, color: barColor),
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${_GorTr.tr('odKapaciteta')} ${V3FormatUtils.formatGorivo(kapacitet)} L ${_GorTr.tr('kapacitetaL')}',
                style: TextStyle(color: Colors.white54, fontSize: isCompact ? 13 : 14),
              ),
            ),
            SizedBox(height: isCompact ? 12 : 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: procenat,
                minHeight: V3ContainerUtils.responsiveHeight(context, isCompact ? 18 : 24),
                backgroundColor: Colors.grey.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('0 L', style: TextStyle(color: Colors.white38, fontSize: 12)),
                Text(
                  '${(procenat * 100).toStringAsFixed(0)}%',
                  style: TextStyle(fontWeight: FontWeight.bold, color: barColor),
                ),
                Text(
                  '${V3FormatUtils.formatGorivo(kapacitet)} L',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _V3DetaljiCard extends StatelessWidget {
  const _V3DetaljiCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final bool isCompact = MediaQuery.of(context).size.width < 360;
    return V3ContainerUtils.styledContainer(
      backgroundColor: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Theme.of(context).glassBorder),
      child: Padding(
        padding: EdgeInsets.all(isCompact ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...children,
          ],
        ),
      ),
    );
  }
}

// ─── Data holder ─────────────────────────────────────────────────────────────

class _GorivoData {
  final V3PumpaStanje? stanje;
  final V3PumpaRezervoar? rezervoar;
  _GorivoData({required this.stanje, required this.rezervoar});
}
