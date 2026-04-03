import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../globals.dart';
import '../models/v3_adresa.dart';
import '../models/v3_putnik.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_adresa_service.dart';
import '../services/v3/v3_putnik_service.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_audit_actor.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dialog_helper.dart';
import '../utils/v3_dialog_utils.dart';
import '../utils/v3_error_utils.dart';
import '../utils/v3_input_utils.dart';
import '../utils/v3_navigation_utils.dart';
import '../utils/v3_phone_utils.dart';
import '../utils/v3_safe_text.dart';
import '../utils/v3_state_utils.dart';
import '../utils/v3_string_utils.dart';
import '../utils/v3_text_utils.dart';
import 'v3_putnik_statistika_screen.dart';

class V3PutniciScreen extends StatefulWidget {
  const V3PutniciScreen({super.key});

  @override
  State<V3PutniciScreen> createState() => _V3PutniciScreenState();
}

class _V3PutniciScreenState extends State<V3PutniciScreen> {
  String _selectedFilter = 'svi';

  @override
  void initState() {
    super.initState();
  }

  String _normalizeTip(dynamic tip) => (tip?.toString() ?? '').trim().toLowerCase();

  bool _isAktivan(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' ||
          normalized == '1' ||
          normalized == 't' ||
          normalized == 'yes' ||
          normalized == 'da';
    }
    return false;
  }

  bool _matchesFilterTip(dynamic tipValue, String selectedTip) {
    if (selectedTip == 'svi') return true;
    return _normalizeTip(tipValue) == _normalizeTip(selectedTip);
  }

  @override
  void dispose() {
    V3TextUtils.disposeController('putnici_search');
    super.dispose();
  }

  // ─── Badge counts ─────────────────────────────────────────────────────────
  int _count(String tip) {
    return V3MasterRealtimeManager.instance.putniciCache.values
        .where((r) => _isAktivan(r['aktivno']) && _matchesFilterTip(r['tip_putnika'], tip))
        .length;
  }

  // ─── Filtered list ────────────────────────────────────────────────────────
  List<V3Putnik> _filtriraj() {
    var lista = V3MasterRealtimeManager.instance.putniciCache.values
        .where((r) => _isAktivan(r['aktivno']))
        .map((r) => V3Putnik.fromJson(r))
        .toList();

    if (_selectedFilter != 'svi') {
      lista = lista.where((p) => _matchesFilterTip(p.tipPutnika, _selectedFilter)).toList();
    }

    final search = V3TextUtils.getControllerText('putnici_search').trim();
    if (search.isNotEmpty) {
      lista = lista.where((p) => V3StringUtils.containsSearch(p.imePrezime, search)).toList();
    }

    lista.sort((a, b) => V3StringUtils.compareForSort(a.imePrezime, b.imePrezime));
    return lista;
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final textScaleFactor = MediaQuery.textScalerOf(context).scale(1.0);
    final headerScaleExtra = (textScaleFactor - 1.0).clamp(0.0, 0.6).toDouble();
    final appBarHeight = 72 + (headerScaleExtra * 16);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(appBarHeight),
        child: StreamBuilder<void>(
          stream: V3MasterRealtimeManager.instance.v3StreamFromCache<void>(
            tables: const ['v3_putnici'],
            build: () {},
          ),
          builder: (context, _) {
            return V3ContainerUtils.iconContainer(
              backgroundColor: Theme.of(context).glassContainer,
              border: Border(
                bottom: BorderSide(color: Theme.of(context).glassBorder, width: 1.5),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // ── Filter icons with badges ──────────────────────
                              _filterBtn('radnik', Icons.engineering, const Color(0xFF5C9CE6), const Color(0xFF3B7DD8)),
                              _filterBtn('ucenik', Icons.school, const Color(0xFF4ECDC4), const Color(0xFF44A08D)),
                              _filterBtn('dnevni', Icons.today, const Color(0xFFFF6B6B), const Color(0xFFFF8E53)),
                              _filterBtn(
                                  'posiljka', Icons.local_shipping, const Color(0xFFFF8C00), const Color(0xFFE65C00)),
                              IconButton(
                                icon: const Icon(Icons.person_add,
                                    color: Colors.white,
                                    shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)]),
                                tooltip: 'Dodaj putnika',
                                onPressed: _showAddDialog,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      body: V3ContainerUtils.backgroundContainer(
        gradient: Theme.of(context).backgroundGradient,
        child: SafeArea(
          child: Column(
            children: [
              // ── Search bar ──────────────────────────────────────────────
              V3ContainerUtils.styledContainer(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                backgroundColor: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 3))
                ],
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: V3TextUtils.putniciSearchController,
                  builder: (context, val, _) => TextField(
                    controller: V3TextUtils.putniciSearchController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      hintText: 'Pretraži putnike...',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      suffixIcon: val.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.grey),
                              onPressed: () => V3TextUtils.clearController('putnici_search'),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              // ── List ────────────────────────────────────────────────────
              Expanded(
                child: StreamBuilder<void>(
                  stream: V3MasterRealtimeManager.instance.v3StreamFromCache<void>(
                    tables: const ['v3_putnici'],
                    build: () {},
                  ),
                  builder: (context, _) {
                    return ValueListenableBuilder<TextEditingValue>(
                      valueListenable: V3TextUtils.putniciSearchController,
                      builder: (context, _, __) {
                        final lista = _filtriraj();

                        if (lista.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  V3TextUtils.getControllerText('putnici_search').isNotEmpty
                                      ? Icons.search_off
                                      : Icons.group_off,
                                  size: 64,
                                  color: Colors.white38,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  V3TextUtils.getControllerText('putnici_search').isNotEmpty
                                      ? 'Nema rezultata pretrage'
                                      : 'Nema putnika',
                                  style: const TextStyle(fontSize: 18, color: Colors.white60),
                                ),
                              ],
                            ),
                          );
                        }

                        return Column(
                          children: [
                            Expanded(
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                physics: const BouncingScrollPhysics(),
                                itemCount: lista.length,
                                itemBuilder: (context, i) {
                                  return TweenAnimationBuilder<double>(
                                    key: ValueKey(lista[i].id),
                                    duration: const Duration(milliseconds: 280),
                                    tween: Tween(begin: 0.0, end: 1.0),
                                    curve: Curves.easeOutCubic,
                                    builder: (context, v, child) => Transform.translate(
                                      offset: Offset(0, 20 * (1 - v)),
                                      child: Opacity(opacity: v, child: child),
                                    ),
                                    child: _PutnikCard(
                                      putnik: lista[i],
                                      redniBroj: i + 1,
                                      onEdit: () => _showEditDialog(lista[i]),
                                      onDelete: () => _obrisi(lista[i]),
                                      onToggle: () => _toggleAktivno(lista[i]),
                                      onDetaljneStatistike: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) => V3PutnikStatistikaScreen(
                                              putnikId: lista[i].id,
                                              imePrezime: lista[i].imePrezime,
                                              tipPutnika: lista[i].tipPutnika,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Filter button with badge ─────────────────────────────────────────────
  Widget _filterBtn(String tip, IconData icon, Color c1, Color c2) {
    final isSelected = _selectedFilter == tip;
    final count = _count(tip);
    return Stack(
      children: [
        IconButton(
          icon: Icon(icon,
              color: isSelected ? Colors.white : Colors.white60,
              shadows: const [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)]),
          tooltip: tip == 'svi' ? 'Svi' : tip[0].toUpperCase() + tip.substring(1),
          onPressed: () => V3StateUtils.safeSetState(this, () => _selectedFilter = isSelected ? 'svi' : tip),
        ),
        if (count > 0)
          Positioned(
            right: 2,
            top: 2,
            child: V3ContainerUtils.gradientContainer(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              gradient: LinearGradient(colors: [c1, c2]),
              borderRadius: BorderRadius.circular(9), // Circle effect
              boxShadow: [BoxShadow(color: c2.withValues(alpha: 0.5), blurRadius: 4, offset: const Offset(0, 2))],
              width: count >= 1000
                  ? 34
                  : count >= 100
                      ? 30
                      : count >= 10
                          ? 24
                          : 18,
              height: V3ContainerUtils.responsiveHeight(context, 18),
              child: Text(
                '$count',
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  // ─── Toggle aktivno ───────────────────────────────────────────────────────
  Future<void> _toggleAktivno(V3Putnik p) async {
    try {
      await V3PutnikService.setAktivno(id: p.id, aktivno: !p.aktivno);
      if (mounted) {
        V3AppSnackBar.success(context, p.aktivno ? '${p.imePrezime} deaktiviran' : '${p.imePrezime} aktiviran');
      }
    } catch (e) {
      V3ErrorUtils.asyncError(this, context, e);
    }
  }

  // ─── Delete ───────────────────────────────────────────────────────────────
  Future<void> _obrisi(V3Putnik p) async {
    final potvrda = await V3DialogHelper.showConfirmDialog(
      context,
      title: 'Potvrdi brisanje',
      message:
          'Da li ste sigurni da želite da obrišete "${p.imePrezime}"?\n\n⚠️ VAŽNO:\n• Putnik će biti TRAJNO obrisan\n• Sve vožnje i statistike se brišu\n• Ova akcija je NEPOVRATNA!',
      confirmText: 'Obriši',
      cancelText: 'Otkaži',
      isDangerous: true,
    );
    if (potvrda != true || !mounted) return;
    try {
      await V3PutnikService.deactivatePutnik(p.id);
      if (mounted) V3AppSnackBar.success(context, '${p.imePrezime} obrisan');
    } catch (e) {
      V3ErrorUtils.asyncError(this, context, e);
    }
  }

  // ─── Add / Edit dialog ────────────────────────────────────────────────────
  void _showAddDialog() => _showPutnikDialog(null);
  void _showEditDialog(V3Putnik p) => _showPutnikDialog(p);

  void _showPutnikDialog(V3Putnik? existing) {
    showDialog(
      context: context,
      builder: (_) => _PutnikDialog(existing: existing),
    );
  }
}

// ─── Putnik Card ──────────────────────────────────────────────────────────────

class _PutnikCard extends StatelessWidget {
  const _PutnikCard({
    required this.putnik,
    required this.redniBroj,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
    required this.onDetaljneStatistike,
  });

  final V3Putnik putnik;
  final int redniBroj;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;
  final VoidCallback onDetaljneStatistike;

  Color get _tipColor => switch (putnik.tipPutnika) {
        'radnik' => const Color(0xFF3B7DD8),
        'ucenik' => const Color(0xFF44A08D),
        'dnevni' => const Color(0xFFFF6B6B),
        'posiljka' => const Color(0xFFE65C00),
        _ => Colors.grey,
      };

  IconData get _tipIcon => switch (putnik.tipPutnika) {
        'radnik' => Icons.engineering,
        'ucenik' => Icons.school,
        'dnevni' => Icons.today,
        'posiljka' => Icons.local_shipping,
        _ => Icons.person,
      };

  String get _tipLabel => switch (putnik.tipPutnika) {
        'radnik' => 'RADNIK',
        'ucenik' => 'UCENIK',
        'dnevni' => 'DNEVNI',
        'posiljka' => 'POSILJKA',
        _ => putnik.tipPutnika.toUpperCase(),
      };

  @override
  Widget build(BuildContext context) {
    final String? adresa;
    final bcNaziv = V3AdresaService.getAdresaById(putnik.adresaBcId)?.naziv ??
        V3AdresaService.getAdresaById(putnik.adresaBcId2)?.naziv;
    final vsNaziv = V3AdresaService.getAdresaById(putnik.adresaVsId)?.naziv ??
        V3AdresaService.getAdresaById(putnik.adresaVsId2)?.naziv;
    adresa = (bcNaziv != null || vsNaziv != null) ? '${bcNaziv ?? "/"} → ${vsNaziv ?? "/"}' : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 4,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: V3ContainerUtils.gradientContainer(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [const Color(0xFF1E2235), const Color(0xFF252840)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _tipColor.withValues(alpha: 0.35), width: 1.5),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────
              Row(
                children: [
                  Text('$redniBroj.',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white38)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(putnik.imePrezime,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_tipIcon, size: 13, color: _tipColor),
                      const SizedBox(width: 4),
                      Text(_tipLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _tipColor)),
                    ],
                  ),
                ],
              ),
              // ── Adresa ──────────────────────────────────────────────
              if (adresa != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 14, color: Colors.white38),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(adresa,
                          style: const TextStyle(fontSize: 12, color: Colors.white54), overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ],
              // ── Skola / opis ─────────────────────────────────────────
              if (putnik.skola != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.school_outlined, size: 14, color: Colors.white38),
                    const SizedBox(width: 4),
                    Flexible(
                        child: Text(putnik.skola!,
                            style: const TextStyle(fontSize: 12, color: Colors.white54),
                            overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              // ── Action buttons row 1 ─────────────────────────────────
              Row(
                children: [
                  Expanded(
                      child: _actionBtn(
                    context: context,
                    icon: putnik.aktivno ? Icons.toggle_on_outlined : Icons.toggle_off_outlined,
                    label: putnik.aktivno ? 'Aktivan' : 'Neaktivan',
                    color: putnik.aktivno ? Colors.green : Colors.grey,
                    onPressed: onToggle,
                  )),
                  const SizedBox(width: 6),
                  Expanded(
                      child: _actionBtn(
                    context: context,
                    icon: Icons.analytics_outlined,
                    label: 'Detaljne statistike',
                    color: Colors.purpleAccent,
                    onPressed: onDetaljneStatistike,
                  )),
                  const SizedBox(width: 6),
                  Expanded(
                      child: _actionBtn(
                    context: context,
                    icon: Icons.lock_outline,
                    label: 'PIN',
                    color: Colors.amber,
                    onPressed: () => _showPinDialog(context),
                  )),
                ],
              ),
              const SizedBox(height: 6),
              // ── Action buttons row 2 ─────────────────────────────────
              Row(
                children: [
                  if (putnik.telefon1 != null || putnik.telefon2 != null) ...[
                    Expanded(
                        child: _actionBtn(
                      context: context,
                      icon: Icons.phone,
                      label: 'Pozovi',
                      color: Colors.green,
                      onPressed: () => _pokaziKontakt(context),
                    )),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                      child: _actionBtn(
                    context: context,
                    icon: Icons.edit_outlined,
                    label: 'Uredi',
                    color: Colors.blue,
                    onPressed: onEdit,
                  )),
                  const SizedBox(width: 6),
                  Expanded(
                      child: _actionBtn(
                    context: context,
                    icon: Icons.delete_outline,
                    label: 'Obriši',
                    color: Colors.red,
                    onPressed: onDelete,
                  )),
                ],
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionBtn({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: V3ContainerUtils.responsiveHeight(context, 32),
      child: V3ContainerUtils.gradientContainer(
        padding: EdgeInsets.zero,
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.08)],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        child: V3ButtonUtils.elevatedButton(
          onPressed: onPressed,
          text: label,
          icon: icon,
          backgroundColor: Colors.transparent,
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          borderRadius: BorderRadius.circular(8),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _pokaziKontakt(BuildContext context) {
    V3NavigationUtils.showBottomSheet<void>(
      context,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Kontaktiraj ${putnik.imePrezime}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              if (putnik.telefon1?.isNotEmpty == true)
                ListTile(
                  leading: const Icon(Icons.person, color: Colors.green),
                  title: const Text('Pozovi (telefon 1)'),
                  subtitle: Text(putnik.telefon1!),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () async {
                    Navigator.pop(context);
                    final uri = Uri(scheme: 'tel', path: putnik.telefon1!);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                ),
              if (putnik.telefon2?.isNotEmpty == true)
                ListTile(
                  leading: const Icon(Icons.phone_android, color: Colors.blue),
                  title: const Text('Pozovi (telefon 2)'),
                  subtitle: Text(putnik.telefon2!),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () async {
                    Navigator.pop(context);
                    final uri = Uri(scheme: 'tel', path: putnik.telefon2!);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                ),
              const SizedBox(height: 8),
              V3ButtonUtils.textButton(onPressed: () => Navigator.pop(context), text: 'Otkaži'),
            ],
          ),
        ),
      ),
    );
  }

  void _showPinDialog(BuildContext context) {
    final ctrl = TextEditingController(text: putnik.pin ?? '');
    V3DialogUtils.showCustomDialog<void>(
      context: context,
      title: '🔐 PIN — ${putnik.imePrezime}',
      content: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        maxLength: 6,
        decoration: const InputDecoration(
          labelText: 'PIN kod',
          hintText: 'Unesi 4–6 cifara',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        V3ButtonUtils.textButton(onPressed: () => Navigator.pop(context), text: 'Otkaži'),
        V3ButtonUtils.primaryButton(
          onPressed: () async {
            Navigator.pop(context);
            try {
              await V3PutnikService.updatePinById(
                putnikId: putnik.id,
                pin: ctrl.text,
                updatedBy: V3AuditActor.cron('admin_pin_edit'),
              );
              if (context.mounted) V3AppSnackBar.success(context, '✅ PIN sačuvan');
            } catch (e) {
              if (context.mounted) V3AppSnackBar.error(context, '❌ Greška: $e');
            }
          },
          text: 'Sačuvaj',
        ),
      ],
    );
  }
}

// ─── Add / Edit Dialog ────────────────────────────────────────────────────────

class _PutnikDialog extends StatefulWidget {
  const _PutnikDialog({this.existing});
  final V3Putnik? existing;

  @override
  State<_PutnikDialog> createState() => _PutnikDialogState();
}

class _PutnikDialogState extends State<_PutnikDialog> {
  late final TextEditingController _ime = TextEditingController(text: widget.existing?.imePrezime ?? '');
  late final TextEditingController _tel1 = TextEditingController(text: widget.existing?.telefon1 ?? '');
  late final TextEditingController _tel2 = TextEditingController(text: widget.existing?.telefon2 ?? '');
  late final TextEditingController _email = TextEditingController(text: widget.existing?.email ?? '');
  late final TextEditingController _skola = TextEditingController(text: widget.existing?.skola ?? '');
  late final TextEditingController _opis = TextEditingController(text: widget.existing?.opisPosiljke ?? '');
  late final TextEditingController _cenaDan = TextEditingController(text: () {
    final tip = widget.existing?.tipPutnika ?? 'radnik';
    final cena =
        (tip == 'dnevni' || tip == 'posiljka') ? widget.existing?.cenaPoPokupljenju : widget.existing?.cenaPoDanu;
    return (cena != null && cena > 0) ? cena.toStringAsFixed(0) : '';
  }());
  late String _tip = widget.existing?.tipPutnika ?? 'radnik';

  // Adrese
  V3Adresa? _adresaBc1;
  V3Adresa? _adresaBc2;
  V3Adresa? _adresaVs1;
  V3Adresa? _adresaVs2;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _adresaBc1 = V3AdresaService.getAdresaById(widget.existing!.adresaBcId);
      _adresaBc2 = V3AdresaService.getAdresaById(widget.existing!.adresaBcId2);
      _adresaVs1 = V3AdresaService.getAdresaById(widget.existing!.adresaVsId);
      _adresaVs2 = V3AdresaService.getAdresaById(widget.existing!.adresaVsId2);
    }
  }

  @override
  void dispose() {
    for (final c in [_ime, _tel1, _tel2, _email, _skola, _opis, _cenaDan]) c.dispose();
    super.dispose();
  }

  Future<void> _sacuvaj() async {
    if (_ime.text.trim().isEmpty) {
      V3AppSnackBar.error(context, '❌ Ime je obavezno');
      return;
    }
    V3StateUtils.safeSetState(this, () => _saving = true);
    try {
      final putnik = V3Putnik(
        id: widget.existing?.id ?? '',
        imePrezime: _ime.text.trim(),
        telefon1: V3PhoneUtils.normalizeOrNull(_tel1.text),
        telefon2: V3PhoneUtils.normalizeOrNull(_tel2.text),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        skola: _tip == 'ucenik' && _skola.text.trim().isNotEmpty ? _skola.text.trim() : null,
        opisPosiljke: _tip == 'posiljka' && _opis.text.trim().isNotEmpty ? _opis.text.trim() : null,
        tipPutnika: _tip,
        cenaPoDanu: (_tip == 'dnevni' || _tip == 'posiljka')
            ? 0.0 // dnevni/posiljka koriste cenaPoPokupljenju
            : double.tryParse(_cenaDan.text.replaceAll(',', '.')) ?? 0.0,
        aktivno: widget.existing?.aktivno ?? true,
        adresaBcId: _adresaBc1?.id,
        adresaBcId2: _adresaBc2?.id,
        adresaVsId: _adresaVs1?.id,
        adresaVsId2: _adresaVs2?.id,
        pin: widget.existing?.pin,
        cenaPoPokupljenju: (_tip == 'dnevni' || _tip == 'posiljka')
            ? double.tryParse(_cenaDan.text.replaceAll(',', '.')) ?? 0.0
            : 0.0, // radnici/ucenici koriste cenaPoDanu
        placeniMesec: widget.existing?.placeniMesec,
        placenaGodina: widget.existing?.placenaGodina,
      );
      await V3PutnikService.addUpdatePutnik(putnik, createdBy: V3AuditActor.cron('admin'));
      if (mounted) {
        V3AppSnackBar.success(context, widget.existing == null ? '✅ Putnik dodan' : '✅ Putnik sačuvan');
        Navigator.pop(context);
      }
    } catch (e) {
      V3AppSnackBar.error(context, 'Greška: $e');
    } finally {
      V3StateUtils.safeSetState(this, () => _saving = false);
    }
  }

  Widget _adresaDropdown({
    required String label,
    required String grad,
    required V3Adresa? value,
    required ValueChanged<V3Adresa?> onChanged,
  }) {
    final adrese = V3AdresaService.getAdreseZaGrad(grad);
    return DropdownButtonFormField<V3Adresa>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
        ),
        isDense: true,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        prefixIcon: Icon(
          grad == 'BC' ? Icons.location_city_outlined : Icons.location_on_outlined,
          size: 18,
          color: grad == 'BC' ? Colors.blueAccent : Colors.orangeAccent,
        ),
        suffixIcon: value != null
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () => onChanged(null),
              )
            : null,
      ),
      hint: const Text('— nije odabrano —', style: TextStyle(fontSize: 13)),
      items: [
        ...adrese.map((a) => DropdownMenuItem(
              value: a,
              child: V3SafeText.userAddress(a.naziv, style: const TextStyle(fontSize: 13)),
            )),
      ],
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final theme = Theme.of(context);
    final adreseBC = V3AdresaService.getAdreseZaGrad('BC');
    final adreseVS = V3AdresaService.getAdreseZaGrad('VS');

    // Uskladi value sa objektom iz liste (DropdownButtonFormField zahtijeva istu referencu)
    if (_adresaBc1 != null) _adresaBc1 = adreseBC.firstWhere((a) => a.id == _adresaBc1!.id, orElse: () => _adresaBc1!);
    if (_adresaBc2 != null) _adresaBc2 = adreseBC.firstWhere((a) => a.id == _adresaBc2!.id, orElse: () => _adresaBc2!);
    if (_adresaVs1 != null) _adresaVs1 = adreseVS.firstWhere((a) => a.id == _adresaVs1!.id, orElse: () => _adresaVs1!);
    if (_adresaVs2 != null) _adresaVs2 = adreseVS.firstWhere((a) => a.id == _adresaVs2!.id, orElse: () => _adresaVs2!);

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──
            V3ContainerUtils.gradientContainer(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              gradient: LinearGradient(
                colors: [theme.colorScheme.primary, theme.colorScheme.primary.withValues(alpha: 0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      isEdit ? Icons.edit_note_rounded : Icons.person_add_alt_1_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEdit ? 'Uredi putnika' : 'Novi putnik',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          isEdit ? 'Ažuriraj podatke i sačuvaj izmene' : 'Unesi podatke i dodaj putnika',
                          style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── Sadržaj ──
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.25)),
                      ),
                      child: Text(
                        'Osnovni podaci',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Tip
                    DropdownButtonFormField<String>(
                      value: _tip,
                      decoration: InputDecoration(
                        labelText: 'Tip putnika',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.4)),
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
                        prefixIcon: const Icon(Icons.category_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'radnik', child: Text('👷 Radnik')),
                        DropdownMenuItem(value: 'ucenik', child: Text('🎒 Učenik')),
                        DropdownMenuItem(value: 'dnevni', child: Text('🚶 Dnevni')),
                        DropdownMenuItem(value: 'posiljka', child: Text('📦 Pošiljka')),
                      ],
                      onChanged: isEdit ? null : (v) => V3StateUtils.safeSetState(this, () => _tip = v!),
                    ),
                    const SizedBox(height: 10),
                    // Ime
                    V3InputUtils.textField(
                      controller: _ime,
                      label: 'Ime i prezime *',
                      icon: Icons.person,
                    ),
                    const SizedBox(height: 10),
                    // Telefoni
                    Row(
                      children: [
                        Expanded(
                          child: V3InputUtils.phoneField(
                            controller: _tel1,
                            label: 'Telefon 1',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: V3InputUtils.phoneField(
                            controller: _tel2,
                            label: 'Telefon 2',
                            isRequired: false,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Email
                    V3InputUtils.emailField(
                      controller: _email,
                      label: 'Email (opciono)',
                      isRequired: false,
                    ),
                    const SizedBox(height: 10),
                    // Cena
                    V3InputUtils.numberField(
                      controller: _cenaDan,
                      label: (_tip == 'dnevni' || _tip == 'posiljka') ? 'Cena po pokupljanju' : 'Cena po danu',
                      suffixText: 'din',
                    ),
                    // Школa
                    if (_tip == 'ucenik') ...[
                      const SizedBox(height: 10),
                      V3InputUtils.textField(
                        controller: _skola,
                        label: 'Школa',
                        icon: Icons.school,
                      ),
                    ],
                    // Opis pošiljke
                    if (_tip == 'posiljka') ...[
                      const SizedBox(height: 10),
                      V3InputUtils.textField(
                        controller: _opis,
                        label: 'Opis pošiljke',
                        icon: Icons.description,
                      ),
                    ],
                    const SizedBox(height: 14),
                    // ── Adrese BC ──
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.location_on, size: 16, color: theme.colorScheme.primary),
                          const SizedBox(width: 4),
                          Text('Adrese — Bela Crkva',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _adresaDropdown(
                      label: 'BC — Adresa 1',
                      grad: 'BC',
                      value: _adresaBc1,
                      onChanged: (v) => V3StateUtils.safeSetState(this, () => _adresaBc1 = v),
                    ),
                    const SizedBox(height: 8),
                    _adresaDropdown(
                      label: 'BC — Adresa 2 (opciono)',
                      grad: 'BC',
                      value: _adresaBc2,
                      onChanged: (v) => V3StateUtils.safeSetState(this, () => _adresaBc2 = v),
                    ),
                    const SizedBox(height: 14),
                    // ── Adrese VS ──
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.28)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on, size: 16, color: Colors.orangeAccent),
                          const SizedBox(width: 4),
                          Text('Adrese — Vršac',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _adresaDropdown(
                      label: 'VS — Adresa 1',
                      grad: 'VS',
                      value: _adresaVs1,
                      onChanged: (v) => V3StateUtils.safeSetState(this, () => _adresaVs1 = v),
                    ),
                    const SizedBox(height: 8),
                    _adresaDropdown(
                      label: 'VS — Adresa 2 (opciono)',
                      grad: 'VS',
                      value: _adresaVs2,
                      onChanged: (v) => V3StateUtils.safeSetState(this, () => _adresaVs2 = v),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            // ── Actions ──
            V3ContainerUtils.styledContainer(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              border: Border(top: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.2))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  V3ButtonUtils.textButton(
                    onPressed: () => Navigator.pop(context),
                    text: 'Otkaži',
                  ),
                  const SizedBox(width: 8),
                  V3ButtonUtils.primaryButton(
                    onPressed: _saving ? null : _sacuvaj,
                    text: isEdit ? 'Sačuvaj' : 'Dodaj',
                    icon: isEdit ? Icons.save_as_rounded : Icons.person_add_alt_1_rounded,
                    isLoading: _saving,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
