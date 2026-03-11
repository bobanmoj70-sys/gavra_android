import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/v2_pin_zahtev_service.dart';
import '../theme.dart';
import '../utils/v2_app_snack_bar.dart';

/// PIN ZAHTEVI SCREEN
/// Admin vidi sve zahteve za PIN i može da odobri/odbije
class V2PinZahteviScreen extends StatefulWidget {
  const V2PinZahteviScreen({super.key});

  @override
  State<V2PinZahteviScreen> createState() => _PinZahteviScreenState();
}

class _PinZahteviScreenState extends State<V2PinZahteviScreen> {
  late final Stream<List<Map<String, dynamic>>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = V2PinZahtevService.streamZahteviKojiCekaju();
  }

  /// Helper: čita telefon iz oba moguća ključa
  static String _getTelefon(Map<String, dynamic> z, {String fallback = '-'}) =>
      z['telefon'] as String? ?? z['broj_telefona'] as String? ?? fallback;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        final zahtevi = snapshot.data ?? [];
        final isLoading = snapshot.connectionState == ConnectionState.waiting && zahtevi.isEmpty;

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('PIN Zahtevi', style: TextStyle(fontWeight: FontWeight.bold)),
            automaticallyImplyLeading: false,
          ),
          body: Container(
            decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
            child: SafeArea(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : zahtevi.isEmpty
                      ? const Center(
                          child: Text(
                            'Nema zahteva na čekanju.',
                            style: TextStyle(color: Colors.white70),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: zahtevi.length,
                          itemBuilder: (context, index) {
                            final zahtev = zahtevi[index];
                            return _buildZahtevCard(zahtev);
                          },
                        ),
            ),
          ),
        );
      },
    );
  }

  /// Pošalji PIN putem SMS-a
  Future<void> _posaljiPinSms(String brojTelefona, String pin, String ime) async {
    final message = 'Vaš PIN za aplikaciju Gavra 013 je: $pin\n'
        'Koristite ovaj PIN zajedno sa brojem telefona za pristup.\n'
        '- Gavra 013';

    final Uri smsUri = Uri(
      scheme: 'sms',
      path: brojTelefona,
      queryParameters: {'body': message},
    );

    try {
      if (!mounted) return;
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);
      } else {
        if (mounted) {
          V2AppSnackBar.warning(context, 'Ne mogu da otvorim SMS aplikaciju');
        }
      }
    } catch (e) {
      if (mounted) {
        V2AppSnackBar.error(context, '❌ Greška pri otvaranju SMS: $e');
      }
    }
  }

  /// Odobri zahtev i dodeli PIN
  Future<void> _odobriZahtev(Map<String, dynamic> zahtev) async {
    final zahtevId = zahtev['id'] as String;
    final ime = zahtev['putnik_ime'] as String? ?? '';
    final brojTelefona = _getTelefon(zahtev, fallback: '');

    final generisaniPin = V2PinZahtevService.generatePin();
    final pinController = TextEditingController(text: generisaniPin);

    String? rezultat;
    rezultat = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.vpn_key, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(child: Text('Dodeli PIN za $ime', style: const TextStyle(color: Colors.white, fontSize: 16))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pinController,
              style: const TextStyle(color: Colors.white, fontSize: 28, letterSpacing: 12),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                hintText: '0000',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.green),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.green),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.green, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                pinController.text = V2PinZahtevService.generatePin();
              },
              icon: const Icon(Icons.refresh, color: Colors.amber),
              label: const Text('Generiši novi', style: TextStyle(color: Colors.amber)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Odustani', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              if (pinController.text.length == 4) {
                Navigator.pop(dialogCtx, pinController.text);
              } else {
                V2AppSnackBar.warning(dialogCtx, 'PIN mora imati 4 cifre');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Dodeli PIN', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ); // showDialog
    pinController.dispose();

    if (rezultat != null) {
      final success = await V2PinZahtevService.odobriZahtev(
        zahtevId: zahtevId,
        pin: rezultat,
      );

      if (!mounted) return;
      if (success) {
        V2AppSnackBar.success(context, '✅ PIN $rezultat dodeljen putniku $ime');
        // Automatski otvori SMS da pošalje PIN
        if (brojTelefona.isNotEmpty && mounted) {
          await _posaljiPinSms(brojTelefona, rezultat, ime);
        }
      } else {
        V2AppSnackBar.error(context, '❌ Greška pri dodeli PIN-a');
      }
    }
  }

  /// Odbij zahtev
  Future<void> _odbijZahtev(Map<String, dynamic> zahtev) async {
    final zahtevId = zahtev['id'] as String;
    final ime = zahtev['putnik_ime'] as String? ?? '';

    final potvrda = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Odbij zahtev?', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          'Da li sigurno želite da odbijete zahtev za PIN od putnika $ime?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Odustani', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Odbij', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (potvrda != true || !mounted) return;
    final success = await V2PinZahtevService.odbijZahtev(zahtevId);
    if (!mounted) return;
    if (success) {
      V2AppSnackBar.warning(context, '🚫 Zahtev od $ime je odbijen');
    } else {
      V2AppSnackBar.error(context, '❌ Greška pri odbijanju');
    }
  }

  Widget _buildZahtevCard(Map<String, dynamic> zahtev) {
    final ime = zahtev['putnik_ime'] as String? ?? '';
    final telefon = _getTelefon(zahtev);
    final email = zahtev['email'] as String? ?? '-';
    final tip = zahtev['tip'] as String? ?? '-';
    final createdAt = zahtev['created_at'] as String?;

    String vremeZahteva = '-';
    if (createdAt != null) {
      final dt = DateTime.tryParse(createdAt)?.toLocal();
      if (dt != null) {
        vremeZahteva = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} '
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    }

    return Card(
      color: const Color(0xFF1a1a2e),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.amber.withValues(alpha: 0.2),
                  child: Text(
                    ime.isNotEmpty ? ime[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ime,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        tip == 'radnik'
                            ? '👷 Radnik'
                            : tip == 'ucenik'
                                ? '🎓 Učenik'
                                : tip,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '⏳ Čeka',
                    style: TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow(Icons.phone, 'Telefon', telefon),
            const SizedBox(height: 8),
            _buildInfoRow(Icons.email, 'Email', email),
            const SizedBox(height: 8),
            _buildInfoRow(Icons.access_time, 'Zahtev poslat', vremeZahteva),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _odbijZahtev(zahtev),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Odbij'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _odobriZahtev(zahtev),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Dodeli PIN'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.5), size: 18),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
