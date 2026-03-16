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
import '../utils/v3_phone_utils.dart';
import '../utils/v3_string_utils.dart';

class V3PutniciScreen extends StatefulWidget {
  const V3PutniciScreen({super.key});

  @override
  State<V3PutniciScreen> createState() => _V3PutniciScreenState();
}

class _V3PutniciScreenState extends State<V3PutniciScreen> {
  String _selectedFilter = 'svi';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ─── Badge counts ─────────────────────────────────────────────────────────
  int _count(String tip) {
    final cache = V3MasterRealtimeManager.instance.putniciCache.values;
    if (tip == 'svi') return cache.where((r) => r['aktivno'] == true).length;
    return cache.where((r) => r['aktivno'] == true && r['tip_putnika'] == tip).length;
  }

  // ─── Filtered list ────────────────────────────────────────────────────────
  List<V3Putnik> _filtriraj() {
    var lista = V3MasterRealtimeManager.instance.putniciCache.values
        .where((r) => r['aktivno'] == true)
        .map((r) => V3Putnik.fromJson(r))
        .toList();

    if (_selectedFilter != 'svi') {
      lista = lista.where((p) => p.tipPutnika == _selectedFilter).toList();
    }

    final search = _searchController.text.trim();
    if (search.isNotEmpty) {
      lista = lista.where((p) => V3StringUtils.containsSearch(p.imePrezime, search)).toList();
    }

    lista.sort((a, b) => V3StringUtils.compareForSort(a.imePrezime, b.imePrezime));

    const limit = 50;
    if (lista.length > limit) return lista.sublist(0, limit);
    return lista;
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(72),
        child: StreamBuilder<void>(
          stream: V3MasterRealtimeManager.instance.onChange,
          builder: (context, _) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).glassContainer,
                border: Border(
                  bottom: BorderSide(color: Theme.of(context).glassBorder, width: 1.5),
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      // ── Filter icons with badges ──────────────────────
                      _filterBtn('svi', Icons.people, Colors.white, Colors.blueGrey),
                      _filterBtn('radnik', Icons.engineering, const Color(0xFF5C9CE6), const Color(0xFF3B7DD8)),
                      _filterBtn('ucenik', Icons.school, const Color(0xFF4ECDC4), const Color(0xFF44A08D)),
                      _filterBtn('dnevni', Icons.today, const Color(0xFFFF6B6B), const Color(0xFFFF8E53)),
                      _filterBtn('posiljka', Icons.local_shipping, const Color(0xFFFF8C00), const Color(0xFFE65C00)),
                      const Spacer(),
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
            );
          },
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              // ── Search bar ──────────────────────────────────────────────
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 3))
                  ],
                ),
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchController,
                  builder: (context, val, _) => TextField(
                    controller: _searchController,
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
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              // ── List ────────────────────────────────────────────────────
              Expanded(
                child: StreamBuilder<void>(
                  stream: V3MasterRealtimeManager.instance.onChange,
                  builder: (context, _) {
                    return ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _searchController,
                      builder: (context, _, __) {
                        final lista = _filtriraj();
                        final total = V3MasterRealtimeManager.instance.putniciCache.values
                            .where((r) =>
                                r['aktivno'] == true &&
                                (_selectedFilter == 'svi' || r['tip_putnika'] == _selectedFilter))
                            .length;
                        final isTruncated = total > 50;

                        if (lista.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _searchController.text.isNotEmpty ? Icons.search_off : Icons.group_off,
                                  size: 64,
                                  color: Colors.white38,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _searchController.text.isNotEmpty ? 'Nema rezultata pretrage' : 'Nema putnika',
                                  style: const TextStyle(fontSize: 18, color: Colors.white60),
                                ),
                              ],
                            ),
                          );
                        }

                        return Column(
                          children: [
                            if (isTruncated)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline, size: 14, color: Colors.white38),
                                    const SizedBox(width: 6),
                                    Text('Prikazano 50 od $total — preciziraj pretragu',
                                        style: const TextStyle(fontSize: 12, color: Colors.white54)),
                                  ],
                                ),
                              ),
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
          onPressed: () => setState(() => _selectedFilter = isSelected ? 'svi' : tip),
        ),
        if (count > 0)
          Positioned(
            right: 2,
            top: 2,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [c1, c2]),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: c2.withValues(alpha: 0.5), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              child: Text(
                count > 99 ? '99+' : '$count',
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
      await supabase.from('v3_putnici').update({'aktivno': !p.aktivno}).eq('id', p.id);
      if (mounted) {
        V3AppSnackBar.success(context, p.aktivno ? '${p.imePrezime} deaktiviran' : '${p.imePrezime} aktiviran');
      }
    } catch (e) {
      if (mounted) V3AppSnackBar.error(context, '❌ Greška: $e');
    }
  }

  // ─── Delete ───────────────────────────────────────────────────────────────
  Future<void> _obrisi(V3Putnik p) async {
    final potvrda = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Potvrdi brisanje'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Da li ste sigurni da želite da obrišete "${p.imePrezime}"?'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.info, color: Colors.red, size: 18),
                    SizedBox(width: 8),
                    Text('Važno:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                  SizedBox(height: 8),
                  Text('• Putnik će biti TRAJNO obrisan'),
                  Text('• Sve vožnje i statistike se brišu'),
                  Text('• Ova akcija je NEPOVRATNA!', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Otkaži')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Obriši', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (potvrda != true || !mounted) return;
    try {
      await V3PutnikService.deactivatePutnik(p.id);
      if (mounted) V3AppSnackBar.success(context, '${p.imePrezime} obrisan');
    } catch (e) {
      if (mounted) V3AppSnackBar.error(context, '❌ Greška: $e');
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
  });

  final V3Putnik putnik;
  final int redniBroj;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

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
    final String? adresa = putnik.adresaBcNaziv != null || putnik.adresaVsNaziv != null
        ? '${putnik.adresaBcNaziv ?? "/"} → ${putnik.adresaVsNaziv ?? "/"}'
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 4,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [const Color(0xFF1E2235), const Color(0xFF252840)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: _tipColor.withValues(alpha: 0.35), width: 1.5),
        ),
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
                    icon: putnik.aktivno ? Icons.toggle_on_outlined : Icons.toggle_off_outlined,
                    label: putnik.aktivno ? 'Aktivan' : 'Neaktivan',
                    color: putnik.aktivno ? Colors.green : Colors.grey,
                    onPressed: onToggle,
                  )),
                  const SizedBox(width: 6),
                  Expanded(
                      child: _actionBtn(
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
                      icon: Icons.phone,
                      label: 'Pozovi',
                      color: Colors.green,
                      onPressed: () => _pokaziKontakt(context),
                    )),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                      child: _actionBtn(
                    icon: Icons.edit_outlined,
                    label: 'Uredi',
                    color: Colors.blue,
                    onPressed: onEdit,
                  )),
                  const SizedBox(width: 6),
                  Expanded(
                      child: _actionBtn(
                    icon: Icons.delete_outline,
                    label: 'Obriši',
                    color: Colors.red,
                    onPressed: onDelete,
                  )),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 32,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.08)],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 13, color: color),
          label: Text(label,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
              overflow: TextOverflow.ellipsis),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          ),
        ),
      ),
    );
  }

  void _pokaziKontakt(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
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
                    Navigator.pop(ctx);
                    await launchUrl(Uri.parse('tel:${putnik.telefon1}'), mode: LaunchMode.externalApplication);
                  },
                ),
              if (putnik.telefon2?.isNotEmpty == true)
                ListTile(
                  leading: const Icon(Icons.phone_android, color: Colors.blue),
                  title: const Text('Pozovi (telefon 2)'),
                  subtitle: Text(putnik.telefon2!),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await launchUrl(Uri.parse('tel:${putnik.telefon2}'), mode: LaunchMode.externalApplication);
                  },
                ),
              const SizedBox(height: 8),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Otkaži')),
            ],
          ),
        ),
      ),
    );
  }

  void _showPinDialog(BuildContext context) {
    final ctrl = TextEditingController(text: putnik.pin ?? '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('🔐 PIN — ${putnik.imePrezime}'),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Otkaži')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await supabase
                    .from('v3_putnici')
                    .update({'pin': ctrl.text.isEmpty ? null : ctrl.text}).eq('id', putnik.id);
                if (context.mounted) V3AppSnackBar.success(context, '✅ PIN sačuvan');
              } catch (e) {
                if (context.mounted) V3AppSnackBar.error(context, '❌ Greška: $e');
              }
            },
            child: const Text('Sačuvaj'),
          ),
        ],
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
  late final TextEditingController _email = TextEditingController(text: widget.existing?.email ?? '');
  late final TextEditingController _skola = TextEditingController(text: widget.existing?.skola ?? '');
  late final TextEditingController _opis = TextEditingController(text: widget.existing?.opisPosiljke ?? '');
  late final TextEditingController _cenaDan = TextEditingController(
      text: widget.existing?.cenaPoDanu != null && widget.existing!.cenaPoDanu > 0
          ? widget.existing!.cenaPoDanu.toStringAsFixed(0)
          : '');
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
    setState(() => _saving = true);
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
        cenaPoDanu: double.tryParse(_cenaDan.text.replaceAll(',', '.')) ?? 0.0,
        aktivno: widget.existing?.aktivno ?? true,
        adresaBcId: _adresaBc1?.id,
        adresaBcNaziv: _adresaBc1?.naziv,
        adresaBcId2: _adresaBc2?.id,
        adresaBcNaziv2: _adresaBc2?.naziv,
        adresaVsId: _adresaVs1?.id,
        adresaVsNaziv: _adresaVs1?.naziv,
        adresaVsId2: _adresaVs2?.id,
        adresaVsNaziv2: _adresaVs2?.naziv,
        pin: widget.existing?.pin,
        cenaPoPokupljenju: widget.existing?.cenaPoPokupljenju ?? 0.0,
        placeniMesec: widget.existing?.placeniMesec,
        placenaGodina: widget.existing?.placenaGodina,
      );
      await V3PutnikService.addUpdatePutnik(putnik, createdBy: 'admin:sistem');
      if (mounted) {
        V3AppSnackBar.success(context, widget.existing == null ? '✅ Putnik dodan' : '✅ Putnik sačuvan');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) V3AppSnackBar.error(context, '❌ Greška: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
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
        border: const OutlineInputBorder(),
        isDense: true,
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
              child: Text(a.naziv, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [theme.colorScheme.primary, theme.colorScheme.primary.withValues(alpha: 0.8)],
                ),
              ),
              child: Text(
                isEdit ? '✏️ Uredi putnika' : '➕ Novi putnik',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            // ── Sadržaj ──
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tip
                    DropdownButtonFormField<String>(
                      value: _tip,
                      decoration:
                          const InputDecoration(labelText: 'Tip putnika', border: OutlineInputBorder(), isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'radnik', child: Text('👷 Radnik')),
                        DropdownMenuItem(value: 'ucenik', child: Text('🎒 Učenik')),
                        DropdownMenuItem(value: 'dnevni', child: Text('🚶 Dnevni')),
                        DropdownMenuItem(value: 'posiljka', child: Text('📦 Pošiljka')),
                      ],
                      onChanged: isEdit ? null : (v) => setState(() => _tip = v!),
                    ),
                    const SizedBox(height: 10),
                    // Ime
                    TextField(
                      controller: _ime,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                          labelText: 'Ime i prezime *', border: OutlineInputBorder(), isDense: true),
                    ),
                    const SizedBox(height: 10),
                    // Telefoni
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _tel1,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                                labelText: 'Telefon 1', border: OutlineInputBorder(), isDense: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _tel2,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                                labelText: 'Telefon 2', border: OutlineInputBorder(), isDense: true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Email
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                          labelText: 'Email (opciono)', border: OutlineInputBorder(), isDense: true),
                    ),
                    const SizedBox(height: 10),
                    // Cena
                    TextField(
                      controller: _cenaDan,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Cena po danu', border: OutlineInputBorder(), isDense: true, suffixText: 'din'),
                    ),
                    // Škola
                    if (_tip == 'ucenik') ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _skola,
                        textCapitalization: TextCapitalization.words,
                        decoration:
                            const InputDecoration(labelText: 'Škola', border: OutlineInputBorder(), isDense: true),
                      ),
                    ],
                    // Opis pošiljke
                    if (_tip == 'posiljka') ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _opis,
                        decoration: const InputDecoration(
                            labelText: 'Opis pošiljke', border: OutlineInputBorder(), isDense: true),
                      ),
                    ],
                    const SizedBox(height: 14),
                    // ── Adrese BC ──
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 16, color: Colors.blueAccent),
                        const SizedBox(width: 4),
                        Text('Adrese — Bela Crkva',
                            style:
                                TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _adresaDropdown(
                      label: 'BC — Adresa 1',
                      grad: 'BC',
                      value: _adresaBc1,
                      onChanged: (v) => setState(() => _adresaBc1 = v),
                    ),
                    const SizedBox(height: 8),
                    _adresaDropdown(
                      label: 'BC — Adresa 2 (opciono)',
                      grad: 'BC',
                      value: _adresaBc2,
                      onChanged: (v) => setState(() => _adresaBc2 = v),
                    ),
                    const SizedBox(height: 14),
                    // ── Adrese VS ──
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 16, color: Colors.orangeAccent),
                        const SizedBox(width: 4),
                        Text('Adrese — Vršac',
                            style:
                                TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _adresaDropdown(
                      label: 'VS — Adresa 1',
                      grad: 'VS',
                      value: _adresaVs1,
                      onChanged: (v) => setState(() => _adresaVs1 = v),
                    ),
                    const SizedBox(height: 8),
                    _adresaDropdown(
                      label: 'VS — Adresa 2 (opciono)',
                      grad: 'VS',
                      value: _adresaVs2,
                      onChanged: (v) => setState(() => _adresaVs2 = v),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            // ── Actions ──
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Otkaži'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _sacuvaj,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save, size: 18),
                    label: Text(isEdit ? 'Sačuvaj' : 'Dodaj'),
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
