// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../helpers/v3_placanje_dialog_helper.dart';
import '../models/v3_putnik.dart';
import '../models/v3_zahtev.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v2_haptic_service.dart';
import '../services/v3/v3_adresa_service.dart';
import '../services/v3/v3_finansije_service.dart';
import '../services/v3/v3_operativna_nedelja_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../services/v3/v3_zahtev_service.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_card_color_policy.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dan_helper.dart';
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
  });

  final V3Putnik putnik;
  final V3Zahtev? zahtev;
  final V3OperativnaNedeljaEntry? entry;
  final int? redniBroj;
  final VoidCallback? onChanged;
  final VoidCallback? onDodeliVozaca;
  final Color? vozacBoja;

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

  V3NaplataInfo? _resolveNaplataInfo() {
    final datumRef = widget.entry?.datum ?? widget.zahtev?.datum ?? DateTime.now();
    return V3FinansijeService.resolveNaplataInfo(
      putnikId: widget.putnik.id,
      datumRef: datumRef,
    );
  }

  bool _isPoDanuModel(String tipPutnika) {
    final tip = tipPutnika.trim().toLowerCase();
    return tip == 'radnik' || tip == 'ucenik';
  }

  ({double defaultCena, int brojVoznji}) _resolvePaymentDefaults({
    required String tipPutnika,
    required bool isPoDanuModel,
  }) {
    if (isPoDanuModel) {
      final datumRef = widget.entry?.datum ?? widget.zahtev?.datum ?? DateTime.now();
      final summary = V3FinansijeService.getNaplataSummaryForPutnik(
        putnikId: widget.putnik.id,
        mesec: datumRef.month,
        godina: datumRef.year,
      );
      final brojVoznji = summary.brojVoznji;
      return (
        defaultCena: widget.putnik.cenaPoDanu * brojVoznji,
        brojVoznji: brojVoznji,
      );
    }

    final tip = tipPutnika.trim().toLowerCase();
    final cena = (tip == 'dnevni' || tip == 'posiljka') ? widget.putnik.cenaPoPokupljenju : widget.putnik.cenaPoDanu;
    return (defaultCena: cena, brojVoznji: 1);
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
      await V3FinansijeService.evidentirajRealizacijuPriPokupljanju(
        putnikId: widget.putnik.id,
        tipPutnika: widget.putnik.tipPutnika,
        datum: widget.entry?.datum ?? widget.zahtev?.datum ?? DateTime.now(),
        evidentiraoBy: currentVozac.id,
      );
      await V2HapticService.putnikPokupljen();
      if (mounted) {
        V3AppSnackBar.success(context, 'Vožnja evidentirana');
        widget.onChanged?.call();
      }
    } catch (e) {
      V3ErrorUtils.safeError(this, context, 'Greška pri evidenciji vožnje: $e');
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

  void _pokaziKontakt(BuildContext context) {
    final tel1 = (widget.putnik.telefon1 ?? '').trim();
    final tel2 = (widget.putnik.telefon2 ?? '').trim();
    V3DialogHelper.showBottomSheet<void>(
      context: context,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Kontaktiraj ${widget.putnik.imePrezime}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (tel1.isNotEmpty) ..._kontaktRed(context, tel1),
              if (tel2.isNotEmpty) ..._kontaktRed(context, tel2),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Otkaži'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _kontaktRed(BuildContext context, String broj) {
    return [
      const Divider(),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(broj, style: const TextStyle(fontSize: 13, color: Colors.black54)),
      ),
      Row(
        children: [
          Expanded(
            child: ListTile(
              leading: const Icon(Icons.phone, color: Colors.green),
              title: const Text('Pozovi'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: () async {
                Navigator.pop(context);
                final uri = Uri(scheme: 'tel', path: broj);
                if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),
          ),
          Expanded(
            child: ListTile(
              leading: const Icon(Icons.sms, color: Colors.blueAccent),
              title: const Text('SMS'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: () async {
                Navigator.pop(context);
                final uri = Uri(scheme: 'sms', path: broj);
                if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),
          ),
        ],
      ),
    ];
  }

  Future<void> _handlePayment() async {
    if (widget.entry == null && widget.zahtev == null) return;
    if (_globalProcessingLock || _isProcessing) return;

    _globalProcessingLock = true;
    V3StateUtils.safeSetState(this, () => _isProcessing = true);

    final tip = widget.putnik.tipPutnika;
    final isPoDanuModel = _isPoDanuModel(tip);
    final defaults = _resolvePaymentDefaults(tipPutnika: tip, isPoDanuModel: isPoDanuModel);

    final cenaPoModelu = isPoDanuModel ? widget.putnik.cenaPoDanu : widget.putnik.cenaPoPokupljenju;
    final imaObracun = cenaPoModelu > 0 && defaults.brojVoznji > 0;
    final ocekivaniIznos = imaObracun ? defaults.defaultCena : 0.0;
    final defaultCena = ocekivaniIznos;

    try {
      final rezultat = await V3PlacanjeDialogHelper.naplati(
        context: context,
        putnikId: widget.putnik.id,
        imePrezime: widget.putnik.imePrezime,
        defaultCena: defaultCena,
        snimiMesecnuUplatu: isPoDanuModel,
        brojVoznji: defaults.brojVoznji,
      );
      if (rezultat != null && mounted) {
        V3AppSnackBar.payment(context, '✅ Naplaćeno ${rezultat.iznos} RSD za ${widget.putnik.imePrezime}');
        if (imaObracun) {
          final razlika = rezultat.iznos - ocekivaniIznos;
          if (razlika.abs() > 0.009) {
            final znak = razlika > 0 ? '+' : '';
            V3AppSnackBar.info(
              context,
              'Obračun ${ocekivaniIznos.toStringAsFixed(0)} RSD, uneto ${rezultat.iznos.toStringAsFixed(0)} RSD, razlika ${znak}${razlika.toStringAsFixed(0)} RSD',
            );
          }
        }
        widget.onChanged?.call();
      }
    } catch (e) {
      V3ErrorUtils.safeError(this, context, 'Greška pri plaćanju: $e');
    } finally {
      _globalProcessingLock = false;
      V3StateUtils.safeSetState(this, () => _isProcessing = false);
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
    final naplataInfo = _resolveNaplataInfo();
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
    final naplataInfo = _resolveNaplataInfo();
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
    final naplataInfo = _resolveNaplataInfo();
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
                                      if (hasTel) iconBtn('📞', () => _pokaziKontakt(context)),
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
                    const String _sistemAkterId = '4feffa3a-8b4d-4e28-9b8b-c0af3c48ea4e';

                    bool _isSistemAkter(String? akterId, {Map<String, dynamic>? auth}) {
                      final id = (akterId ?? '').trim();
                      if (id.isNotEmpty && id == _sistemAkterId) return true;
                      final tip = (auth?['tip']?.toString() ?? '').trim().toLowerCase();
                      return tip == 'sistem';
                    }

                    Color _bojaZaAkteraId(String? akterId, {bool fallbackToCurrentVozac = true}) {
                      if (akterId != null && akterId.isNotEmpty) {
                        final auth = V3MasterRealtimeManager.instance.authCache[akterId];
                        if (_isSistemAkter(akterId, auth: auth)) {
                          return const Color(0xFF212121);
                        }
                        final authBoja = auth?['boja']?.toString();
                        final parsedAuthBoja = V3CardColorPolicy.tryParseHexColor(authBoja);
                        if (parsedAuthBoja != null) return parsedAuthBoja;

                        final v = V3VozacService.getVozacById(akterId);
                        if (v != null) return V3CardColorPolicy.tryParseHexColor(v.boja) ?? const Color(0xFF9E9E9E);
                      }
                      if (fallbackToCurrentVozac) {
                        return V3CardColorPolicy.tryParseHexColor(_currentVozac?.boja) ?? const Color(0xFF9E9E9E);
                      }
                      return const Color(0xFFC62828);
                    }

                    final bojaPokupljen = _bojaZaAkteraId(widget.entry?.pokupljenBy, fallbackToCurrentVozac: true);
                    final bojaNaplata = _bojaZaAkteraId(naplataById, fallbackToCurrentVozac: true);
                    final otkazaoAkterId = widget.entry?.otkazanoBy ?? widget.entry?.updatedBy;
                    final otkazaoJePutnik =
                        otkazaoAkterId != null && otkazaoAkterId.isNotEmpty && otkazaoAkterId == widget.entry?.putnikId;
                    final bojaOtkaz =
                        otkazaoJePutnik ? Colors.red : _bojaZaAkteraId(otkazaoAkterId, fallbackToCurrentVozac: false);

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
                              return dtStr.isNotEmpty ? 'Vožnja: $dtStr' : 'Vožnja';
                            }(),
                            style: TextStyle(fontSize: 13, color: bojaPokupljen, fontWeight: FontWeight.bold),
                          ),
                        ],

                        // 3. ZELENA: pokupljen + plaćen
                        if (isPokupljen && isPlacen) ...[
                          Text(
                            () {
                              final dtStr = _fmt(widget.entry?.pokupljenAt);
                              return dtStr.isNotEmpty ? 'Vožnja: $dtStr' : 'Vožnja';
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
