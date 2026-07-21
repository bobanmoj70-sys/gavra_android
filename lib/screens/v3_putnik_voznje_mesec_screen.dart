import 'package:flutter/material.dart';

import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_putnik_statistika_service.dart';
import '../services/v3_locale_manager.dart';
import '../theme.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_date_utils.dart';
import '../utils/v3_style_helper.dart';

class _VoznjeMesecTr {
  static const Map<String, Map<String, String>> _t = {
    'dnevniPregled': {
      'sr': 'Dnevni pregled vožnji',
      'en': 'Daily ride overview',
      'ru': 'Ежедневный обзор поездок',
      'de': 'Tägliche Fahrtenübersicht',
    },
    'nemaVoznji': {
      'sr': 'Nema vožnji u izabranom mesecu.',
      'en': 'No rides in the selected month.',
      'ru': 'В выбранном месяце нет поездок.',
      'de': 'Keine Fahrten im ausgewählten Monat.',
    },
    'voznji': {'sr': 'vožnji', 'en': 'rides', 'ru': 'поездок', 'de': 'Fahrten'},
    'voznja': {'sr': 'vožnja', 'en': 'ride', 'ru': 'поездка', 'de': 'Fahrt'},
    'voznje': {'sr': 'vožnje', 'en': 'rides', 'ru': 'поездки', 'de': 'Fahrten'},
    'uplata': {'sr': 'Uplata', 'en': 'Payment', 'ru': 'Оплата', 'de': 'Zahlung'},
    'vozac': {'sr': 'Vozač', 'en': 'Driver', 'ru': 'Водитель', 'de': 'Fahrer'},
    'pokupio': {'sr': 'Pokupio', 'en': 'Picked up', 'ru': 'Подобрал', 'de': 'Abgeholt'},
    'ukupno': {'sr': 'Ukupno', 'en': 'Total', 'ru': 'Всего', 'de': 'Gesamt'},
  };

  static String tr(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    return _t[key]?[code] ?? _t[key]?['sr'] ?? key;
  }

  static String _danNaziv(int weekday) {
    const sr = ['', 'Pon', 'Uto', 'Sre', 'Čet', 'Pet', 'Sub', 'Ned'];
    const en = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const ru = ['', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    const de = ['', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

    final code = V3LocaleManager().currentLocale.languageCode;
    final list = code == 'en'
        ? en
        : code == 'ru'
            ? ru
            : code == 'de'
                ? de
                : sr;
    if (weekday >= 1 && weekday <= 7) return list[weekday];
    return '';
  }
}

class V3PutnikVoznjeMesecScreen extends StatefulWidget {
  final String putnikId;
  final String imePrezime;
  final String tipPutnika;
  final int godina;
  final int mesec;

  const V3PutnikVoznjeMesecScreen({
    super.key,
    required this.putnikId,
    required this.imePrezime,
    required this.tipPutnika,
    required this.godina,
    required this.mesec,
  });

  @override
  State<V3PutnikVoznjeMesecScreen> createState() => _V3PutnikVoznjeMesecScreenState();
}

class _V3PutnikVoznjeMesecScreenState extends State<V3PutnikVoznjeMesecScreen> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: V3MasterRealtimeManager.instance
          .tablesRevisionStream(const ['v3_operativna_nedelja', 'v3_finansije', 'v3_auth']),
      builder: (context, _) {
        final stavke = V3PutnikStatistikaService.getDnevneStavkeZaMesec(
          putnikId: widget.putnikId,
          godina: widget.godina,
          mesec: widget.mesec,
          tipPutnika: widget.tipPutnika,
        );

        final ukupnoVoznji = stavke.fold<int>(0, (sum, s) => sum + s.brojVoznji);
        final ukupnoUplata = stavke.fold<double>(0, (sum, s) => sum + s.uplataIznos);

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              _VoznjeMesecTr.tr('dnevniPregled'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          body: V3ContainerUtils.backgroundContainer(
            gradient: Theme.of(context).backgroundGradient,
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: V3ContainerUtils.styledContainer(
                      padding: const EdgeInsets.all(14),
                      backgroundColor: V3StyleHelper.whiteAlpha06,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: V3StyleHelper.whiteAlpha13),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.imePrezime,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${V3DateUtils.mesecNaziv(widget.mesec)} ${widget.godina}',
                            style: TextStyle(
                              color: V3StyleHelper.whiteAlpha65,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _HeaderKpi(
                                  label: _VoznjeMesecTr.tr('voznji'),
                                  value: '$ukupnoVoznji',
                                  color: Colors.greenAccent,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _HeaderKpi(
                                  label: _VoznjeMesecTr.tr('uplata'),
                                  value: '${ukupnoUplata.toStringAsFixed(0)} RSD',
                                  color: Colors.blueAccent,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: stavke.isEmpty
                        ? Center(
                            child: Text(
                              _VoznjeMesecTr.tr('nemaVoznji'),
                              style: TextStyle(
                                color: V3StyleHelper.whiteAlpha65,
                                fontSize: 14,
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: stavke.length,
                            itemBuilder: (context, index) => _DnevnaStavkaRow(stavka: stavke[index]),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HeaderKpi extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _HeaderKpi({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return V3ContainerUtils.styledContainer(
      padding: const EdgeInsets.symmetric(vertical: 10),
      backgroundColor: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(color: V3StyleHelper.whiteAlpha65, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _DnevnaStavkaRow extends StatelessWidget {
  final V3PutnikDnevnaStavka stavka;

  const _DnevnaStavkaRow({required this.stavka});

  @override
  Widget build(BuildContext context) {
    final danNaziv = _VoznjeMesecTr._danNaziv(stavka.datum.weekday);
    final datumText =
        '${danNaziv}, ${stavka.datum.day.toString().padLeft(2, '0')}.${stavka.datum.month.toString().padLeft(2, '0')}.${stavka.datum.year}';

    return V3ContainerUtils.styledContainer(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      backgroundColor: V3StyleHelper.whiteAlpha06,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: V3StyleHelper.whiteAlpha13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                datumText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${stavka.brojVoznji} ${_brojVoznjiLabel(stavka.brojVoznji)}',
                style: TextStyle(
                  color: V3StyleHelper.whiteAlpha75,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (stavka.vozaciPokupljeni.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.person_outline, size: 14, color: V3StyleHelper.whiteAlpha65),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${_VoznjeMesecTr.tr('pokupio')}: ${stavka.vozaciPokupljeni.join(', ')}',
                    style: TextStyle(color: V3StyleHelper.whiteAlpha65, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
          if (stavka.imaUplatu) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _VoznjeMesecTr.tr('uplata'),
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${stavka.uplataIznos.toStringAsFixed(0)} RSD',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (stavka.uplatioVozac != null && stavka.uplatioVozac!.isNotEmpty)
                        Text(
                          '${_VoznjeMesecTr.tr('vozac')}: ${stavka.uplatioVozac}',
                          style: TextStyle(
                            color: Colors.greenAccent.withValues(alpha: 0.8),
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _brojVoznjiLabel(int broj) {
    if (broj == 1) return _VoznjeMesecTr.tr('voznja');
    if (broj >= 2 && broj <= 4) return _VoznjeMesecTr.tr('voznje');
    return _VoznjeMesecTr.tr('voznji');
  }
}
