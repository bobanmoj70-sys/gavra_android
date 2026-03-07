// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';

import '../models/v2_registrovani_putnik.dart';
import '../services/v2_auth_manager.dart';
import '../services/v2_cena_obracun_service.dart';
import '../services/v2_statistika_istorija_service.dart';
import '../theme.dart';
import '../utils/v2_app_snack_bar.dart';
import '../utils/v2_vozac_cache.dart';

/// Rezultat koji helper vraca pozivaocu
class V2PlacanjeRezultat {
  final double iznos;
  final String mesec;
  const V2PlacanjeRezultat({required this.iznos, required this.mesec});
}

/// Jedinstven dijalog za placanje svih tipova putnika.
class V2PlacanjeDialogHelper {
  V2PlacanjeDialogHelper._();

  static Future<V2PlacanjeRezultat?> prikaziDialog({
    required BuildContext context,
    required String putnikId,
    required String putnikIme,
    required String putnikTabela,
    required double cena,
    int brojMesta = 1,
    VoidCallback? onDetaljno,
  }) async {
    final double ukupnaCena = cena > 0 ? cena * brojMesta : 0.0;
    final bool jeFiksna = cena > 0;

    final ukupnoPlaceno = await V2StatistikaIstorijaService.dohvatiUkupnoPlaceno(putnikId);
    final futurePoslednjePlacanje =
        V2StatistikaIstorijaService.dohvatiPlacanja(putnikId).then((l) => l.isNotEmpty ? l.first : null);

    if (!context.mounted) return null;

    V2PlacanjeRezultat? rezultat;

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (BuildContext dialogContext) {
        return _PlacanjeDialogContent(
          putnikIme: putnikIme,
          putnikTabela: putnikTabela,
          jeFiksna: jeFiksna,
          ukupnaCena: ukupnaCena,
          brojMesta: brojMesta,
          ukupnoPlaceno: ukupnoPlaceno,
          futurePoslednjePlacanje: futurePoslednjePlacanje,
          onDetaljno: onDetaljno,
          onConfirm: (r) => rezultat = r,
        );
      },
    );

    return rezultat;
  }

  static Future<bool> sacuvajPlacanje({
    required BuildContext context,
    required String putnikId,
    required String putnikIme,
    required String putnikTabela,
    required double iznos,
    required String mesec,
    String? requestId,
    String? dan,
    String? grad,
    String? vreme,
  }) async {
    try {
      final vozacIme = await V2AuthManager.getCurrentDriver() ?? '';
      final parts = mesec.split(' ');
      if (parts.length != 2) throw Exception('Neispravan format meseca: $mesec');
      final monthNumber = _getMonthNumber(parts[0]);
      if (monthNumber == 0) throw Exception('Neispravno ime meseca: ${parts[0]}');
      final year = int.tryParse(parts[1]) ?? 0;

      final uspeh = await V2StatistikaIstorijaService.upisPlacanjaULog(
        putnikId: putnikId,
        putnikIme: putnikIme,
        putnikTabela: putnikTabela,
        iznos: iznos,
        vozacIme: vozacIme,
        datum: DateTime.now(),
        placeniMesec: monthNumber,
        placenaGodina: year,
        requestId: requestId,
        dan: dan,
        grad: grad,
        vreme: vreme,
      );

      if (uspeh && context.mounted) {
        V2AppSnackBar.payment(context, '\u2705 Pla\u0107anje od ${iznos.toStringAsFixed(0)} RSD za $mesec je sa\u010duvano');
      } else if (!uspeh) {
        throw Exception('Gre\u0161ka pri \u010duvanju pla\u0107anja u bazu');
      }
      return uspeh;
    } catch (e) {
      if (context.mounted) {
        V2AppSnackBar.error(context, '\u274c Gre\u0161ka: $e');
      }
      return false;
    }
  }

  static String _getCurrentMonthYear() {
    final now = DateTime.now();
    return '${_getMonthName(now.month)} ${now.year}';
  }

  static List<String> _getMonthOptions() {
    final now = DateTime.now();
    return List.generate(12, (i) => '${_getMonthName(i + 1)} ${now.year}');
  }

  static int _getMonthNumber(String name) {
    const months = ['', 'Januar', 'Februar', 'Mart', 'April', 'Maj', 'Jun',
        'Jul', 'Avgust', 'Septembar', 'Oktobar', 'Novembar', 'Decembar'];
    return months.indexOf(name).clamp(0, 12);
  }

  static String _getMonthName(int month) {
    const months = ['', 'Januar', 'Februar', 'Mart', 'April', 'Maj', 'Jun',
        'Jul', 'Avgust', 'Septembar', 'Oktobar', 'Novembar', 'Decembar'];
    return month >= 1 && month <= 12 ? months[month] : '';
  }

  static String _tipOpis(String tabela, String ime, double ukupnaCena, int brojMesta) {
    final imeLower = ime.toLowerCase();
    if (tabela == 'v2_posiljke' && imeLower.contains('zubi')) return 'Tip: Po\u0161iljka ZUBI (${ukupnaCena.toStringAsFixed(0)} RSD)';
    if (tabela == 'v2_posiljke') return 'Tip: Po\u0161iljka (${ukupnaCena.toStringAsFixed(0)} RSD)';
    if (tabela == 'v2_dnevni') return brojMesta > 1 ? 'Tip: Dnevni \u2014 $brojMesta mesta (${ukupnaCena.toStringAsFixed(0)} RSD)' : 'Tip: Dnevni (${ukupnaCena.toStringAsFixed(0)} RSD)';
    if (tabela == 'v2_radnici') return 'Tip: Radnik (${ukupnaCena.toStringAsFixed(0)} RSD)';
    if (tabela == 'v2_ucenici') return 'Tip: U\u010denik (${ukupnaCena.toStringAsFixed(0)} RSD)';
    return 'Iznos: ${ukupnaCena.toStringAsFixed(0)} RSD';
  }

  static Color _tipBoja(String tabela, String ime) {
    final imeLower = ime.toLowerCase();
    if (tabela == 'v2_posiljke' && imeLower.contains('zubi')) return Colors.purpleAccent;
    if (tabela == 'v2_posiljke') return Colors.lightBlueAccent;
    if (tabela == 'v2_dnevni') return Colors.orange;
    if (tabela == 'v2_radnici') return Colors.greenAccent;
    if (tabela == 'v2_ucenici') return Colors.cyanAccent;
    return Colors.white70;
  }

  static double getCenaZaPutnika(V2RegistrovaniPutnik putnik, {int brojMesta = 1}) {
    return V2CenaObracunService.getCenaPoDanu(putnik) * brojMesta;
  }
}

// ── PRIVATE WIDGET ────────────────────────────────────────────────────────────

class _PlacanjeDialogContent extends StatefulWidget {
  const _PlacanjeDialogContent({
    required this.putnikIme,
    required this.putnikTabela,
    required this.jeFiksna,
    required this.ukupnaCena,
    required this.brojMesta,
    required this.ukupnoPlaceno,
    required this.futurePoslednjePlacanje,
    required this.onConfirm,
    this.onDetaljno,
  });

  final String putnikIme;
  final String putnikTabela;
  final bool jeFiksna;
  final double ukupnaCena;
  final int brojMesta;
  final double ukupnoPlaceno;
  final Future<Map<String, dynamic>?> futurePoslednjePlacanje;
  final void Function(V2PlacanjeRezultat) onConfirm;
  final VoidCallback? onDetaljno;

  @override
  State<_PlacanjeDialogContent> createState() => _PlacanjeDialogContentState();
}

class _PlacanjeDialogContentState extends State<_PlacanjeDialogContent> {
  late final TextEditingController _iznosController;
  late String _selectedMonth;

  @override
  void initState() {
    super.initState();
    _iznosController = TextEditingController(
      text: widget.ukupnaCena > 0 ? widget.ukupnaCena.toStringAsFixed(0) : '',
    );
    _selectedMonth = V2PlacanjeDialogHelper._getCurrentMonthYear();
  }

  @override
  void dispose() {
    _iznosController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = widget.jeFiksna ? Colors.orange : Colors.purpleAccent;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.95,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        decoration: BoxDecoration(
          gradient: Theme.of(context).backgroundGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 24,
              spreadRadius: 2,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // HEADER
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                border: Border(bottom: BorderSide(color: Theme.of(context).glassBorder)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: accentColor.withValues(alpha: 0.5)),
                    ),
                    child: Icon(
                      widget.jeFiksna ? Icons.lock : Icons.payments_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.jeFiksna ? 'Fiksna naplata' : 'Pla\u0107anje',
                          style: const TextStyle(fontSize: 11, color: Colors.white60, letterSpacing: 0.5),
                        ),
                        Text(
                          widget.putnikIme,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            // CONTENT
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.jeFiksna)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          V2PlacanjeDialogHelper._tipOpis(widget.putnikTabela, widget.putnikIme, widget.ukupnaCena, widget.brojMesta),
                          style: TextStyle(
                            color: V2PlacanjeDialogHelper._tipBoja(widget.putnikTabela, widget.putnikIme),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (!widget.jeFiksna)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.orange, size: 14),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Cena nije postavljena \u2014 unesi iznos ru\u010dno.',
                                style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (widget.ukupnoPlaceno > 0) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Ukupno pla\u0107eno: ${widget.ukupnoPlaceno.toStringAsFixed(0)} RSD',
                                        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.greenAccent, fontSize: 14),
                                      ),
                                      FutureBuilder<Map<String, dynamic>?>(
                                        future: widget.futurePoslednjePlacanje,
                                        builder: (context, snapshot) {
                                          final p = snapshot.data;
                                          if (p == null) return const SizedBox.shrink();
                                          final vozacIme = p['vozac_ime'] as String?;
                                          final datum = p['datum'] as String?;
                                          return Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              if (datum != null)
                                                Text('Poslednje: $datum', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                                              if (vozacIme != null)
                                                Text(
                                                  'Naplatio: $vozacIme',
                                                  style: TextStyle(fontSize: 11, color: V2VozacCache.getColor(vozacIme), fontWeight: FontWeight.w500),
                                                ),
                                            ],
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.blue.withValues(alpha: 0.35)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.add_circle_outline, color: Colors.lightBlueAccent, size: 14),
                                  SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Dodavanje novog pla\u0107anja (bi\u0107e dodato na postoje\u0107a)',
                                      style: TextStyle(fontSize: 11, color: Colors.white60, fontStyle: FontStyle.italic),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        border: Border.all(color: Theme.of(context).glassBorder),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedMonth,
                          isExpanded: true,
                          dropdownColor: Theme.of(context).backgroundGradient.colors.first,
                          icon: const Icon(Icons.calendar_month, color: Colors.white70),
                          style: const TextStyle(color: Colors.white, fontSize: 15),
                          menuMaxHeight: 300,
                          onChanged: (String? newValue) {
                            if (newValue != null) setState(() => _selectedMonth = newValue);
                          },
                          items: V2PlacanjeDialogHelper._getMonthOptions()
                              .map<DropdownMenuItem<String>>((v) => DropdownMenuItem<String>(value: v, child: Text(v)))
                              .toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _iznosController,
                      enabled: !widget.jeFiksna,
                      readOnly: widget.jeFiksna,
                      keyboardType: TextInputType.number,
                      autofocus: !widget.jeFiksna,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: widget.jeFiksna ? 'Fiksni iznos (RSD)' : 'Iznos (RSD)',
                        labelStyle: const TextStyle(color: Colors.white60),
                        prefixIcon: Icon(
                          widget.jeFiksna ? Icons.lock_outline : Icons.attach_money,
                          color: widget.jeFiksna ? Colors.white38 : accentColor,
                        ),
                        helperText: widget.jeFiksna ? 'Fiksna cena za ovaj tip putnika.' : null,
                        helperStyle: const TextStyle(color: Colors.white38),
                        fillColor: Colors.white.withValues(alpha: widget.jeFiksna ? 0.04 : 0.07),
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Theme.of(context).glassBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: accentColor, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        if (widget.onDetaljno != null) ...[
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                widget.onDetaljno!();
                              },
                              icon: const Icon(Icons.analytics_outlined, size: 16),
                              label: const Text('Detaljno'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.lightBlueAccent,
                                side: BorderSide(color: Colors.lightBlueAccent.withValues(alpha: 0.5)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          flex: widget.onDetaljno != null ? 2 : 1,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              final iznos = double.tryParse(_iznosController.text);
                              if (iznos != null && iznos > 0) {
                                widget.onConfirm(V2PlacanjeRezultat(iznos: iznos, mesec: _selectedMonth));
                                Navigator.of(context).pop();
                              } else {
                                V2AppSnackBar.error(context, 'Unesite valjan iznos');
                              }
                            },
                            icon: Icon(widget.ukupnoPlaceno > 0 ? Icons.add : Icons.save, size: 16),
                            label: Text(widget.ukupnoPlaceno > 0 ? '+ Dodaj pla\u0107anje' : 'Sa\u010duvaj'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accentColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 4,
                            ),
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
    );
  }
}
