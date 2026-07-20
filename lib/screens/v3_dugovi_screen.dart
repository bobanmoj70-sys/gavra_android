import 'package:flutter/material.dart';
import 'package:gavra_android/models/v3_dug.dart';
import 'package:gavra_android/services/v3/v3_finansije_service.dart';
import 'package:gavra_android/utils/v3_date_utils.dart';
import 'package:gavra_android/utils/v3_string_utils.dart';

import '../helpers/v3_placanje_dialog_helper.dart';
import '../services/v3_locale_manager.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_safe_text.dart';
import '../utils/v3_state_utils.dart';

class _DugTr {
  static const Map<String, Map<String, String>> _t = {
    'dugovanja': {'sr': 'Dugovanja', 'en': 'Debts', 'ru': 'Долги', 'de': 'Schulden'},
    'ukupnoDugova': {'sr': 'Ukupno dugova', 'en': 'Total debts', 'ru': 'Всего долгов', 'de': 'Gesamtschulden'},
    'ukupanIznos': {'sr': 'Ukupan iznos', 'en': 'Total amount', 'ru': 'Общая сумма', 'de': 'Gesamtbetrag'},
    'pretraziPutnike': {
      'sr': '🔍  Pretraži putnike...',
      'en': '🔍  Search passengers...',
      'ru': '🔍  Поиск пассажиров...',
      'de': '🔍  Passagiere suchen...',
    },
    'nemaEvidentiranihDugovanja': {
      'sr': 'Nema evidentiranih dugovanja',
      'en': 'No recorded debts',
      'ru': 'Нет зарегистрированных долгов',
      'de': 'Keine erfassten Schulden',
    },
    'nemaRezultataZa': {
      'sr': 'Nema rezultata za',
      'en': 'No results for',
      'ru': 'Нет результатов для',
      'de': 'Keine Ergebnisse für',
    },
    'naplaceno': {'sr': 'Naplaćeno', 'en': 'Collected', 'ru': 'Взыскано', 'de': 'Eingezogen'},
    'za': {'sr': 'za', 'en': 'for', 'ru': 'для', 'de': 'für'},
    'period': {'sr': 'Period', 'en': 'Period', 'ru': 'Период', 'de': 'Zeitraum'},
    'obracun': {'sr': 'Obračun', 'en': 'Calculation', 'ru': 'Расчёт', 'de': 'Abrechnung'},
    'uplaceno': {'sr': 'Uplaćeno', 'en': 'Paid', 'ru': 'Оплачено', 'de': 'Bezahlt'},
    'pokupio': {'sr': 'Pokupio', 'en': 'Collected by', 'ru': 'Забрал', 'de': 'Abgeholt von'},
    'naplatio': {'sr': 'Naplatio', 'en': 'Charged by', 'ru': 'Взыскал', 'de': 'Eingezogen von'},
    'naplacenoCreatedAt': {
      'sr': 'Naplaćeno (created_at)',
      'en': 'Collected (created_at)',
      'ru': 'Взыскано (created_at)',
      'de': 'Eingezogen (created_at)',
    },
    'updatedAt': {'sr': 'Updated at', 'en': 'Updated at', 'ru': 'Обновлено', 'de': 'Aktualisiert am'},
    'finansijeNaziv': {'sr': 'Finansije naziv', 'en': 'Finance name', 'ru': 'Название финансов', 'de': 'Finanzname'},
    'naplati': {'sr': 'NAPLATI', 'en': 'COLLECT', 'ru': 'ВЗЫСКАТЬ', 'de': 'EINZIEHEN'},
  };

  static String tr(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    return _t[key]?[code] ?? _t[key]?['sr'] ?? key;
  }
}

class V3DugoviScreen extends StatefulWidget {
  const V3DugoviScreen({super.key});

  @override
  State<V3DugoviScreen> createState() => _V3DugoviScreenState();
}

class _V3DugoviScreenState extends State<V3DugoviScreen> {
  String _filter = '';
  final Set<String> _processingDugIds = <String>{};

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<V3Dug>>(
      stream: V3FinansijeService.streamDugovi(),
      builder: (context, snapshot) {
        final isLoading = !snapshot.hasData && snapshot.connectionState == ConnectionState.waiting;
        final allDugovi = snapshot.data ?? [];
        final dugovi = allDugovi.where((d) => V3StringUtils.containsSearch(d.imePrezime, _filter)).toList();
        final ukupanIznos = allDugovi.fold(0.0, (s, d) => s + d.iznos);

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
            centerTitle: true,
            title: Text(
              _DugTr.tr('dugovanja'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white),
            ),
          ),
          body: Container(
            decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
            child: SafeArea(
              child: Column(
                children: [
                  // ─── Stats kartica ───
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Row(
                      children: [
                        _StatCard(
                          label: _DugTr.tr('ukupnoDugova'),
                          value: '${allDugovi.length}',
                          icon: '💳',
                          color: Colors.redAccent,
                        ),
                        const SizedBox(width: 8),
                        _StatCard(
                          label: _DugTr.tr('ukupanIznos'),
                          value: '${ukupanIznos.toStringAsFixed(0)} RSD',
                          icon: '💰',
                          color: Colors.orange,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ─── Search box ───
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                      ),
                      child: TextField(
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: _DugTr.tr('pretraziPutnike'),
                          hintStyle: const TextStyle(color: Colors.white54),
                          prefixIcon: const Icon(Icons.search, color: Colors.white54),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onChanged: (v) => V3StateUtils.safeSetState(this, () => _filter = v),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ─── Lista dugova ───
                  Expanded(
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator(color: Colors.white))
                        : dugovi.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('✅', style: TextStyle(fontSize: 48)),
                                    const SizedBox(height: 12),
                                    Text(
                                      _filter.isEmpty
                                          ? _DugTr.tr('nemaEvidentiranihDugovanja')
                                          : '${_DugTr.tr('nemaRezultataZa')} "$_filter"',
                                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                                itemCount: dugovi.length,
                                itemBuilder: (context, i) => _DugCard(
                                  dug: dugovi[i],
                                  onNaplati: () async {
                                    final dug = dugovi[i];
                                    if (_processingDugIds.contains(dug.id)) return;
                                    _processingDugIds.add(dug.id);
                                    try {
                                      final rezultat = await V3PlacanjeDialogHelper.naplati(
                                        context: context,
                                        putnikId: dug.putnikId,
                                        imePrezime: dug.imePrezime,
                                        defaultCena: dug.iznos,
                                        cenaPoModelu: dug.cena,
                                        snimiMesecnuUplatu: true,
                                        brojVoznji: dug.brojVoznji,
                                        mesec: dug.mesec,
                                        godina: dug.godina,
                                      );
                                      if (rezultat == null) return;

                                      if (context.mounted) {
                                        V3AppSnackBar.success(
                                          context,
                                          '✅ ${_DugTr.tr('naplaceno')} ${rezultat.iznos.toStringAsFixed(0)} RSD ${_DugTr.tr('za')} ${dug.imePrezime}',
                                        );
                                      }
                                    } finally {
                                      _processingDugIds.remove(dug.id);
                                    }
                                  },
                                ),
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

// ─────────────────────────────────────────────
// Stats kartica
// ─────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
                  Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Kartica jednog duga
// ─────────────────────────────────────────────
class _DugCard extends StatelessWidget {
  const _DugCard({required this.dug, required this.onNaplati});

  final V3Dug dug;
  final VoidCallback onNaplati;

  String _formatTs(DateTime? ts) {
    if (ts == null) return '-';
    final dd = ts.day.toString().padLeft(2, '0');
    final mm = ts.month.toString().padLeft(2, '0');
    final hh = ts.hour.toString().padLeft(2, '0');
    final mi = ts.minute.toString().padLeft(2, '0');
    return '$dd.$mm.${ts.year} $hh:$mi';
  }

  @override
  Widget build(BuildContext context) {
    final initial = dug.imePrezime.isNotEmpty ? dug.imePrezime[0].toUpperCase() : '?';
    final periodStr = '${V3DateUtils.mesecNaziv(dug.mesec)} ${dug.godina}';
    final obracunStr =
        '${dug.brojVoznji} × ${dug.cena.toStringAsFixed(0)} = ${dug.ukupnaObaveza.toStringAsFixed(0)} RSD';
    final uplataStr = '${dug.uplaceno.toStringAsFixed(0)} RSD';
    final naplatioStr = (dug.uplaceno > 0 && dug.vozacIme.isNotEmpty) ? dug.vozacIme : null;
    final azuriraoStr = null;
    final naplacenoAtStr = _formatTs(dug.naplacenoAt ?? dug.createdAt);
    final updatedAtStr = _formatTs(dug.updatedAt);
    final finansijeNaziv = (dug.finansijeNaziv ?? '').trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              backgroundColor: Colors.redAccent.withValues(alpha: 0.8),
              radius: 22,
              child:
                  Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  V3SafeText.userName(dug.imePrezime,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Text('💰 ', style: TextStyle(fontSize: 13)),
                      Text(
                        '${dug.iznos.toStringAsFixed(0)} RSD',
                        style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text('${_DugTr.tr('period')}: $periodStr',
                      style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  const SizedBox(height: 1),
                  Text('${_DugTr.tr('obracun')}: $obracunStr',
                      style: const TextStyle(color: Colors.white60, fontSize: 11)),
                  const SizedBox(height: 1),
                  Text('${_DugTr.tr('uplaceno')}: $uplataStr',
                      style: const TextStyle(color: Colors.white60, fontSize: 11)),
                  const SizedBox(height: 1),
                  if (dug.pokupioVozacIme.isNotEmpty) ...[
                    Text('${_DugTr.tr('pokupio')}: ${dug.pokupioVozacIme}',
                        style: const TextStyle(color: Colors.white60, fontSize: 11)),
                    const SizedBox(height: 1),
                  ],
                  if (naplatioStr != null) ...[
                    Text('${_DugTr.tr('naplatio')}: $naplatioStr',
                        style: const TextStyle(color: Colors.white60, fontSize: 11)),
                    const SizedBox(height: 1),
                  ],
                  if (dug.uplaceno > 0) ...[
                    Text('${_DugTr.tr('naplacenoCreatedAt')}: $naplacenoAtStr',
                        style: const TextStyle(color: Colors.white60, fontSize: 11)),
                    const SizedBox(height: 1),
                  ],
                  const SizedBox(height: 1),
                  if (dug.updatedAt != null) ...[
                    Text('${_DugTr.tr('updatedAt')}: $updatedAtStr',
                        style: const TextStyle(color: Colors.white60, fontSize: 11)),
                    const SizedBox(height: 1),
                  ],
                  if (finansijeNaziv.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text('${_DugTr.tr('finansijeNaziv')}: $finansijeNaziv',
                        style: const TextStyle(color: Colors.white60, fontSize: 11)),
                  ],
                ],
              ),
            ),
            // Naplati dugme
            GestureDetector(
              onTap: onNaplati,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _DugTr.tr('naplati'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
