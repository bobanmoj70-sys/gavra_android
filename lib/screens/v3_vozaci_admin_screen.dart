import 'package:flutter/material.dart';

import '../globals.dart';
import '../models/v3_vozac.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_vozac_service.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dialog_utils.dart';
import '../utils/v3_error_utils.dart';
import '../utils/v3_navigation_utils.dart';
import '../utils/v3_state_utils.dart';

/// V3 admin ekran za upravljanje vozačima.
/// Dodaj / uredi / deaktiviraj vozače.
class V3VozaciAdminScreen extends StatefulWidget {
  const V3VozaciAdminScreen({super.key});

  @override
  State<V3VozaciAdminScreen> createState() => _V3VozaciAdminScreenState();
}

class _V3VozaciAdminScreenState extends State<V3VozaciAdminScreen> {
  bool _showNeaktivni = false;

  // Predefinisane boje
  static const List<Color> _paletaBoja = [
    Color(0xFF7C4DFF),
    Color(0xFFFF9800),
    Color(0xFF00E5FF),
    Color(0xFFFF1493),
    Color(0xFFFFD700),
    Color(0xFF4CAF50),
    Color(0xFFE91E63),
    Color(0xFF2196F3),
    Color(0xFFFFEB3B),
    Color(0xFF9C27B0),
    Color(0xFFFF5722),
    Color(0xFF00BCD4),
  ];

  // ─── Helpers ─────────────────────────────────────────────────────────────

  /// Hex string (#RRGGBB) → Color
  static Color _hexToColor(String? hex) {
    if (hex == null || hex.isEmpty) return Colors.blueAccent;
    final h = hex.replaceAll('#', '');
    try {
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) {
      return Colors.blueAccent;
    }
  }

  /// Color → hex string (#RRGGBB)
  static String _colorToHex(Color color) =>
      '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  // ─── Actions ─────────────────────────────────────────────────────────────

  void _showDodajDialog() {
    _showVozacDialog(vozac: null);
  }

  void _showUrediDialog(V3Vozac vozac) {
    _showVozacDialog(vozac: vozac);
  }

  Future<void> _showVozacDialog({V3Vozac? vozac}) async {
    final isEdit = vozac != null;
    final imeCtrl = TextEditingController(text: vozac?.imePrezime ?? '');
    final emailCtrl = TextEditingController(text: vozac?.email ?? '');
    final sifraCtrl = TextEditingController(text: vozac?.sifra ?? '');
    final tel1Ctrl = TextEditingController(text: vozac?.telefon1 ?? '');
    final tel2Ctrl = TextEditingController(text: vozac?.telefon2 ?? '');
    Color selectedColor = _hexToColor(vozac?.boja);
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              gradient: Theme.of(context).backgroundGradient,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isEdit ? '✏️ UREDI VOZAČA' : '➕ DODAJ VOZAČA',
                      style: const TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1.2),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isEdit ? (vozac.imePrezime) : 'Novi vozač',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                    ),
                    const SizedBox(height: 20),

                    // Ime
                    _inputField(
                      controller: imeCtrl,
                      label: 'Ime i prezime',
                      icon: Icons.person,
                      validator: (v) => (v?.isEmpty ?? true) ? 'Unesite ime' : null,
                    ),
                    const SizedBox(height: 12),

                    // Email
                    _inputField(
                      controller: emailCtrl,
                      label: 'Email',
                      icon: Icons.email,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v?.isEmpty ?? true) return 'Unesite email';
                        if (!v!.contains('@')) return 'Neispravan email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Šifra
                    _inputField(
                      controller: sifraCtrl,
                      label: 'Šifra',
                      icon: Icons.lock,
                      obscureText: true,
                    ),
                    const SizedBox(height: 12),

                    // Telefon 1
                    _inputField(
                      controller: tel1Ctrl,
                      label: 'Telefon 1',
                      icon: Icons.phone,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),

                    // Telefon 2
                    _inputField(
                      controller: tel2Ctrl,
                      label: 'Telefon 2 (opciono)',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 20),

                    // Boja picker
                    Text(
                      'BOJA VOZAČA',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11, letterSpacing: 1),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _paletaBoja.map((c) {
                        final isSel = selectedColor.value == c.value;
                        return GestureDetector(
                          onTap: () => setS(() => selectedColor = c),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSel ? Colors.white : Colors.transparent,
                                width: 3,
                              ),
                              boxShadow: isSel ? [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 10)] : null,
                            ),
                            child: isSel ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),

                    // Sačuvaj
                    SizedBox(
                      width: double.infinity,
                      child: V3ButtonUtils.elevatedButton(
                        onPressed: () async {
                          if (!formKey.currentState!.validate()) return;
                          final novi = V3Vozac(
                            id: vozac?.id ?? '',
                            imePrezime: imeCtrl.text.trim(),
                            email: emailCtrl.text.trim().toLowerCase(),
                            sifra: sifraCtrl.text.isEmpty ? vozac?.sifra : sifraCtrl.text,
                            telefon1: tel1Ctrl.text.trim().isEmpty ? null : tel1Ctrl.text.trim(),
                            telefon2: tel2Ctrl.text.trim().isEmpty ? null : tel2Ctrl.text.trim(),
                            boja: _colorToHex(selectedColor),
                            aktivno: true,
                          );
                          try {
                            await V3VozacService.addUpdateVozac(novi);
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            if (mounted) {
                              V3AppSnackBar.success(
                                context,
                                isEdit ? '✅ ${novi.imePrezime} ažuriran' : '✅ ${novi.imePrezime} dodat',
                              );
                            }
                          } catch (e) {
                            V3ErrorUtils.asyncError(this, context, e);
                          }
                        },
                        text: isEdit ? 'Sačuvaj izmjene' : 'Dodaj vozača',
                        backgroundColor: selectedColor.withValues(alpha: 0.3),
                        foregroundColor: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Dispose nakon što animacija zatvaranja završi — sprječava "used after dispose" crash
    WidgetsBinding.instance.addPostFrameCallback((_) {
      imeCtrl.dispose();
      emailCtrl.dispose();
      sifraCtrl.dispose();
      tel1Ctrl.dispose();
      tel2Ctrl.dispose();
    });
  }

  Future<void> _confirmDeactivate(V3Vozac vozac) async {
    final potvrda = await V3NavigationUtils.showConfirmDialog(
      context,
      title: 'Deaktiviraj vozača',
      message: 'Vozač ${vozac.imePrezime} neće moći da se prijavi.\nMoguće reaktivirati kasnije.',
      confirmText: 'Deaktiviraj',
      cancelText: 'Otkaži',
      isDangerous: true,
    );
    if (potvrda != true) return;
    try {
      await V3VozacService.deactivateVozac(vozac.id);
      if (mounted) V3AppSnackBar.success(context, '🗑️ ${vozac.imePrezime} deaktiviran');
    } catch (e) {
      V3ErrorUtils.asyncError(this, context, e);
    }
  }

  Future<void> _reaktivirajVozaca(V3Vozac vozac) async {
    try {
      await supabase.from('v3_vozaci').update({'aktivno': true}).eq('id', vozac.id);
      if (mounted) V3AppSnackBar.success(context, '✅ ${vozac.imePrezime} reaktiviran');
    } catch (e) {
      V3ErrorUtils.asyncError(this, context, e);
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: V3MasterRealtimeManager.instance.onChange,
      builder: (context, _) {
        final svi = V3VozacService.getAllVozaci();
        final aktivni = svi.where((v) => v.aktivno).toList();
        final neaktivni = svi.where((v) => !v.aktivno).toList();
        final prikazani = _showNeaktivni ? svi : aktivni;

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '🚗 Vozači Admin',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    '${aktivni.length}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Dodaj vozača',
                icon: const Icon(Icons.add_circle, color: Colors.greenAccent, size: 28),
                onPressed: _showDodajDialog,
              ),
            ],
          ),
          body: V3ContainerUtils.backgroundContainer(
            gradient: Theme.of(context).backgroundGradient,
            child: SafeArea(
              child: Column(
                children: [
                  // Neaktivni toggle
                  if (neaktivni.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                      child: InkWell(
                        onTap: () => V3StateUtils.safeSetState(this, () => _showNeaktivni = !_showNeaktivni),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _showNeaktivni ? Icons.visibility_off : Icons.visibility,
                                color: Colors.redAccent,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _showNeaktivni
                                    ? 'Sakrij neaktivne (${neaktivni.length})'
                                    : 'Prikaži neaktivne (${neaktivni.length})',
                                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Lista vozača
                  Expanded(
                    child: prikazani.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.directions_car_outlined,
                                    size: 56, color: Colors.white.withValues(alpha: 0.25)),
                                const SizedBox(height: 16),
                                Text(
                                  'Nema vozača.\nKlikni + da dodaš.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 17),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 80),
                            physics: const BouncingScrollPhysics(),
                            itemCount: prikazani.length,
                            itemBuilder: (_, i) {
                              final v = prikazani[i];
                              final boja = _hexToColor(v.boja);
                              final jeNeaktivan = !v.aktivno;
                              return _VozacKartica(
                                vozac: v,
                                boja: boja,
                                jeNeaktivan: jeNeaktivan,
                                onEdit: () => _showUrediDialog(v),
                                onDeactivate: jeNeaktivan ? null : () => _confirmDeactivate(v),
                                onReactivate: jeNeaktivan ? () => _reaktivirajVozaca(v) : null,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Input field helper ────────────────────────────────────────────────────
  Widget _inputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        prefixIcon: Icon(icon, color: Colors.blueAccent),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blueAccent),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
      ),
    );
  }
}

// ─── Vozac kartica ────────────────────────────────────────────────────────────
class _VozacKartica extends StatelessWidget {
  const _VozacKartica({
    required this.vozac,
    required this.boja,
    required this.jeNeaktivan,
    required this.onEdit,
    this.onDeactivate,
    this.onReactivate,
  });

  final V3Vozac vozac;
  final Color boja;
  final bool jeNeaktivan;
  final VoidCallback onEdit;
  final VoidCallback? onDeactivate;
  final VoidCallback? onReactivate;

  @override
  Widget build(BuildContext context) {
    final cardColor = jeNeaktivan ? Colors.white24 : boja;

    return Opacity(
      opacity: jeNeaktivan ? 0.55 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: cardColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cardColor.withValues(alpha: 0.5), width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                backgroundColor: cardColor.withValues(alpha: 0.3),
                radius: 24,
                child: Text(
                  vozac.imePrezime.isNotEmpty ? vozac.imePrezime[0].toUpperCase() : '?',
                  style: TextStyle(color: cardColor, fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
              const SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            vozac.imePrezime,
                            style: TextStyle(
                              color: cardColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (jeNeaktivan)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                            ),
                            child: const Text('neaktivan', style: TextStyle(color: Colors.redAccent, fontSize: 10)),
                          ),
                      ],
                    ),
                    if (vozac.email?.isNotEmpty == true)
                      Row(
                        children: [
                          const Icon(Icons.email, size: 12, color: Colors.white38),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              vozac.email!,
                              style: const TextStyle(color: Colors.white60, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    if (vozac.telefon1?.isNotEmpty == true)
                      Row(
                        children: [
                          const Icon(Icons.phone, size: 12, color: Colors.white38),
                          const SizedBox(width: 4),
                          Text(vozac.telefon1!, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                          if (vozac.telefon2?.isNotEmpty == true) ...[
                            const SizedBox(width: 8),
                            const Text('/', style: TextStyle(color: Colors.white38, fontSize: 13)),
                            const SizedBox(width: 8),
                            Text(vozac.telefon2!, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                          ],
                        ],
                      ),
                  ],
                ),
              ),

              // Akcije
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.edit, color: cardColor, size: 20),
                    onPressed: onEdit,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Uredi',
                  ),
                  if (onReactivate != null)
                    IconButton(
                      icon: const Icon(Icons.restore, color: Colors.greenAccent, size: 20),
                      onPressed: onReactivate,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Reaktiviraj',
                    )
                  else if (onDeactivate != null)
                    IconButton(
                      icon: const Icon(Icons.person_off, color: Colors.redAccent, size: 20),
                      onPressed: onDeactivate,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Deaktiviraj',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
