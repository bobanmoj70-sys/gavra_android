import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/v3/v3_pin_zahtev_service.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dan_helper.dart';
import '../utils/v3_input_utils.dart';
import '../utils/v3_state_utils.dart';

/// PIN ZAHTEVI SCREEN
/// Admin vidi sve zahteve za PIN i može da odobri/odbije
class V3PinZahteviScreen extends StatefulWidget {
  const V3PinZahteviScreen({super.key});

  @override
  State<V3PinZahteviScreen> createState() => _V3PinZahteviScreenState();
}

class _V3PinZahteviScreenState extends State<V3PinZahteviScreen> {
  late final Stream<List<Map<String, dynamic>>> _stream = V3PinZahtevService.streamZahteviKojiCekaju();

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
            title: const Text(
              'PIN Zahtevi',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
            automaticallyImplyLeading: true,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: V3ContainerUtils.gradientContainer(
            gradient: Theme.of(context).backgroundGradient,
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
                          itemBuilder: (context, index) => _pinZahtevCard(
                            context: context,
                            zahtev: zahtevi[index],
                            onOdobri: () => _odobriZahtev(zahtevi[index]),
                            onOdbij: () => _odbijZahtev(zahtevi[index]),
                          ),
                        ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _odobriZahtev(Map<String, dynamic> zahtev) {
    return showDialog<void>(
      context: context,
      builder: (_) => _PinOdobriDialog(
        zahtev: zahtev,
        getTelefon: _getTelefon,
      ),
    );
  }

  Future<void> _odbijZahtev(Map<String, dynamic> zahtev) {
    return showDialog<void>(
      context: context,
      builder: (_) => _PinOdbijDialog(zahtev: zahtev),
    );
  }
}

// ─── top-level: pošalji PIN SMS ─────────────────────────────────────────────

Future<void> _pinPosaljiSms(BuildContext ctx, String brojTelefona, String pin, String ime) async {
  final smsUri = Uri(
    scheme: 'sms',
    path: brojTelefona,
    queryParameters: {
      'body': 'Vaš PIN za aplikaciju Gavra 013 je: $pin\n'
          'Koristite ovaj PIN zajedno sa brojem telefona za pristup.\n'
          '- Gavra 013',
    },
  );
  try {
    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri);
    } else if (ctx.mounted) {
      V3AppSnackBar.warning(ctx, 'Ne mogu da otvorim SMS aplikaciju');
    }
  } catch (e) {
    if (ctx.mounted) V3AppSnackBar.error(ctx, '❌ Greška pri otvaranju SMS: $e');
  }
}

// ─── top-level: zahtev card ──────────────────────────────────────────────────

Widget _pinZahtevCard({
  required BuildContext context,
  required Map<String, dynamic> zahtev,
  required VoidCallback onOdobri,
  required VoidCallback onOdbij,
}) {
  final ime = zahtev['putnik_ime'] as String? ?? '';
  final telefon = zahtev['telefon'] as String? ?? zahtev['broj_telefona'] as String? ?? '-';
  final email = zahtev['email'] as String? ?? '-';
  final createdAt = zahtev['created_at'] as String?;

  String vremeZahteva = '-';
  if (createdAt != null) {
    final dt = DateTime.tryParse(createdAt)?.toLocal();
    if (dt != null) {
      vremeZahteva = V3DanHelper.formatDatumVreme(dt);
    }
  }

  return V3ContainerUtils.styledContainer(
    margin: const EdgeInsets.only(bottom: 12),
    backgroundColor: Colors.white.withValues(alpha: 0.06),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Theme.of(context).glassBorder),
    boxShadow: [
      BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8),
    ],
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
                child: Text(
                  ime,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              V3ContainerUtils.iconContainer(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                backgroundColor: Colors.orange.withValues(alpha: 0.2),
                borderRadiusGeometry: BorderRadius.circular(8),
                child: const Text(
                  '⏳ Čeka',
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _pinInfoRow(Icons.phone, 'Telefon', telefon),
          const SizedBox(height: 8),
          _pinInfoRow(Icons.email, 'Email', email),
          const SizedBox(height: 8),
          _pinInfoRow(Icons.access_time, 'Zahtev poslat', vremeZahteva),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: V3ButtonUtils.outlinedButton(
                  onPressed: onOdbij,
                  text: 'Odbij',
                  icon: Icons.close,
                  borderColor: Colors.red,
                  foregroundColor: Colors.red,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: V3ButtonUtils.successButton(
                  onPressed: onOdobri,
                  text: 'Dodeli PIN',
                  icon: Icons.check,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

Widget _pinInfoRow(IconData icon, String label, String value) {
  return Row(
    children: [
      Icon(icon, color: Colors.white54, size: 18),
      const SizedBox(width: 8),
      Text('$label: ', style: const TextStyle(color: Colors.white54, fontSize: 13)),
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

// ─── _PinOdobriDialog ────────────────────────────────────────────────────────

class _PinOdobriDialog extends StatefulWidget {
  const _PinOdobriDialog({
    required this.zahtev,
    required this.getTelefon,
  });
  final Map<String, dynamic> zahtev;
  final String Function(Map<String, dynamic>, {String fallback}) getTelefon;

  @override
  State<_PinOdobriDialog> createState() => _PinOdobriDialogState();
}

class _PinOdobriDialogState extends State<_PinOdobriDialog> {
  late final TextEditingController _pinCtrl;

  @override
  void initState() {
    super.initState();
    _pinCtrl = TextEditingController(text: V3PinZahtevService.generatePin());
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ime = widget.zahtev['putnik_ime'] as String? ?? '';
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.vpn_key, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Dodeli PIN za $ime',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          V3InputUtils.pinField(
            controller: _pinCtrl,
            label: 'PIN',
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => V3StateUtils.safeSetState(this, () => _pinCtrl.text = V3PinZahtevService.generatePin()),
            icon: const Icon(Icons.refresh, color: Colors.amber),
            label: const Text('Generiši novi', style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
      actions: [
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.pop(context),
          text: 'Odustani',
          foregroundColor: Colors.grey,
        ),
        V3ButtonUtils.successButton(
          onPressed: () async {
            if (_pinCtrl.text.length != 4) {
              V3AppSnackBar.warning(context, 'PIN mora imati 4 cifre');
              return;
            }
            final pin = _pinCtrl.text;
            final zahtevId = widget.zahtev['id'] as String;
            final brojTelefona = widget.getTelefon(widget.zahtev, fallback: '');

            final success = await V3PinZahtevService.odobriZahtev(
              zahtevId: zahtevId,
              pin: pin,
            );
            if (!context.mounted) return;
            Navigator.pop(context);
            if (success) {
              V3AppSnackBar.success(context, '✅ PIN $pin dodeljen putniku $ime');
              if (brojTelefona.isNotEmpty && context.mounted) {
                await _pinPosaljiSms(context, brojTelefona, pin, ime);
              }
            } else {
              V3AppSnackBar.error(context, '❌ Greška pri dodeli PIN-a');
            }
          },
          text: 'Dodeli PIN',
        ),
      ],
    );
  }
}

// ─── _PinOdbijDialog ─────────────────────────────────────────────────────────

class _PinOdbijDialog extends StatelessWidget {
  const _PinOdbijDialog({required this.zahtev});
  final Map<String, dynamic> zahtev;

  @override
  Widget build(BuildContext context) {
    final zahtevId = zahtev['id'] as String;
    final ime = zahtev['putnik_ime'] as String? ?? '';
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
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
        V3ButtonUtils.textButton(
          onPressed: () => Navigator.pop(context),
          text: 'Odustani',
          foregroundColor: Colors.grey,
        ),
        V3ButtonUtils.dangerButton(
          onPressed: () async {
            Navigator.pop(context);
            final success = await V3PinZahtevService.odbijZahtev(zahtevId);
            if (!context.mounted) return;
            if (success) {
              V3AppSnackBar.warning(context, '🚫 Zahtev od $ime je odbijen');
            } else {
              V3AppSnackBar.error(context, '❌ Greška pri odbijanju');
            }
          },
          text: 'Odbij',
        ),
      ],
    );
  }
}
