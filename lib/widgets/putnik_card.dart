// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/putnik.dart';
import '../services/cena_obracun_service.dart';
import '../services/haptic_service.dart';
import '../services/permission_service.dart';
import '../services/putnik_service.dart';
import '../services/registrovani_putnik_service.dart';
import '../services/unified_geocoding_service.dart';
import '../theme.dart';
import '../utils/app_snack_bar.dart';
import '../utils/card_color_helper.dart';
import '../utils/vozac_cache.dart';

/// Widget za prikaz putnik kartice sa podrškom za mesecne i dnevne putnike

class PutnikCard extends StatefulWidget {
  const PutnikCard({
    super.key,
    required this.putnik,
    this.showActions = true,
    required this.currentDriver,
    this.redniBroj,
    this.bcVremena,
    this.vsVremena,
    this.selectedVreme,
    this.selectedGrad,
    this.selectedDay,
    this.onChanged,
    this.onPokupljen,
  });
  final Putnik putnik;
  final bool showActions;
  final String currentDriver;
  final int? redniBroj;
  final List<String>? bcVremena;
  final List<String>? vsVremena;
  final String? selectedVreme;
  final String? selectedGrad;
  final String? selectedDay;
  final VoidCallback? onChanged;
  final VoidCallback? onPokupljen;

  @override
  State<PutnikCard> createState() => _PutnikCardState();
}

class _PutnikCardState extends State<PutnikCard> {
  late Putnik _putnik;
  Timer? _longPressTimer;
  bool _isLongPressActive = false;
  bool _isProcessing = false; // ⏳ Sprečava duple klikove tokom procesiranja

  // 🔒 GLOBALNI LOCK - blokira SVE kartice dok jedan putnik nije zaVrsen u bazi
  static bool _globalProcessingLock = false;

  @override
  void initState() {
    super.initState();
    _putnik = widget.putnik;
  }

  @override
  void didUpdateWidget(PutnikCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 🔄 FIX: UVEK ažuriraj _putnik kada se widget promeni
    // Ovo garantuje da realtime promene (pokupljenje, otkazivanje)
    // budu odmah vidljive bez obzira na == operator
    _putnik = widget.putnik;
  }

  // Format za otkazivanje - prikazuje vreme ako je danas, inače datum i vreme
  String _formatOtkazivanje(DateTime vreme) {
    final danas = DateTime.now();
    final jeDanas = vreme.year == danas.year && vreme.month == danas.month && vreme.day == danas.day;

    final vremeStr = '${vreme.hour.toString().padLeft(2, '0')}:${vreme.minute.toString().padLeft(2, '0')}';

    if (jeDanas) {
      // Danas - prikaži samo vreme
      return vremeStr;
    } else {
      // Ranije - prikaži datum i vreme za veću preciznost
      return '${vreme.day}.${vreme.month}. $vremeStr';
    }
  }

  String _formatVreme(DateTime vreme) {
    return '${vreme.hour.toString().padLeft(2, '0')}:${vreme.minute.toString().padLeft(2, '0')}';
  }

  // 💰 UNIVERZALNA METODA ZA PLAĆANJE - custom cena za sve tipove putnika
  Future<void> _handlePayment() async {
    // 🛡️ FIX: Validacija vozača pre pokušaja plaćanja - koristi VozacCache
    final vozacUuid = VozacCache.getUuidByIme(widget.currentDriver);
    if (vozacUuid == null) {
      if (mounted) {
        AppSnackBar.error(context, 'Greška: Vozač nije definisan u sistemu');
      }
      return;
    }

    if (_putnik.mesecnaKarta == true) {
      // MESECNI PUTNIK - CUSTOM CENA umesto fiksne
      await _handleRegistrovaniPayment();
    } else if (_putnik.isDnevniTip) {
      // DNEVNI PUTNIK - obračun na osnovu cene iz baze
      await _handleDnevniPayment();
    } else {
      // OBICNI PUTNIK - unos custom iznosa
      await _handleObicniPayment();
    }
  }

  // ?? PLACANJE DNEVNOG PUTNIKA - ukupna suma odjednom
  Future<void> _handleDnevniPayment() async {
    // Koristi centralizovanu logiku cena iz modela
    final double cenaPoMestu = _putnik.effectivePrice;

    final int brojMesta = _putnik.brojMesta;
    final double ukupnaSuma = cenaPoMestu * brojMesta;

    // Naplacujemo sve odjednom
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outline,
              width: 2,
            ),
          ),
          title: Row(
            children: [
              Icon(
                Icons.today,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Dnevna karta',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Putnik: ${_putnik.ime}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Relacija: ${_putnik.grad}',
                style: TextStyle(color: Colors.grey[600]),
              ),
              Text(
                'Polazak: ${_putnik.polazak}',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  children: [
                    if (brojMesta > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          'Ukupno za $brojMesta mesta:',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
                          ),
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.attach_money,
                          size: 32,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${ukupnaSuma.toStringAsFixed(0)} RSD',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Odustani'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.payment),
              label: const Text('Potvrdi placanje'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      // Provjeri da li putnik ima valjan ID
      if (_putnik.id == null || _putnik.id.toString().isEmpty) {
        if (mounted) {
          AppSnackBar.error(context, 'Putnik nema valjan ID - ne može se naplatiti');
        }
        return;
      }

      // Izvr�i placanje za sve odjednom
      await _executePayment(
        ukupnaSuma,
        isRegistrovani: false,
      );

      if (mounted) {
        AppSnackBar.payment(context, 'Naplaćeno $brojMesta mesta - Ukupno: ${ukupnaSuma.toStringAsFixed(0)} RSD');
      }
    }
  }

  // ?? PLACANJE MESECNE KARTE - CUSTOM CENA (korisnik unosi iznos)
  Future<void> _handleRegistrovaniPayment() async {
    // Prvo dohvati mesecnog putnika iz baze po imenu (ne po ID!)
    final registrovaniPutnik = await RegistrovaniPutnikService.getRegistrovaniPutnikByIme(_putnik.ime);

    if (registrovaniPutnik == null) {
      if (mounted) {
        AppSnackBar.error(context, 'Greška: Mesečni putnik "${_putnik.ime}" nije pronađen');
      }
      return;
    }

    // UCITAJ SVA PLACANJA IZ BAZE za ovog putnika
    Set<String> placeniMeseci = {};
    try {
      final svaPlacanja = await RegistrovaniPutnikService().dohvatiPlacanjaZaPutnika(_putnik.ime);
      for (var placanje in svaPlacanja) {
        final mesec = placanje['placeniMesec'];
        final godina = placanje['placenaGodina'];
        if (mesec != null && godina != null) {
          // Format: "mesec-godina" za internu proveru
          placeniMeseci.add('$mesec-$godina');
        }
      }
    } catch (e) {
      // Ako ne mo�emo ucitati, ostaje prazan set
    }

    // Racuna za ceo trenutni mesec (1. do 30.)
    final currentDate = DateTime.now();
    final firstDayOfMonth = DateTime(currentDate.year, currentDate.month);
    final lastDayOfMonth = DateTime(
      currentDate.year,
      currentDate.month + 1,
      0,
    ); // poslednji dan u mesecu

    // Broj putovanja za trenutni mesec
    int brojPutovanja = 0;
    int brojOtkazivanja = 0;
    try {
      brojPutovanja = await RegistrovaniPutnikService.izracunajBrojPutovanjaIzIstorije(
        _putnik.id! as String,
      );
      // Racunaj otkazivanja iz stvarne istorije
      brojOtkazivanja = await RegistrovaniPutnikService.izracunajBrojOtkazivanjaIzIstorije(
        _putnik.id! as String,
      );
    } catch (e) {
      // Greška pri čitanju - koristi 0
      brojPutovanja = 0;
      brojOtkazivanja = 0;
    }

    if (!mounted) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        // 💰 Sugeriši cenu na osnovu tipa putnika
        final sugerisanaCena = CenaObracunService.getCenaPoDanu(registrovaniPutnik);

        final tipLower = registrovaniPutnik.tip.toLowerCase();
        final imeLower = registrovaniPutnik.putnikIme.toLowerCase();

        // 🔒 FIKSNE CENE (Vozači ne mogu da menjaju)
        final jeZubi = tipLower == 'posiljka' && imeLower.contains('zubi');
        final jePosiljka = tipLower == 'posiljka';
        final jeDnevni = tipLower == 'dnevni';
        final jeFiksna = jeZubi || jePosiljka || jeDnevni;

        final controller = TextEditingController(text: sugerisanaCena.toStringAsFixed(0));
        String selectedMonth = '${_getMonthNameStatic(DateTime.now().month)} ${DateTime.now().year}';

        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outline,
                width: 2,
              ),
            ),
            title: Row(
              children: [
                Icon(
                  jeFiksna ? Icons.lock : Icons.card_membership,
                  color: jeFiksna ? Colors.orange : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  jeFiksna ? 'Naplata (FIKSNO)' : 'Mesecna karta',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Osnovne informacije
                  Text(
                    'Putnik: ${_putnik.ime}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (jeFiksna)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        jeZubi
                            ? 'Tip: Po�iljka ZUBI (300 RSD)'
                            : (jePosiljka ? 'Tip: Po�iljka (500 RSD)' : 'Tip: Dnevni (600 RSD)'),
                        style: TextStyle(
                          color: jeZubi ? Colors.purple : (jePosiljka ? Colors.blue : Colors.orange),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'Grad: ${_putnik.grad}',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),

                  // STATISTIKE ODSEK
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.analytics,
                              color: Theme.of(context).colorScheme.primary,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Statistike za trenutni mesec',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '📅 Putovanja:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                Text(
                                  '$brojPutovanja',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.successPrimary,
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Otkazivanja:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                Text(
                                  '$brojOtkazivanja',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (placeniMeseci.isNotEmpty) ...[
                          // Prika�i period ako ima placanja
                          const SizedBox(height: 6),
                          Text(
                            'Period: ${_formatDate(firstDayOfMonth)} - ${_formatDate(lastDayOfMonth)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // IZBOR MESECA
                  Text(
                    'Mesec za koji se placa:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: TripleBlueFashionStyles.dropdownDecoration,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedMonth,
                        isExpanded: true,
                        dropdownColor: Theme.of(context).colorScheme.surface,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        items: _getMonthOptionsStatic().map((monthYear) {
                          // ?? Proveri da li je mesec placen - KORISTI PODATKE IZ BAZE
                          final parts = monthYear.split(' ');
                          final monthNumber = _getMonthNumberStatic(parts[0]);
                          final year = int.tryParse(parts[1]) ?? 0;
                          final bool isPlacen = placeniMeseci.contains('$monthNumber-$year');

                          return DropdownMenuItem<String>(
                            value: monthYear,
                            child: Row(
                              children: [
                                Icon(
                                  isPlacen ? Icons.check_circle : Icons.calendar_today,
                                  size: 16,
                                  color: isPlacen
                                      ? Theme.of(context).colorScheme.successPrimary
                                      : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  monthYear,
                                  style: TextStyle(
                                    color: isPlacen ? Theme.of(context).colorScheme.successPrimary : null,
                                    fontWeight: isPlacen ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (String? newMonth) {
                          if (newMonth != null) {
                            if (mounted) {
                              setState(() {
                                selectedMonth = newMonth;
                              });
                            }
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // UNOS CENE
                  TextField(
                    controller: controller,
                    enabled: !jeFiksna, // ?? Onemoguci izmenu za fiksne cene
                    readOnly: jeFiksna, // ?? Read only
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: jeFiksna ? 'Fiksni iznos (RSD)' : 'Iznos (RSD)',
                      prefixIcon: const Icon(Icons.attach_money),
                      border: const OutlineInputBorder(),
                      fillColor: jeFiksna ? Colors.grey.withOpacity(0.1) : null,
                      filled: jeFiksna,
                      helperText: jeFiksna ? 'Ovaj tip putnika ima fiksnu cenu.' : null,
                    ),
                    autofocus: !jeFiksna,
                  ),
                  const SizedBox(height: 12),

                  // INFO ODSEK
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.successPrimary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Theme.of(context).colorScheme.successPrimary,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Mo�ete platiti isti mesec vi�e puta. Svako placanje se evidentira.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Odustani'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  final value = double.tryParse(controller.text);
                  if (value != null && value > 0) {
                    Navigator.of(ctx).pop({
                      'iznos': value,
                      'mesec': selectedMonth,
                    });
                  }
                },
                icon: const Icon(Icons.payment),
                label: const Text('Potvrdi placanje'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.successPrimary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );
      },
    );

    if (result != null && result['iznos'] != null && mounted) {
      // Koristimo iznos koji je korisnik uneo u dialog
      await _executePayment(
        result['iznos'] as double,
        mesec: result['mesec'] as String?,
        isRegistrovani: true,
      );
    }
  }

  // ?? PLACANJE OBICNOG PUTNIKA - standardno
  Future<void> _handleObicniPayment() async {
    double? iznos = await showDialog<double>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outline,
              width: 2,
            ),
          ),
          title: Row(
            children: [
              Icon(
                Icons.person,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Placanje putovanja',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Putnik: ${_putnik.ime}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Relacija: ${_putnik.grad}',
                style: TextStyle(color: Colors.grey[600]),
              ),
              Text(
                'Polazak: ${_putnik.polazak}',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Iznos (RSD)',
                  prefixIcon: Icon(Icons.attach_money),
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Odustani'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final value = double.tryParse(controller.text);
                if (value != null && value > 0) {
                  Navigator.of(ctx).pop(value);
                }
              },
              icon: const Icon(Icons.payment),
              label: const Text('Potvrdi placanje'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );

    if (iznos != null && iznos > 0) {
      // Provjeri da li putnik ima valjan ID
      if (_putnik.id == null || _putnik.id.toString().isEmpty) {
        if (mounted) {
          AppSnackBar.error(context, 'Putnik nema valjan ID - ne može se naplatiti');
        }
        return;
      }

      try {
        await _executePayment(iznos, isRegistrovani: false);

        // Haptic feedback za uspe�no placanje
        HapticService.lightImpact();
      } catch (e) {
        if (mounted) {
          AppSnackBar.error(context, 'Greška pri plaćanju: $e');
        }
      }
    }
  }

  // Izvr�avanje placanja - zajednicko za oba tipa
  Future<void> _executePayment(
    double iznos, {
    required bool isRegistrovani,
    String? mesec,
  }) async {
    // 🔒 GLOBALNI LOCK - ako BILO KOJA kartica procesira, ignoriši
    if (_globalProcessingLock) return;
    // 🔒 ZAŠTITA OD DUPLOG KLIKA - ako već procesiramo, ignoriši
    if (_isProcessing) return;

    try {
      _globalProcessingLock = true;
      if (mounted) {
        setState(() {
          _isProcessing = true;
        });
      }

      // ⏱️ KRATKA PAUZA - samo da se UI osveži
      await Future<void>.delayed(const Duration(milliseconds: 100));

      if (!mounted) {
        _globalProcessingLock = false;
        return;
      }

      // Pozovi odgovarajući service za plaćanje
      if (isRegistrovani && mesec != null) {
        // Validacija da putnik ime nije prazno
        if (_putnik.ime.trim().isEmpty) {
          throw Exception('Ime putnika je prazno - ne mo�e se pronaci u bazi');
        }

        // Za mesecne putnike koristi funkciju iz registrovani_putnici_screen.dart
        final registrovaniPutnik = await RegistrovaniPutnikService.getRegistrovaniPutnikByIme(_putnik.ime);
        if (registrovaniPutnik != null) {
          // Koristi static funkciju kao u registrovani_putnici_screen.dart
          await _sacuvajPlacanjeStatic(
            putnikId: registrovaniPutnik.id,
            iznos: iznos,
            mesec: mesec,
            vozacIme: widget.currentDriver,
          );
        } else {
          throw Exception('Mesecni putnik "${_putnik.ime}" nije pronaden u bazi');
        }
      } else {
        // Za obicne putnike koristi postojeci servis
        if (_putnik.id == null) {
          throw Exception('Putnik nema valjan ID - ne mo�e se naplatiti');
        }

        // ? FIX: �alji grad umesto place - oznaciPlaceno sada sam racuna place
        // ISTO kao oznaciPokupljen - konzistentna logika!
        await PutnikService().oznaciPlaceno(
          _putnik.id!,
          iznos,
          widget.currentDriver,
          grad: _putnik.grad,
          selectedVreme: _putnik.polazak,
          selectedDan: _putnik.dan,
        );
      }

      // ✅ OSVEŽI STANJE PUTNIKA - postavi placeno na true
      if (mounted) {
        setState(() {
          _putnik = _putnik.copyWith(placeno: true);
        });

        AppSnackBar.payment(context, 'Plaćanje uspešno evidentirano: $iznos RSD');
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, 'Greška pri plaćanju: $e');
      }
    } finally {
      // ✅ OBAVEZNO OSLOBODI LOCK
      _globalProcessingLock = false;
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  // 🚶 Metoda za pokupljenje putnika
  Future<void> _handlePickup() async {
    if (_globalProcessingLock || _isProcessing) return;

    _globalProcessingLock = true;
    _isProcessing = true;

    try {
      // 📳 Haptic feedback
      HapticService.mediumImpact();

      // 🛡️ NOVO: Direktno označi kao pokupljen u bazi (seat_requests)
      await PutnikService().oznaciPokupljen(
        _putnik.id!,
        true,
        grad: _putnik.grad,
        vreme: _putnik.polazak,
        driver: widget.currentDriver,
        datum: _putnik.datum,
        requestId: _putnik.requestId,
      );

      if (mounted) {
        // 📳 JACA VIBRACIJA
        await HapticService.putnikPokupljen();

        if (widget.onChanged != null) {
          widget.onChanged!();
        }

        AppSnackBar.success(context, 'Pokupljen: ${_putnik.ime}');
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, 'Greška pri pokupljenju: $e');
      }
    } finally {
      // ✅ OBAVEZNO OSLOBODI LOCK
      _globalProcessingLock = false;
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _pozovi() async {
    if (_putnik.brojTelefona == null || _putnik.brojTelefona!.isEmpty) return;

    final Uri launchUri = Uri(
      scheme: 'tel',
      path: _putnik.brojTelefona,
    );
    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      }
    } catch (e) {
      debugPrint('Greška pri pozivu: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Odredi ko je "vlasnik" ovog putnika za potrebe bojenja (siva vs bela)
    String displayDodeljenVozac = _putnik.dodeljenVozac ?? '';

    // 🎨 BOJE KARTICE - koristi CardColorHelper sa pročišćenim vozačem
    final _colorHelper = CardColorHelper();
    final BoxDecoration cardDecoration = _colorHelper.getCardDecorationWithDriver(
      _putnik,
      widget.currentDriver, // Ko gleda
    );

    // FIX: Ako putnik nije moj (ni po slotu ni direktno), forsira sivu boju preko stanja
    // Ali CardColorHelper to već radi ako mu prosledimo ko je vlasnik putnika vs ko gleda.
    // Međutim, CardColorHelper unutra gleda putnik.dodeljenVozac.
    // Moramo mu "podmetnuti" putnika sa ispravnim vozačem ili izmeniti CardColorHelper.

    // Jednostavnije: Privremeni putnik za kalkulaciju boja
    final displayPutnik = _putnik.copyWith(dodeljenVozac: displayDodeljenVozac);

    final BoxDecoration finalDecoration = _colorHelper.getCardDecorationWithDriver(
      displayPutnik,
      widget.currentDriver,
    );
    final Color textColor = _colorHelper.getTextColorWithDriver(
      displayPutnik,
      widget.currentDriver,
      context,
      successPrimary: Theme.of(context).colorScheme.successPrimary,
    );
    final Color secondaryTextColor = _colorHelper.getSecondaryTextColorWithDriver(
      displayPutnik,
      widget.currentDriver,
    );

    // Prava po vozacu
    final String driver = widget.currentDriver;
    final bool isBojan = driver == 'Bojan';
    final bool isAdmin = isBojan; // Full admin prava
    final bool isVozac = driver == 'Bruda' || driver == 'Bilevski' || driver == 'Voja'; // Svi vozaci

    if (_putnik.ime.toLowerCase().contains('rado') ||
        _putnik.ime.toLowerCase().contains('radović') ||
        _putnik.ime.toLowerCase().contains('radosev')) {}

    return GestureDetector(
      behavior: HitTestBehavior.opaque, // ? FIX: Hvata tap na celoj kartici
      onLongPressStart: (_) => _startLongPressTimer(),
      onLongPressEnd: (_) => _cancelLongPressTimer(),
      onLongPressCancel: _cancelLongPressTimer,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
        decoration: finalDecoration, // Koristi CardColorHelper
        child: Padding(
          padding: const EdgeInsets.all(6.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.redniBroj != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 4.0),
                      child: Text(
                        '${widget.redniBroj}.',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: textColor, // Koristi CardColorHelper
                        ),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _putnik.ime,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontStyle: FontStyle.italic,
                                  fontSize: 14,
                                  color: textColor,
                                ),
                                // Forsiraj jedan red kao na Samsung-u
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            // Prikaži oznaku broja mesta ako je više od 1
                            if (_putnik.brojMesta > 1)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: textColor.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    // ? Ako je plaćeno, prikaži plaćeni iznos; inače prikaži cenu po mestu
                                    (_putnik.cena != null && (_putnik.cena ?? 0) > 0)
                                        ? 'x${_putnik.brojMesta} (${_putnik.cena!.toStringAsFixed(0)} RSD)'
                                        : 'x${_putnik.brojMesta} (${(_putnik.effectivePrice * _putnik.brojMesta).toStringAsFixed(0)} RSD)',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: textColor,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        // 📍 ADRESA - prikaži adresu sa fallback učitavanjem ako je NULL
                        StreamBuilder<String?>(
                          stream: Stream.fromFuture(_putnik.adresa != null &&
                                  _putnik.adresa!.isNotEmpty &&
                                  _putnik.adresa != 'Adresa nije definisana'
                              ? Future.value(_putnik.adresa) // Ako vec imamo adresu, koristi je odmah
                              : _putnik.getAdresaFallback()), // Inace ucitaj iz baze
                          builder: (context, snapshot) {
                            final displayAdresa = snapshot.data;

                            // 📍 Prikaži adresu samo ako je dostupna i nije placeholder
                            if (displayAdresa != null &&
                                displayAdresa.isNotEmpty &&
                                displayAdresa != 'Adresa nije definisana') {
                              return Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  displayAdresa,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: secondaryTextColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }

                            return const SizedBox.shrink(); // Ništa ako nema adrese
                          },
                        ),
                      ],
                    ),
                  ),
                  // OPTIMIZOVANE ACTION IKONE - koristi Flexible + Wrap umesto fiksne širine
                  // da spreči overflow na manjim ekranima ili kada ima više ikona
                  // Smanjen flex na 0 da ikone ne "kradu" prostor od imena
                  if ((isAdmin || isVozac) && widget.showActions && driver.isNotEmpty)
                    Flexible(
                      flex: 0, // Ne uzimaj dodatni prostor - koristi samo minimalno potreban
                      child: Transform.translate(
                        offset: const Offset(-1, 0), // Pomera ikone levo za 1px
                        child: Container(
                          alignment: Alignment.centerRight,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 🎫 MESEČNA BADGE – prikazuj samo za radnik i učenik tipove
                              if (_putnik.isMesecniTip)
                                Align(
                                  alignment: Alignment.topRight,
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.successPrimary.withOpacity(0.10),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '🎫 MESEČNA',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.successPrimary,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                ),
                              // ULTRA-SAFE ADAPTIVE ACTION IKONE - potpuno eliminiše overflow
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  // Izračunaj dostupnu širinu za ikone
                                  final availableWidth = constraints.maxWidth;

                                  // Ultra-conservative prag sa safety margin - povećani pragovi
                                  final bool isMaliEkran = availableWidth < 180; // povećao sa 170
                                  final bool isMiniEkran = availableWidth < 150; // povećao sa 140

                                  // Tri nivoa adaptacije - značajno smanjene ikone za garantovano fitovanje u jedan red
                                  final double iconSize = isMiniEkran
                                      ? 20 // smanjio sa 22 za mini ekrane
                                      : (isMaliEkran
                                          ? 22 // smanjio sa 25 za male ekrane
                                          : 24); // smanjio sa 28 za normalne ekrane
                                  final double iconInnerSize = isMiniEkran
                                      ? 16 // smanjio sa 18
                                      : (isMaliEkran
                                          ? 18 // smanjio sa 21
                                          : 20); // smanjio sa 24

                                  // Use a Wrap for action icons so they can flow to a
                                  // second line on very narrow devices instead of
                                  // compressing the name text down to a single line.
                                  return Wrap(
                                    alignment: WrapAlignment.end,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      // GPS IKONA ZA NAVIGACIJU - ako postoji adresa (mesecni ili dnevni putnik)
                                      if ((_putnik.mesecnaKarta == true) ||
                                          (_putnik.adresa != null && _putnik.adresa!.isNotEmpty)) ...[
                                        GestureDetector(
                                          onTap: () {
                                            showDialog<void>(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                title: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.location_on,
                                                      color: Theme.of(context).colorScheme.primary,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        '📍 ${_putnik.ime}',
                                                        overflow: TextOverflow.ellipsis,
                                                        maxLines: 1,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                content: Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    const Text(
                                                      'Adresa za pokupljanje:',
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.grey,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Container(
                                                      width: double.infinity,
                                                      padding: const EdgeInsets.all(
                                                        12,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                                        borderRadius: BorderRadius.circular(8),
                                                        border: Border.all(
                                                          color: Colors.blue.withOpacity(0.3),
                                                        ),
                                                      ),
                                                      child: Text(
                                                        _putnik.adresa?.isNotEmpty == true
                                                            ? _putnik.adresa!
                                                            : 'Adresa nije definisana',
                                                        style: const TextStyle(
                                                          fontSize: 16,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                        overflow: TextOverflow.fade,
                                                        maxLines: 3,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                actions: [
                                                  // Dugme za navigaciju - uvek prikaži, koordinate ce se dobiti po potrebi
                                                  TextButton.icon(
                                                    onPressed: () async {
                                                      // INSTANT GPS - koristi novi PermissionService
                                                      final hasPermission =
                                                          await PermissionService.ensureGpsForNavigation();
                                                      if (!hasPermission) {
                                                        if (mounted && context.mounted) {
                                                          AppSnackBar.error(
                                                              context, '📍 GPS dozvole su potrebne za navigaciju');
                                                        }
                                                        return;
                                                      }

                                                      // Proveri internetsku konekciju i dozvole
                                                      try {
                                                        // Pokaži loading sa dužim timeout-om
                                                        if (mounted && context.mounted) {
                                                          AppSnackBar.info(context, '🔄 Pripremam navigaciju...');
                                                        }

                                                        // Dobij koordinate - UNIFIKOVANO za sve putnike
                                                        final koordinate = await _getKoordinateZaAdresu(
                                                          _putnik.grad,
                                                          _putnik.adresa,
                                                          _putnik.adresaId,
                                                        );

                                                        if (mounted && context.mounted) {
                                                          ScaffoldMessenger.of(
                                                            context,
                                                          ).hideCurrentSnackBar();

                                                          if (koordinate != null) {
                                                            // Uspešno - pokaži pozitivnu poruku
                                                            AppSnackBar.success(context, '🚀 Otvaram navigaciju...');
                                                            await _otvoriNavigaciju(
                                                              koordinate,
                                                            );
                                                          } else {
                                                            // Neuspešno - prikaži detaljniju grešku
                                                            AppSnackBar.warning(context,
                                                                '📍 Lokacija nije pronađena\nAdresa: ${_putnik.adresa}\n🔄 Pokušajte ponovo za 10 sekundi');
                                                          }
                                                        }
                                                      } catch (e) {
                                                        if (mounted && context.mounted) {
                                                          AppSnackBar.error(context, '❌ Greška: ${e.toString()}');
                                                        }
                                                      }
                                                    },
                                                    icon: Icon(
                                                      Icons.navigation,
                                                      color: Theme.of(context).colorScheme.primary,
                                                    ),
                                                    label: const Text(
                                                      'Navigacija',
                                                    ),
                                                    style: TextButton.styleFrom(
                                                      foregroundColor: Theme.of(context).colorScheme.primary,
                                                    ),
                                                  ),
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(context),
                                                    child: const Text('Zatvori'),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                          child: Container(
                                            width: iconSize, // Adaptive veličina
                                            height: iconSize,
                                            decoration: BoxDecoration(
                                              // 🌟 Glassmorphism pozadina
                                              gradient: LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [
                                                  Colors.white.withOpacity(0.25),
                                                  Colors.white.withOpacity(0.10),
                                                ],
                                              ),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: Colors.white.withOpacity(0.4),
                                                width: 1.0,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withOpacity(0.15),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Center(
                                              child: Text(
                                                '📍',
                                                style: TextStyle(fontSize: iconInnerSize * 0.8),
                                              ),
                                            ),
                                          ),
                                        ),
                                        // keep spacing minimal for compact layout
                                      ],
                                      // TELEFON IKONA - ako putnik ima telefon
                                      if (_putnik.brojTelefona != null && _putnik.brojTelefona!.isNotEmpty) ...[
                                        GestureDetector(
                                          onTap: _pozovi,
                                          child: Container(
                                            width: iconSize,
                                            height: iconSize,
                                            decoration: BoxDecoration(
                                              // 🌟 Glassmorphism pozadina
                                              gradient: LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [
                                                  Colors.white.withOpacity(0.25),
                                                  Colors.white.withOpacity(0.10),
                                                ],
                                              ),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: Colors.white.withOpacity(0.4),
                                                width: 1.0,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withOpacity(0.15),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Center(
                                              child: Text(
                                                '📞',
                                                style: TextStyle(fontSize: iconInnerSize * 0.8),
                                              ),
                                            ),
                                          ),
                                        ),
                                        // spacer removed to let Wrap spacing control gaps
                                      ],
                                      // 💰 IKONA ZA PLACANJE - za sve korisnike (3. po redu)
                                      if (!_putnik.jeOtkazan &&
                                          (_putnik.mesecnaKarta == true ||
                                              (_putnik.iznosPlacanja == null || _putnik.iznosPlacanja == 0))) ...[
                                        GestureDetector(
                                          onTap: () => _handlePayment(),
                                          child: Container(
                                            width: iconSize,
                                            height: iconSize,
                                            decoration: BoxDecoration(
                                              // 🌟 Glassmorphism pozadina
                                              gradient: LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [
                                                  Colors.white.withOpacity(0.25),
                                                  Colors.white.withOpacity(0.10),
                                                ],
                                              ),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: Colors.white.withOpacity(0.4),
                                                width: 1.0,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withOpacity(0.15),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Center(
                                              child: Text(
                                                '💰',
                                                style: TextStyle(fontSize: iconInnerSize * 0.8),
                                              ),
                                            ),
                                          ),
                                        ),
                                        // spacer removed to let Wrap spacing control gaps
                                      ],
                                      // IKS DUGME - za sve korisnike (4. po redu)
                                      // Vozaci: direktno otkazivanje | Admini: popup sa opcijama
                                      if (!_putnik.jeOtkazan &&
                                          (_putnik.mesecnaKarta == true ||
                                              _putnik.isDnevniTip ||
                                              (_putnik.vremePokupljenja == null &&
                                                  (_putnik.iznosPlacanja == null || _putnik.iznosPlacanja == 0))))
                                        GestureDetector(
                                          onTap: () {
                                            if (isAdmin) {
                                              _showAdminPopup();
                                            } else {
                                              _handleOtkazivanje();
                                            }
                                          },
                                          child: Container(
                                            width: iconSize,
                                            height: iconSize,
                                            decoration: BoxDecoration(
                                              // 🌟 Glassmorphism pozadina
                                              gradient: LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [
                                                  Colors.white.withOpacity(0.25),
                                                  Colors.white.withOpacity(0.10),
                                                ],
                                              ),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: Colors.white.withOpacity(0.4),
                                                width: 1.0,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withOpacity(0.15),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Center(
                                              child: Text(
                                                '❌',
                                                style: TextStyle(fontSize: iconInnerSize * 0.8),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              // Red 2: Pokupljen / Placeno / Otkazano / Odsustvo info
              if (_putnik.jePokupljen || _putnik.jeOtkazan || _putnik.jeOdsustvo || (_putnik.placeno == true))
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: Row(
                    children: [
                      // Pokupljen info
                      if (_putnik.jePokupljen && _putnik.vremePokupljenja != null)
                        Text(
                          'Pokupljen: ${_putnik.vremePokupljenja!.hour.toString().padLeft(2, '0')}:${_putnik.vremePokupljenja!.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 13,
                            color: VozacCache.getColorByUuid(_putnik.pokupioVozacId) != Colors.grey
                                ? VozacCache.getColorByUuid(_putnik.pokupioVozacId)
                                : VozacCache.getColor(_putnik.pokupioVozac ?? _putnik.vozac),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      // Placeno info
                      if (_putnik.placeno == true && _putnik.iznosPlacanja != null) ...[
                        if (_putnik.vremePokupljenja != null) const SizedBox(width: 12),
                        if (_putnik.naplatioVozac != null)
                          Text(
                            'Plaćeno: ${_putnik.iznosPlacanja!.toStringAsFixed(0)}${_putnik.vremePlacanja != null ? ' ${_formatVreme(_putnik.vremePlacanja!)}' : ''}',
                            style: TextStyle(
                              fontSize: 13,
                              color: VozacCache.getColorByUuid(_putnik.naplatioVozacId) != Colors.grey
                                  ? VozacCache.getColorByUuid(_putnik.naplatioVozacId)
                                  : VozacCache.getColor(_putnik.naplatioVozac),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                      // Otkazano info
                      if (_putnik.jeOtkazan && _putnik.vremeOtkazivanja != null) ...[
                        if (_putnik.vremePokupljenja != null || (_putnik.placeno == true)) const SizedBox(width: 12),
                        Text(
                          '${(_putnik.otkazaoVozac == null || _putnik.otkazaoVozac == 'Putnik') ? 'Putnik otkazao' : 'Otkazao'}: ${_formatOtkazivanje(_putnik.vremeOtkazivanja!)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: (_putnik.otkazaoVozac == null || _putnik.otkazaoVozac == 'Putnik')
                                ? Colors.red.shade900
                                : (VozacCache.getColorByUuid(_putnik.otkazaoVozacId) != Colors.grey
                                    ? VozacCache.getColorByUuid(_putnik.otkazaoVozacId)
                                    : VozacCache.getColor(_putnik.otkazaoVozac)),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      // Odsustvo info
                      if (_putnik.jeOdsustvo) ...[
                        if (_putnik.vremePokupljenja != null || _putnik.jeOtkazan || (_putnik.placeno == true))
                          const SizedBox(width: 12),
                        Text(
                          _putnik.jeBolovanje
                              ? 'Bolovanje'
                              : _putnik.jeGodisnji
                                  ? 'Godišnji'
                                  : 'Odsustvo',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              // Status se prikazuje kroz ikone i boje (bolovanje/godišnji), 'radi' status se ne prikazuje
            ], // kraj children liste za Column
          ), // kraj Column
        ), // kraj Padding
      ), // kraj AnimatedContainer
    ); // kraj GestureDetector
  }

  // Helper metode za mesecno placanje
  String _formatDate(DateTime date) {
    return '${date.day}.${date.month}.${date.year}';
  }

  // HELPER FUNKCIJE - ISTO kao u registrovani_putnici_screen.dart
  String _getMonthNameStatic(int month) {
    const months = [
      '',
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
      'Decembar',
    ];
    return months[month];
  }

  int _getMonthNumberStatic(String monthName) {
    const months = {
      'Januar': 1,
      'Februar': 2,
      'Mart': 3,
      'April': 4,
      'Maj': 5,
      'Jun': 6,
      'Jul': 7,
      'Avgust': 8,
      'Septembar': 9,
      'Oktobar': 10,
      'Novembar': 11,
      'Decembar': 12,
    };
    return months[monthName] ?? 0;
  }

  List<String> _getMonthOptionsStatic() {
    final now = DateTime.now();
    List<String> options = [];

    // Dodaj svih 12 meseci trenutne godine
    for (int month = 1; month <= 12; month++) {
      final monthYear = '${_getMonthNameStatic(month)} ${now.year}';
      options.add(monthYear);
    }

    return options;
  }

  // ?? CUVANJE PLACANJA - KOPIJA iz registrovani_putnici_screen.dart
  Future<void> _sacuvajPlacanjeStatic({
    required String putnikId,
    required double iznos,
    required String mesec,
    required String vozacIme,
  }) async {
    try {
      // Parsiraj izabrani mesec (format: "Septembar 2025")
      final parts = mesec.split(' ');
      if (parts.length != 2) {
        throw Exception('Neispravno format meseca: $mesec');
      }

      final monthName = parts[0];
      final year = int.tryParse(parts[1]);
      if (year == null) {
        throw Exception('Neispravna godina: ${parts[1]}');
      }

      final monthNumber = _getMonthNumberStatic(monthName);
      if (monthNumber == 0) {
        throw Exception('Neispravno ime meseca: $monthName');
      }

      // Kreiraj DateTime za pocetak izabranog meseca
      final pocetakMeseca = DateTime(year, monthNumber);
      final krajMeseca = DateTime(year, monthNumber + 1, 0, 23, 59, 59);

      // ?? FIX: Prosleduj IME vozaca, ne UUID - konverzija se radi u servisu
      // Ime vozaca se koristi za validaciju plaćanja u voznje_log

      // Koristi metodu koja postavlja vreme placanja na trenutni datum
      final uspeh = await RegistrovaniPutnikService().azurirajPlacanjeZaMesec(
        putnikId,
        iznos,
        vozacIme, // 🛠️ FIX: šaljemo IME, ne UUID
        pocetakMeseca,
        krajMeseca,
      );

      if (uspeh) {
        if (mounted) {
          AppSnackBar.payment(context, '💰 Plaćanje od ${iznos.toStringAsFixed(0)} RSD za $mesec je sačuvano');
        }
      } else {
        // ❌ FIX: Baci exception da _executePayment ne prikaže uspešnu poruku
        throw Exception('Greška pri čuvanju plaćanja u bazu');
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, '❌ Greška: $e');
      }
    }
  }

  // ADMIN POPUP MENI - jedinstven pristup svim admin funkcijama
  void _showAdminPopup() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Admin opcije - ${_putnik.ime}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
              // Opcije
              Column(
                children: [
                  // Otkaži
                  if (!_putnik.jeOtkazan)
                    ListTile(
                      leading: const Icon(Icons.close, color: Colors.orange),
                      title: const Text('Otkaži putnika'),
                      subtitle: const Text('Otkaži za trenutno vreme i datum'),
                      onTap: () {
                        Navigator.pop(context);
                        _handleOtkazivanje();
                      },
                    ),
                  // Bez polaska
                  if (!_putnik.jeOtkazan && _putnik.polazak.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.schedule, color: Colors.blue),
                      title: const Text('Bez polaska'),
                      subtitle: const Text('Ukloni vreme polaska'),
                      onTap: () {
                        Navigator.pop(context);
                        _handleBezPolaska();
                      },
                    ),
                  // Godišnji/Bolovanje
                  if (_putnik.mesecnaKarta == true && !_putnik.jeOtkazan && !_putnik.jeOdsustvo)
                    ListTile(
                      leading: const Icon(Icons.beach_access, color: Colors.orange),
                      title: const Text('Godišnji/Bolovanje'),
                      subtitle: const Text('Postavi odsustvo'),
                      onTap: () {
                        Navigator.pop(context);
                        _pokaziOdsustvoPicker();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ?? BEZ POLASKA - Postavi polazak na null (kao "Bez polaska" opcija)
  Future<void> _handleBezPolaska() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: Theme.of(context).colorScheme.outline,
            width: 2,
          ),
        ),
        title: Text(
          'Bez polaska',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Da li ste sigurni da želite da uklonite vreme polaska za ovog putnika?',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        actions: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.grey.shade400,
                  Colors.grey.shade600,
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text(
                'Ne',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: TripleBlueFashionStyles.gradientButton,
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(
                'Da',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // Ukloni polazak za ovaj termin - to će sakriti putnika iz liste (status: bez_polaska)
        await PutnikService().ukloniPolazak(
          _putnik.id!,
          grad: _putnik.grad,
          vreme: _putnik.polazak,
          selectedDan: _putnik.dan,
          datum: _putnik.datum,
          requestId: _putnik.requestId,
        );

        if (mounted) {
          AppSnackBar.info(context, 'Vreme polaska je uklonjeno za danas.');
          // Osvježi lokalno stanje
          setState(() {
            _putnik = _putnik.copyWith(status: 'bez_polaska');
          });
          // Pozovi callback da parent zna da se lista promenila
          widget.onChanged?.call();
        }
      } catch (e) {
        if (mounted) {
          AppSnackBar.error(context, 'Greška: $e');
        }
      }
    }
  }

  // ?? OTKAZIVANJE - izdvojeno u funkciju
  Future<void> _handleOtkazivanje() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: Theme.of(context).colorScheme.outline,
            width: 2,
          ),
        ),
        title: Text(
          'Otkazivanje putnika',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Da li ste sigurni da �elite da oznacite ovog putnika kao otkazanog?',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        actions: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.grey.shade400,
                  Colors.grey.shade600,
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text(
                'Ne',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: TripleBlueFashionStyles.gradientButton,
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(
                'Da',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // Otkaži seat_request za ovaj termin - postavi status 'otkazano' i upiši u voznje_log
        await PutnikService().otkaziPutnika(
          _putnik.id!,
          widget.currentDriver,
          grad: _putnik.grad,
          vreme: _putnik.polazak,
          selectedDan: _putnik.dan,
          datum: _putnik.datum,
          requestId: _putnik.requestId,
          status: 'otkazano',
        );

        // Ažuriraj lokalni _putnik sa novim statusom
        if (mounted) {
          setState(() {
            _putnik = _putnik.copyWith(status: 'otkazano');
          });
          AppSnackBar.error(context, 'Putnik označen kao otkazan.');
          // Pozovi callback da parent zna da se lista promenila
          widget.onChanged?.call();
        }
      } catch (e) {
        if (mounted) {
          AppSnackBar.error(context, 'Greška: $e');
        }
      }
    }
  }

  // 📍 POMOĆNA METODA: Dobij koordinate za adresu (sa keširanjem i validacijom)
  Future<Position?> _getKoordinateZaAdresu(String? grad, String? adresa, String? adresaId) async {
    if (adresa == null || adresa.isEmpty || adresa == 'Adresa nije definisana') return null;

    try {
      // Koristi UnifiedGeocodingService koji ima saVrsenu logiku (Baza -> API)
      final result = await UnifiedGeocodingService.getCoordinatesForPutnici(
        [_putnik],
        saveToDatabase: true, // Automatski sačuvaj u bazu ako nađeš preko API-ja
      );

      if (result.isNotEmpty && result.containsKey(_putnik)) {
        return result[_putnik];
      }
    } catch (e) {
      debugPrint('Greška pri dobijanju koordinata: $e');
    }
    return null;
  }

  // 🚀 NAVIGACIJA — samo HERE WeGo
  Future<void> _otvoriNavigaciju(Position position) async {
    final lat = position.latitude;
    final lng = position.longitude;

    // HERE WeGo native URL scheme
    final hereUrl = Uri.parse('here-route://mylocation/$lat,$lng/now');

    try {
      if (await canLaunchUrl(hereUrl)) {
        await launchUrl(hereUrl, mode: LaunchMode.externalApplication);
      } else {
        // HERE WeGo nije instaliran — prikaži dialog
        if (mounted) {
          showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('HERE WeGo nije instaliran'),
              content: const Text(
                'Da biste koristili navigaciju, potrebno je da instalirate HERE WeGo aplikaciju iz Google Play prodavnice.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Otkaži'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final playUrl = Uri.parse('market://details?id=com.here.app.maps');
                    final playWebUrl = Uri.parse('https://play.google.com/store/apps/details?id=com.here.app.maps');
                    if (await canLaunchUrl(playUrl)) {
                      await launchUrl(playUrl, mode: LaunchMode.externalApplication);
                    } else {
                      await launchUrl(playWebUrl, mode: LaunchMode.externalApplication);
                    }
                  },
                  child: const Text('Instaliraj'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Greška pri otvaranju navigacije: $e');
    }
  }

  // 🏥 PICKER ZA ODSUSTVO (Bolovanje / Godišnji)
  void _pokaziOdsustvoPicker() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.medical_services, color: Colors.red),
              title: const Text('Bolovanje'),
              onTap: () {
                Navigator.pop(context);
                _postaviOdsustvo('bolovanje');
              },
            ),
            ListTile(
              leading: const Icon(Icons.beach_access, color: Colors.blue),
              title: const Text('Godišnji odmor'),
              onTap: () {
                Navigator.pop(context);
                _postaviOdsustvo('godisnji');
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // 📝 POSTAVI ODSUSTVO U BAZU
  Future<void> _postaviOdsustvo(String tip) async {
    try {
      await PutnikService().oznaciBolovanjeGodisnji(
        _putnik.id!,
        tip,
        widget.currentDriver,
      );

      if (mounted) {
        if (widget.onChanged != null) widget.onChanged!();
        AppSnackBar.warning(context, 'Postavljeno: ${tip == 'bolovanje' ? 'Bolovanje' : 'Godišnji'}');
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, 'Greška: $e');
      }
    }
  }

  void _startLongPressTimer() {
    _longPressTimer?.cancel();
    _isLongPressActive = true;

    // 📳 POČETNA VIBRACIJA - da vozač zna da je započeto čekanje
    HapticService.selectionClick();

    // ⏱️ 1.5 sekundi long press - POKUPLJENJE PUTNIKA
    _longPressTimer = Timer(const Duration(milliseconds: 1500), () {
      if (_isLongPressActive && mounted && !_putnik.jeOtkazan && !_putnik.jePokupljen) {
        _handlePickup();
      }
    });
  }

  void _cancelLongPressTimer() {
    _longPressTimer?.cancel();
    _isLongPressActive = false;
  }
}
