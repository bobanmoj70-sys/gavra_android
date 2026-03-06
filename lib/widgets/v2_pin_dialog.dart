import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/realtime/v2_master_realtime_manager.dart';
import '../services/v2_pin_zahtev_service.dart';
import '../utils/v2_app_snack_bar.dart';

/// PIN DIALOG za mesečne putnike
/// Prikazuje/generiše/šalje PIN kod
class V2PinDialog extends StatefulWidget {
  final String putnikId;
  final String putnikIme;
  final String putnikTabela;
  final String? trenutniPin;
  final String? brojTelefona;

  const V2PinDialog({
    super.key,
    required this.putnikId,
    required this.putnikIme,
    required this.putnikTabela,
    this.trenutniPin,
    this.brojTelefona,
  });

  @override
  State<V2PinDialog> createState() => _V2PinDialogState();
}

class _V2PinDialogState extends State<V2PinDialog> {
  late String? _pin;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _pin = widget.trenutniPin;
  }

  /// Sačuvaj PIN u bazu
  Future<void> _savePin(String newPin) async {
    setState(() => _isLoading = true);

    try {
      await V2MasterRealtimeManager.instance.v2UpdatePin(widget.putnikId, newPin, widget.putnikTabela);

      // Audit log — direktna izmena PIN-a od strane admina (bez zahteva putnika)
      unawaited(V2PinZahtevService.logujDirektnaIzmena(
        putnikId: widget.putnikId,
        putnikTabela: widget.putnikTabela,
      ));

      setState(() {
        _pin = newPin;
        _isLoading = false;
      });

      if (mounted) {
        V2AppSnackBar.success(context, 'PIN sačuvan!');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        V2AppSnackBar.error(context, 'Greška: $e');
      }
    }
  }

  /// Pošalji PIN putem SMS-a
  Future<void> _sendSms() async {
    if (widget.brojTelefona == null || widget.brojTelefona!.isEmpty) {
      V2AppSnackBar.warning(context, 'V2Putnik nema broj telefona!');
      return;
    }

    if (_pin == null || _pin!.isEmpty) {
      V2AppSnackBar.warning(context, 'Prvo generiši PIN!');
      return;
    }

    final message = 'Vaš PIN za aplikaciju Gavra 013 je: $_pin\n'
        'Koristite ovaj PIN zajedno sa brojem telefona za pristup.\n'
        '- Gavra 013';

    final Uri smsUri = Uri(
      scheme: 'sms',
      path: widget.brojTelefona,
      queryParameters: {'body': message},
    );

    try {
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);
      } else {
        throw Exception('Ne mogu da otvorim SMS aplikaciju');
      }
    } catch (e) {
      if (mounted) {
        V2AppSnackBar.error(context, 'Greška: $e');
      }
    }
  }

  /// Kopiraj PIN u clipboard
  void _copyPin() {
    if (_pin != null && _pin!.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: _pin!));
      V2AppSnackBar.info(context, 'PIN kopiran!');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      title: Row(
        children: [
          const Icon(Icons.lock, color: Colors.amber, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'PIN - ${widget.putnikIme}',
              style: const TextStyle(color: Colors.white, fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Prikaz PIN-a
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withOpacity(0.5)),
              ),
              child: Column(
                children: [
                  Text(
                    _pin ?? 'Nema PIN',
                    style: TextStyle(
                      color: _pin != null ? Colors.amber : Colors.white54,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                    ),
                  ),
                  if (_pin != null) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _copyPin,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.copy, color: Colors.white54, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            'Kopiraj',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Dugmad
            Row(
              children: [
                // Generiši PIN
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () async {
                            final newPin = V2PinZahtevService.generatePin();
                            await _savePin(newPin);
                          },
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: Text(_pin == null ? 'Generiši' : 'Novi PIN'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Pošalji SMS
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_pin == null || widget.brojTelefona == null) ? null : _sendSms,
                    icon: const Icon(Icons.sms, size: 18),
                    label: const Text('Pošalji'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),

            // Info o telefonu
            if (widget.brojTelefona == null || widget.brojTelefona!.isEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.orange, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'V2Putnik nema broj telefona',
                        style: TextStyle(color: Colors.orange, fontSize: 12),
                      ),
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
          onPressed: () => Navigator.pop(context),
          child: const Text('Zatvori'),
        ),
      ],
    );
  }
}
