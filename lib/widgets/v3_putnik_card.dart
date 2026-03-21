// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../helpers/v3_placanje_dialog_helper.dart';
import '../../models/v3_adresa.dart';
import '../../models/v3_putnik.dart';
import '../../models/v3_zahtev.dart';
import '../../services/v2_haptic_service.dart';
import '../../services/v3/v3_adresa_service.dart';
import '../../services/v3/v3_operativna_nedelja_service.dart';
import '../../services/v3/v3_vozac_service.dart';
import '../../services/v3/v3_zahtev_service.dart';
import '../../utils/v3_app_snack_bar.dart';
import '../../utils/v3_dan_helper.dart';
import '../../utils/v3_state_utils.dart';
import '../../utils/v3_validation_utils.dart';

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
  Timer? _longPressTimer;
  bool _isLongPressActive = false;
  bool _isProcessing = false;

  // Globalni lock — blokira duple klikove dok se jedna operacija završi
  static bool _globalProcessingLock = false;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  // ─── Long press za pokupljanje (1.5s) ──────────────────────────

  void _startLongPressTimer() {
    _longPressTimer?.cancel();
    _isLongPressActive = true;
    V2HapticService.selectionClick();
    _longPressTimer = Timer(const Duration(milliseconds: 1500), () {
      if (_isLongPressActive && mounted) {
        final status = widget.entry?.statusFinal ?? widget.zahtev?.status ?? '';
        final isPokupljen = widget.entry?.pokupljen ?? false;
        if (status != 'otkazano' && !isPokupljen) {
          _handlePickup();
        }
      }
    });
  }

  void _cancelLongPressTimer() {
    _longPressTimer?.cancel();
    _isLongPressActive = false;
  }

  // ─── Akcije ────────────────────────────────────────────────────

  Future<void> _handlePickup() async {
    if (widget.entry == null && widget.zahtev == null) return;
    if (_globalProcessingLock || _isProcessing) return;
    _globalProcessingLock = true;
    V3StateUtils.safeSetState(this, () => setState(() => _isProcessing = true));
    try {
      V2HapticService.mediumImpact();
      final currentVozac = V3VozacService.currentVozac;
      if (currentVozac == null) throw 'Niste logovani u V3 sistem';
      final isAlreadyPokupljen = widget.entry?.pokupljen ?? false;
      await V3ZahtevService.oznaciPokupljen(pokupljenVozacId: currentVozac.id, operativnaId: widget.entry?.id);
      await V2HapticService.putnikPokupljen();
      if (mounted) {
        V3AppSnackBar.success(context, isAlreadyPokupljen ? 'Vraćeno u obradu' : 'Putnik pokupljen');
        widget.onChanged?.call();
      }
    } catch (e) {
      if (mounted) V3AppSnackBar.error(context, 'Greška pri pokupljenju: $e');
    } finally {
      _globalProcessingLock = false;
      V3StateUtils.safeSetState(this, () => _isProcessing = false);
    }
  }

  Future<void> _handleCall() async {
    final tel = widget.putnik.telefon1 ?? widget.putnik.telefon2;
    if (tel == null || tel.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: tel);
    try {
      if (await canLaunchUrl(uri)) await launchUrl(uri);
    } catch (e) {
      debugPrint('[V3PutnikCard._handleCall] Greška: $e');
    }
  }

  Future<void> _handlePayment() async {
    if (widget.entry == null && widget.zahtev == null) return;
    if (_globalProcessingLock || _isProcessing) return;
    final tip = widget.putnik.tipPutnika;
    final defaultCena =
        (tip == 'dnevni' || tip == 'posiljka') ? widget.putnik.cenaPoPokupljenju : widget.putnik.cenaPoDanu;
    final rezultat = await V3PlacanjeDialogHelper.prikaziDialog(
      context: context,
      imePrezime: widget.putnik.imePrezime,
      defaultCena: defaultCena,
    );
    if (rezultat == null) return;
    _globalProcessingLock = true;
    V3StateUtils.safeSetState(this, () => setState(() => _isProcessing = true));
    try {
      final ok = await V3PlacanjeDialogHelper.sacuvajPlacanje(
        context: context,
        putnikId: widget.putnik.id,
        imePrezime: widget.putnik.imePrezime,
        rezultat: rezultat,
      );
      if (ok && widget.entry != null) {
        await V3OperativnaNedeljaService.updateNaplata(
          id: widget.entry!.id,
          iznos: rezultat.iznos,
          naplatioVozacId: V3VozacService.currentVozac?.id,
        );
      }
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) V3AppSnackBar.error(context, 'Greška pri plaćanju: $e');
    } finally {
      _globalProcessingLock = false;
      V3StateUtils.safeSetState(this, () => _isProcessing = false);
    }
  }

  Future<void> _handleNavigation() async {
    // Prioritet 1: direktan adresa_id_override
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
      final googleUrl = Uri.parse('https://maps.google.com/?q=${adresa.gpsLat},${adresa.gpsLng}');
      if (await canLaunchUrl(googleUrl)) {
        await launchUrl(googleUrl, mode: LaunchMode.externalApplication);
        return;
      }
    }
    if (mounted) {
      final naziv = adresaNaziv ?? '/';
      V3AppSnackBar.warning(context, '⚠️ GPS koordinate nisu dostupne za: $naziv');
    }
  }

  Future<void> _handleOtkazivanje() async {
    final operativnaId = widget.entry?.id;
    if (operativnaId == null || operativnaId.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Theme.of(context).colorScheme.outline, width: 1),
        ),
        title: Text(
          'Otkazivanje putnika',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Da li ste sigurni da želite da otkaže ${widget.putnik.imePrezime}?',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        actions: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.grey.shade400, Colors.grey.shade600]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Ne', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF1976D2), Color(0xFF0D47A1)]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Da', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await V3ZahtevService.otkaziZahtev('',
            otkazaoVozacId: V3VozacService.currentVozac?.id, operativnaId: operativnaId);
        if (mounted) {
          V3AppSnackBar.warning(context, 'Otkazano: ${widget.putnik.imePrezime}');
          widget.onChanged?.call();
        }
      } catch (e) {
        if (mounted) V3AppSnackBar.error(context, 'Greška: $e');
      }
    }
  }

  // ─── Boje kartice po statusu ───────────────────────────────────

  BoxDecoration _getCardDecoration() {
    final status = widget.entry?.statusFinal ?? widget.zahtev?.status ?? '';
    if (status == 'otkazano') {
      return BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFCDD2), Color(0xFFEF9A9A)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE57373), width: 0.6),
        boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.15), blurRadius: 4, offset: const Offset(0, 2))],
      );
    }
    final bool isPokupljen = widget.entry?.pokupljen ?? false;
    if (isPokupljen) {
      final bool isPlacen = widget.entry?.naplataStatus == 'placeno';
      if (isPlacen) {
        return BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFC8E6C9), Color(0xFFA5D6A7)],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF81C784), width: 0.6),
          boxShadow: [BoxShadow(color: Colors.green.withOpacity(0.15), blurRadius: 4, offset: const Offset(0, 2))],
        );
      }
      return BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFBBDEFB), Color(0xFF90CAF9)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF64B5F6), width: 0.6),
        boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.15), blurRadius: 4, offset: const Offset(0, 2))],
      );
    }
    // Bijela kartica — default
    if (widget.vozacBoja != null) {
      // Color blending - bleda boja vozača preko bele osnove
      final blendedColor = Color.lerp(Colors.white, widget.vozacBoja!, 0.20)!; // 20% mix
      return BoxDecoration(
        color: blendedColor, // Blended boja
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFE0E0E0),
          width: 0.8,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 3, offset: const Offset(0, 1))],
      );
    }
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: const Color(0xFFE0E0E0),
        width: 0.8,
      ),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 3, offset: const Offset(0, 1))],
    );
  }

  Color _getTextColor() {
    final status = widget.entry?.statusFinal ?? widget.zahtev?.status ?? '';
    if (status == 'otkazano') return const Color(0xFFB71C1C);
    if (widget.entry?.pokupljen ?? false) {
      final isPlacen = widget.entry?.naplataStatus == 'placeno';
      return isPlacen ? const Color(0xFF1B5E20) : const Color(0xFF0D47A1);
    }
    return Colors.black87;
  }

  Color _getSecondaryTextColor() {
    final status = widget.entry?.statusFinal ?? widget.zahtev?.status ?? '';
    if (status == 'otkazano') return const Color(0xFFC62828);
    if (widget.entry?.pokupljen ?? false) {
      final isPlacen = widget.entry?.naplataStatus == 'placeno';
      return isPlacen ? const Color(0xFF2E7D32) : const Color(0xFF1565C0);
    }
    return Colors.grey.shade700;
  }

  // ─── Tip badge ─────────────────────────────────────────────────

  Color _getTipColor() {
    switch (widget.putnik.tipPutnika.toLowerCase()) {
      case 'radnik':
        return const Color(0xFF3B7DD8);
      case 'ucenik':
        return const Color(0xFF44A08D);
      case 'posiljka':
        return const Color(0xFFE65C00);
      case 'dnevni':
        return const Color(0xFFFF6B6B);
      default:
        return Colors.green;
    }
  }

  String _getTipLabel() {
    switch (widget.putnik.tipPutnika.toLowerCase()) {
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
  }

  // ─── Adresa helper ─────────────────────────────────────────────

  String? _getAdresaNaziv() {
    // Prioritet 1: direktan adresa_id_override
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

  Color? _parseHexColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final clean = hex.replaceAll('#', '').trim();
    if (clean.length == 6) {
      final value = int.tryParse('FF$clean', radix: 16);
      return value != null ? Color(value) : null;
    }
    if (clean.length == 8) {
      final value = int.tryParse(clean, radix: 16);
      return value != null ? Color(value) : null;
    }
    return null;
  }

  // ─── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final status = widget.entry?.statusFinal ?? widget.zahtev?.status ?? '';
    final bool isPokupljen = widget.entry?.pokupljen ?? false;
    final bool isOtkazan = status == 'otkazano';
    final bool isPlacen = widget.entry?.naplataStatus == 'placeno';
    final bool hasTel = widget.putnik.telefon1 != null || widget.putnik.telefon2 != null;
    final String? adresaNaziv = _getAdresaNaziv();
    final bool hasAdresa = adresaNaziv != null && adresaNaziv.isNotEmpty;
    final Color textColor = _getTextColor();
    final Color secondaryTextColor = _getSecondaryTextColor();
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
                              child: Text(
                                widget.putnik.imePrezime,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontStyle: FontStyle.italic,
                                  fontSize: 14,
                                  color: textColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            if (brojMesta > 1)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: textColor.withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: textColor.withOpacity(0.45), width: 0.6),
                                  ),
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
                            child: Text(
                              adresaNaziv,
                              style: TextStyle(fontSize: 13, color: secondaryTextColor, fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _getTipColor().withOpacity(0.20),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _getTipLabel(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: _getTipColor(),
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
                        if (v != null) return _parseHexColor(v.boja) ?? const Color(0xFF9E9E9E);
                      }
                      return _parseHexColor(_currentVozac?.boja) ?? const Color(0xFF9E9E9E);
                    }

                    final bojaPokupljen = _bojaZaVozacId(widget.entry?.pokupljenVozacId);
                    final bojaNaplata = _bojaZaVozacId(widget.entry?.naplatioVozacId);
                    final bojaOtkaz = _bojaZaVozacId(widget.entry?.otkazaoVozacId);
                    final otkazaoPutnikId = widget.entry?.otkazaoPutnikId;

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
                              final iznos = widget.entry?.iznosNaplacen ?? 0;
                              final vpl = widget.entry?.vremePlacen;
                              final iznosStr = iznos > 0 ? '${iznos.toStringAsFixed(0)} RSD' : '';
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
                              final dtStr = _fmt(widget.entry?.vremePokupljen);
                              return dtStr.isNotEmpty ? 'Pokupljen: $dtStr' : 'Pokupljen';
                            }(),
                            style: TextStyle(fontSize: 13, color: bojaPokupljen, fontWeight: FontWeight.bold),
                          ),
                        ],

                        // 3. ZELENA: pokupljen + plaćen
                        if (isPokupljen && isPlacen) ...[
                          Text(
                            () {
                              final dtStr = _fmt(widget.entry?.vremePokupljen);
                              return dtStr.isNotEmpty ? 'Pokupljen: $dtStr' : 'Pokupljen';
                            }(),
                            style: TextStyle(fontSize: 13, color: bojaPokupljen, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            () {
                              final iznos = widget.entry?.iznosNaplacen ?? 0;
                              final vpl = widget.entry?.vremePlacen;
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
                              final vp = widget.entry?.vremePokupljen;
                              final dtStr = _fmt(vp);
                              final koOtkaz = otkazaoPutnikId != null ? 'Putnik otkazao' : 'Vozač otkazao';
                              return dtStr.isNotEmpty ? '$koOtkaz: $dtStr' : koOtkaz;
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
