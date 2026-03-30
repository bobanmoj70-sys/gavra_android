import 'package:flutter/material.dart';

import '../models/v3_finansije.dart';
import '../models/v3_putnik_arhiva.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_finansije_service.dart';
import '../services/v3/v3_putnici_arhiva_service.dart';
import '../services/v3/v3_putnik_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../utils/v3_app_snack_bar.dart';

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
    final cache = V3MasterRealtimeManager.instance.operativnaNedeljaCache.values;
    final placenoRows = cache.where((row) {
      if (row['putnik_id']?.toString() != putnikId) return false;
      if ((row['naplata_status']?.toString() ?? '') != 'placeno') return false;
      final vremePlacen = row['vreme_placen']?.toString();
      return vremePlacen != null && vremePlacen.isNotEmpty;
    }).toList();

    if (placenoRows.isEmpty) return null;

    placenoRows.sort((a, b) {
      final aDt = DateTime.tryParse(a['vreme_placen']?.toString() ?? '') ?? DateTime(2000);
      final bDt = DateTime.tryParse(b['vreme_placen']?.toString() ?? '') ?? DateTime(2000);
      return bDt.compareTo(aDt);
    });

    final last = placenoRows.first;
    final vozacId = last['naplatio_vozac_id']?.toString();
    final vozacIme = vozacId == null ? null : V3VozacService.getVozacById(vozacId)?.imePrezime;

    return {
      'vreme_placen': last['vreme_placen'],
      'iznos_naplacen': (last['iznos_naplacen'] as num?)?.toDouble() ?? 0.0,
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
    final zadnjaNaplata = _getZadnjaNaplata(putnikId);
    final vremePlacen = DateTime.tryParse(zadnjaNaplata?['vreme_placen']?.toString() ?? '');
    final zadnjiIznos = (zadnjaNaplata?['iznos_naplacen'] as num?)?.toDouble() ?? 0.0;
    final naplatioIme = (zadnjaNaplata?['naplatio_ime']?.toString() ?? 'Nepoznato').trim();

    return showDialog<V3PlacanjeRezultat>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1D2438),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
          contentPadding: const EdgeInsets.fromLTRB(22, 6, 22, 8),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.payments_outlined, color: Colors.greenAccent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Naplata: $imePrezime',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
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
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Zadnja naplata',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Datum: ${vremePlacen == null ? '-' : _formatDatumVreme(vremePlacen.toLocal())}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      Text(
                        'Iznos: ${zadnjiIznos.toStringAsFixed(0)} RSD',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      Text('Naplatio: $naplatioIme', style: const TextStyle(color: Colors.white70)),
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
                style: const TextStyle(color: Colors.white),
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
                      items: [2024, 2025, 2026].map((y) {
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
              child: const Text('ODUSTANI', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onPressed: () {
                final iznos = zakljucajIznos ? defaultCena : (double.tryParse(_iznosController.text) ?? 0);
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
        ),
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
    String? zahtevId,
  }) async {
    try {
      final vozac = V3VozacService.currentVozac;
      if (vozac == null) throw 'Vozač nije ulogovan u V3';
      final putnik = V3PutnikService.getPutnikById(putnikId);
      final tipPutnika = putnik?.tipPutnika ?? '';
      final isMesecnaUplata = tipPutnika == 'radnik' || tipPutnika == 'ucenik';

      final unos = V3FinansijskiUnos(
        id: '', // Baza će generisati UUID
        tip: 'prihod',
        kategorija: 'voznja',
        opis: 'Uplata: $imePrezime (${rezultat.mesec}/${rezultat.godina})',
        iznos: rezultat.iznos,
        datum: DateTime(rezultat.godina, rezultat.mesec, 1),
        vozacId: vozac.id,
        putnikId: putnikId,
        createdAt: DateTime.now(),
      );

      await V3FinansijeService.addUnos(unos);

      await V3PutniciArhivaService.addZapis(
        V3PutnikArhiva(
          id: '',
          putnikId: putnikId,
          putnikImePrezime: imePrezime,
          iznos: rezultat.iznos,
          tipAkcije: isMesecnaUplata ? 'uplata_mesecna' : 'uplata_voznja',
          zaMesec: rezultat.mesec,
          zaGodinu: rezultat.godina,
          vozacId: vozac.id,
          vozacImePrezime: vozac.imePrezime,
          createdBy: 'vozac:${vozac.id}',
          updatedBy: 'vozac:${vozac.id}',
        ),
      );

      // Za radnika i učenika upisujemo i status plaćenog perioda na kartonu putnika.
      if (putnik != null && isMesecnaUplata) {
        final azuriran = putnik.copyWith(
          placeniMesec: rezultat.mesec,
          placenaGodina: rezultat.godina,
        );
        await V3PutnikService.addUpdatePutnik(azuriran, updatedBy: 'vozac:${vozac.id}');
      }

      if (context.mounted) {
        V3AppSnackBar.payment(context, '✅ Naplaćeno ${rezultat.iznos} RSD za $imePrezime');
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
