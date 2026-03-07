// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../helpers/v2_placanje_dialog_helper.dart';
import '../models/v2_putnik.dart';
import '../services/v2_auth_manager.dart'; // V2AdminSecurityService spojen ovde
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

  // Univerzalna metoda za placanje — koristi V2PlacanjeDialogHelper
  Future<void> _handlePayment() async {
    final vozacUuid = V2VozacCache.getUuidByIme(widget.currentDriver);
    if (vozacUuid == null) {
      if (mounted) {
        V2AppSnackBar.error(context, 'Greška: Vozač nije definisan u sistemu');
      }
      return;
    }

    if (_putnik.id == null || _putnik.id.toString().isEmpty) {
      if (mounted) {
        V2AppSnackBar.error(context, 'V2Putnik nema valjan ID — ne može se naplatiti');
      }
      return;
    }

    // Cena: effectivePrice * brojMesta (0 = slobodan unos)
    final cena = _putnik.effectivePrice;
    final int brMesta = _putnik.brojMesta;

    // Tabela iz tipPutnika
    final tabela = const {
          'radnik': 'v2_radnici',
          'ucenik': 'v2_ucenici',
          'dnevni': 'v2_dnevni',
          'posiljka': 'v2_posiljke',
        }[_putnik.tipPutnika] ??
        'v2_radnici';

    final rezultat = await V2PlacanjeDialogHelper.prikaziDialog(
      context: context,
      putnikId: _putnik.id.toString(),
      putnikIme: _putnik.ime,
      putnikTabela: tabela,
      cena: cena,
      brojMesta: brMesta,
    );

    if (rezultat == null || !mounted) return;

    await _executePayment(
      rezultat.iznos,
      mesec: rezultat.mesec,
      isRegistrovani: _putnik.isRadnik || _putnik.isUcenik,
    );
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
            requestId: _putnik.requestId,
            dan: _putnik.dan.isNotEmpty ? _putnik.dan : null,
            grad: _putnik.grad.isNotEmpty ? _putnik.grad : null,
            vreme: _putnik.polazak != '---' ? _putnik.polazak : null,
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
          vozacIme: widget.currentDriver,
          grad: _putnik.grad,
          selectedVreme: _putnik.polazak,
          selectedDan: _putnik.dan,
          requestId: _putnik.requestId,
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

  // CUVANJE PLACANJA
  Future<void> _sacuvajPlacanjeStatic({
    required String putnikId,
    required String putnikIme,
    required String putnikTabela,
    required double iznos,
    required String mesec,
    required String vozacIme,
    String? requestId,
    String? dan,
    String? grad,
    String? vreme,
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

      const _monthMap = {
        'Januar': 1, 'Februar': 2, 'Mart': 3, 'April': 4, 'Maj': 5, 'Jun': 6,
        'Jul': 7, 'Avgust': 8, 'Septembar': 9, 'Oktobar': 10, 'Novembar': 11, 'Decembar': 12,
      };
      final monthNumber = _monthMap[monthName] ?? 0;
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
        requestId: requestId,
        dan: dan,
        grad: grad,
        vreme: vreme,
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
