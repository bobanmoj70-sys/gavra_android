import 'dart:async';

import 'package:flutter/material.dart';

import '../models/v3_finansije.dart';
import '../models/v3_kredit.dart';
import '../screens/v3_krediti_screen.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_finansije_service.dart';
import '../services/v3/v3_kredit_service.dart';
import '../services/v3_locale_manager.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dan_helper.dart';
import '../utils/v3_date_utils.dart';
import '../utils/v3_dialog_helper.dart';
import '../utils/v3_error_utils.dart';
import '../utils/v3_format_utils.dart';
import '../utils/v3_input_utils.dart';
import '../utils/v3_state_utils.dart';

class _FinTr {
  static const Map<String, Map<String, String>> _t = {
    'finansije': {'sr': 'Finansije', 'en': 'Finances', 'ru': 'Финансы', 'de': 'Finanzen'},
    'potrazivanjaDugovi': {
      'sr': 'Potraživanja (Dugovi)',
      'en': 'Receivables (Debts)',
      'ru': 'Дебиторская задолженность (Долги)',
      'de': 'Forderungen (Schulden)',
    },
    'neplaceneVoznjeSvihPutnika': {
      'sr': 'Neplaćene vožnje svih putnika',
      'en': 'Unpaid rides of all passengers',
      'ru': 'Неоплаченные поездки всех пассажиров',
      'de': 'Unbezahlte Fahrten aller Passagiere',
    },
    'krediti': {'sr': 'Krediti', 'en': 'Loans', 'ru': 'Кредиты', 'de': 'Kredite'},
    'preostaliDugZaKredite': {
      'sr': 'Preostali dug za kredite',
      'en': 'Remaining loan debt',
      'ru': 'Остаток долга по кредитам',
      'de': 'Verbleibende Kreditschuld',
    },
    'danas': {'sr': 'Danas', 'en': 'Today', 'ru': 'Сегодня', 'de': 'Heute'},
    'ovaNedelja': {'sr': 'Ova nedelja', 'en': 'This week', 'ru': 'Эта неделя', 'de': 'Diese Woche'},
    'ovajMesec': {'sr': 'Ovaj mesec', 'en': 'This month', 'ru': 'Этот месяц', 'de': 'Dieser Monat'},
    'ovaGodina': {'sr': 'Ova godina', 'en': 'This year', 'ru': 'Этот год', 'de': 'Dieses Jahr'},
    'ceoGodisnjiBilans': {
      'sr': 'Ceo godišnji bilans',
      'en': 'Full yearly balance',
      'ru': 'Полный годовой баланс',
      'de': 'Gesamte Jahresbilanz',
    },
    'uplata': {'sr': 'uplata', 'en': 'payments', 'ru': 'платежей', 'de': 'Zahlungen'},
    'prihod': {'sr': 'Prihod', 'en': 'Income', 'ru': 'Доход', 'de': 'Einnahmen'},
    'troskovi': {'sr': 'Troškovi', 'en': 'Expenses', 'ru': 'Расходы', 'de': 'Ausgaben'},
    'neto': {'sr': 'NETO', 'en': 'NET', 'ru': 'НЕТТО', 'de': 'NETTO'},
    'mesecniTroskovi': {
      'sr': '📋 Mesečni troškovi',
      'en': '📋 Monthly expenses',
      'ru': '📋 Ежемесячные расходы',
      'de': '📋 Monatliche Ausgaben',
    },
    'nemaTroskovaZaOvajMesec': {
      'sr': 'Nema troškova za ovaj mesec',
      'en': 'No expenses for this month',
      'ru': 'Нет расходов за этот месяц',
      'de': 'Keine Ausgaben für diesen Monat',
    },
    'dodajTroskove': {
      'sr': 'Dodaj troškove',
      'en': 'Add expenses',
      'ru': 'Добавить расходы',
      'de': 'Ausgaben hinzufügen'
    },
    'unesiIznosDodas': {
      'sr': 'Unesi iznos koji želiš da DODAŠ na trenutni trošak.',
      'en': 'Enter the amount you want to ADD to the current expense.',
      'ru': 'Введите сумму, которую хотите ДОБАВИТЬ к текущему расходу.',
      'de': 'Geben Sie den Betrag ein, den Sie zur aktuellen Ausgabe HINZUFÜGEN möchten.',
    },
    'trenutno': {'sr': 'Trenutno:', 'en': 'Current:', 'ru': 'Текущее:', 'de': 'Aktuell:'},
    'dodajDots': {'sr': 'Dodaj...', 'en': 'Add...', 'ru': 'Добавить...', 'de': 'Hinzufügen...'},
    'troskoviDodati': {
      'sr': '✅ Troškovi dodati',
      'en': '✅ Expenses added',
      'ru': '✅ Расходы добавлены',
      'de': '✅ Ausgaben hinzugefügt',
    },
    'katGorivo': {'sr': 'Gorivo', 'en': 'Fuel', 'ru': 'Топливо', 'de': 'Kraftstoff'},
    'katOdrzavanje': {'sr': 'Održavanje', 'en': 'Maintenance', 'ru': 'Обслуживание', 'de': 'Wartung'},
    'katPlate': {'sr': 'Plate', 'en': 'Salaries', 'ru': 'Зарплаты', 'de': 'Gehälter'},
    'katKredit': {'sr': 'Kredit', 'en': 'Loan', 'ru': 'Кредит', 'de': 'Kredit'},
    'katRegistracija': {'sr': 'Registracija', 'en': 'Registration', 'ru': 'Регистрация', 'de': 'Zulassung'},
    'katYuAuto': {'sr': 'YU auto', 'en': 'YU auto', 'ru': 'YU авто', 'de': 'YU Auto'},
    'katMajstori': {'sr': 'Majstori', 'en': 'Repairmen', 'ru': 'Мастера', 'de': 'Handwerker'},
    'katPorez': {'sr': 'Porez', 'en': 'Tax', 'ru': 'Налог', 'de': 'Steuer'},
    'katAlimentacija': {'sr': 'Alimentacija', 'en': 'Child support', 'ru': 'Алименты', 'de': 'Unterhalt'},
    'katRacuni': {'sr': 'Računi', 'en': 'Bills', 'ru': 'Счета', 'de': 'Rechnungen'},
    'katOstalo': {'sr': 'Ostalo', 'en': 'Other', 'ru': 'Прочее', 'de': 'Sonstiges'},
  };

  static String tr(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    return _t[key]?[code] ?? _t[key]?['sr'] ?? key;
  }
}

/// FINANSIJE — V3
/// Prihodi/Rashodi: v3_finansije cache (tip = prihod/rashod)
/// Potraživanja: V3FinansijeService.getDugovi()
class V3FinansijeScreen extends StatefulWidget {
  const V3FinansijeScreen({super.key});

  @override
  State<V3FinansijeScreen> createState() => _V3FinansijeScreenState();
}

// ─── Podaci ───────────────────────────────────────────────────────────────────

class _V3IzvestajData {
  final double potrazivanjaIznos;
  final double kreditiIznos;
  final double prihodDanas;
  final double trosakDanas;
  final int voznjiDanas;
  final double prihodNedelja;
  final double trosakNedelja;
  final int voznjiNedelja;
  final double prihodMesec;
  final double trosakMesec;
  final int voznjiMesec;
  final double prihodGodina;
  final double trosakGodina;
  final int voznjiGodina;
  final Map<String, double> troskoviPoKategoriji;
  final String danasPeriod;
  final String nedeljaPeriod;
  final int godinaBroj;

  const _V3IzvestajData({
    required this.potrazivanjaIznos,
    required this.kreditiIznos,
    required this.prihodDanas,
    required this.trosakDanas,
    required this.voznjiDanas,
    required this.prihodNedelja,
    required this.trosakNedelja,
    required this.voznjiNedelja,
    required this.prihodMesec,
    required this.trosakMesec,
    required this.voznjiMesec,
    required this.prihodGodina,
    required this.trosakGodina,
    required this.voznjiGodina,
    required this.troskoviPoKategoriji,
    required this.danasPeriod,
    required this.nedeljaPeriod,
    required this.godinaBroj,
  });
}

_V3IzvestajData _buildIzvestaj() {
  final now = DateTime.now();
  final rm = V3MasterRealtimeManager.instance;
  final finansijeCache = rm.getCache('v3_finansije').values;

  // Dan
  final danas = V3DanHelper.dateOnlyFrom(now.year, now.month, now.day);
  final sutra = danas.add(const Duration(days: 1));

  // Operativna nedelja iz app settings (active_week_start/end)
  final aktivnaNedelja = V3DanHelper.schedulingWeekRange(now: now);
  final nedeljaStart = aktivnaNedelja.start;
  final nedeljaEnd = aktivnaNedelja.end;
  final nedeljaEndExclusive = nedeljaEnd.add(const Duration(days: 1));

  // Mesec
  final mesStart = V3DanHelper.dateOnlyFrom(now.year, now.month, 1);
  final mesEnd = V3DanHelper.dateOnlyFrom(now.year, now.month + 1, 1);

  // Ova godina
  final godStart = V3DanHelper.dateOnlyFrom(now.year, 1, 1);
  final godEnd = V3DanHelper.dateOnlyFrom(now.year + 1, 1, 1);

  double prihodDan = 0, prihodNed = 0, prihodMes = 0, prihodGod = 0;
  int voznjiDan = 0, voznjiNed = 0, voznjiMes = 0, voznjiGod = 0;

  for (final row in finansijeCache) {
    if (row['tip'] != 'prihod') continue;
    final kategorija = (row['kategorija']?.toString() ?? '').toLowerCase();
    if (kategorija == 'dnevna_predaja') continue;

    // Prihodi se računaju isključivo iz pojedinačnih uplata (uplate_json),
    // jer red može biti kreiran ranije (created_at) a ažuriran kasnije.
    final uplate = V3FinansijeService.getUplateFromRow(row);
    for (final uplata in uplate) {
      final dt = uplata.datum;
      final iznos = uplata.iznos;
      if (iznos <= 0) continue;

      // Dnevni period (danas)
      if (!dt.isBefore(danas) && dt.isBefore(sutra)) {
        prihodDan += iznos;
      }
      // Nedeljni period
      if (!dt.isBefore(nedeljaStart) && dt.isBefore(nedeljaEndExclusive)) {
        prihodNed += iznos;
      }
      // Mesecni period
      if (!dt.isBefore(mesStart) && dt.isBefore(mesEnd)) {
        prihodMes += iznos;
      }
      // Godišnji period (ova godina)
      if (!dt.isBefore(godStart) && dt.isBefore(godEnd)) {
        prihodGod += iznos;
      }
    }

    // Broj vožnji se računa iz realizovanih vožnji (realizovane_voznje_json).
    final voznje = V3FinansijeService.getRealizovaneVoznjeFromRow(row);
    for (final voznja in voznje) {
      final dt = voznja.datum;
      // Dnevni period (danas)
      if (!dt.isBefore(danas) && dt.isBefore(sutra)) {
        voznjiDan++;
      }
      // Nedeljni period
      if (!dt.isBefore(nedeljaStart) && dt.isBefore(nedeljaEndExclusive)) {
        voznjiNed++;
      }
      // Mesecni period
      if (!dt.isBefore(mesStart) && dt.isBefore(mesEnd)) {
        voznjiMes++;
      }
      // Godišnji period (ova godina)
      if (!dt.isBefore(godStart) && dt.isBefore(godEnd)) {
        voznjiGod++;
      }
    }
  }

  // Troškovi iz cache
  double trosakDan = 0, trosakNed = 0, trosakMes = 0, trosakGod = 0;
  final troskoviMes = V3FinansijeService.getTroskoviMesec(mesec: now.month, godina: now.year);

  for (final row in finansijeCache) {
    if (row['tip'] != 'rashod') continue;
    final createdStr = row['created_at'] as String?;
    if (createdStr == null) continue;
    final dt = V3DateUtils.parseTs(createdStr);
    if (dt == null) continue;
    final iznos = (row['iznos'] as num?)?.toDouble() ?? 0.0;

    if (!dt.isBefore(danas) && dt.isBefore(sutra)) {
      trosakDan += iznos;
    }
    if (!dt.isBefore(nedeljaStart) && dt.isBefore(nedeljaEndExclusive)) {
      trosakNed += iznos;
    }
    if (!dt.isBefore(godStart) && dt.isBefore(godEnd)) {
      trosakGod += iznos;
    }
  }

  final Map<String, double> poKat = {};
  for (final t in troskoviMes) {
    trosakMes += t.iznos;
    final kat = _katLabel(t.kategorija);
    poKat[kat] = (poKat[kat] ?? 0) + t.iznos;
  }
  // Potraživanja
  final dugovi = V3FinansijeService.getDugovi();
  final potr = dugovi.fold(0.0, (s, d) => s + d.iznos);

  // Krediti / lična dugovanja
  final kreditiIznos = V3KreditService.getUkupnoPreostalo();

  // Period stringovi
  final danPeriod = V3DanHelper.formatDanMesec(danas);
  final nedeljaPeriod = '${V3DanHelper.formatDanMesec(nedeljaStart)} - ${V3DanHelper.formatDanMesec(nedeljaEnd)}';

  return _V3IzvestajData(
    potrazivanjaIznos: potr,
    kreditiIznos: kreditiIznos,
    prihodDanas: prihodDan,
    trosakDanas: trosakDan,
    voznjiDanas: voznjiDan,
    prihodNedelja: prihodNed,
    trosakNedelja: trosakNed,
    voznjiNedelja: voznjiNed,
    prihodMesec: prihodMes,
    trosakMesec: trosakMes,
    voznjiMesec: voznjiMes,
    prihodGodina: prihodGod,
    trosakGodina: trosakGod,
    voznjiGodina: voznjiGod,
    troskoviPoKategoriji: poKat,
    danasPeriod: danPeriod,
    nedeljaPeriod: nedeljaPeriod,
    godinaBroj: now.year,
  );
}

String _katLabel(String? kat) {
  final map = {
    'gorivo': _FinTr.tr('katGorivo'),
    'odrzavanje': _FinTr.tr('katOdrzavanje'),
    'plate': _FinTr.tr('katPlate'),
    'plata': _FinTr.tr('katPlate'),
    'kredit': _FinTr.tr('katKredit'),
    'registracija': _FinTr.tr('katRegistracija'),
    'yu_auto': _FinTr.tr('katYuAuto'),
    'majstori': _FinTr.tr('katMajstori'),
    'porez': _FinTr.tr('katPorez'),
    'alimentacija': _FinTr.tr('katAlimentacija'),
    'racuni': _FinTr.tr('katRacuni'),
    'ostalo': _FinTr.tr('katOstalo'),
  };
  return map[kat] ?? (kat ?? _FinTr.tr('katOstalo'));
}

// ─── State ────────────────────────────────────────────────────────────────────

class _V3FinansijeScreenState extends State<V3FinansijeScreen> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: V3MasterRealtimeManager.instance
          .tablesRevisionStream(const ['v3_finansije', 'v3_krediti', 'v3_auth', 'v3_app_settings']),
      builder: (context, _) {
        final iz = _buildIzvestaj();
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
            centerTitle: true,
            title: Text(_FinTr.tr('finansije'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          body: V3ContainerUtils.backgroundContainer(
            gradient: Theme.of(context).backgroundGradient,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPotrazivanjaCard(iz.potrazivanjaIznos),
                    const SizedBox(height: 16),
                    _buildKreditiCard(iz.kreditiIznos),
                    const SizedBox(height: 16),
                    _buildPeriodCard(
                      icon: '📅',
                      naslov: 'Danas',
                      podnaslov: V3DateUtils.mesecNaziv(DateTime.now().month, fallback: ''),
                      prihod: iz.prihodDanas,
                      troskovi: iz.trosakDanas,
                      voznjiLabel: '${iz.voznjiDanas} uplata',
                      color: Colors.blue,
                    ),
                    const SizedBox(height: 16),
                    _buildPeriodCard(
                      icon: '📆',
                      naslov: 'Ova nedelja',
                      podnaslov: iz.nedeljaPeriod,
                      prihod: iz.prihodNedelja,
                      troskovi: iz.trosakNedelja,
                      voznjiLabel: '${iz.voznjiNedelja} uplata',
                      color: Colors.indigo,
                    ),
                    const SizedBox(height: 16),
                    _buildPeriodCard(
                      icon: '🗓️',
                      naslov: 'Ovaj mesec',
                      podnaslov: V3DateUtils.mesecNaziv(DateTime.now().month, fallback: ''),
                      prihod: iz.prihodMesec,
                      troskovi: iz.trosakMesec,
                      voznjiLabel: '${iz.voznjiMesec} uplata',
                      color: Colors.green,
                    ),
                    const SizedBox(height: 16),
                    _buildPeriodCard(
                      icon: '📊',
                      naslov: 'Ova godina (${iz.godinaBroj})',
                      podnaslov: 'Ceo godišnji bilans',
                      prihod: iz.prihodGodina,
                      troskovi: iz.trosakGodina,
                      voznjiLabel: '${iz.voznjiGodina} uplata',
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    _buildTroskoviDetailsList(iz.troskoviPoKategoriji),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: V3ButtonUtils.outlinedButton(
                        onPressed: () => _showTroskoviDialog(iz.troskoviPoKategoriji),
                        text: _FinTr.tr('dodajTroskove'),
                        icon: Icons.edit,
                        borderColor: Colors.white24,
                        foregroundColor: Colors.white70,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPotrazivanjaCard(double iznos) {
    return V3ContainerUtils.gradientContainer(
      gradient: LinearGradient(
        colors: [Colors.orange.shade800, Colors.orange.shade600],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(18),
      boxShadow: [BoxShadow(color: Colors.orange.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 5))],
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          V3ContainerUtils.iconContainer(
            width: 52,
            height: V3ContainerUtils.responsiveHeight(context, 52),
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            borderRadiusGeometry: BorderRadius.circular(14),
            child: const Center(child: Text('💰', style: TextStyle(fontSize: 26))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_FinTr.tr('potrazivanjaDugovi'),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 2),
                Text(_FinTr.tr('neplaceneVoznjeSvihPutnika'),
                    style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
              ],
            ),
          ),
          Text(_fmtIznos(iznos),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildKreditiCard(double iznos) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const V3KreditiScreen()),
      ),
      child: V3ContainerUtils.gradientContainer(
        gradient: LinearGradient(
          colors: [Colors.blue.shade800, Colors.blue.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.blue.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 5))],
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            V3ContainerUtils.iconContainer(
              width: 52,
              height: V3ContainerUtils.responsiveHeight(context, 52),
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              borderRadiusGeometry: BorderRadius.circular(14),
              child: const Center(child: Text('🏦', style: TextStyle(fontSize: 26))),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_FinTr.tr('krediti'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(_FinTr.tr('preostaliDugZaKredite'),
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
                ],
              ),
            ),
            Row(
              children: [
                Text(_fmtIznos(iznos),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: Colors.white70),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodCard({
    required String icon,
    required String naslov,
    required String podnaslov,
    required double prihod,
    required double troskovi,
    required String voznjiLabel,
    required Color color,
  }) {
    final neto = prihod - troskovi;
    final isPositive = neto >= 0;
    final netoColor = isPositive ? const Color(0xFF4ADE80) : const Color(0xFFF87171);

    return V3ContainerUtils.iconContainer(
      backgroundColor: const Color(0xFF1E2235),
      borderRadiusGeometry: BorderRadius.circular(18),
      border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
      boxShadow: [BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 4))],
      child: Column(
        children: [
          V3ContainerUtils.gradientContainer(
            gradient: LinearGradient(
              colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0.1)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(naslov,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text(podnaslov, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6))),
                    ],
                  ),
                ),
                V3ContainerUtils.iconContainer(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  backgroundColor: color.withValues(alpha: 0.25),
                  borderRadiusGeometry: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                  child: Text(voznjiLabel,
                      style: TextStyle(
                          color: color == Colors.grey ? Colors.white70 : color,
                          fontWeight: FontWeight.bold,
                          fontSize: 11)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              children: [
                _FinRow(_FinTr.tr('prihod'), prihod, const Color(0xFF4ADE80), prefix: '+'),
                const SizedBox(height: 8),
                _FinRow(_FinTr.tr('troskovi'), troskovi, const Color(0xFFF87171), prefix: '-'),
                const SizedBox(height: 10),
                Divider(color: Colors.white.withValues(alpha: 0.1)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_FinTr.tr('neto'),
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white.withValues(alpha: 0.9))),
                    Row(
                      children: [
                        Icon(isPositive ? Icons.trending_up : Icons.trending_down, color: netoColor, size: 20),
                        const SizedBox(width: 6),
                        Text(_fmtIznos(neto.abs()),
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: netoColor)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTroskoviDetailsList(Map<String, double> poKat) {
    final ukupno = poKat.values.fold(0.0, (s, v) => s + v);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E2235),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          V3ContainerUtils.gradientContainer(
            gradient: LinearGradient(
              colors: [Colors.red.withValues(alpha: 0.3), Colors.red.withValues(alpha: 0.1)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_FinTr.tr('mesecniTroskovi'),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                Text(_fmtIznos(ukupno),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFFF87171))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: poKat.isEmpty
                ? Text(_FinTr.tr('nemaTroskovaZaOvajMesec'),
                    style: const TextStyle(color: Colors.white38, fontSize: 13))
                : Column(
                    children: poKat.entries
                        .map((e) => _FinRow(e.key, e.value, e.value > 0 ? const Color(0xFFF87171) : Colors.white38,
                            fontSize: 14, labelColor: Colors.white70))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  void _showTroskoviDialog(Map<String, double> poKat) {
    V3DialogHelper.showBottomSheet(
      context: context,
      child: _TroskoviBottomSheet(poKat: poKat),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _fmtIznos(double iznos) => '${V3FormatUtils.formatBroj(iznos.round())} din';

// ─── _FinRow Widget ───────────────────────────────────────────────────────────

class _FinRow extends StatelessWidget {
  const _FinRow(
    this.label,
    this.iznos,
    this.color, {
    this.prefix,
    this.fontSize = 15,
    this.labelColor = Colors.white60,
  });

  final String label;
  final double iznos;
  final Color color;
  final String? prefix;
  final double fontSize;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: fontSize, color: labelColor, fontWeight: FontWeight.normal)),
          Text(
            '${prefix ?? ''}${_fmtIznos(iznos.abs())}',
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

// ─── Troškovi Bottom Sheet ────────────────────────────────────────────────────

class _TroskoviBottomSheet extends StatefulWidget {
  const _TroskoviBottomSheet({required this.poKat});
  final Map<String, double> poKat;

  @override
  State<_TroskoviBottomSheet> createState() => _TroskoviBottomSheetState();
}

class _TroskoviBottomSheetState extends State<_TroskoviBottomSheet> {
  static List<(String, String, String)> get _stavke => [
        ('plate', '💰', _FinTr.tr('katPlate')),
        ('kredit', '🏦', _FinTr.tr('katKredit')),
        ('gorivo', '⛽', _FinTr.tr('katGorivo')),
        ('registracija', '📋', _FinTr.tr('katRegistracija')),
        ('yu_auto', '🚗', _FinTr.tr('katYuAuto')),
        ('majstori', '🛠️', _FinTr.tr('katMajstori')),
        ('porez', '🏗️', _FinTr.tr('katPorez')),
        ('alimentacija', '👶', _FinTr.tr('katAlimentacija')),
        ('racuni', '🧾', _FinTr.tr('katRacuni')),
        ('ostalo', '📦', _FinTr.tr('katOstalo')),
      ];

  late final Map<String, TextEditingController> _ctrls = {
    for (final s in _stavke) s.$1: TextEditingController(),
  };
  bool _saving = false;
  late final List<V3Kredit> _krediti = V3KreditService.getKrediti();
  String? _selectedKreditId;

  @override
  void initState() {
    super.initState();
    if (_krediti.isNotEmpty) _selectedKreditId = _krediti.first.id;
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) c.dispose();
    super.dispose();
  }

  Future<void> _sacuvaj() async {
    V3StateUtils.safeSetState(this, () => _saving = true);
    final now = DateTime.now();
    try {
      final futures = <Future<void>>[];
      for (final s in _stavke) {
        final val = double.tryParse(_ctrls[s.$1]!.text.replaceAll(',', '.')) ?? 0;
        if (val <= 0) continue;

        if (s.$1 == 'kredit' && _selectedKreditId != null) {
          // Otplata konkretnog kredita: umanjuje preostali dug tog kredita
          // i evidentira trošak radi statistike.
          final kredit = _krediti.firstWhere((k) => k.id == _selectedKreditId);
          futures.add(V3KreditService.uplati(
            id: kredit.id,
            iznos: val,
            napomena: 'Uplata sa ekrana Finansije',
          ));
          futures.add(V3FinansijeService.addTrosak(V3Trosak(
            id: '',
            naziv: '${s.$3} (${kredit.naziv})',
            kategorija: s.$1,
            iznos: val,
            isplataIz: 'pazar',
            mesec: now.month,
            godina: now.year,
          )));
          continue;
        }

        futures.add(V3FinansijeService.addTrosak(V3Trosak(
          id: '',
          naziv: s.$3,
          kategorija: s.$1,
          iznos: val,
          isplataIz: 'pazar',
          mesec: now.month,
          godina: now.year,
        )));
      }
      await Future.wait(futures);
      if (mounted) {
        V3AppSnackBar.success(context, _FinTr.tr('troskoviDodati'));
        Navigator.pop(context);
      }
    } catch (e) {
      V3ErrorUtils.asyncError(this, context, e);
    } finally {
      V3StateUtils.safeSetState(this, () => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                V3ContainerUtils.styledContainer(
                  width: 40,
                  height: V3ContainerUtils.responsiveHeight(context, 4, intensity: 0.2),
                  backgroundColor: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                  child: const SizedBox(),
                ),
                const SizedBox(height: 16),
                Text(_FinTr.tr('dodajTroskove'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(_FinTr.tr('unesiIznosDodas'), style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 20),
                for (final s in _stavke) ...[
                  Row(
                    children: [
                      Text(s.$2, style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.$3, style: const TextStyle(fontSize: 16)),
                            if ((widget.poKat[_katLabel(s.$1)] ?? 0) > 0)
                              Text(
                                '${_FinTr.tr('trenutno')} ${V3FormatUtils.formatBroj((widget.poKat[_katLabel(s.$1)] ?? 0).round())}',
                                style:
                                    TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: V3InputUtils.numberField(
                          controller: _ctrls[s.$1]!,
                          label: _FinTr.tr('dodajDots'),
                          suffixText: 'din',
                        ),
                      ),
                    ],
                  ),
                  if (s.$1 == 'kredit' && _krediti.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 34),
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedKreditId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Koji kredit se otplaćuje?',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: _krediti
                            .map((k) => DropdownMenuItem(
                                  value: k.id,
                                  child: Text('${k.naziv} (${_fmtIznos(k.preostalo)} preostalo)'),
                                ))
                            .toList(),
                        onChanged: (val) => V3StateUtils.safeSetState(this, () => _selectedKreditId = val),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: V3ButtonUtils.successButton(
                    onPressed: _saving ? null : _sacuvaj,
                    text: _FinTr.tr('dodajTroskove'),
                    icon: Icons.add_circle,
                    isLoading: _saving,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
