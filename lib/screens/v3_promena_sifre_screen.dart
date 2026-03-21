import 'package:flutter/material.dart';

import '../globals.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_input_utils.dart';
import '../utils/v3_state_utils.dart';
import '../utils/v3_text_utils.dart';

/// PROMENA ŠIFRE SCREEN (v3)
/// Vozač može da promeni svoju šifru nakon uspešnog logina
class V3PromenaSifreScreen extends StatefulWidget {
  final String vozacIme;

  const V3PromenaSifreScreen({super.key, required this.vozacIme});

  @override
  State<V3PromenaSifreScreen> createState() => _V3PromenaSifreScreenState();
}

class _V3PromenaSifreScreenState extends State<V3PromenaSifreScreen> {
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _staraSifraVisible = false;
  bool _novaSifraVisible = false;
  bool _potvrdaVisible = false;

  String? _trenutnaSifra;

  @override
  void initState() {
    super.initState();
    _loadTrenutnaSifra();
  }

  @override
  void dispose() {
    V3TextUtils.disposeController('stara_sifra');
    V3TextUtils.disposeController('nova_sifra');
    V3TextUtils.disposeController('potvrda_sifra');
    super.dispose();
  }

  Future<void> _loadTrenutnaSifra() async {
    try {
      final row = await supabase.from('v3_vozaci').select('sifra').eq('ime_prezime', widget.vozacIme).maybeSingle();
      if (row != null && mounted) {
        setState(() {
          _trenutnaSifra = row['sifra']?.toString() ?? '';
        });
      }
    } catch (e) {
      debugPrint('[V3PromenaSifre] _loadTrenutnaSifra greška: $e');
    }
  }

  Future<void> _promeniSifru() async {
    if (!_formKey.currentState!.validate()) return;

    V3StateUtils.safeSetState(this, () => _isLoading = true);

    try {
      final staraSifra = V3TextUtils.getControllerText('stara_sifra');
      if (_trenutnaSifra != null && _trenutnaSifra!.isNotEmpty && _trenutnaSifra != staraSifra) {
        V3AppSnackBar.error(context, 'Pogrešna trenutna šifra.');
        return;
      }

      await supabase
          .from('v3_vozaci')
          .update({'sifra': V3TextUtils.getControllerText('nova_sifra')}).eq('ime_prezime', widget.vozacIme);

      if (!mounted) return;

      V3AppSnackBar.success(context, 'Šifra uspešno promenjena!');
      Navigator.pop(context);
    } catch (e) {
      V3AppSnackBar.error(context, 'Greška: $e');
    } finally {
      V3StateUtils.safeSetState(this, () => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool imaSifru = _trenutnaSifra != null && _trenutnaSifra!.isNotEmpty;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          '🔑 Promena šifre',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: V3ContainerUtils.backgroundContainer(
        gradient: Theme.of(context).backgroundGradient,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + kToolbarHeight + 24, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.lock_reset, color: Colors.amber, size: 60),
                const SizedBox(height: 16),
                Text(
                  widget.vozacIme,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  imaSifru ? 'Promeni svoju šifru' : 'Postavi novu šifru',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (imaSifru) ...[
                  V3InputUtils.passwordField(
                    controller: V3TextUtils.staraSifraController,
                    isVisible: _staraSifraVisible,
                    onToggleVisibility: () =>
                        V3StateUtils.safeSetState(this, () => _staraSifraVisible = !_staraSifraVisible),
                    label: 'Trenutna šifra',
                    validator: (v) => V3InputUtils.requiredValidator(v, 'Unesite trenutnu šifru'),
                  ),
                  const SizedBox(height: 16),
                ],
                V3InputUtils.passwordField(
                  controller: V3TextUtils.novaSifraController,
                  isVisible: _novaSifraVisible,
                  onToggleVisibility: () =>
                      V3StateUtils.safeSetState(this, () => _novaSifraVisible = !_novaSifraVisible),
                  label: 'Nova šifra',
                  validator: V3InputUtils.passwordValidator,
                ),
                const SizedBox(height: 16),
                V3InputUtils.passwordField(
                  controller: V3TextUtils.potvrdaSifraController,
                  isVisible: _potvrdaVisible,
                  onToggleVisibility: () => V3StateUtils.safeSetState(this, () => _potvrdaVisible = !_potvrdaVisible),
                  label: 'Potvrdi novu šifru',
                  validator: (v) =>
                      V3InputUtils.confirmPasswordValidator(v, V3TextUtils.getControllerText('nova_sifra')),
                ),
                const SizedBox(height: 32),
                V3ButtonUtils.elevatedButton(
                  onPressed: _isLoading ? null : _promeniSifru,
                  text: imaSifru ? '🔄 Promeni šifru' : '✅ Postavi šifru',
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  isLoading: _isLoading,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                const SizedBox(height: 24),
                V3ContainerUtils.styledContainer(
                  padding: const EdgeInsets.all(12),
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.white54, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Nova šifra će važiti od sledeće prijave.',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
