// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/v2_putnik.dart';
import '../models/v2_registrovani_putnik.dart';
import '../services/v2_auth_manager.dart'; // V2AdminSecurityService spojen ovde
import '../services/v2_cena_obracun_service.dart';
import '../services/v2_haptic_service.dart';
import '../services/v2_permission_service.dart';
import '../services/v2_polasci_service.dart';
import '../services/v2_statistika_istorija_service.dart';
import '../services/v2_unified_geocoding_service.dart';
import '../theme.dart';
import '../utils/v2_app_snack_bar.dart';
import '../utils/v2_card_color_helper.dart';
import '../utils/v2_vozac_cache.dart';

/// Widget za prikaz V2Putnik kartice sa podrškom za radnike, učenike, dnevne i pošiljke

class V2PutnikCard extends StatefulWidget {
  const V2PutnikCard({
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
  final V2Putnik putnik;
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
  State<V2PutnikCard> createState() => _PutnikCardState();
}

class _PutnikCardState extends State<V2PutnikCard> {
  late V2Putnik _putnik;
  Timer? _longPressTimer;
  bool _isLongPressActive = false;
  bool _isProcessing = false; // Sprecava duple klikove tokom procesiranja

  // GLOBALNI LOCK - blokira SVE kartice dok jedan V2Putnik nije zaVrsen u bazi
  static bool _globalProcessingLock = false;

  @override
  void initState() {
    super.initState();
    _putnik = widget.putnik;
  }

  @override
  void didUpdateWidget(V2PutnikCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // FIX: UVEK ažuriraj _putnik kada se widget promeni
    // Ovo garantuje da realtime promene (pokupljenje, otkazivanje)
    // budu odmah vidljive bez obzira na == operator
    _putnik = widget.putnik;
  }

  // Format za otkazivanje - prikazuje vreme ako je danas, inace datum i vreme
  String _formatOtkazivanje(DateTime vreme) {
    final danas = DateTime.now();
    final jeDanas = vreme.year == danas.year && vreme.month == danas.month && vreme.day == danas.day;

    final vremeStr = '${vreme.hour.toString().padLeft(2, '0')}:${vreme.minute.toString().padLeft(2, '0')}';

    if (jeDanas) {
      // Danas - prikaži samo vreme
      return vremeStr;
    } else {
      // Ranije - prikaži datum i vreme za vecu preciznost
      return '${vreme.day}.${vreme.month}. $vremeStr';
    }
  }

  String _formatVreme(DateTime vreme) {
    return '${vreme.hour.toString().padLeft(2, '0')}:${vreme.minute.toString().padLeft(2, '0')}';
  }

  String _formatDatumVreme(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')} ${_formatVreme(dt)}';
  }

  // Univerzalna metoda za placanje - custom cena za sve tipove putnika
  Future<void> _handlePayment() async {
    // Validacija vozaca pre pokusaja placanja - koristi V2VozacCache
    final vozacUuid = V2VozacCache.getUuidByIme(widget.currentDriver);
    if (vozacUuid == null) {
      if (mounted) {
        V2AppSnackBar.error(context, 'Greška: Vozac nije definisan u sistemu');
      }
      return;
    }

    if (_putnik.isRadnik || _putnik.isUcenik) {
      // RADNIK / UCENIK - CUSTOM CENA umesto fiksne
      await _handleRegistrovaniPayment();
    } else if (_putnik.isDnevniTip) {
      // DNEVNI / POSILJKA - obracun na osnovu cene iz baze
      await _handleDnevniPosiljkaPayment();
    } else {
      // FALLBACK - unos custom iznosa
      await _handleObicniPayment();
    }
  }

  // PLACANJE DNEVNOG PUTNIKA - ukupna suma odjednom
  Future<void> _handleDnevniPosiljkaPayment() async {
    // Koristi centralizovanu logiku cena iz modela
    final double cenaPoMestu = _putnik.effectivePrice;
    final bool cenaNePostoji = cenaPoMestu <= 0;

    final int brojMesta = _putnik.brojMesta;
    final double ukupnaSuma = cenaPoMestu * brojMesta;

    // Naplacujemo sve odjednom
    final customController = TextEditingController(
      text: cenaNePostoji ? '' : ukupnaSuma.toStringAsFixed(0),
    );
    final theme = Theme.of(context);
    final double? confirmedIznos = await showDialog<double>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dCtx, setStateDialog) => AlertDialog(
            backgroundColor: Theme.of(dCtx).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(
                color: Theme.of(dCtx).colorScheme.outline,
                width: 2,
              ),
            ),
            title: Row(
              children: [
                Icon(
                  _putnik.isPosiljka ? Icons.inventory_2 : Icons.today,
                  color: cenaNePostoji ? Colors.orange : theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Naplata — ${_putnik.isPosiljka ? 'Pošiljka' : 'Dnevni'}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'V2Putnik: ${_putnik.ime}',
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
                  if (cenaNePostoji) ...[
                    // Slobodan unos ako cena nije postavljena
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.orange, size: 16),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Cena nije postavljena. Unesi iznos ručno.',
                              style: TextStyle(fontSize: 12, color: Colors.orange),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: customController,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Iznos (RSD)',
                        prefixIcon: Icon(Icons.attach_money),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ] else ...[
                    // Fiksni prikaz kad cena postoji
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.primary.withOpacity(0.3),
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
                                  color: theme.colorScheme.primary.withOpacity(0.7),
                                ),
                              ),
                            ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.attach_money,
                                size: 32,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${ukupnaSuma.toStringAsFixed(0)} RSD',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
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
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('Odustani'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  if (cenaNePostoji) {
                    final value = double.tryParse(customController.text);
                    if (value != null && value > 0) {
                      Navigator.of(ctx).pop(value);
                    }
                  } else {
                    Navigator.of(ctx).pop(ukupnaSuma);
                  }
                },
                icon: const Icon(Icons.payment),
                label: const Text('Potvrdi placanje'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );
      },
    );
    customController.dispose();

    if (confirmedIznos != null && confirmedIznos > 0) {
      if (_putnik.id == null || _putnik.id.toString().isEmpty) {
        if (mounted) {
          V2AppSnackBar.error(context, 'V2Putnik nema valjan ID - ne može se naplatiti');
        }
        return;
      }

      await _executePayment(
        confirmedIznos,
        isRegistrovani: false,
      );

      if (mounted) {
        V2AppSnackBar.payment(context, 'Naplaceno $brojMesta mesta - Ukupno: ${confirmedIznos.toStringAsFixed(0)} RSD');
      }
    }
  }

  // PLACANJE RADNIK/UCENIK - CUSTOM CENA (korisnik unosi iznos)
  Future<void> _handleRegistrovaniPayment() async {
    // Dohvati putnika iz baze po ID-u
    final putnikId = _putnik.id?.toString() ?? '';
    final putnikMap = putnikId.isNotEmpty ? await V2StatistikaIstorijaService.v2FindPutnikById(putnikId) : null;
    final registrovaniPutnik = putnikMap != null ? V2RegistrovaniPutnik.fromMap(putnikMap) : null;

    if (registrovaniPutnik == null) {
      if (mounted) {
        V2AppSnackBar.error(context, 'Greška: V2Putnik "${_putnik.ime}" nije pronaden');
      }
      return;
    }

    Set<String> placeniMeseci = {};
    try {
      final svaPlacanja = await V2StatistikaIstorijaService.dohvatiPlacanja(putnikId);
      for (var placanje in svaPlacanja) {
        final mesec = placanje['placeni_mesec'];
        final godina = placanje['placena_godina'];
        if (mesec != null && godina != null) {
          // Format: "mesec-godina" za internu proveru
          placeniMeseci.add('$mesec-$godina');
        }
      }
    } catch (e) {
      // Ako ne mo?emo ucitati, ostaje prazan set
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
      brojPutovanja = await V2StatistikaIstorijaService.izracunajBrojVoznji(
        _putnik.id! as String,
      );
      // Racunaj otkazivanja iz stvarne istorije
      brojOtkazivanja = await V2StatistikaIstorijaService.izracunajBrojOtkazivanja(
        _putnik.id! as String,
      );
    } catch (e) {
      // Greška pri citanju - koristi 0
      brojPutovanja = 0;
      brojOtkazivanja = 0;
    }

    if (!mounted) return;

    // Sugeriši cenu na osnovu tipa putnika
    final sugerisanaCenaOut = V2CenaObracunService.getCenaPoDanu(registrovaniPutnik);
    final controller = TextEditingController(text: sugerisanaCenaOut.toStringAsFixed(0));
    final theme = Theme.of(context);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => _RegistrovaniPaymentDialog(
        putnikIme: _putnik.ime,
        putnikGrad: _putnik.grad,
        registrovaniPutnik: registrovaniPutnik,
        controller: controller,
        placeniMeseci: placeniMeseci,
        brojPutovanja: brojPutovanja,
        brojOtkazivanja: brojOtkazivanja,
        firstDayOfMonth: firstDayOfMonth,
        lastDayOfMonth: lastDayOfMonth,
        getMonthOptions: _getMonthOptionsStatic,
        getMonthNumber: _getMonthNumberStatic,
        formatDate: _formatDate,
      ),
    );
    controller.dispose();

    if (result != null && result['iznos'] != null && mounted) {
      // Koristimo iznos koji je korisnik uneo u dialog
      await _executePayment(
        result['iznos'] as double,
        mesec: result['mesec'] as String?,
        isRegistrovani: true,
      );
    }
  }

  // PLACANJE OBICNOG PUTNIKA - standardno
  Future<void> _handleObicniPayment() async {
    double? iznos = await showDialog<double>(
      context: context,
      useRootNavigator: true,
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
                'V2Putnik: ${_putnik.ime}',
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
      if (_putnik.id == null || _putnik.id.toString().isEmpty) {
        if (mounted) {
          V2AppSnackBar.error(context, 'V2Putnik nema valjan ID - ne može se naplatiti');
        }
        return;
      }

      try {
        await _executePayment(iznos, isRegistrovani: false);

        // Haptic feedback za uspe?no placanje
        V2HapticService.lightImpact();
      } catch (e) {
        if (mounted) {
          V2AppSnackBar.error(context, 'Greška pri placanju: $e');
        }
      }
    }
  }

  // Izvr?avanje placanja - zajednicko za oba tipa
  Future<void> _executePayment(
    double iznos, {
    required bool isRegistrovani,
    String? mesec,
  }) async {
    // GLOBALNI LOCK - ako BILO KOJA kartica procesira, ignoriši
    if (_globalProcessingLock) return;
    // ZAŠTITA OD DUPLOG KLIKA - ako vec procesiramo, ignoriši
    if (_isProcessing) return;

    try {
      _globalProcessingLock = true;
      if (mounted) {
        setState(() {
          _isProcessing = true;
        });
      }

      // KRATKA PAUZA - samo da se UI osveži
      await Future<void>.delayed(const Duration(milliseconds: 100));

      if (!mounted) {
        _globalProcessingLock = false;
        return;
      }

      if (isRegistrovani && mesec != null) {
        // Validacija da V2Putnik ime nije prazno
        if (_putnik.ime.trim().isEmpty) {
          throw Exception('Ime putnika je prazno - ne može se pronaci u bazi');
        }

        // Za radnike/učenike koristi funkciju za mesecno placanje
        final existingId = _putnik.id?.toString() ?? '';
        final existingMap =
            existingId.isNotEmpty ? await V2StatistikaIstorijaService.v2FindPutnikById(existingId) : null;
        if (existingMap != null) {
          final tabela = existingMap['_tabela'] as String? ?? 'v2_radnici';
          // Koristi static funkciju za cuvanje placanja
          await _sacuvajPlacanjeStatic(
            putnikId: existingId,
            putnikIme: _putnik.ime,
            putnikTabela: tabela,
            iznos: iznos,
            mesec: mesec,
            vozacIme: widget.currentDriver,
          );
        } else {
          throw Exception('V2Putnik "${_putnik.ime}" nije pronaden u bazi');
        }
      } else {
        // Za obicne putnike koristi postojeci servis
        if (_putnik.id == null) {
          throw Exception('V2Putnik nema valjan ID - ne može se naplatiti');
        }

        await V2PolasciService.v2OznaciPlaceno(
          putnikId: _putnik.id!,
          iznos: iznos,
          vozacId: widget.currentDriver,
          grad: _putnik.grad,
          selectedVreme: _putnik.polazak,
          selectedDan: _putnik.dan,
          tipPutnika: _putnik.tipPutnika,
          putnikIme: _putnik.ime,
          putnikTabela: const {
            'dnevni': 'v2_dnevni',
            'radnik': 'v2_radnici',
            'ucenik': 'v2_ucenici',
            'posiljka': 'v2_posiljke',
          }[_putnik.tipPutnika],
        );
      }

      // OSVEŽI STANJE PUTNIKA - postavi placeno na true + vreme placanja
      if (mounted) {
        setState(() {
          _putnik = _putnik.copyWith(placeno: true, vremePlacanja: DateTime.now());
        });

        V2AppSnackBar.payment(context, 'Placanje uspešno evidentirano: $iznos RSD');
      }
    } catch (e) {
      if (mounted) {
        V2AppSnackBar.error(context, 'Greška pri placanju: $e');
      }
    } finally {
      // OBAVEZNO OSLOBODI LOCK
      _globalProcessingLock = false;
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  // Metoda za promenu broja mesta — vozač označava da putnik povede više osoba
  Future<void> _handleSetBrojMesta() async {
    int trenutni = _putnik.brojMesta;
    int novi = trenutni;

    final potvrda = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setS) {
            return AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outline,
                  width: 2,
                ),
              ),
              title: Row(
                children: [
                  Icon(Icons.event_seat, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text('Broj mesta', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _putnik.ime,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: novi > 1 ? () => setS(() => novi--) : null,
                        icon: const Icon(Icons.remove_circle_outline, size: 32),
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 60,
                        alignment: Alignment.center,
                        child: Text(
                          '$novi',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: novi < 9 ? () => setS(() => novi++) : null,
                        icon: const Icon(Icons.add_circle_outline, size: 32),
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    novi == 1 ? '1 sede\u0161te' : '$novi sedi\u0161ta/mesta',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text('Odustani'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(novi),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Potvrdi'),
                ),
              ],
            );
          },
        );
      },
    );

    if (potvrda == null || potvrda == trenutni) return;

    try {
      final ok = await V2PolasciService.v2SetBrojMesta(
        putnikId: _putnik.id!,
        grad: _putnik.grad,
        vreme: _putnik.polazak,
        dan: _putnik.dan,
        brojMesta: potvrda,
      );

      if (ok && mounted) {
        setState(() {
          _putnik = _putnik.copyWith(brojMesta: potvrda);
        });
        V2AppSnackBar.success(
          context,
          potvrda == 1 ? '${_putnik.ime} — 1 sedi\u0161te' : '${_putnik.ime} — $potvrda mesta',
        );
        widget.onChanged?.call();
      } else if (mounted) {
        V2AppSnackBar.error(context, 'Greška: nije pronaden aktivan zahtev');
      }
    } catch (e) {
      if (mounted) V2AppSnackBar.error(context, 'Greška: $e');
    }
  }

  // Metoda za pokupljenje putnika
  Future<void> _handlePickup() async {
    if (_globalProcessingLock || _isProcessing) return;

    _globalProcessingLock = true;
    _isProcessing = true;

    try {
      // Haptic feedback
      V2HapticService.mediumImpact();

      await V2PolasciService.v2OznaciPokupljen(
        putnikId: _putnik.id!,
        pokupljen: true,
        grad: _putnik.grad,
        vreme: _putnik.polazak,
        driver: widget.currentDriver,
        datum: _putnik.datum,
        requestId: _putnik.requestId,
      );

      if (mounted) {
        // JACA VIBRACIJA
        await V2HapticService.putnikPokupljen();

        if (widget.onChanged != null) {
          widget.onChanged!();
        }

        V2AppSnackBar.success(context, 'Pokupljen: ${_putnik.ime}');
      }
    } catch (e) {
      if (mounted) {
        V2AppSnackBar.error(context, 'Greška pri pokupljenju: $e');
      }
    } finally {
      // OBAVEZNO OSLOBODI LOCK
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
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    // Odredi ko je "vlasnik" ovog putnika za potrebe bojenja (siva vs bela)
    String displayDodeljenVozac = _putnik.dodeljenVozac ?? '';

    // BOJE KARTICE - privremeni V2Putnik sa ispravnim vozacem za kalkulaciju boja
    final _colorHelper = V2CardColorHelper();
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

    // Prava po vozacu (centralizovano)
    final String driver = widget.currentDriver;
    final bool isAdmin = V2AdminSecurityService.isAdmin(driver);
    final bool isVozac = V2VozacCache.imenaVozaca.contains(driver);

    if (_putnik.ime.toLowerCase().contains('rado') ||
        _putnik.ime.toLowerCase().contains('radovic') ||
        _putnik.ime.toLowerCase().contains('radosev')) {}

    return GestureDetector(
      behavior: HitTestBehavior.opaque, // FIX: Hvata tap na celoj kartici
      onLongPressStart: (_) => _startLongPressTimer(),
      onLongPressEnd: (_) => _cancelLongPressTimer(),
      onLongPressCancel: _cancelLongPressTimer,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
        decoration: finalDecoration, // Koristi V2CardColorHelper
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
                          color: textColor, // Koristi V2CardColorHelper
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
                            // Broj mesta badge — tap otvara dijalog za promenu
                            if ((isAdmin || isVozac) &&
                                widget.showActions &&
                                !_putnik.jeOtkazan &&
                                _putnik.brojMesta > 1)
                              GestureDetector(
                                onTap: _handleSetBrojMesta,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: textColor.withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: textColor.withOpacity(0.45),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
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
                              )
                            else if (_putnik.brojMesta > 1)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: textColor.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
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
                        // ADRESA - prikaži adresu iz rm cache-a (sync)
                        Builder(
                          builder: (context) {
                            final displayAdresa = _putnik.getAdresaFallback();

                            // Prikaži adresu samo ako je dostupna i nije placeholder
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
                  // da spreci overflow na manjim ekranima ili kada ima više ikona
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
                              // TABELA BADGE - prikazuj tip putnika iz koje tabele dolazi
                              // Boje uskladjene sa filterima na putnici ekranu
                              if (_putnik.tipPutnika != null)
                                Align(
                                  alignment: Alignment.topRight,
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: () {
                                        switch (_putnik.tipPutnika?.toLowerCase()) {
                                          case 'radnik':
                                            return const Color(0xFF3B7DD8).withOpacity(0.20);
                                          case 'ucenik':
                                            return const Color(0xFF4ECDC4).withOpacity(0.20);
                                          case 'posiljka':
                                            return const Color(0xFFFF8C00).withOpacity(0.20);
                                          case 'dnevni':
                                            return const Color(0xFFFF6B6B).withOpacity(0.20);
                                          default:
                                            return Theme.of(context).colorScheme.successPrimary.withOpacity(0.10);
                                        }
                                      }(),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      () {
                                        switch (_putnik.tipPutnika?.toLowerCase()) {
                                          case 'radnik':
                                            return 'RADNIK';
                                          case 'ucenik':
                                            return 'UCENIK';
                                          case 'posiljka':
                                            return 'POSILJKA';
                                          case 'dnevni':
                                            return 'DNEVNI';
                                          default:
                                            return 'PUTNIK';
                                        }
                                      }(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: () {
                                          switch (_putnik.tipPutnika?.toLowerCase()) {
                                            case 'radnik':
                                              return const Color(0xFF3B7DD8);
                                            case 'ucenik':
                                              return const Color(0xFF44A08D);
                                            case 'posiljka':
                                              return const Color(0xFFE65C00);
                                            case 'dnevni':
                                              return const Color(0xFFFF6B6B);
                                            default:
                                              return Theme.of(context).colorScheme.successPrimary;
                                          }
                                        }(),
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                ),
                              // ULTRA-SAFE ADAPTIVE ACTION IKONE - potpuno eliminiše overflow
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  // Izracunaj dostupnu širinu za ikone
                                  final availableWidth = constraints.maxWidth;

                                  // Ultra-conservative prag sa safety margin - povecani pragovi
                                  final bool isMaliEkran = availableWidth < 180; // povecao sa 170
                                  final bool isMiniEkran = availableWidth < 150; // povecao sa 140

                                  // Tri nivoa adaptacije - znacajno smanjene ikone za garantovano fitovanje u jedan red
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
                                      // GPS IKONA ZA NAVIGACIJU - ako putnik ima adresu (bilo koji tip)
                                      if (_putnik.getAdresaFallback() != null &&
                                          _putnik.getAdresaFallback()!.isNotEmpty) ...[
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
                                                        _putnik.getAdresaFallback() ?? 'Adresa nije definisana',
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
                                                      // INSTANT GPS - koristi novi V2PermissionService
                                                      final hasPermission =
                                                          await V2PermissionService.ensureGpsForNavigation();
                                                      if (!hasPermission) {
                                                        if (mounted && context.mounted) {
                                                          V2AppSnackBar.error(
                                                              context, '⚠️ GPS dozvole su potrebne za navigaciju');
                                                        }
                                                        return;
                                                      }

                                                      try {
                                                        // Pokaži loading sa dušim timeout-om
                                                        if (mounted && context.mounted) {
                                                          V2AppSnackBar.info(context, '🗺️ Pripremam navigaciju...');
                                                        }

                                                        // Dobij koordinate - UNIFIKOVANO za sve putnike
                                                        final adresaZaNav = _putnik.getAdresaFallback();
                                                        final koordinate = await _getKoordinateZaAdresu(
                                                          _putnik.grad,
                                                          adresaZaNav,
                                                          _putnik.adresaId,
                                                        );

                                                        if (mounted && context.mounted) {
                                                          ScaffoldMessenger.of(
                                                            context,
                                                          ).hideCurrentSnackBar();

                                                          if (koordinate != null) {
                                                            V2AppSnackBar.success(context, '🧭 Otvaram navigaciju...');
                                                            await _otvoriNavigaciju(koordinate);
                                                          } else {
                                                            V2AppSnackBar.warning(context,
                                                                '⚠️ Lokacija nije pronadena za: ${adresaZaNav ?? _putnik.adresa}');
                                                          }
                                                        }
                                                      } catch (e) {
                                                        if (mounted && context.mounted) {
                                                          V2AppSnackBar.error(context, '❌ Greška: ${e.toString()}');
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
                                            width: iconSize, // Adaptive velicina
                                            height: iconSize,
                                            decoration: BoxDecoration(
                                              // Glassmorphism pozadina
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
                                      // TELEFON IKONA - ako V2Putnik ima telefon
                                      if (_putnik.brojTelefona != null && _putnik.brojTelefona!.isNotEmpty) ...[
                                        GestureDetector(
                                          onTap: _pozovi,
                                          child: Container(
                                            width: iconSize,
                                            height: iconSize,
                                            decoration: BoxDecoration(
                                              // Glassmorphism pozadina
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
                                      // IKONA ZA PLACANJE - za sve korisnike (3. po redu)
                                      if (!_putnik.jeOtkazan) ...[
                                        GestureDetector(
                                          onTap: () => _handlePayment(),
                                          child: Container(
                                            width: iconSize,
                                            height: iconSize,
                                            decoration: BoxDecoration(
                                              // Glassmorphism pozadina
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
                                          ((_putnik.isRadnik || _putnik.isUcenik) ||
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
                                              // Glassmorphism pozadina
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
                            color: V2VozacCache.getColorByUuid(_putnik.pokupioVozacId) != Colors.grey
                                ? V2VozacCache.getColorByUuid(_putnik.pokupioVozacId)
                                : V2VozacCache.getColor(_putnik.pokupioVozac ?? _putnik.vozac),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      // Placeno info
                      if (_putnik.placeno == true && _putnik.iznosPlacanja != null) ...[
                        if (_putnik.vremePokupljenja != null) const SizedBox(width: 12),
                        if (_putnik.naplatioVozac != null)
                          Text(
                            'Placeno: ${_putnik.iznosPlacanja!.toStringAsFixed(0)}${_putnik.vremePlacanja != null ? ' ${_formatDatumVreme(_putnik.vremePlacanja!)}' : ''}',
                            style: TextStyle(
                              fontSize: 13,
                              color: V2VozacCache.getColorByUuid(_putnik.naplatioVozacId) != Colors.grey
                                  ? V2VozacCache.getColorByUuid(_putnik.naplatioVozacId)
                                  : V2VozacCache.getColor(_putnik.naplatioVozac),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                      // Otkazano info
                      if (_putnik.jeOtkazan && _putnik.vremeOtkazivanja != null) ...[
                        if (_putnik.vremePokupljenja != null || (_putnik.placeno == true)) const SizedBox(width: 12),
                        Text(
                          '${(_putnik.otkazaoVozac == null || _putnik.otkazaoVozac == 'V2Putnik') ? 'V2Putnik otkazao' : 'Otkazao'}: ${_formatOtkazivanje(_putnik.vremeOtkazivanja!)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: (_putnik.otkazaoVozac == null || _putnik.otkazaoVozac == 'V2Putnik')
                                ? Colors.red.shade900
                                : (V2VozacCache.getColorByUuid(_putnik.otkazaoVozacId) != Colors.grey
                                    ? V2VozacCache.getColorByUuid(_putnik.otkazaoVozacId)
                                    : V2VozacCache.getColor(_putnik.otkazaoVozac)),
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

  // Helper metode za placanje radnik/ucenik
  String _formatDate(DateTime date) {
    return '${date.day}.${date.month}.${date.year}';
  }

  // HELPER FUNKCIJE za mesecno placanje
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

  // CUVANJE PLACANJA
  Future<void> _sacuvajPlacanjeStatic({
    required String putnikId,
    required String putnikIme,
    required String putnikTabela,
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

      // FIX: Prosleduj IME vozaca, ne UUID - konverzija se radi u servisu
      // datum = danas (kad je uplata izvršena), placeniMesec/placenaGodina = izabrani mesec
      final uspeh = await V2StatistikaIstorijaService.upisPlacanjaULog(
        putnikId: putnikId,
        putnikIme: putnikIme,
        putnikTabela: putnikTabela,
        iznos: iznos,
        vozacIme: vozacIme,
        datum: DateTime.now(),
        placeniMesec: pocetakMeseca.month,
        placenaGodina: pocetakMeseca.year,
      );

      if (uspeh) {
        if (mounted) {
          V2AppSnackBar.payment(context, '💰 Placanje od ${iznos.toStringAsFixed(0)} RSD za $mesec je sacuvano');
        }
      } else {
        // FIX: Baci exception da _executePayment ne prikaže uspešnu poruku
        throw Exception('Greška pri cuvanju placanja u bazu');
      }
    } catch (e) {
      if (mounted) {
        V2AppSnackBar.error(context, '❌ Greška: $e');
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
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // OTKAZIVANJE - izdvojeno u funkciju
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
          'Da li ste sigurni da želite da oznacite ovog putnika kao otkazanog?',
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
        await V2PolasciService.v2OtkaziPutnika(
          putnikId: _putnik.id!,
          vozacId: widget.currentDriver,
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
          V2AppSnackBar.error(context, 'V2Putnik oznacen kao otkazan.');
          widget.onChanged?.call();
        }
      } catch (e) {
        if (mounted) {
          V2AppSnackBar.error(context, 'Greška: $e');
        }
      }
    }
  }

  // POMOCNA METODA: Dobij koordinate za adresu (sa keširanjem i validacijom)
  Future<Position?> _getKoordinateZaAdresu(String? grad, String? adresa, String? adresaId) async {
    if (adresa == null || adresa.isEmpty || adresa == 'Adresa nije definisana') return null;

    try {
      // Koristi V2UnifiedGeocodingService koji ima saVrsenu logiku (Baza -> API)
      final result = await V2UnifiedGeocodingService.getCoordinatesForPutnici(
        [_putnik],
        saveToDatabase: true, // Automatski sacuvaj u bazu ako nadež preko API-ja
      );

      if (result.isNotEmpty && result.containsKey(_putnik)) {
        return result[_putnik];
      }
    } catch (e) {}
    return null;
  }

  // NAVIGACIJA ž samo HERE WeGo
  Future<void> _otvoriNavigaciju(Position position) async {
    final lat = position.latitude;
    final lng = position.longitude;

    // HERE WeGo native URL scheme
    final hereUrl = Uri.parse('here-route://mylocation/$lat,$lng/now');

    try {
      if (await canLaunchUrl(hereUrl)) {
        await launchUrl(hereUrl, mode: LaunchMode.externalApplication);
      } else {
        // HERE WeGo nije instaliran ž prikaži dialog
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
    } catch (e) {}
  }

  // PICKER ZA ODSUSTVO (Bolovanje / Godišnji)
  void _startLongPressTimer() {
    _longPressTimer?.cancel();
    _isLongPressActive = true;

    // POCETNA VIBRACIJA - da vozac zna da je zapoceto cekanje
    V2HapticService.selectionClick();

    // 1.5 sekundi long press - POKUPLJENJE PUTNIKA
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

// ─── Privatni dialog widget za plaćanje registrovanog putnika ───────────────
class _RegistrovaniPaymentDialog extends StatefulWidget {
  const _RegistrovaniPaymentDialog({
    required this.putnikIme,
    required this.putnikGrad,
    required this.registrovaniPutnik,
    required this.controller,
    required this.placeniMeseci,
    required this.brojPutovanja,
    required this.brojOtkazivanja,
    required this.firstDayOfMonth,
    required this.lastDayOfMonth,
    required this.getMonthOptions,
    required this.getMonthNumber,
    required this.formatDate,
  });

  final String putnikIme;
  final String putnikGrad;
  final V2RegistrovaniPutnik registrovaniPutnik;
  final TextEditingController controller;
  final Set<String> placeniMeseci;
  final int brojPutovanja;
  final int brojOtkazivanja;
  final DateTime firstDayOfMonth;
  final DateTime lastDayOfMonth;
  final List<String> Function() getMonthOptions;
  final int Function(String) getMonthNumber;
  final String Function(DateTime) formatDate;

  @override
  State<_RegistrovaniPaymentDialog> createState() => _RegistrovaniPaymentDialogState();
}

class _RegistrovaniPaymentDialogState extends State<_RegistrovaniPaymentDialog> {
  late String selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    selectedMonth = '${_monthName(now.month)} ${now.year}';
  }

  static String _monthName(int m) {
    const names = [
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
      'Decembar'
    ];
    return names[m];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.registrovaniPutnik;
    final tipLower = r.v2Tabela;
    final imeLower = r.ime.toLowerCase();
    final jeZubi = tipLower == 'v2_posiljke' && imeLower.contains('zubi');
    final jePosiljka = tipLower == 'v2_posiljke';
    final jeDnevni = tipLower == 'v2_dnevni';
    final sugerisanaCena = V2CenaObracunService.getCenaPoDanu(r);
    final cenaNePostoji = sugerisanaCena <= 0;
    final jeFiksna = (jeZubi || jePosiljka || jeDnevni) && !cenaNePostoji;

    return AlertDialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: theme.colorScheme.outline, width: 2),
      ),
      title: Row(
        children: [
          Icon(
            jeFiksna ? Icons.lock : Icons.card_membership,
            color: jeFiksna ? Colors.orange : theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              jeFiksna
                  ? 'Naplata (FIKSNO)'
                  : 'Naplata — ${const {
                        'v2_radnici': 'Radnik',
                        'v2_ucenici': 'Ucenik',
                        'v2_dnevni': 'Dnevni',
                        'v2_posiljke': 'Posiljka'
                      }[tipLower] ?? 'Putnik'}',
              style: TextStyle(color: theme.colorScheme.onSurface),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'V2Putnik: ${widget.putnikIme}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (cenaNePostoji)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.orange.withOpacity(0.4)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange, size: 14),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Cena nije postavljena — unesi iznos ručno.',
                          style: TextStyle(fontSize: 12, color: Colors.orange),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (jeFiksna)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  jeZubi ? 'Tip: Pošiljka ZUBI' : (jePosiljka ? 'Tip: Pošiljka' : 'Tip: Dnevni'),
                  style: TextStyle(
                    color: jeZubi ? Colors.purple : (jePosiljka ? Colors.blue : Colors.orange),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Text('Grad: ${widget.putnikGrad}', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            // STATISTIKE
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.primary.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.analytics, color: theme.colorScheme.primary, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Statistike za trenutni mesec',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
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
                          Text('🚌 Putovanja:', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                          Text(
                            '${widget.brojPutovanja}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.successPrimary,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Otkazivanja:', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                          Text(
                            '${widget.brojOtkazivanja}',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (widget.placeniMeseci.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Period: ${widget.formatDate(widget.firstDayOfMonth)} - ${widget.formatDate(widget.lastDayOfMonth)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            // IZBOR MESECA
            Text(
              'Mesec za koji se placa:',
              style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700]),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: TripleBlueFashionStyles.dropdownDecoration,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedMonth,
                  isExpanded: true,
                  dropdownColor: theme.colorScheme.surface,
                  style: TextStyle(color: theme.colorScheme.onSurface),
                  items: widget.getMonthOptions().map((monthYear) {
                    final parts = monthYear.split(' ');
                    final monthNumber = widget.getMonthNumber(parts[0]);
                    final year = int.tryParse(parts[1]) ?? 0;
                    final bool isPlacen = widget.placeniMeseci.contains('$monthNumber-$year');
                    return DropdownMenuItem<String>(
                      value: monthYear,
                      child: Row(
                        children: [
                          Icon(
                            isPlacen ? Icons.check_circle : Icons.calendar_today,
                            size: 16,
                            color: isPlacen
                                ? theme.colorScheme.successPrimary
                                : theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            monthYear,
                            style: TextStyle(
                              color: isPlacen ? theme.colorScheme.successPrimary : null,
                              fontWeight: isPlacen ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (String? newMonth) {
                    if (newMonth != null) setState(() => selectedMonth = newMonth);
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            // UNOS CENE
            TextField(
              controller: widget.controller,
              enabled: !jeFiksna,
              readOnly: jeFiksna,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: jeFiksna ? 'Fiksni iznos (RSD)' : 'Iznos (RSD)',
                prefixIcon: const Icon(Icons.attach_money),
                border: const OutlineInputBorder(),
                fillColor: jeFiksna ? Colors.grey.withOpacity(0.1) : null,
                filled: jeFiksna,
                helperText: jeFiksna ? 'Ovaj tip putnika ima fiksnu cenu.' : null,
              ),
            ),
            const SizedBox(height: 12),
            // INFO
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.successPrimary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: theme.colorScheme.successPrimary, size: 16),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Možete platiti isti mesec više puta. Svako placanje se evidentira.',
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Odustani'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            final value = double.tryParse(widget.controller.text);
            if (value != null && value > 0) {
              Navigator.of(context).pop({'iznos': value, 'mesec': selectedMonth});
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
    );
  }
}
