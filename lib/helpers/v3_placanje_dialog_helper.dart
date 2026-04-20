import 'package:flutter/material.dart';

import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_finansije_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_date_utils.dart';
import '../utils/v3_dialog_helper.dart';

class V3PlacanjeRezultat {
  final double iznos;
  final int mesec;
  final int godina;
  const V3PlacanjeRezultat({
    required this.iznos,
    required this.mesec,
    required this.godina,
  });
}

class V3PlacanjeDialogHelper {
  V3PlacanjeDialogHelper._();

  static Map<String, dynamic>? _getZadnjaNaplata(String putnikId) {
    final cache = V3MasterRealtimeManager.instance.getCache('v3_finansije').values;
    final placenoRows = cache.where((row) {
      if (row['tip']?.toString() != 'prihod') return false;
      if ((row['kategorija']?.toString().toLowerCase() ?? '') != 'operativna_naplata') return false;
      if (row['putnik_v3_auth_id']?.toString() != putnikId) return false;
      final vremePlacen = row['created_at']?.toString();
      return vremePlacen != null && vremePlacen.isNotEmpty;
    }).toList();

    if (placenoRows.isEmpty) return null;

    placenoRows.sort((a, b) {
      final aDt = V3DateUtils.parseTs(a['created_at']?.toString()) ?? DateTime(2000);
      final bDt = V3DateUtils.parseTs(b['created_at']?.toString()) ?? DateTime(2000);
      return bDt.compareTo(aDt);
    });

    final last = placenoRows.first;
    final vozacId = last['naplacen_by']?.toString();
    final vozacIme = vozacId == null ? null : V3VozacService.getVozacById(vozacId)?.imePrezime;

    return {
      'placeno_at': last['created_at'],
      'placeno_iznos': (last['iznos'] as num?)?.toDouble() ?? 0.0,
      'naplatio_ime': vozacIme ?? 'Nepoznato',
    };
  }

  static String _formatDatumVreme(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  static Future<V3PlacanjeRezultat?> prikaziDialog({
    required BuildContext context,
    required String putnikId,
    required String imePrezime,
    required double defaultCena,
    bool zakljucajIznos = false,
  }) async {
    final TextEditingController _iznosController = TextEditingController(text: defaultCena.toStringAsFixed(0));

    int _selectedMonth = DateTime.now().month;
    int _selectedYear = DateTime.now().year;
    final currentYear = DateTime.now().year;
    final years = List.generate(6, (i) => currentYear - 1 + i);
    final zadnjaNaplata = _getZadnjaNaplata(putnikId);
    final vremePlacen = V3DateUtils.parseTs(zadnjaNaplata?['placeno_at']?.toString());
    final zadnjiIznos = (zadnjaNaplata?['placeno_iznos'] as num?)?.toDouble() ?? 0.0;
    final naplatioIme = (zadnjaNaplata?['naplatio_ime']?.toString() ?? 'Nepoznato').trim();

    return V3DialogHelper.showDialogBuilder<V3PlacanjeRezultat>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final cs = Theme.of(context).colorScheme;
          return AlertDialog(
            backgroundColor: cs.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: cs.outline.withValues(alpha: 0.25), width: 1),
            ),
            titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
            contentPadding: const EdgeInsets.fromLTRB(22, 6, 22, 8),
            actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            title: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.payments_outlined, color: cs.primary, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Naplata: $imePrezime',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (zadnjaNaplata != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Zadnja naplata',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Datum: ${vremePlacen == null ? '-' : _formatDatumVreme(vremePlacen)}',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                        Text(
                          'Iznos: ${zadnjiIznos.toStringAsFixed(0)} RSD',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                        Text('Naplatio: $naplatioIme', style: TextStyle(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                TextField(
                  controller: _iznosController,
                  readOnly: zakljucajIznos,
                  decoration: InputDecoration(
                    labelText: zakljucajIznos ? 'Iznos (zaključano)' : 'Iznos (RSD)',
                    suffixText: 'RSD',
                    prefixIcon: const Icon(Icons.payments_outlined),
                  ),
                  style: TextStyle(color: cs.onSurface),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: 'Mesec',
                          prefixIcon: Icon(Icons.calendar_month_outlined),
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        value: _selectedMonth,
                        isExpanded: true,
                        items: List.generate(12, (i) => i + 1).map((m) {
                          return DropdownMenuItem(
                            value: m,
                            child: Text(_getMonthName(m)),
                          );
                        }).toList(),
                        onChanged: (v) => setState(() => _selectedMonth = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: 'Godina',
                          prefixIcon: Icon(Icons.event_outlined),
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        value: _selectedYear,
                        isExpanded: true,
                        items: years.map((y) {
                          return DropdownMenuItem(value: y, child: Text('$y.'));
                        }).toList(),
                        onChanged: (v) => setState(() => _selectedYear = v!),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(foregroundColor: cs.error),
                child: const Text('ODUSTANI'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                onPressed: () {
                  final rawIznos = _iznosController.text.trim().replaceAll(',', '.');
                  final iznos = zakljucajIznos ? defaultCena : (double.tryParse(rawIznos) ?? 0);
                  if (iznos <= 0) {
                    V3AppSnackBar.warning(context, 'Unesite ispravan iznos (> 0 RSD).');
                    return;
                  }
                  Navigator.pop(
                    context,
                    V3PlacanjeRezultat(
                      iznos: iznos,
                      mesec: _selectedMonth,
                      godina: _selectedYear,
                    ),
                  );
                },
                child: const Text('POTVRDI'),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _getMonthName(int m) {
    const names = [
      'Januar',
      'Februar',
      'Mart',
      'April',
      'Maj',
      'Jun',
      'Jul',
      'Avgust',
      'Septembar',
      'Oktobar',
      'Novembar',
      'Decembar'
    ];
    return names[m - 1];
  }

  static Future<bool> sacuvajPlacanje({
    required BuildContext context,
    required String putnikId,
    required String imePrezime,
    required V3PlacanjeRezultat rezultat,
    String? operativnaId,
    String? zahtevId,
    bool snimiMesecnuUplatu = false,
  }) async {
    try {
      final vozac = V3VozacService.currentVozac;
      if (vozac == null) throw 'Vozač nije ulogovan u V3';

      if (snimiMesecnuUplatu) {
        await V3FinansijeService.sacuvajMesecnuOperativnuNaplatu(
          putnikId: putnikId,
          naplacenoBy: vozac.id,
          iznos: rezultat.iznos,
          mesec: rezultat.mesec,
          godina: rezultat.godina,
        );
      } else {
        final operativna = (operativnaId ?? '').trim();
        if (operativna.isEmpty) {
          throw 'Operativna vožnja nije pronađena za ovu naplatu.';
        }
        await V3FinansijeService.sacuvajOperativnuNaplatu(
          operativnaId: operativna,
          putnikId: putnikId,
          naplacenoBy: vozac.id,
          iznos: rezultat.iznos,
          datum: DateTime.now(),
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        V3AppSnackBar.error(context, 'Greška pri naplati: $e');
      }
      return false;
    }
  }
}
