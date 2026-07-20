import 'package:flutter/material.dart';

import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_putnik_statistika_service.dart';
import '../services/v3_locale_manager.dart';
import '../theme.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_style_helper.dart';

class _StatTr {
  static const Map<String, Map<String, String>> _t = {
    'detaljneStatistike': {
      'sr': 'Detaljne statistike',
      'en': 'Detailed statistics',
      'ru': 'Подробная статистика',
      'de': 'Detaillierte Statistik',
    },
    'tipRadnik': {
      'sr': 'Tip: Radnik (model po danu)',
      'en': 'Type: Worker (per-day model)',
      'ru': 'Тип: Рабочий (модель по дням)',
      'de': 'Typ: Arbeiter (Modell pro Tag)',
    },
    'tipUcenik': {
      'sr': 'Tip: Učenik (model po danu)',
      'en': 'Type: Student (per-day model)',
      'ru': 'Тип: Ученик (модель по дням)',
      'de': 'Typ: Schüler (Modell pro Tag)',
    },
    'tipPosiljka': {
      'sr': 'Tip: Pošiljka (model po vožnji)',
      'en': 'Type: Shipment (per-ride model)',
      'ru': 'Тип: Посылка (модель по поездкам)',
      'de': 'Typ: Sendung (Modell pro Fahrt)',
    },
    'tipDnevni': {
      'sr': 'Tip: Dnevni (model po vožnji)',
      'en': 'Type: Daily (per-ride model)',
      'ru': 'Тип: Ежедневный (модель по поездкам)',
      'de': 'Typ: Täglich (Modell pro Fahrt)',
    },
    'prikazPoMesecima': {
      'sr': 'Prikaz po mesecima (januar-decembar %s)',
      'en': 'Monthly view (January-December %s)',
      'ru': 'Ежемесячный просмотр (январь-декабрь %s)',
      'de': 'Monatsansicht (Januar-Dezember %s)',
    },
    'voznji': {'sr': 'Vožnji', 'en': 'Rides', 'ru': 'Поездки', 'de': 'Fahrten'},
    'otkazano': {'sr': 'Otkazano', 'en': 'Canceled', 'ru': 'Отменено', 'de': 'Storniert'},
    'obaveza': {'sr': 'Obaveza', 'en': 'Amount due', 'ru': 'Задолженность', 'de': 'Fälliger Betrag'},
    'placeno': {'sr': 'Plaćeno', 'en': 'Paid', 'ru': 'Оплачено', 'de': 'Bezahlt'},
    'dug': {'sr': 'Dug', 'en': 'Debt', 'ru': 'Долг', 'de': 'Schulden'},
    'ukupanDug': {
      'sr': 'Ukupan dug',
      'en': 'Total debt',
      'ru': 'Общий долг',
      'de': 'Gesamtschulden',
    },
    'poslednjaUplata': {
      'sr': 'Poslednja uplata',
      'en': 'Last payment',
      'ru': 'Последний платеж',
      'de': 'Letzte Zahlung',
    },
  };

  static String tr(String key, [String? arg]) {
    final code = V3LocaleManager().currentLocale.languageCode;
    var text = _t[key]?[code] ?? _t[key]?['sr'] ?? key;
    if (arg != null) text = text.replaceFirst('%s', arg);
    return text;
  }
}

class V3PutnikStatistikaScreen extends StatefulWidget {
  final String putnikId;
  final String imePrezime;
  final String tipPutnika;

  const V3PutnikStatistikaScreen({
    super.key,
    required this.putnikId,
    required this.imePrezime,
    required this.tipPutnika,
  });

  @override
  State<V3PutnikStatistikaScreen> createState() => _V3PutnikStatistikaScreenState();
}

class _V3PutnikStatistikaScreenState extends State<V3PutnikStatistikaScreen> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: V3MasterRealtimeManager.instance
          .tablesRevisionStream(const ['v3_operativna_nedelja', 'v3_finansije', 'v3_auth']),
      builder: (context, _) {
        final godina = DateTime.now().year;
        final meseci = V3PutnikStatistikaService.getZaGodinu(widget.putnikId, godina: godina);

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
            centerTitle: true,
            title: Text(_StatTr.tr('detaljneStatistike'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          body: V3ContainerUtils.backgroundContainer(
            gradient: Theme.of(context).backgroundGradient,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    V3ContainerUtils.styledContainer(
                      padding: const EdgeInsets.all(14),
                      backgroundColor: V3StyleHelper.whiteAlpha06,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: V3StyleHelper.whiteAlpha13),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.imePrezime,
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _tipLabel(widget.tipPutnika),
                            style:
                                TextStyle(color: V3StyleHelper.whiteAlpha65, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _StatTr.tr('prikazPoMesecima', '$godina'),
                            style: TextStyle(color: V3StyleHelper.whiteAlpha65, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...meseci.map((m) => _MesecCard(putnikId: widget.putnikId, stats: m)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _tipLabel(String tip) {
    final normalized = tip.toLowerCase();
    if (normalized == 'radnik') return _StatTr.tr('tipRadnik');
    if (normalized == 'ucenik') return _StatTr.tr('tipUcenik');
    if (normalized == 'posiljka') return _StatTr.tr('tipPosiljka');
    return _StatTr.tr('tipDnevni');
  }
}

class _MesecCard extends StatelessWidget {
  final String putnikId;
  final V3PutnikMesecnaStatistika stats;

  const _MesecCard({required this.putnikId, required this.stats});

  @override
  Widget build(BuildContext context) {
    final ukupanDug = V3PutnikStatistikaService.getUkupanDugZaSveMesece(putnikId);
    return V3ContainerUtils.styledContainer(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      backgroundColor: V3StyleHelper.whiteAlpha06,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: V3StyleHelper.whiteAlpha13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${stats.mesecNaziv} ${stats.godina}',
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _MiniKpi(label: _StatTr.tr('voznji'), value: '${stats.ukupnoVoznji}', color: Colors.greenAccent),
                const SizedBox(width: 12),
                _MiniKpi(label: _StatTr.tr('otkazano'), value: '${stats.otkazano}', color: Colors.redAccent),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (stats.cena > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_StatTr.tr('obaveza'), style: TextStyle(color: V3StyleHelper.whiteAlpha75, fontSize: 13)),
                Text(
                  '${stats.ukupnoVoznji} × ${stats.cena.toStringAsFixed(0)} = ${stats.ukupnaObaveza.toStringAsFixed(0)} RSD',
                  style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_StatTr.tr('placeno'), style: TextStyle(color: V3StyleHelper.whiteAlpha75, fontSize: 13)),
              Text(
                '${stats.naplacenoIznos.toStringAsFixed(0)} RSD',
                style: const TextStyle(color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${_StatTr.tr('dug')} (${stats.neplaceno})',
                  style: TextStyle(color: V3StyleHelper.whiteAlpha75, fontSize: 13)),
              Text(
                '${stats.dugIznos.toStringAsFixed(0)} RSD',
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (stats.poslednjaUplata != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_StatTr.tr('poslednjaUplata'), style: TextStyle(color: V3StyleHelper.whiteAlpha75, fontSize: 13)),
                Text(
                  stats.poslednjaUplataVozac != null && stats.poslednjaUplataVozac!.isNotEmpty
                      ? '${stats.poslednjaUplata!.day.toString().padLeft(2, '0')}.${stats.poslednjaUplata!.month.toString().padLeft(2, '0')}. (${stats.poslednjaUplataVozac})'
                      : '${stats.poslednjaUplata!.day.toString().padLeft(2, '0')}.${stats.poslednjaUplata!.month.toString().padLeft(2, '0')}.',
                  style: const TextStyle(color: Colors.blueAccent, fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_StatTr.tr('ukupanDug'), style: TextStyle(color: V3StyleHelper.whiteAlpha75, fontSize: 13)),
              Text(
                '${ukupanDug.toStringAsFixed(0)} RSD',
                style: const TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniKpi extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniKpi({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return V3ContainerUtils.styledContainer(
      width: 90,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      backgroundColor: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
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
}
