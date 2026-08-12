import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_translations.dart';
import '../models/v3_adresa.dart';
import '../models/v3_putnik.dart';
import '../models/v3_vozac.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_admin_service.dart';
import '../services/v3/v3_adresa_service.dart';
import '../services/v3/v3_putnik_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../services/v3_locale_manager.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_belgrade_time.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dialog_helper.dart';
import '../utils/v3_error_utils.dart';
import '../utils/v3_input_utils.dart';
import '../utils/v3_phone_utils.dart';
import '../utils/v3_safe_text.dart';
import '../utils/v3_state_utils.dart';
import '../utils/v3_string_utils.dart';
import '../utils/v3_text_utils.dart';
import '../utils/v3_tip_putnika_utils.dart';
import '../utils/v3_uuid_utils.dart';
import 'v3_putnik_statistika_screen.dart';

class _PutTr {
  static final Map<String, Map<String, String>> _t = AppTranslations.ns('putniciScreen');

  static String tr(String key, [List<String>? args]) {
    final code = V3LocaleManager().currentLocale.languageCode;
    var text = _t[key]?[code] ?? _t[key]?['sr'] ?? key;
    if (args != null) {
      for (final a in args) {
        text = text.replaceFirst('%s', a);
      }
    }
    return text;
  }
}

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
        .where((r) => _matchesFilterTip(r['tip_putnika'], tip))
        .length;
  }

  int _countVozaci() => V3MasterRealtimeManager.instance.vozaciCache.length;

  // ─── Filtered list ────────────────────────────────────────────────────────
  List<V3Putnik> _filtriraj() {
    var lista = V3MasterRealtimeManager.instance.putniciCache.values.map((r) => V3Putnik.fromJson(r)).toList();

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
        child: StreamBuilder<int>(
          stream: V3MasterRealtimeManager.instance.tableRevisionStream('v3_auth'),
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
                              Stack(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.admin_panel_settings,
                                        color: Colors.white,
                                        shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)]),
                                    tooltip: _PutTr.tr('uloge'),
                                    onPressed: _showUlogeDialog,
                                  ),
                                  if (_countVozaci() > 0)
                                    Positioned(
                                      right: 2,
                                      top: 2,
                                      child: V3ContainerUtils.gradientContainer(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                                        gradient: const LinearGradient(colors: [Color(0xFF5A5DE8), Color(0xFF3B7DD8)]),
                                        borderRadius: BorderRadius.circular(9),
                                        boxShadow: const [
                                          BoxShadow(color: Color(0x803B7DD8), blurRadius: 4, offset: Offset(0, 2)),
                                        ],
                                        width: _countVozaci() >= 1000
                                            ? 34
                                            : _countVozaci() >= 100
                                                ? 30
                                                : _countVozaci() >= 10
                                                    ? 24
                                                    : 18,
                                        height: V3ContainerUtils.responsiveHeight(context, 18),
                                        child: Text(
                                          '${_countVozaci()}',
                                          style: const TextStyle(
                                              color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                ],
                              ),

                              IconButton(
                                icon: const Icon(Icons.person_add,
                                    color: Colors.white,
                                    shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)]),
                                tooltip: _PutTr.tr('dodajPutnika'),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                child: V3InputUtils.searchField(
                  controller: V3TextUtils.putniciSearchController,
                  hint: _PutTr.tr('pretraziPutnike'),
                  textCapitalization: TextCapitalization.words,
                  onClear: () => V3TextUtils.clearController('putnici_search'),
                ),
              ),
              // ── List ──────────────────────────────────────────────────
              Expanded(
                child: StreamBuilder<int>(
                  stream: V3MasterRealtimeManager.instance.tableRevisionStream('v3_auth'),
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
                                      ? _PutTr.tr('nemaRezultataPretrage')
                                      : _PutTr.tr('nemaPutnika'),
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
                                  return _PutnikCard(
                                    putnik: lista[i],
                                    redniBroj: i + 1,
                                    onEdit: () => _showEditDialog(lista[i]),
                                    onDelete: () => _obrisi(lista[i]),
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
          tooltip: tip == 'svi' ? _PutTr.tr('svi') : tip[0].toUpperCase() + tip.substring(1),
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

  // ─── Delete ───────────────────────────────────────────────────────────────
  Future<void> _obrisi(V3Putnik p) async {
    final potvrda = await V3DialogHelper.showConfirmDialog(
      context,
      title: _PutTr.tr('potvrdiBrisanje'),
      message: _PutTr.tr('daLiSteSigurniObrisatiPutnika', [p.imePrezime]),
      confirmText: _PutTr.tr('obrisi'),
      cancelText: _PutTr.tr('otkazi'),
      isDangerous: true,
    );
    if (potvrda != true || !mounted) return;
    try {
      await V3PutnikService.deactivatePutnik(p.id);
      if (mounted) V3AppSnackBar.success(context, '${p.imePrezime} ${_PutTr.tr('obrisan')}');
    } catch (e) {
      V3ErrorUtils.asyncError(this, context, e);
    }
  }

  // ─── Add / Edit dialog ────────────────────────────────────────────────────
  void _showAddDialog() => _showPutnikDialog(null);
  void _showEditDialog(V3Putnik p) => _showPutnikDialog(p);

  void _showUlogeDialog() {
    V3DialogHelper.showDialogBuilder<void>(
      context: context,
      builder: (_) => const _UlogeDialog(),
    );
  }

  void _showPutnikDialog(V3Putnik? existing) {
    V3DialogHelper.showDialogBuilder<void>(
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
    required this.onDetaljneStatistike,
  });

  final V3Putnik putnik;
  final int redniBroj;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDetaljneStatistike;

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
        border: Border.all(color: V3TipPutnikaUtils.color(putnik.tipPutnika).withValues(alpha: 0.35), width: 1.5),
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
                      Icon(V3TipPutnikaUtils.icon(putnik.tipPutnika),
                          size: 13, color: V3TipPutnikaUtils.color(putnik.tipPutnika)),
                      const SizedBox(width: 4),
                      Text(V3TipPutnikaUtils.badgeLabel(putnik.tipPutnika),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: V3TipPutnikaUtils.color(putnik.tipPutnika))),
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
              const SizedBox(height: 10),
              // ── Action buttons row 1 ─────────────────────────────────
              Row(
                children: [
                  if (putnik.telefon1 != null || putnik.telefon2 != null) ...[
                    Expanded(
                        child: _actionBtn(
                      context: context,
                      icon: Icons.phone,
                      label: _PutTr.tr('pozovi'),
                      color: Colors.green,
                      onPressed: () => _pokaziKontakt(context),
                    )),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                      child: _actionBtn(
                    context: context,
                    icon: Icons.analytics_outlined,
                    label: _PutTr.tr('detaljneStatistike'),
                    color: Colors.purpleAccent,
                    onPressed: onDetaljneStatistike,
                  )),
                ],
              ),
              const SizedBox(height: 6),
              // ── Action buttons row 2 ─────────────────────────────────
              Row(
                children: [
                  Expanded(
                      child: _actionBtn(
                    context: context,
                    icon: Icons.edit_outlined,
                    label: _PutTr.tr('uredi'),
                    color: Colors.blue,
                    onPressed: onEdit,
                  )),
                  const SizedBox(width: 6),
                  Expanded(
                      child: _actionBtn(
                    context: context,
                    icon: Icons.delete_outline,
                    label: _PutTr.tr('obrisi'),
                    color: Colors.red,
                    onPressed: onDelete,
                  )),
                ],
              ),
              _buildLastSeenBtn(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLastSeenBtn(BuildContext context) {
    final s1 = putnik.lastSeenAt;
    final s2 = putnik.lastSeenAt2;
    if (s1 == null && s2 == null) return const SizedBox.shrink();

    String pad(int n) => n.toString().padLeft(2, '0');
    String fmt(DateTime dt) {
      final d = V3BelgradeTime.fromUtc(dt);
      return '${pad(d.day)}.${pad(d.month)}.${d.year}  ${pad(d.hour)}:${pad(d.minute)}';
    }

    final label = [
      if (s1 != null) fmt(s1),
      if (s2 != null) fmt(s2),
    ].join('   ');

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: _actionBtn(
              context: context,
              label: label,
              color: Colors.amber,
              onPressed: () {},
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required BuildContext context,
    IconData? icon,
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
              Text('${_PutTr.tr('kontaktiraj')} ${putnik.imePrezime}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (putnik.telefon1?.isNotEmpty == true) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(putnik.telefon1!, style: const TextStyle(fontSize: 13, color: Colors.black54)),
                ),
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        leading: const Icon(Icons.phone, color: Colors.green),
                        title: Text(_PutTr.tr('pozovi')),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        onTap: () async {
                          Navigator.pop(context);
                          final uri = Uri(scheme: 'tel', path: putnik.telefon1!);
                          if (await canLaunchUrl(uri)) await launchUrl(uri);
                        },
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        leading: const Icon(Icons.sms, color: Colors.blueAccent),
                        title: Text(_PutTr.tr('sms')),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        onTap: () async {
                          Navigator.pop(context);
                          final uri = Uri(scheme: 'sms', path: putnik.telefon1!);
                          if (await canLaunchUrl(uri)) await launchUrl(uri);
                        },
                      ),
                    ),
                  ],
                ),
              ],
              if (putnik.telefon2?.isNotEmpty == true) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(putnik.telefon2!, style: const TextStyle(fontSize: 13, color: Colors.black54)),
                ),
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        leading: const Icon(Icons.phone, color: Colors.green),
                        title: Text(_PutTr.tr('pozovi')),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        onTap: () async {
                          Navigator.pop(context);
                          final uri = Uri(scheme: 'tel', path: putnik.telefon2!);
                          if (await canLaunchUrl(uri)) await launchUrl(uri);
                        },
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        leading: const Icon(Icons.sms, color: Colors.blueAccent),
                        title: Text(_PutTr.tr('sms')),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        onTap: () async {
                          Navigator.pop(context);
                          final uri = Uri(scheme: 'sms', path: putnik.telefon2!);
                          if (await canLaunchUrl(uri)) await launchUrl(uri);
                        },
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              V3ButtonUtils.textButton(onPressed: () => Navigator.pop(context), text: _PutTr.tr('otkazi')),
            ],
          ),
        ),
      ),
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
  late final TextEditingController _cenaDan = TextEditingController(text: () {
    final tip = widget.existing?.tipPutnika ?? 'radnik';
    final cena =
        (tip == 'dnevni' || tip == 'posiljka') ? widget.existing?.cenaPoPokupljenju : widget.existing?.cenaPoDanu;
    return (cena != null && cena > 0) ? cena.toStringAsFixed(0) : '';
  }());
  late String _tip = widget.existing?.tipPutnika ?? 'radnik';
  String _ulogaVozaca = V3AdminService.roleVozac;

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
    for (final c in [_ime, _tel1, _tel2, _cenaDan]) c.dispose();
    super.dispose();
  }

  Future<void> _sacuvaj() async {
    final telText = _tel1.text.trim().isNotEmpty ? _tel1.text.trim() : _tel2.text.trim();
    final imeVal = _ime.text.trim();

    // Ako ne unese ni ime ni telefon, prekinemo
    if (imeVal.isEmpty && telText.isEmpty) {
      V3AppSnackBar.error(context, _PutTr.tr('unesiteImeIliTelefon'));
      return;
    }

    // Konverzija postojećeg putnika u vozača briše putnik-specifične podatke
    // (tip_putnika, adrese, cene) — traži eksplicitnu potvrdu da se izbegne
    // slučajan gubitak podataka pri promeni dropdown-a.
    final isConvertingPutnikToVozac =
        widget.existing != null && widget.existing!.tipPutnika != 'vozac' && _tip == 'vozac';
    if (isConvertingPutnikToVozac) {
      final potvrda = await V3DialogHelper.showConfirmDialog(
        context,
        title: _PutTr.tr('potvrda'),
        message: _PutTr.tr('konverzijaPutnikaUVozacaUpozorenje'),
        confirmText: _PutTr.tr('nastavi'),
        cancelText: _PutTr.tr('otkazi'),
        isDangerous: true,
      );
      if (potvrda != true || !mounted) return;
    }

    V3StateUtils.safeSetState(this, () => _saving = true);
    try {
      if (_tip == 'vozac') {
        final vozac = V3Vozac(
          id: widget.existing?.id ?? '',
          imePrezime: imeVal,
          telefon1: V3PhoneUtils.normalizeOrNull(_tel1.text),
          telefon2: V3PhoneUtils.normalizeOrNull(_tel2.text),
          uloga: _ulogaVozaca,
        );
        await V3VozacService.addUpdateVozac(vozac);
        if (mounted) {
          V3AppSnackBar.success(
              context, widget.existing == null ? _PutTr.tr('putnikDodan') : _PutTr.tr('putnikSacuvan'));
          Navigator.pop(context);
        }
        return;
      }

      final putnik = V3Putnik(
        id: widget.existing?.id ?? '',
        imePrezime: imeVal,
        telefon1: V3PhoneUtils.normalizeOrNull(_tel1.text),
        telefon2: V3PhoneUtils.normalizeOrNull(_tel2.text),
        tipPutnika: _tip,
        cenaPoDanu: (_tip == 'dnevni' || _tip == 'posiljka')
            ? 0.0 // dnevni/posiljka koriste cenaPoPokupljenju
            : double.tryParse(_cenaDan.text.replaceAll(',', '.')) ?? 0.0,
        adresaBcId: _adresaBc1?.id,
        adresaBcId2: _adresaBc2?.id,
        adresaVsId: _adresaVs1?.id,
        adresaVsId2: _adresaVs2?.id,
        cenaPoPokupljenju: (_tip == 'dnevni' || _tip == 'posiljka')
            ? double.tryParse(_cenaDan.text.replaceAll(',', '.')) ?? 0.0
            : 0.0, // radnici/ucenici koriste cenaPoDanu
      );
      await V3PutnikService.addUpdatePutnik(
        putnik,
        createdBy: V3UuidUtils.normalizeUuid('admin'),
      );
      if (mounted) {
        V3AppSnackBar.success(context, widget.existing == null ? _PutTr.tr('putnikDodan') : _PutTr.tr('putnikSacuvan'));
        Navigator.pop(context);
      }
    } catch (e) {
      V3AppSnackBar.error(context, '${_PutTr.tr('greska')}: $e');
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
      dropdownColor: V3InputStyle.dropdownMenu,
      style: V3InputUtils.fieldTextStyle,
      decoration: V3InputUtils.dropdownDecoration(
        label: label,
        icon: grad == 'BC' ? Icons.location_city_outlined : Icons.location_on_outlined,
        prefixIconColor: grad == 'BC' ? const Color(0xFF2563EB) : const Color(0xFFEA580C),
        suffixIcon: value != null
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18, color: V3InputStyle.label),
                onPressed: () => onChanged(null),
              )
            : null,
      ),
      hint: Text(
        _PutTr.tr('nijeOdabrano'),
        style: const TextStyle(fontSize: 13, color: V3InputStyle.label),
      ),
      items: [
        ...adrese.map((a) => DropdownMenuItem(
              value: a,
              child: V3SafeText.userAddress(
                a.naziv,
                style: const TextStyle(fontSize: 13, color: V3InputStyle.text),
              ),
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

    final gradient = theme.backgroundGradient;

    return Dialog(
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: BoxDecoration(gradient: gradient),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.18),
                  border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
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
                            isEdit ? _PutTr.tr('urediPutnika') : _PutTr.tr('noviPutnik'),
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            isEdit ? _PutTr.tr('azurirajPodatke') : _PutTr.tr('unesiPodatke'),
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
                      // Sekcija header
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          _PutTr.tr('osnovniPodaci'),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Tip
                      DropdownButtonFormField<String>(
                        value: _tip,
                        dropdownColor: V3InputStyle.dropdownMenu,
                        style: V3InputUtils.fieldTextStyle,
                        decoration: V3InputUtils.dropdownDecoration(
                          label: _PutTr.tr('tipPutnika'),
                          icon: Icons.category_outlined,
                        ),
                        items: [
                          DropdownMenuItem(value: 'radnik', child: Text(_PutTr.tr('radnik'))),
                          DropdownMenuItem(value: 'ucenik', child: Text(_PutTr.tr('ucenik'))),
                          DropdownMenuItem(value: 'dnevni', child: Text(_PutTr.tr('dnevni'))),
                          DropdownMenuItem(value: 'posiljka', child: Text(_PutTr.tr('posiljka'))),
                          const DropdownMenuItem(value: 'vozac', child: Text('Vozač')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          V3StateUtils.safeSetState(this, () => _tip = v);
                        },
                      ),
                      const SizedBox(height: 10),
                      V3InputUtils.textField(
                        controller: _ime,
                        label: _PutTr.tr('imePrezime'),
                        icon: Icons.person,
                      ),
                      const SizedBox(height: 10),
                      V3InputUtils.formField(
                        controller: _tel1,
                        label: _PutTr.tr('telefon1'),
                        icon: Icons.phone,
                        keyboardType: TextInputType.phone,
                        validator: (v) => V3InputUtils.phoneValidator(v, isRequired: true),
                      ),
                      const SizedBox(height: 10),
                      V3InputUtils.formField(
                        controller: _tel2,
                        label: _PutTr.tr('telefon2'),
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        validator: (v) => V3InputUtils.phoneValidator(v, isRequired: false),
                      ),
                      const SizedBox(height: 10),
                      if (_tip != 'vozac')
                        V3InputUtils.formField(
                          controller: _cenaDan,
                          label: (_tip == 'dnevni' || _tip == 'posiljka')
                              ? _PutTr.tr('cenaPoVoznji')
                              : _PutTr.tr('cenaPoDanu'),
                          icon: Icons.numbers,
                          keyboardType: TextInputType.number,
                          suffixText: 'din',
                        ),
                      if (_tip == 'vozac')
                        DropdownButtonFormField<String>(
                          value: _ulogaVozaca,
                          dropdownColor: V3InputStyle.dropdownMenu,
                          style: V3InputUtils.fieldTextStyle,
                          decoration: V3InputUtils.dropdownDecoration(
                            label: 'Uloga',
                            icon: Icons.admin_panel_settings_outlined,
                          ),
                          items: V3AdminService.allRoles
                              .map((r) => DropdownMenuItem<String>(value: r, child: Text(r)))
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            V3StateUtils.safeSetState(this, () => _ulogaVozaca = v);
                          },
                        ),
                      const SizedBox(height: 14),
                      // ── Adrese BC (samo za putnike) ──
                      if (_tip != 'vozac') ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.lightBlueAccent.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on, size: 16, color: Colors.lightBlueAccent),
                              const SizedBox(width: 4),
                              Text(_PutTr.tr('adreseBc'),
                                  style: const TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.bold, color: Colors.lightBlueAccent)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        _adresaDropdown(
                          label: _PutTr.tr('bcAdresa1'),
                          grad: 'BC',
                          value: _adresaBc1,
                          onChanged: (v) => V3StateUtils.safeSetState(this, () => _adresaBc1 = v),
                        ),
                        const SizedBox(height: 8),
                        _adresaDropdown(
                          label: _PutTr.tr('bcAdresa2'),
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
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on, size: 16, color: Colors.orangeAccent),
                              const SizedBox(width: 4),
                              Text(_PutTr.tr('adreseVs'),
                                  style: const TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        _adresaDropdown(
                          label: _PutTr.tr('vsAdresa1'),
                          grad: 'VS',
                          value: _adresaVs1,
                          onChanged: (v) => V3StateUtils.safeSetState(this, () => _adresaVs1 = v),
                        ),
                        const SizedBox(height: 8),
                        _adresaDropdown(
                          label: _PutTr.tr('vsAdresa2'),
                          grad: 'VS',
                          value: _adresaVs2,
                          onChanged: (v) => V3StateUtils.safeSetState(this, () => _adresaVs2 = v),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ),
              // ── Actions ──
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.18),
                  border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    V3ButtonUtils.textButton(
                      onPressed: () => Navigator.pop(context),
                      text: _PutTr.tr('otkazi'),
                      foregroundColor: Colors.white70,
                    ),
                    const SizedBox(width: 8),
                    V3ButtonUtils.primaryButton(
                      onPressed: _saving ? null : _sacuvaj,
                      text: isEdit ? _PutTr.tr('sacuvaj') : _PutTr.tr('dodaj'),
                      icon: isEdit ? Icons.save_as_rounded : Icons.person_add_alt_1_rounded,
                      isLoading: _saving,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Uloge Dialog (admin/dispecer/vozac) ──────────────────────────────────────

class _UlogeDialog extends StatefulWidget {
  const _UlogeDialog();

  @override
  State<_UlogeDialog> createState() => _UlogeDialogState();
}

class _UlogeDialogState extends State<_UlogeDialog> {
  final Set<String> _saving = <String>{};

  Color _colorForUloga(String uloga) {
    switch (uloga) {
      case V3AdminService.roleAdmin:
        return const Color(0xFFE65C00);
      case V3AdminService.roleDispecer:
        return const Color(0xFF3B7DD8);
      default:
        return Colors.white54;
    }
  }

  Future<void> _promeniUlogu(V3Vozac vozac, String novaUloga) async {
    if (vozac.uloga == novaUloga) return;
    setState(() => _saving.add(vozac.id));
    try {
      await V3AdminService.setUloga(vozacId: vozac.id, uloga: novaUloga);
    } catch (e) {
      if (mounted) V3AppSnackBar.error(context, _PutTr.tr('greskaCuvanja'));
    } finally {
      if (mounted) setState(() => _saving.remove(vozac.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: V3MasterRealtimeManager.instance.tableRevisionStream('v3_auth'),
      builder: (context, _) {
        final vozaci = V3VozacService.getAllVozaci();

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          child: V3ContainerUtils.gradientContainer(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [Color(0xFF1E2235), Color(0xFF252840)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 12, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.admin_panel_settings, color: Colors.white, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_PutTr.tr('uloge'),
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white12, height: 1),
                  Flexible(
                    child: vozaci.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_PutTr.tr('nemaPutnika'), style: const TextStyle(color: Colors.white60)),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shrinkWrap: true,
                            itemCount: vozaci.length,
                            itemBuilder: (context, i) {
                              final v = vozaci[i];
                              final isSaving = _saving.contains(v.id);
                              final boja = _colorForUloga(v.uloga);
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: boja.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: boja.withValues(alpha: 0.35)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(v.imePrezime,
                                          style: const TextStyle(
                                              fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                                    ),
                                    if (isSaving)
                                      const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    else
                                      DropdownButton<String>(
                                        value: V3AdminService.allRoles.contains(v.uloga)
                                            ? v.uloga
                                            : V3AdminService.roleVozac,
                                        dropdownColor: const Color(0xFF252840),
                                        underline: const SizedBox.shrink(),
                                        style: TextStyle(color: boja, fontWeight: FontWeight.bold, fontSize: 13),
                                        items: V3AdminService.allRoles
                                            .map((r) => DropdownMenuItem<String>(value: r, child: Text(r)))
                                            .toList(),
                                        onChanged: (novaUloga) {
                                          if (novaUloga != null) _promeniUlogu(v, novaUloga);
                                        },
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
