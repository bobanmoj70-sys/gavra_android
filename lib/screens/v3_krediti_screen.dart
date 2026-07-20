import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/v3_kredit.dart';
import '../services/v3/v3_kredit_service.dart';
import '../services/v3_locale_manager.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dialog_helper.dart';
import '../utils/v3_error_utils.dart';
import '../utils/v3_format_utils.dart';
import '../utils/v3_input_utils.dart';
import '../utils/v3_state_utils.dart';

class _KredTr {
  static const Map<String, Map<String, String>> _t = {
    'mojiKrediti': {'sr': 'Moji krediti', 'en': 'My loans', 'ru': 'Мои кредиты', 'de': 'Meine Kredite'},
    'nemaEvidentiranihKredita': {
      'sr': 'Nema evidentiranih kredita',
      'en': 'No recorded loans',
      'ru': 'Нет зарегистрированных кредитов',
      'de': 'Keine erfassten Kredite',
    },
    'dodajKredit': {'sr': 'Dodaj kredit', 'en': 'Add loan', 'ru': 'Добавить кредит', 'de': 'Kredit hinzufügen'},
    'preostalaDugovanja': {
      'sr': 'Preostala dugovanja',
      'en': 'Remaining debts',
      'ru': 'Оставшиеся долги',
      'de': 'Verbleibende Schulden',
    },
    'ukupnoPreostaloZaOtplatu': {
      'sr': 'Ukupno preostalo za otplatu',
      'en': 'Total remaining to repay',
      'ru': 'Всего осталось погасить',
      'de': 'Insgesamt zu zahlender Restbetrag',
    },
    'kreditDodat': {
      'sr': '✅ Kredit dodat',
      'en': '✅ Loan added',
      'ru': '✅ Кредит добавлен',
      'de': '✅ Kredit hinzugefügt'
    },
    'kreditIzmenjen': {
      'sr': '✅ Kredit izmenjen',
      'en': '✅ Loan updated',
      'ru': '✅ Кредит изменён',
      'de': '✅ Kredit aktualisiert'
    },
    'uplataEvidentirana': {
      'sr': '✅ Uplata evidentirana',
      'en': '✅ Payment recorded',
      'ru': '✅ Платёж зарегистрирован',
      'de': '✅ Zahlung erfasst',
    },
    'obrisiKredit': {'sr': 'Obriši kredit', 'en': 'Delete loan', 'ru': 'Удалить кредит', 'de': 'Kredit löschen'},
    'daLiSteSigurniObrisatiKredit': {
      'sr': 'Da li si siguran da želiš da obrišeš „%NAZIV%"?',
      'en': 'Are you sure you want to delete "%NAZIV%"?',
      'ru': 'Вы уверены, что хотите удалить «%NAZIV%»?',
      'de': 'Möchten Sie „%NAZIV%" wirklich löschen?',
    },
    'obrisi': {'sr': 'Obriši', 'en': 'Delete', 'ru': 'Удалить', 'de': 'Löschen'},
    'kreditObrisan': {
      'sr': '✅ Kredit obrisan',
      'en': '✅ Loan deleted',
      'ru': '✅ Кредит удалён',
      'de': '✅ Kredit gelöscht'
    },
    'istorijaUplata': {
      'sr': 'Istorija uplata',
      'en': 'Payment history',
      'ru': 'История платежей',
      'de': 'Zahlungsverlauf',
    },
    'nemaEvidentiranihUplata': {
      'sr': 'Nema evidentiranih uplata',
      'en': 'No recorded payments',
      'ru': 'Нет зарегистрированных платежей',
      'de': 'Keine erfassten Zahlungen',
    },
    'obrisiUplatu': {'sr': 'Obriši uplatu', 'en': 'Delete payment', 'ru': 'Удалить платёж', 'de': 'Zahlung löschen'},
    'daLiSteSigurniObrisatiUplatu': {
      'sr': 'Da li si siguran da želiš da obrišeš ovu uplatu?',
      'en': 'Are you sure you want to delete this payment?',
      'ru': 'Вы уверены, что хотите удалить этот платёж?',
      'de': 'Möchten Sie diese Zahlung wirklich löschen?',
    },
    'uplataObrisana': {
      'sr': '✅ Uplata obrisana',
      'en': '✅ Payment deleted',
      'ru': '✅ Платёж удалён',
      'de': '✅ Zahlung gelöscht'
    },
    'zatvori': {'sr': 'Zatvori', 'en': 'Close', 'ru': 'Закрыть', 'de': 'Schließen'},
    'otplaceno': {'sr': 'OTPLAĆENO', 'en': 'PAID OFF', 'ru': 'ПОГАШЕНО', 'de': 'ABBEZAHLT'},
    'kraj': {'sr': 'Kraj', 'en': 'End', 'ru': 'Конец', 'de': 'Ende'},
    'ukupanIznos': {'sr': 'Ukupan iznos', 'en': 'Total amount', 'ru': 'Общая сумма', 'de': 'Gesamtbetrag'},
    'uplaceno': {'sr': 'Uplaćeno', 'en': 'Paid', 'ru': 'Оплачено', 'de': 'Bezahlt'},
    'preostalo': {'sr': 'Preostalo', 'en': 'Remaining', 'ru': 'Осталось', 'de': 'Verbleibend'},
    'uplati': {'sr': 'UPLATI', 'en': 'PAY', 'ru': 'ОПЛАТИТЬ', 'de': 'ZAHLEN'},
    'uplateStat': {'sr': 'Uplate', 'en': 'Payments', 'ru': 'Платежи', 'de': 'Zahlungen'},
    'prosek': {'sr': 'Prosek', 'en': 'Average', 'ru': 'Среднее', 'de': 'Durchschnitt'},
    'najveca': {'sr': 'Najveća', 'en': 'Largest', 'ru': 'Наибольший', 'de': 'Größte'},
    'grafikUplataPoMesecima': {
      'sr': 'Grafik uplata po mesecima',
      'en': 'Payments by month chart',
      'ru': 'График платежей по месяцам',
      'de': 'Zahlungsdiagramm nach Monaten',
    },
    'nazivPlaceholder': {
      'sr': 'Naziv (npr. BMW, Mama)',
      'en': 'Name (e.g. BMW, Mom)',
      'ru': 'Название (напр. BMW, Мама)',
      'de': 'Name (z.B. BMW, Mama)',
    },
    'ukupanIznosRsd': {
      'sr': 'Ukupan iznos (RSD)',
      'en': 'Total amount (RSD)',
      'ru': 'Общая сумма (RSD)',
      'de': 'Gesamtbetrag (RSD)',
    },
    'napomenaOpciono': {
      'sr': 'Napomena (opciono)',
      'en': 'Note (optional)',
      'ru': 'Примечание (опционально)',
      'de': 'Notiz (optional)',
    },
    'krajKreditaOpciono': {
      'sr': 'Kraj kredita (opciono)',
      'en': 'Loan end (optional)',
      'ru': 'Конец кредита (опционально)',
      'de': 'Kreditende (optional)',
    },
    'krajKreditaZadnjaRata': {
      'sr': 'Kraj kredita / zadnja rata',
      'en': 'Loan end / last installment',
      'ru': 'Конец кредита / последний платёж',
      'de': 'Kreditende / letzte Rate',
    },
    'izaberiDatum': {'sr': 'Izaberi datum', 'en': 'Select date', 'ru': 'Выберите дату', 'de': 'Datum wählen'},
    'otkazi': {'sr': 'Otkaži', 'en': 'Cancel', 'ru': 'Отмена', 'de': 'Abbrechen'},
    'sacuvaj': {'sr': 'Sačuvaj', 'en': 'Save', 'ru': 'Сохранить', 'de': 'Speichern'},
    'nazivJeObavezan': {
      'sr': 'Naziv je obavezan',
      'en': 'Name is required',
      'ru': 'Название обязательно',
      'de': 'Name ist erforderlich',
    },
    'iznosNeMozeBitiNegativan': {
      'sr': 'Iznos ne može biti negativan',
      'en': 'Amount cannot be negative',
      'ru': 'Сумма не может быть отрицательной',
      'de': 'Betrag darf nicht negativ sein',
    },
    'uplataNaziv': {
      'sr': 'Uplata',
      'en': 'Payment',
      'ru': 'Платёж',
      'de': 'Zahlung',
    },
    'iznosUplate': {'sr': 'Iznos uplate', 'en': 'Payment amount', 'ru': 'Сумма платежа', 'de': 'Zahlungsbetrag'},
    'iznosMoraBitiVeciOdNule': {
      'sr': 'Iznos mora biti veći od nule',
      'en': 'Amount must be greater than zero',
      'ru': 'Сумма должна быть больше нуля',
      'de': 'Betrag muss größer als null sein',
    },
    'dodajKreditTitle': {'sr': 'Dodaj kredit', 'en': 'Add loan', 'ru': 'Добавить кредит', 'de': 'Kredit hinzufügen'},
    'izmeniKredit': {'sr': 'Izmeni kredit', 'en': 'Edit loan', 'ru': 'Изменить кредит', 'de': 'Kredit bearbeiten'},
  };

  static String tr(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    return _t[key]?[code] ?? _t[key]?['sr'] ?? key;
  }
}

class V3KreditiScreen extends StatefulWidget {
  const V3KreditiScreen({super.key});

  @override
  State<V3KreditiScreen> createState() => _V3KreditiScreenState();
}

class _V3KreditiScreenState extends State<V3KreditiScreen> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<V3Kredit>>(
      stream: V3KreditService.streamKrediti(),
      builder: (context, snapshot) {
        final krediti = snapshot.data ?? V3KreditService.getKrediti();
        final ukupnoPreostalo = krediti.fold<double>(
          0.0,
          (sum, k) => sum + (k.preostalo > 0 ? k.preostalo : 0),
        );

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            automaticallyImplyLeading: false,
            title: Text(_KredTr.tr('mojiKrediti'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          body: V3ContainerUtils.backgroundContainer(
            gradient: Theme.of(context).backgroundGradient,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildUkupnoCard(ukupnoPreostalo),
                    const SizedBox(height: 16),
                    Expanded(
                      child: krediti.isEmpty
                          ? Center(
                              child: Text(
                                _KredTr.tr('nemaEvidentiranihKredita'),
                                style: const TextStyle(color: Colors.white70, fontSize: 16),
                              ),
                            )
                          : ListView.builder(
                              itemCount: krediti.length,
                              itemBuilder: (context, index) => _KreditCard(
                                kredit: krediti[index],
                                onUplati: () => _showUplataDialog(krediti[index]),
                                onIzmeni: () => _showKreditDialog(krediti[index]),
                                onObrisi: () => _obrisiKredit(krediti[index]),
                                onIstorija: () => _showIstorijaDialog(krediti[index]),
                              ),
                            ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: V3ButtonUtils.successButton(
                        onPressed: () => _showKreditDialog(null),
                        text: _KredTr.tr('dodajKredit'),
                        icon: Icons.add_circle,
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

  Widget _buildUkupnoCard(double iznos) {
    return V3ContainerUtils.gradientContainer(
      gradient: LinearGradient(
        colors: [Colors.red.shade800, Colors.red.shade600],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(18),
      boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 5))],
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          V3ContainerUtils.iconContainer(
            width: 52,
            height: 52,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            borderRadiusGeometry: BorderRadius.circular(14),
            child: const Center(child: Text('🏦', style: TextStyle(fontSize: 26))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_KredTr.tr('preostalaDugovanja'),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 2),
                Text(_KredTr.tr('ukupnoPreostaloZaOtplatu'),
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

  Future<void> _showKreditDialog(V3Kredit? kredit) async {
    final result = await showDialog<_KreditFormResult>(
      context: context,
      builder: (context) => _KreditDialog(kredit: kredit),
    );
    if (result == null) return;

    try {
      if (kredit == null) {
        await V3KreditService.dodaj(
          naziv: result.naziv,
          ukupanIznos: result.ukupanIznos,
          napomena: result.napomena,
          krajKredita: result.krajKredita,
        );
        if (mounted) V3AppSnackBar.success(context, _KredTr.tr('kreditDodat'));
      } else {
        await V3KreditService.izmeni(
          id: kredit.id,
          naziv: result.naziv,
          ukupanIznos: result.ukupanIznos,
          napomena: result.napomena,
          krajKredita: result.krajKredita,
        );
        if (mounted) V3AppSnackBar.success(context, _KredTr.tr('kreditIzmenjen'));
      }
    } catch (e) {
      if (mounted) V3ErrorUtils.asyncError(this, context, e);
    }
  }

  Future<void> _showUplataDialog(V3Kredit kredit) async {
    final result = await showDialog<_UplataResult>(
      context: context,
      builder: (context) => _UplataDialog(kredit: kredit),
    );
    if (result == null || result.iznos <= 0) return;

    try {
      await V3KreditService.uplati(
        id: kredit.id,
        iznos: result.iznos,
        napomena: result.napomena,
      );
      if (mounted) V3AppSnackBar.success(context, _KredTr.tr('uplataEvidentirana'));
    } catch (e) {
      if (mounted) V3ErrorUtils.asyncError(this, context, e);
    }
  }

  Future<void> _obrisiKredit(V3Kredit kredit) async {
    final confirmed = await V3DialogHelper.showConfirmDialog(
      context,
      title: _KredTr.tr('obrisiKredit'),
      message: _KredTr.tr('daLiSteSigurniObrisatiKredit').replaceAll('%NAZIV%', kredit.naziv),
      confirmText: _KredTr.tr('obrisi'),
      isDangerous: true,
    );
    if (confirmed != true) return;

    try {
      await V3KreditService.obrisi(kredit.id);
      if (mounted) V3AppSnackBar.success(context, _KredTr.tr('kreditObrisan'));
    } catch (e) {
      if (mounted) V3ErrorUtils.asyncError(this, context, e);
    }
  }

  Future<void> _showIstorijaDialog(V3Kredit kredit) async {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9, maxHeight: MediaQuery.of(context).size.height * 0.7),
          decoration: BoxDecoration(
            gradient: Theme.of(context).backgroundGradient,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Theme.of(context).glassBorder, width: 0.8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${_KredTr.tr('istorijaUplata')}: ${kredit.naziv}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: kredit.uplate.isEmpty
                      ? Center(
                          child: Text(
                            _KredTr.tr('nemaEvidentiranihUplata'),
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                        )
                      : ListView.builder(
                          itemCount: kredit.uplate.length,
                          itemBuilder: (context, index) {
                            final uplata = kredit.uplate[index];
                            final datumStr =
                                '${uplata.datum.day.toString().padLeft(2, '0')}.${uplata.datum.month.toString().padLeft(2, '0')}.${uplata.datum.year}';
                            final vremeStr =
                                '${uplata.datum.hour.toString().padLeft(2, '0')}:${uplata.datum.minute.toString().padLeft(2, '0')}';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E2235),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red.withValues(alpha: 0.3), width: 1.5),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${V3FormatUtils.formatBroj(uplata.iznos.round())} din',
                                          style: const TextStyle(
                                              fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '$datumStr $vremeStr',
                                          style: const TextStyle(fontSize: 12, color: Colors.white54),
                                        ),
                                        if (uplata.napomena != null && uplata.napomena!.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            uplata.napomena!,
                                            style: const TextStyle(fontSize: 11, color: Colors.white38),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () async {
                                      final confirmed = await V3DialogHelper.showConfirmDialog(
                                        context,
                                        title: _KredTr.tr('obrisiUplatu'),
                                        message: _KredTr.tr('daLiSteSigurniObrisatiUplatu'),
                                        confirmText: _KredTr.tr('obrisi'),
                                        isDangerous: true,
                                      );
                                      if (confirmed == true) {
                                        try {
                                          await V3KreditService.obrisiUplatu(
                                            kreditId: kredit.id,
                                            uplataId: uplata.uplataId,
                                          );
                                          if (mounted) V3AppSnackBar.success(context, _KredTr.tr('uplataObrisana'));
                                          Navigator.pop(context);
                                        } catch (e) {
                                          if (mounted) V3ErrorUtils.asyncError(this, context, e);
                                        }
                                      }
                                    },
                                    icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
                V3ButtonUtils.outlinedButton(
                  onPressed: () => Navigator.pop(context),
                  text: _KredTr.tr('zatvori'),
                  borderColor: Colors.white24,
                  foregroundColor: Colors.white70,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fmtIznos(double iznos) => '${V3FormatUtils.formatBroj(iznos.round())} din';
}

// ─── Kartica kredita ─────────────────────────────────────────────────────────

class _KreditCard extends StatelessWidget {
  const _KreditCard({
    required this.kredit,
    required this.onUplati,
    required this.onIzmeni,
    required this.onObrisi,
    required this.onIstorija,
  });

  final V3Kredit kredit;
  final VoidCallback onUplati;
  final VoidCallback onIzmeni;
  final VoidCallback onObrisi;
  final VoidCallback onIstorija;

  @override
  Widget build(BuildContext context) {
    final preostalo = kredit.preostalo > 0 ? kredit.preostalo : 0.0;
    final progress = kredit.procenatOtplacenosti;
    final procenatText = '${(progress * 100).toStringAsFixed(0)}%';

    return GestureDetector(
      onTap: onIstorija,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2235),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      kredit.naziv,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  if (kredit.jeOtplacen)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
                      ),
                      child: Text(_KredTr.tr('otplaceno'),
                          style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              if (kredit.napomena != null && kredit.napomena!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(kredit.napomena!, style: const TextStyle(fontSize: 12, color: Colors.white54)),
              ],
              if (kredit.krajKredita != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 12, color: Colors.white38),
                    const SizedBox(width: 6),
                    Text(
                      '${_KredTr.tr('kraj')}: ${kredit.krajKredita!.day.toString().padLeft(2, '0')}.${kredit.krajKredita!.month.toString().padLeft(2, '0')}.${kredit.krajKredita!.year}',
                      style: const TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              _buildRow(_KredTr.tr('ukupanIznos'), kredit.ukupanIznos, Colors.white70),
              _buildRow(_KredTr.tr('uplaceno'), kredit.uplaceno, const Color(0xFF4ADE80)),
              _buildRow(_KredTr.tr('preostalo'), preostalo, const Color(0xFFF87171)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          kredit.jeOtplacen ? Colors.green : Colors.redAccent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(procenatText,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: kredit.jeOtplacen ? Colors.green : Colors.redAccent,
                      )),
                ],
              ),
              const SizedBox(height: 12),
              _buildStatsRow(),
              if (kredit.uplate.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(height: 100, child: _KreditChart(kredit: kredit)),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: V3ButtonUtils.successButton(
                      onPressed: onUplati,
                      text: _KredTr.tr('uplati'),
                      icon: Icons.payments,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _IconButton(icon: Icons.history, onTap: onIstorija, color: Colors.amber),
                  const SizedBox(width: 8),
                  _IconButton(icon: Icons.edit, onTap: onIzmeni, color: Colors.blueAccent),
                  const SizedBox(width: 8),
                  _IconButton(icon: Icons.delete, onTap: onObrisi, color: Colors.redAccent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(label: _KredTr.tr('uplateStat'), value: '${kredit.brojUplata}'),
          _StatItem(label: _KredTr.tr('prosek'), value: V3FormatUtils.formatBroj(kredit.prosecnaUplata.round())),
          _StatItem(label: _KredTr.tr('najveca'), value: V3FormatUtils.formatBroj(kredit.najvecaUplata.round())),
        ],
      ),
    );
  }

  Widget _buildRow(String label, double iznos, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.white60)),
          Text('${V3FormatUtils.formatBroj(iznos.round())} din',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
      ],
    );
  }
}

class _KreditChart extends StatelessWidget {
  const _KreditChart({required this.kredit});
  final V3Kredit kredit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2235),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_KredTr.tr('grafikUplataPoMesecima'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70)),
          const SizedBox(height: 8),
          Expanded(
            child: BarChart(
              _buildChartData(),
              swapAnimationDuration: const Duration(milliseconds: 300),
              swapAnimationCurve: Curves.easeInOut,
            ),
          ),
        ],
      ),
    );
  }

  BarChartData _buildChartData() {
    final mesecniIznosi = <String, double>{};
    for (final uplata in kredit.uplate) {
      final key = '${uplata.datum.month.toString().padLeft(2, '0')}.${uplata.datum.year}';
      mesecniIznosi[key] = (mesecniIznosi[key] ?? 0) + uplata.iznos;
    }

    final sortedKeys = mesecniIznosi.keys.toList()..sort();
    final maxY = mesecniIznosi.values.isEmpty ? 1.0 : mesecniIznosi.values.reduce((a, b) => a > b ? a : b) * 1.2;

    return BarChartData(
      alignment: BarChartAlignment.spaceAround,
      maxY: maxY,
      barTouchData: BarTouchData(enabled: false),
      titlesData: FlTitlesData(
        show: true,
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index < 0 || index >= sortedKeys.length) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  sortedKeys[index],
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              );
            },
            reservedSize: 28,
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (value, meta) {
              if (value == 0) return const SizedBox.shrink();
              return Text(
                value >= 1000 ? '${(value / 1000).toStringAsFixed(0)}k' : value.toStringAsFixed(0),
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              );
            },
          ),
        ),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      gridData: FlGridData(show: true, horizontalInterval: maxY / 4),
      borderData: FlBorderData(show: false),
      barGroups: sortedKeys.asMap().entries.map((entry) {
        final index = entry.key;
        final key = entry.value;
        return BarChartGroupData(
          x: index,
          barRods: [
            BarChartRodData(
              toY: mesecniIznosi[key] ?? 0,
              color: Colors.greenAccent,
              width: 16,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ],
        );
      }).toList(),
    );
  }
}

// ─── Dijalozi ────────────────────────────────────────────────────────────────

class _KreditFormResult {
  final String naziv;
  final double ukupanIznos;
  final String? napomena;
  final DateTime? krajKredita;
  const _KreditFormResult({
    required this.naziv,
    required this.ukupanIznos,
    this.napomena,
    this.krajKredita,
  });
}

class _KreditDialog extends StatefulWidget {
  const _KreditDialog({this.kredit});
  final V3Kredit? kredit;

  @override
  State<_KreditDialog> createState() => _KreditDialogState();
}

class _KreditDialogState extends State<_KreditDialog> {
  late final TextEditingController _nazivCtrl;
  late final TextEditingController _iznosCtrl;
  late final TextEditingController _napomenaCtrl;
  DateTime? _krajKredita;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nazivCtrl = TextEditingController(text: widget.kredit?.naziv ?? '');
    _iznosCtrl = TextEditingController(
      text: widget.kredit != null ? widget.kredit!.ukupanIznos.toStringAsFixed(0) : '',
    );
    _napomenaCtrl = TextEditingController(text: widget.kredit?.napomena ?? '');
    _krajKredita = widget.kredit?.krajKredita;
  }

  @override
  void dispose() {
    _nazivCtrl.dispose();
    _iznosCtrl.dispose();
    _napomenaCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _krajKredita ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: _KredTr.tr('krajKreditaZadnjaRata'),
    );
    if (picked != null) {
      V3StateUtils.safeSetState(this, () => _krajKredita = picked);
    }
  }

  Future<void> _save() async {
    final naziv = _nazivCtrl.text.trim();
    final iznos = double.tryParse(_iznosCtrl.text.replaceAll(',', '.')) ?? 0.0;

    if (naziv.isEmpty) {
      V3AppSnackBar.error(context, _KredTr.tr('nazivJeObavezan'));
      return;
    }
    if (iznos < 0) {
      V3AppSnackBar.error(context, _KredTr.tr('iznosNeMozeBitiNegativan'));
      return;
    }

    V3StateUtils.safeSetState(this, () => _saving = true);
    await Future<void>.delayed(Duration.zero);
    if (mounted) {
      Navigator.pop(
        context,
        _KreditFormResult(
          naziv: naziv,
          ukupanIznos: iznos,
          napomena: _napomenaCtrl.text.trim().isEmpty ? null : _napomenaCtrl.text.trim(),
          krajKredita: _krajKredita,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.9),
        decoration: BoxDecoration(
          gradient: Theme.of(context).backgroundGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).glassBorder, width: 0.8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.kredit == null ? _KredTr.tr('dodajKreditTitle') : _KredTr.tr('izmeniKredit'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 16),
              V3InputUtils.textField(
                controller: _nazivCtrl,
                label: _KredTr.tr('nazivPlaceholder'),
              ),
              const SizedBox(height: 12),
              V3InputUtils.numberField(
                controller: _iznosCtrl,
                label: _KredTr.tr('ukupanIznosRsd'),
                suffixText: 'din',
              ),
              const SizedBox(height: 12),
              V3InputUtils.textField(
                controller: _napomenaCtrl,
                label: _KredTr.tr('napomenaOpciono'),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: _KredTr.tr('krajKreditaOpciono'),
                    labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.78)),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white30),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                    ),
                    suffixIcon: _krajKredita != null
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white54, size: 20),
                            onPressed: () => V3StateUtils.safeSetState(this, () => _krajKredita = null),
                          )
                        : const Icon(Icons.calendar_today, color: Colors.amber, size: 20),
                  ),
                  child: Text(
                    _krajKredita != null
                        ? '${_krajKredita!.day.toString().padLeft(2, '0')}.${_krajKredita!.month.toString().padLeft(2, '0')}.${_krajKredita!.year}'
                        : _KredTr.tr('izaberiDatum'),
                    style: TextStyle(
                      color: _krajKredita != null ? Colors.white : Colors.white54,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: V3ButtonUtils.outlinedButton(
                      onPressed: () => Navigator.pop(context),
                      text: _KredTr.tr('otkazi'),
                      borderColor: Colors.white24,
                      foregroundColor: Colors.white70,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: V3ButtonUtils.successButton(
                      onPressed: _saving ? null : _save,
                      text: _KredTr.tr('sacuvaj'),
                      icon: Icons.save,
                      isLoading: _saving,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UplataResult {
  final double iznos;
  final String? napomena;
  const _UplataResult({required this.iznos, this.napomena});
}

class _UplataDialog extends StatefulWidget {
  const _UplataDialog({required this.kredit});
  final V3Kredit kredit;

  @override
  State<_UplataDialog> createState() => _UplataDialogState();
}

class _UplataDialogState extends State<_UplataDialog> {
  late final TextEditingController _iznosCtrl;
  late final TextEditingController _napomenaCtrl;

  @override
  void initState() {
    super.initState();
    _iznosCtrl = TextEditingController(
      text: widget.kredit.preostalo > 0 ? widget.kredit.preostalo.toStringAsFixed(0) : '',
    );
    _napomenaCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _iznosCtrl.dispose();
    _napomenaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.9),
        decoration: BoxDecoration(
          gradient: Theme.of(context).backgroundGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).glassBorder, width: 0.8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${_KredTr.tr('uplataNaziv')}: ${widget.kredit.naziv}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                '${_KredTr.tr('preostalo')}: ${V3FormatUtils.formatBroj(widget.kredit.preostalo.round())} din',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              V3InputUtils.numberField(
                controller: _iznosCtrl,
                label: _KredTr.tr('iznosUplate'),
                suffixText: 'din',
              ),
              const SizedBox(height: 12),
              V3InputUtils.textField(
                controller: _napomenaCtrl,
                label: _KredTr.tr('napomenaOpciono'),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: V3ButtonUtils.outlinedButton(
                      onPressed: () => Navigator.pop(context),
                      text: _KredTr.tr('otkazi'),
                      borderColor: Colors.white24,
                      foregroundColor: Colors.white70,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: V3ButtonUtils.successButton(
                      onPressed: () {
                        final iznos = double.tryParse(_iznosCtrl.text.replaceAll(',', '.')) ?? 0.0;
                        if (iznos <= 0) {
                          V3AppSnackBar.error(context, _KredTr.tr('iznosMoraBitiVeciOdNule'));
                          return;
                        }
                        Navigator.pop(
                          context,
                          _UplataResult(
                            iznos: iznos,
                            napomena: _napomenaCtrl.text.trim().isEmpty ? null : _napomenaCtrl.text.trim(),
                          ),
                        );
                      },
                      text: _KredTr.tr('uplati'),
                      icon: Icons.payments,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap, required this.color});
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}
