// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../helpers/v3_placanje_dialog_helper.dart';
import '../models/v3_adresa.dart';
import '../models/v3_putnik.dart';
import '../models/v3_zahtev.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v2_haptic_service.dart';
import '../services/v3/v3_adresa_service.dart';
import '../services/v3/v3_operativna_nedelja_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../services/v3/v3_zahtev_service.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_card_color_policy.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dan_helper.dart';
import '../utils/v3_date_utils.dart';
import '../utils/v3_dialog_helper.dart';
import '../utils/v3_error_utils.dart';
import '../utils/v3_safe_text.dart';
import '../utils/v3_state_utils.dart';
import '../utils/v3_status_policy.dart';
import '../utils/v3_stream_utils.dart';
import '../utils/v3_style_helper.dart';
import '../utils/v3_tip_putnika_utils.dart';
import '../utils/v3_validation_utils.dart';

/// Widget za prikaz V3Putnik kartice sa podrškom za radnike, učenike, dnevne i pošiljke.
/// Vizuelni stil i logika prepisani iz V2PutnikCard.
class _V3NaplataInfo {
  final bool isPaid;
  final double iznos;
  final DateTime? paidAt;
  final String? paidBy;

  const _V3NaplataInfo({
    required this.isPaid,
    required this.iznos,
    this.paidAt,
    this.paidBy,
  });
}

class V3PutnikCard extends StatefulWidget {
  const V3PutnikCard({
    super.key,
    required this.putnik,
    this.zahtev,
    this.entry,
    this.redniBroj,
    this.onChanged,
    this.onDodeliVozaca,
    this.vozacBoja,
    this.isExcludedFromOptimization = false,
  });

  final V3Putnik putnik;
  final V3Zahtev? zahtev;
  final V3OperativnaNedeljaEntry? entry;
  final int? redniBroj;
  final VoidCallback? onChanged;
  final VoidCallback? onDodeliVozaca;
  final Color? vozacBoja;
  final bool isExcludedFromOptimization;

  @override
  State<V3PutnikCard> createState() => _V3PutnikCardState();
}

class _V3PutnikCardState extends State<V3PutnikCard> {
  bool _isLongPressActive = false;
  bool _isProcessing = false;

  // Globalni lock — blokira duple klikove dok se jedna operacija završi
  static bool _globalProcessingLock = false;

  @override
  void dispose() {
    V3StreamUtils.cancelTimer('putnik_card_${widget.putnik.id}_longpress');
    super.dispose();
  }

  // ─── Long press za pokupljanje (1.5s) ──────────────────────────

  void _startLongPressTimer() {
    V3StreamUtils.cancelTimer('putnik_card_${widget.putnik.id}_longpress');
    _isLongPressActive = true;
    V2HapticService.selectionClick();
    V3StreamUtils.createLongPressTimer(
        key: 'putnik_card_${widget.putnik.id}',
        duration: const Duration(milliseconds: 1500),
        onLongPress: () {
          if (_isLongPressActive && mounted) {
            final isPokupljen = V3StatusPolicy.isTimestampSet(widget.entry?.pokupljenAt);
            final isOtkazan = widget.entry?.otkazanoAt != null;
            if (!isOtkazan && !isPokupljen) {
              _handlePickup();
            }
          }
        });
  }

  void _cancelLongPressTimer() {
    V3StreamUtils.cancelTimer('putnik_card_${widget.putnik.id}_longpress');
    _isLongPressActive = false;
  }

  _V3NaplataInfo? _getNaplataInfo({required bool isMesecniModel}) {
    final cache = V3MasterRealtimeManager.instance.getCache('v3_finansije').values;
    if (cache.isEmpty) return null;

    if (!isMesecniModel) {
      final operativnaId = widget.entry?.id;
      if (operativnaId == null || operativnaId.isEmpty) return null;

      final candidates = cache.where((row) {
        if (row['tip'] != 'prihod') return false;
        final kategorija = (row['kategorija']?.toString() ?? '').toLowerCase();
        if (kategorija != 'operativna_naplata') return false;
        return (row['operativna_id']?.toString() ?? '') == operativnaId;
      }).toList();

      if (candidates.isEmpty) return null;
      candidates.sort((a, b) {
        final bDt = V3DateUtils.parseTs(b['created_at']?.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final aDt = V3DateUtils.parseTs(a['created_at']?.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDt.compareTo(aDt);
      });

      final row = candidates.first;
      final iznos = (row['iznos'] as num?)?.toDouble() ?? 0;
      final paidAt = V3DateUtils.parseTs(row['created_at']?.toString());
      final paidBy = row['naplaceno_by']?.toString();
      return _V3NaplataInfo(isPaid: iznos > 0, iznos: iznos, paidAt: paidAt, paidBy: paidBy);
    }

    final datumRef = widget.entry?.datum ?? widget.zahtev?.datum ?? DateTime.now();
    final mesec = datumRef.month;
    final godina = datumRef.year;
    final putnikId = widget.putnik.id;

    final candidates = cache.where((row) {
      if (row['tip'] != 'prihod') return false;
      final kategorija = (row['kategorija']?.toString() ?? '').toLowerCase();
      if (kategorija != 'operativna_naplata') return false;
      if ((row['putnik_v3_auth_id']?.toString() ?? '') != putnikId) return false;

      final rMesec = (row['mesec'] as num?)?.toInt();
      final rGodina = (row['godina'] as num?)?.toInt();
      return rMesec == mesec && rGodina == godina;
    }).toList();

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final bDt = V3DateUtils.parseTs(b['created_at']?.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final aDt = V3DateUtils.parseTs(a['created_at']?.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDt.compareTo(aDt);
    });

    final latest = candidates.first;
    final ukupno = candidates.fold<double>(0, (sum, row) => sum + ((row['iznos'] as num?)?.toDouble() ?? 0));
    return _V3NaplataInfo(
      isPaid: ukupno > 0,
      iznos: ukupno,
      paidAt: V3DateUtils.parseTs(latest['created_at']?.toString()),
      paidBy: latest['naplaceno_by']?.toString(),
    );
  }

  // ─── Akcije ────────────────────────────────────────────────────

  Future<void> _handlePickup() async {
    if (widget.entry == null && widget.zahtev == null) return;
    if (_globalProcessingLock || _isProcessing) return;
    _globalProcessingLock = true;
    V3StateUtils.safeSetState(this, () => _isProcessing = true);
    try {
      V2HapticService.mediumImpact();
      final currentVozac = V3VozacService.currentVozac;
      if (currentVozac == null) throw 'Niste logovani u V3 sistem';
      await V3ZahtevService.oznaciPokupljen(pokupljenBy: currentVozac.id, operativnaId: widget.entry?.id);
      await V2HapticService.putnikPokupljen();
      if (mounted) {
        V3AppSnackBar.success(context, 'Putnik pokupljen');
        widget.onChanged?.call();
      }
    } catch (e) {
      V3ErrorUtils.safeError(this, context, 'Greška pri pokupljenju: $e');
    } finally {
      _globalProcessingLock = false;
      V3StateUtils.safeSetState(this, () => _isProcessing = false);
    }
  }

  String? _firstValidTelefon() {
    final telefon1 = (widget.putnik.telefon1 ?? '').trim();
    if (telefon1.isNotEmpty) return telefon1;

    final telefon2 = (widget.putnik.telefon2 ?? '').trim();
    if (telefon2.isNotEmpty) return telefon2;

    return null;
  }

  Future<void> _handleCall() async {
    final tel = _firstValidTelefon();
    if (tel == null || tel.isEmpty) return;

    // Za widgets koristimo direktnu implementaciju sa basic error handling
    final uri = Uri(scheme: 'tel', path: tel);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[V3PutnikCard._handleCall] Greška: $e');
    }
  }

  Future<void> _handlePayment() async {
    if (widget.entry == null && widget.zahtev == null) return;
    if (_globalProcessingLock || _isProcessing) return;

    _globalProcessingLock = true;
    V3StateUtils.safeSetState(this, () => _isProcessing = true);

    final tip = widget.putnik.tipPutnika;
    final isMesecniModel = tip == 'radnik' || tip == 'ucenik';
    final isPoPokupljenjuModel = tip == 'dnevni' || tip == 'posiljka';
    final defaultCena =
        (tip == 'dnevni' || tip == 'posiljka') ? widget.putnik.cenaPoPokupljenju : widget.putnik.cenaPoDanu;
    final zakljucajIznos = defaultCena > 0;

    if (isPoPokupljenjuModel && widget.entry == null) {
      if (mounted) {
        V3AppSnackBar.warning(context, 'Naplata je moguća tek nakon potvrđenog termina.');
      }
      _globalProcessingLock = false;
      V3StateUtils.safeSetState(this, () => _isProcessing = false);
      return;
    }

    if (isPoPokupljenjuModel && !V3StatusPolicy.isTimestampSet(widget.entry?.pokupljenAt)) {
      if (mounted) {
        V3AppSnackBar.warning(context, 'Naplata je moguća tek nakon pokupljanja putnika.');
      }
      _globalProcessingLock = false;
      V3StateUtils.safeSetState(this, () => _isProcessing = false);
      return;
    }

    final naplataInfo = _getNaplataInfo(isMesecniModel: isMesecniModel);
    final alreadyPaid = !isMesecniModel && (naplataInfo?.isPaid ?? false);

    try {
      if (alreadyPaid && widget.entry != null) {
        final confirmOverwrite = await V3DialogHelper.showConfirmDialog(
          context,
          title: 'Naplata već postoji',
          message: 'Ovaj termin je već naplaćen. Da li želite da prepišete postojeću naplatu?',
          confirmText: 'DA, PREPIŠI',
          cancelText: 'NE',
          isDangerous: true,
        );
        if (confirmOverwrite != true) return;
      }

      final rezultat = await V3PlacanjeDialogHelper.prikaziDialog(
        context: context,
        putnikId: widget.putnik.id,
        imePrezime: widget.putnik.imePrezime,
        defaultCena: defaultCena,
        zakljucajIznos: zakljucajIznos,
      );
      if (rezultat == null) return;

      final ok = await V3PlacanjeDialogHelper.sacuvajPlacanje(
        context: context,
        putnikId: widget.putnik.id,
        imePrezime: widget.putnik.imePrezime,
        rezultat: rezultat,
        operativnaId: widget.entry?.id,
        snimiMesecnuUplatu: isMesecniModel,
      );
      if (ok && mounted) {
        V3AppSnackBar.payment(context, '✅ Naplaćeno ${rezultat.iznos} RSD za ${widget.putnik.imePrezime}');
      }
      widget.onChanged?.call();
    } catch (e) {
      V3ErrorUtils.safeError(this, context, 'Greška pri plaćanju: $e');
    } finally {
      _globalProcessingLock = false;
      V3StateUtils.safeSetState(this, () => _isProcessing = false);
    }
  }

  Future<void> _handleNavigation() async {
    // Prioritet 1: direktan adresa_override_id
    final overrideId = widget.entry?.adresaIdOverride;
    final String? adresaId;
    if (overrideId != null && overrideId.isNotEmpty) {
      adresaId = overrideId;
    } else {
      final grad = V3ValidationUtils.normalizeGrad(widget.entry?.grad ?? widget.zahtev?.grad ?? '');
      final koristiSekundarnu = widget.entry?.koristiSekundarnu ?? false;
      if (grad != 'BC' && grad != 'VS') {
        if (mounted) V3AppSnackBar.warning(context, '⚠️ Grad nije definisan za ovog putnika');
        return;
      }
      adresaId = grad == 'BC'
          ? (koristiSekundarnu ? widget.putnik.adresaBcId2 : widget.putnik.adresaBcId) ??
              widget.putnik.adresaBcId ??
              widget.putnik.adresaBcId2
          : (koristiSekundarnu ? widget.putnik.adresaVsId2 : widget.putnik.adresaVsId) ??
              widget.putnik.adresaVsId ??
              widget.putnik.adresaVsId2;
    }
    final adresaNaziv = _getAdresaNaziv();
    final V3Adresa? adresa = V3AdresaService.getAdresaById(adresaId);

    if (adresa != null && adresa.hasValidCoordinates) {
      final hereUrl = Uri.parse('here-route://mylocation/${adresa.gpsLat},${adresa.gpsLng}/now');
      if (await canLaunchUrl(hereUrl)) {
        await launchUrl(hereUrl, mode: LaunchMode.externalApplication);
        return;
      }
      if (mounted) {
        V3AppSnackBar.warning(context, '⚠️ HERE aplikacija nije dostupna na uređaju');
      }
      return;
    }
    if (mounted) {
      final naziv = adresaNaziv ?? '/';
      V3AppSnackBar.warning(context, '⚠️ GPS koordinate nisu dostupne za: $naziv');
    }
  }

  Future<void> _handleOtkazivanje() async {
    final operativnaId = widget.entry?.id;
    if (operativnaId == null || operativnaId.isEmpty) return;

    if (_globalProcessingLock || _isProcessing) return;
    _globalProcessingLock = true;
    V3StateUtils.safeSetState(this, () => _isProcessing = true);

    try {
      final confirm = await V3DialogHelper.showConfirmDialog(
        context,
        title: 'Otkazivanje putnika',
        message: 'Da li ste sigurni da želite da otkaže ${widget.putnik.imePrezime}?',
        confirmText: 'Da',
        cancelText: 'Ne',
        isDangerous: true,
      );

      if (confirm == true) {
        await V3ZahtevService.otkaziZahtev('',
            otkazaoVozacId: V3VozacService.currentVozac?.id, operativnaId: operativnaId);
        if (mounted) {
          V3AppSnackBar.warning(context, 'Otkazano: ${widget.putnik.imePrezime}');
          widget.onChanged?.call();
        }
      }
    } catch (e) {
      V3ErrorUtils.safeError(this, context, 'Greška: $e');
    } finally {
      _globalProcessingLock = false;
      V3StateUtils.safeSetState(this, () => _isProcessing = false);
    }
  }

  // ─── Boje kartice po statusu ───────────────────────────────────

  BoxDecoration _getCardDecoration() {
    final status = V3StatusPolicy.normalizeStatus(widget.entry?.statusFinal ?? widget.zahtev?.status ?? '');
    final bool isPokupljen = V3StatusPolicy.isTimestampSet(widget.entry?.pokupljenAt);
    final tip = widget.putnik.tipPutnika;
    final isMesecniModel = tip == 'radnik' || tip == 'ucenik';
    final naplataInfo = _getNaplataInfo(isMesecniModel: isMesecniModel);
    final bool isPlacen = naplataInfo?.isPaid ?? false;

    return V3StyleHelper.putnikCard(
      status: status,
      isPokupljen: isPokupljen,
      isPlacen: isPlacen,
      vozacBoja: widget.vozacBoja,
    );
  }

  V3StatusTextUi _getStatusTextStyle() {
    final status = widget.entry?.statusFinal ?? widget.zahtev?.status;
    final pokupljen = V3StatusPolicy.isTimestampSet(widget.entry?.pokupljenAt);
    final tip = widget.putnik.tipPutnika;
    final isMesecniModel = tip == 'radnik' || tip == 'ucenik';
    final naplataInfo = _getNaplataInfo(isMesecniModel: isMesecniModel);
    final placen = naplataInfo?.isPaid ?? false;
    return V3StatusPolicy.textForCard(
      status: status,
      pokupljen: pokupljen,
      placen: placen,
    );
  }

  // ─── Tip badge ─────────────────────────────────────────────────

  // ─── Adresa helper ─────────────────────────────────────────────

  String? _getAdresaNaziv() {
    // Prioritet 1: direktan adresa_override_id
    final overrideId = widget.entry?.adresaIdOverride;
    if (overrideId != null && overrideId.isNotEmpty) {
      return V3AdresaService.getAdresaById(overrideId)?.naziv;
    }
    final grad = V3ValidationUtils.normalizeGrad(widget.entry?.grad ?? widget.zahtev?.grad ?? '');
    final koristiSekundarnu = widget.entry?.koristiSekundarnu ?? false;
    if (grad == 'BC') {
      final id = koristiSekundarnu ? widget.putnik.adresaBcId2 : widget.putnik.adresaBcId;
      return V3AdresaService.getAdresaById(id ?? widget.putnik.adresaBcId)?.naziv ??
          V3AdresaService.getAdresaById(widget.putnik.adresaBcId2)?.naziv;
    }
    if (grad == 'VS') {
      final id = koristiSekundarnu ? widget.putnik.adresaVsId2 : widget.putnik.adresaVsId;
      return V3AdresaService.getAdresaById(id ?? widget.putnik.adresaVsId)?.naziv ??
          V3AdresaService.getAdresaById(widget.putnik.adresaVsId2)?.naziv;
    }
    return null;
  }

  // ─── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final status = V3StatusPolicy.normalizeStatus(widget.entry?.statusFinal ?? widget.zahtev?.status ?? '');
    final bool isPokupljen = V3StatusPolicy.isTimestampSet(widget.entry?.pokupljenAt);
    final bool isOtkazan = widget.entry?.otkazanoAt != null;
    final tip = widget.putnik.tipPutnika;
    final isMesecniModel = tip == 'radnik' || tip == 'ucenik';
    final naplataInfo = _getNaplataInfo(isMesecniModel: isMesecniModel);
    final bool isPlacen = naplataInfo?.isPaid ?? false;
    final String? naplataById = naplataInfo?.paidBy;
    final DateTime? naplataAt = naplataInfo?.paidAt;
    final double naplataIznos = naplataInfo?.iznos ?? 0;
    final bool hasTel = _firstValidTelefon() != null;
    final String? adresaNaziv = _getAdresaNaziv();
    final bool hasAdresa = adresaNaziv != null && adresaNaziv.isNotEmpty;
    final textStyle = _getStatusTextStyle();
    final Color textColor = textStyle.primary;
    final Color secondaryTextColor = textStyle.secondary;
    final int brojMesta = widget.entry?.brojMesta ?? widget.zahtev?.brojMesta ?? 1;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) => _startLongPressTimer(),
      onLongPressEnd: (_) => _cancelLongPressTimer(),
      onLongPressCancel: _cancelLongPressTimer,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
        decoration: _getCardDecoration(),
        child: Padding(
          padding: const EdgeInsets.all(6.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Redni broj
                  if (widget.redniBroj != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 4.0),
                      child: Text(
                        '${widget.redniBroj}.',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: textColor),
                      ),
                    ),

                  // Ime + adresa
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: V3SafeText.userName(
                                widget.putnik.imePrezime,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontStyle: FontStyle.italic,
                                  fontSize: 14,
                                  color: textColor,
                                ),
                              ),
                            ),
                            if (brojMesta > 1)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: V3ContainerUtils.styledContainer(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  backgroundColor: textColor.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: textColor.withOpacity(0.45), width: 0.6),
                                  child: Text(
                                    'x$brojMesta',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: textColor),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (hasAdresa)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: V3SafeText.userAddress(
                              adresaNaziv,
                              style: TextStyle(fontSize: 13, color: secondaryTextColor, fontWeight: FontWeight.w500),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Akcije desno — tip badge + glassmorphism ikone
                  if (widget.entry != null || widget.zahtev != null)
                    Flexible(
                      flex: 0,
                      child: Transform.translate(
                        offset: const Offset(-1, 0),
                        child: Container(
                          alignment: Alignment.centerRight,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Tip badge
                              Align(
                                alignment: Alignment.topRight,
                                child: V3ContainerUtils.styledContainer(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  backgroundColor: V3TipPutnikaUtils.color(widget.putnik.tipPutnika).withOpacity(0.20),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Text(
                                    V3TipPutnikaUtils.badgeLabel(widget.putnik.tipPutnika),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: V3TipPutnikaUtils.color(widget.putnik.tipPutnika),
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ),
                              // Adaptive glassmorphism ikone
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final double availableWidth = constraints.maxWidth;
                                  final bool isMiniEkran = availableWidth < 150;
                                  final bool isMaliEkran = availableWidth < 180;
                                  final double iconSize = isMiniEkran ? 20 : (isMaliEkran ? 22 : 24);
                                  final double iconInnerSize = isMiniEkran ? 16 : (isMaliEkran ? 18 : 20);

                                  Widget iconBtn(String emoji, VoidCallback onTap) {
                                    return GestureDetector(
                                      onTap: onTap,
                                      child: Container(
                                        width: iconSize,
                                        height: iconSize,
                                        decoration: BoxDecoration(
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
                                            emoji,
                                            style: TextStyle(fontSize: iconInnerSize * 0.8),
                                          ),
                                        ),
                                      ),
                                    );
                                  }

                                  return Wrap(
                                    alignment: WrapAlignment.end,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      if (widget.onDodeliVozaca != null) iconBtn('👤', widget.onDodeliVozaca!),
                                      if (hasAdresa) iconBtn('📍', _handleNavigation),
                                      if (hasTel) iconBtn('📞', _handleCall),
                                      if (!isOtkazan) iconBtn('💰', _handlePayment),
                                      if (!isOtkazan) iconBtn('❌', _handleOtkazivanje),
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

              // Red 2 — status info
              if (isPokupljen || isOtkazan || isPlacen)
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: Builder(builder: (_) {
                    // Vozač boja po akteru — svaki tekst koristi ID aktera koji je stvarno izvršio akciju
                    final _currentVozac = V3VozacService.currentVozac;
                    Color _bojaZaVozacId(String? vozacId) {
                      if (vozacId != null) {
                        final v = V3VozacService.getVozacById(vozacId);
                        if (v != null) return V3CardColorPolicy.tryParseHexColor(v.boja) ?? const Color(0xFF9E9E9E);
                      }
                      return V3CardColorPolicy.tryParseHexColor(_currentVozac?.boja) ?? const Color(0xFF9E9E9E);
                    }

                    final bojaPokupljen = _bojaZaVozacId(widget.entry?.pokupljenBy);
                    final bojaNaplata = _bojaZaVozacId(naplataById);
                    final bojaOtkaz =
                        (widget.entry?.otkazanoBy != null && widget.entry?.otkazanoBy == widget.entry?.putnikId)
                            ? Colors.red
                            : _bojaZaVozacId(widget.entry?.otkazanoBy);

                    String _fmt(DateTime? dt) {
                      if (dt == null) return '';
                      return V3DanHelper.formatDatumVremeKratko(dt);
                    }

                    return Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // 1. BIJELA: plaćeno ali nije pokupljen — cyan
                        if (isPlacen && !isPokupljen) ...[
                          Text(
                            () {
                              final vpl = naplataAt;
                              final iznosSafe = naplataIznos;
                              final iznosStr = iznosSafe > 0 ? '${iznosSafe.toStringAsFixed(0)} RSD' : '';
                              final dtStr = _fmt(vpl);
                              return 'Plaćeno: ${[
                                if (iznosStr.isNotEmpty) iznosStr,
                                if (dtStr.isNotEmpty) dtStr
                              ].join(' • ')}';
                            }(),
                            style: TextStyle(fontSize: 13, color: bojaNaplata, fontWeight: FontWeight.w700),
                          ),
                        ],

                        // 2. PLAVA: pokupljen, nije platio
                        if (isPokupljen && !isPlacen) ...[
                          Text(
                            () {
                              final dtStr = _fmt(widget.entry?.pokupljenAt);
                              return dtStr.isNotEmpty ? 'Pokupljen: $dtStr' : 'Pokupljen';
                            }(),
                            style: TextStyle(fontSize: 13, color: bojaPokupljen, fontWeight: FontWeight.bold),
                          ),
                        ],

                        // 3. ZELENA: pokupljen + plaćen
                        if (isPokupljen && isPlacen) ...[
                          Text(
                            () {
                              final dtStr = _fmt(widget.entry?.pokupljenAt);
                              return dtStr.isNotEmpty ? 'Pokupljen: $dtStr' : 'Pokupljen';
                            }(),
                            style: TextStyle(fontSize: 13, color: bojaPokupljen, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            () {
                              final iznos = naplataIznos;
                              final vpl = naplataAt;
                              final iznosStr = iznos > 0 ? '${iznos.toStringAsFixed(0)} RSD' : '';
                              final dtStr = _fmt(vpl);
                              return 'Plaćeno: ${[
                                if (iznosStr.isNotEmpty) iznosStr,
                                if (dtStr.isNotEmpty) dtStr
                              ].join(' • ')}';
                            }(),
                            style: TextStyle(fontSize: 13, color: bojaNaplata, fontWeight: FontWeight.w600),
                          ),
                        ],

                        // 5. CRVENA: otkazano
                        if (isOtkazan) ...[
                          Text(
                            () {
                              final dtStr = _fmt(widget.entry?.otkazanoAt);
                              return dtStr.isNotEmpty ? 'Otkazano: $dtStr' : 'Otkazano';
                            }(),
                            style: TextStyle(fontSize: 13, color: bojaOtkaz, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ],
                    );
                  }),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
