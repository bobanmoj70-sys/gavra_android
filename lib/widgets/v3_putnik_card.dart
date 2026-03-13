import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../helpers/v3_placanje_dialog_helper.dart';
import '../../models/v3_putnik.dart';
import '../../models/v3_zahtev.dart';
import '../../services/v2_haptic_service.dart';
import '../../services/v3/v3_vozac_service.dart';
import '../../services/v3/v3_zahtev_service.dart';
import '../../utils/v2_app_snack_bar.dart';

class V3PutnikCard extends StatefulWidget {
  final V3Putnik putnik;
  final V3Zahtev? zahtev;

  const V3PutnikCard({
    super.key,
    required this.putnik,
    this.zahtev,
  });

  @override
  State<V3PutnikCard> createState() => _V3PutnikCardState();
}

class _V3PutnikCardState extends State<V3PutnikCard> with SingleTickerProviderStateMixin {
  late AnimationController _longPressController;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _longPressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void dispose() {
    _longPressController.dispose();
    super.dispose();
  }

  Future<void> _handleCall() async {
    final tel = widget.putnik.telefon1 ?? widget.putnik.telefon2;
    if (tel == null || tel.isEmpty) return;

    final uri = Uri.parse('tel:$tel');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _handlePickup() async {
    if (widget.zahtev == null || _isProcessing) return;

    setState(() => _isProcessing = true);
    V2HapticService.selectionClick();

    try {
      final currentVozac = V3VozacService.currentVozac;
      if (currentVozac == null) throw 'Niste logovani u V3 sistem';

      final isAlreadyPokupljen = widget.zahtev!.status == 'pokupljen';

      await V3ZahtevService.oznaciPokupljen(
        zahtevId: widget.zahtev!.id,
        pokupljen: !isAlreadyPokupljen,
        vozacId: currentVozac.id,
      );

      V2HapticService.mediumImpact();
      if (!mounted) return;

      V2AppSnackBar.success(context, isAlreadyPokupljen ? 'Vraćeno u obradu' : 'Putnik pokupljen');
    } catch (e) {
      if (mounted) V2AppSnackBar.error(context, 'Greška: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handlePayment() async {
    if (widget.zahtev == null || _isProcessing) return;

    final rezultat = await V3PlacanjeDialogHelper.prikaziDialog(
      context: context,
      putnikIme: widget.putnik.imePrezime,
      defaultCena: 10.0,
    );

    if (rezultat == null) return;

    setState(() => _isProcessing = true);
    try {
      await V3PlacanjeDialogHelper.sacuvajPlacanje(
        context: context,
        putnikId: widget.putnik.id,
        putnikIme: widget.putnik.imePrezime,
        rezultat: rezultat,
        zahtevId: widget.zahtev!.id,
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Color _getTipColor() {
    final t = widget.putnik.tipPutnika.toLowerCase();
    if (t.contains('radnik')) return Colors.orange;
    if (t.contains('ucenik')) return Colors.blue;
    if (t.contains('posiljka')) return Colors.purple;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    final bool isPokupljen = widget.zahtev?.status == 'pokupljen';

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: isPokupljen ? 0.6 : 1.0,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: isPokupljen ? BorderSide(color: Colors.green.withOpacity(0.5), width: 2) : BorderSide.none,
        ),
        elevation: isPokupljen ? 1 : 4,
        child: InkWell(
          onTap: () {
            // TODO: Detalji putnika
          },
          onLongPress: _handlePickup,
          borderRadius: BorderRadius.circular(15),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _getTipColor(),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.putnik.imePrezime,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              decoration: isPokupljen ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          Text(
                            '${widget.putnik.adresaBcNaziv ?? "/"} ➔ ${widget.putnik.adresaVsNaziv ?? "/"}',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    if (isPokupljen)
                      const Icon(Icons.check_circle, color: Colors.green, size: 30)
                    else if (widget.putnik.telefon1 != null || widget.putnik.telefon2 != null)
                      IconButton(
                        icon: const Icon(Icons.phone, color: Colors.green),
                        onPressed: _handleCall,
                      ),
                  ],
                ),
                if (!isPokupljen && widget.zahtev != null) ...[
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Status: Čeka na ukrcavanje',
                        style: TextStyle(fontStyle: FontStyle.italic, color: Colors.blue),
                      ),
                      TextButton.icon(
                        onPressed: _handlePayment,
                        icon: const Icon(Icons.payments_outlined),
                        label: const Text('NAPLATI'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
