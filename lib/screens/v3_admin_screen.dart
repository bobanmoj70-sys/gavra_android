import 'package:flutter/material.dart';

import '../globals.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v2_theme_manager.dart';
import '../services/v3/v3_dug_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_navigation_utils.dart';
import 'v3_admin_raspored_screen.dart';
import 'v3_adrese_screen.dart';
import 'v3_dnevnik_naplate_screen.dart';
import 'v3_dugovi_screen.dart';
import 'v3_finansije_screen.dart';
import 'v3_gorivo_screen.dart';
import 'v3_kapacitet_screen.dart';
import 'v3_odrzavanje_screen.dart';
import 'v3_pin_zahtevi_screen.dart';
import 'v3_posiljke_zahtevi_screen.dart';
import 'v3_putnici_screen.dart';
import 'v3_radnici_zahtevi_screen.dart';
import 'v3_ucenici_zahtevi_screen.dart';
import 'v3_vozaci_admin_screen.dart';
import 'v3_zahtevi_dnevni_screen.dart';

class V3AdminScreen extends StatefulWidget {
  const V3AdminScreen({super.key});

  @override
  State<V3AdminScreen> createState() => _V3AdminScreenState();
}

class _V3AdminScreenState extends State<V3AdminScreen> {
  late final V2ThemeManager _themeManager;

  @override
  void initState() {
    super.initState();
    _themeManager = V2ThemeManager();
  }

  void _showStatistikeMenu(BuildContext context) {
    V3NavigationUtils.showBottomSheet<void>(
      context,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                V3ContainerUtils.styledContainer(
                  width: 40,
                  height: 4,
                  backgroundColor: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                  child: const SizedBox(),
                ),
                const SizedBox(height: 16),
                const Text(
                  '📊 Statistike',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Text('💹', style: TextStyle(fontSize: 24)),
                  title: const Text('Finansije'),
                  subtitle: const Text('Prihodi, troškovi, neto zarada'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(context);
                    V3NavigationUtils.pushScreen(context, const V3FinansijeScreen());
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Text('🔧', style: TextStyle(fontSize: 24)),
                  title: const Text('Kolska knjiga'),
                  subtitle: const Text('Servisi, registracija, gume...'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(context);
                    V3NavigationUtils.pushScreen(context, const V3OdrzavanjeScreen());
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Računa pazar po vozaču iz operativnaNedeljaCache — samo danas, akter = naplatio_vozac_id
  Map<String, double> _getPazarPoVozacu() {
    final cache = V3MasterRealtimeManager.instance.operativnaNedeljaCache;
    final danas = DateTime.now();
    final result = <String, double>{};
    for (final row in cache.values) {
      final status = row['naplata_status'] as String? ?? '';
      if (status != 'placeno') continue;
      // Datum plaćanja
      final vremeStr = row['vreme_placen'] as String? ?? row['updated_at'] as String?;
      if (vremeStr != null) {
        final dt = DateTime.tryParse(vremeStr);
        if (dt == null) continue;
        if (dt.year != danas.year || dt.month != danas.month || dt.day != danas.day) continue;
      } else {
        continue; // nema datuma — preskači
      }
      // Akter: ko je naplatio
      final akterId = row['naplatio_vozac_id']?.toString();
      if (akterId == null || akterId.isEmpty) continue;
      final iznos = (row['iznos_naplacen'] as num?)?.toDouble() ?? 0.0;
      result[akterId] = (result[akterId] ?? 0.0) + iznos;
    }
    return result;
  }

  Color _bojaVozaca(String vozacId) {
    final hex = V3MasterRealtimeManager.instance.vozaciCache[vozacId]?['boja']?.toString();
    if (hex == null || hex.isEmpty) return Colors.blueGrey;
    try {
      final clean = hex.replaceFirst('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return Colors.blueGrey;
    }
  }

  /// Broj zahteva sa statusom 'na_cekanju' iz zahteviCache
  int _getUceniciZahteviCount() {
    final rm = V3MasterRealtimeManager.instance;
    final uceniciIds = rm.putniciCache.values
        .where((p) => (p['tip_putnika'] as String? ?? '').toLowerCase() == 'ucenik')
        .map((p) => p['id'] as String)
        .toSet();
    return rm.zahteviCache.values.where((r) => uceniciIds.contains(r['putnik_id']) && r['status'] == 'obrada').length;
  }

  int _getRadniciZahteviCount() {
    final rm = V3MasterRealtimeManager.instance;
    final radniciIds = rm.putniciCache.values
        .where((p) => (p['tip_putnika'] as String? ?? '').toLowerCase() == 'radnik')
        .map((p) => p['id'] as String)
        .toSet();
    return rm.zahteviCache.values.where((r) => radniciIds.contains(r['putnik_id']) && r['status'] == 'obrada').length;
  }

  int _getZahteviCount() {
    final rm = V3MasterRealtimeManager.instance;
    return rm.zahteviCache.values.where((row) {
      if ((row['status']?.toString() ?? '') != 'obrada') return false;
      final createdBy = row['created_by'] as String? ?? '';
      return createdBy.startsWith('putnik:');
    }).length;
  }

  int _getPinZahteviCount() {
    final cache = V3MasterRealtimeManager.instance.pinZahteviCache;
    return cache.values.where((row) => (row['status']?.toString() ?? '') == 'ceka').length;
  }

  int _getPosiljkeZahteviCount() {
    final rm = V3MasterRealtimeManager.instance;
    final posiljkaPutnici = rm.putniciCache.values
        .where((p) => (p['tip_putnika'] as String? ?? '').toLowerCase() == 'posiljka')
        .map((p) => p['id'] as String)
        .toSet();
    return rm.zahteviCache.values
        .where((r) => posiljkaPutnici.contains(r['putnik_id']) && r['status'] == 'obrada')
        .length;
  }

  /// saVS/ukBC widget — aktivnih termin-ova / ukupno
  Widget _buildSaVsWidget(BuildContext context) {
    final termini = V3MasterRealtimeManager.instance.v3GpsRasporedCache;
    final ukBC = termini.length;
    final saVS = termini.values.where((r) => (r['aktivan'] == true)).length;
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.7), width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$saVS/$ukBC',
            style: const TextStyle(
              color: Colors.orange,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text(
            'akt/uk',
            style: TextStyle(color: Colors.white70, fontSize: 9),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: V3MasterRealtimeManager.instance.onChange,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final vozac = V3VozacService.currentVozac;
    final ime = vozac?.imePrezime ?? 'Admin';
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: _themeManager.currentGradient),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 10),

              // ─── RED 1: Kompaktni emoji gumbi (h=40) ───
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                child: Row(
                  children: [
                    // 📍 Adrese
                    Expanded(
                      child: _NavBtn(
                        color: Colors.teal,
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3AdreseScreen(),
                        ),
                        child: const Text('📍', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 💰 Kapacitet
                    Expanded(
                      child: _NavBtn(
                        color: Colors.green,
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3VozaciAdminScreen(),
                        ),
                        child: const Text('💰', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 📊 Statistike (popup)
                    Expanded(
                      child: _NavBtn(
                        color: Colors.purple,
                        onTap: () => _showStatistikeMenu(context),
                        child: const Text('📊', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // ⛽ Gorivo
                    Expanded(
                      child: _NavBtn(
                        color: Colors.orange,
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3GorivoScreen(),
                        ),
                        child: const Text('⛽', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 🔧 Raspored + Vozaci admin popup
                    ValueListenableBuilder<String>(
                      valueListenable: navBarTypeNotifier,
                      builder: (context, navType, _) {
                        const labels = {'zimski': '❄️', 'letnji': '☀️', 'praznici': '🎉'};
                        return _NavBtn(
                          color: Colors.blueGrey,
                          onTap: () async {
                            final RenderBox button = context.findRenderObject()! as RenderBox;
                            final RenderBox overlay =
                                Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
                            final RelativeRect position = RelativeRect.fromRect(
                              Rect.fromPoints(
                                button.localToGlobal(Offset.zero, ancestor: overlay),
                                button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
                              ),
                              Offset.zero & overlay.size,
                            );
                            final val = await showMenu<String>(
                              context: context,
                              position: position,
                              color: Theme.of(context).colorScheme.primary,
                              items: [
                                PopupMenuItem(
                                  enabled: false,
                                  height: 28,
                                  child: Text('Tip rasporeda', style: TextStyle(color: Colors.white54, fontSize: 12)),
                                ),
                                const PopupMenuItem(
                                    value: 'zimski', child: Text('❄️  Zimski', style: TextStyle(color: Colors.white))),
                                const PopupMenuItem(
                                    value: 'letnji', child: Text('☀️  Ljetnji', style: TextStyle(color: Colors.white))),
                                const PopupMenuItem(
                                    value: 'praznici',
                                    child: Text('🎉  Praznici', style: TextStyle(color: Colors.white))),
                                const PopupMenuDivider(),
                                const PopupMenuItem(
                                    value: '__kapacitet__',
                                    child: Text('📅  Kapacitet termina', style: TextStyle(color: Colors.white))),
                                const PopupMenuItem(
                                    value: '__vozaci__',
                                    child: Text('🚗  Vozači admin', style: TextStyle(color: Colors.white))),
                              ],
                            );
                            if (val == null) return;
                            if (val == '__kapacitet__') {
                              if (context.mounted) {
                                V3NavigationUtils.pushScreen<void>(context, const V3KapacitetScreen());
                              }
                              return;
                            }
                            if (val == '__vozaci__') {
                              if (context.mounted) {
                                V3NavigationUtils.pushScreen<void>(context, const V3VozaciAdminScreen());
                              }
                              return;
                            }
                            navBarTypeNotifier.value = val;
                            try {
                              await supabase.from('v3_app_settings').update({'nav_bar_type': val}).eq('id', 'global');
                              debugPrint('[AdminScreen] nav_bar_type sačuvan u bazi: $val');
                            } catch (e) {
                              debugPrint('[AdminScreen] Greška pri čuvanju nav_bar_type: $e');
                            }
                          },
                          child: Text(labels[navType] ?? '⚙️', style: const TextStyle(fontSize: 20)),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // ─── RED 2: Raspored, Putnici ───
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                child: Row(
                  children: [
                    // 📅 Raspored
                    _NavBtn(
                      color: Colors.blue,
                      onTap: () => V3NavigationUtils.pushScreen<void>(
                        context,
                        const V3AdminRasporedScreen(),
                      ),
                      child: const Text('📅', style: TextStyle(fontSize: 20)),
                    ),
                    const SizedBox(width: 6),
                    // Putnici
                    Expanded(
                      child: _NavBtn(
                        color: Colors.blueGrey,
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3PutniciScreen(),
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Putnici',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Colors.white,
                              shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ─── RED 3: Dnevnik naplate, saVS/ukBC ───
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Row(
                  children: [
                    // Dnevnik naplate
                    Expanded(
                      child: _NavBtn(
                        color: Colors.indigo,
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3DnevnikNaplateScreen(),
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '📒',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Colors.white,
                              shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // saVS/ukBC statistika
                    _buildSaVsWidget(context),
                  ],
                ),
              ),

              // ─── RED 4: Badge gumbi — Učenici, Radnici, Pošiljke, PIN, Zahtevi ───
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Row(
                  children: [
                    // 🔔 Zahtevi (polasci)
                    Expanded(
                      child: _BadgeBtn(
                        emoji: '🔔',
                        color: Colors.deepOrange,
                        badgeCount: _getZahteviCount(),
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3ZahteviDnevniScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 🎓 Učenici zahtevi
                    Expanded(
                      child: _BadgeBtn(
                        emoji: '🎓',
                        color: Colors.lightBlue,
                        badgeCount: _getUceniciZahteviCount(),
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3UceniciZahteviScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 👷 Radnici zahtevi
                    Expanded(
                      child: _BadgeBtn(
                        emoji: '👷',
                        color: Colors.green,
                        badgeCount: _getRadniciZahteviCount(),
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3RadniciZahteviScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 📦 Pošiljke zahtevi
                    Expanded(
                      child: _BadgeBtn(
                        emoji: '📦',
                        color: Colors.deepOrangeAccent,
                        badgeCount: _getPosiljkeZahteviCount(),
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3PosiljkeZahteviScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 🔑 PIN zahtevi
                    Expanded(
                      child: _BadgeBtn(
                        emoji: '🔑',
                        color: Colors.amber,
                        badgeCount: _getPinZahteviCount(),
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3PinZahteviScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // ─── DONJI DIO: Vozači s pazarom + Dužnici + Ukupno ───
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + MediaQuery.of(context).padding.bottom),
                  child: _buildPazarSection(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPazarSection(BuildContext context) {
    final vozaci = V3VozacService.getAllVozaci();
    final pazarPoVozacu = _getPazarPoVozacu();
    final sveDugovi = V3DugService.getDugovi();
    // Dužnici = samo dnevni putnici koji nisu platili
    final dugovi = sveDugovi.where((d) => d.tipPutnika == 'dnevni').toList();
    final dugoviIznos = dugovi.fold(0.0, (s, d) => s + d.iznos);
    final ukupnoPazar = pazarPoVozacu.values.fold(0.0, (s, v) => s + v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Lista vozača sa pazarom
        ...vozaci.map((v) {
          final boja = _bojaVozaca(v.id);
          final pazar = pazarPoVozacu[v.id] ?? 0.0;
          return Container(
            height: 56,
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: boja.withValues(alpha: 60 / 255),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: boja.withValues(alpha: 120 / 255)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: boja,
                  radius: 15,
                  child: Text(
                    v.imePrezime.isNotEmpty ? v.imePrezime[0] : '?',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    v.imePrezime,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: boja),
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.monetization_on, color: boja, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '${pazar.toStringAsFixed(0)} RSD',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: boja),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),

        const SizedBox(height: 6),

        // Dužnici dugme
        InkWell(
          onTap: () => V3NavigationUtils.pushScreen<void>(
            context,
            const V3DugoviScreen(),
          ),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Dužnici',
                    style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                Text(
                  '${dugoviIznos.toStringAsFixed(0)} RSD',
                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.monetization_on, color: Colors.redAccent, size: 16),
              ],
            ),
          ),
        ),

        const SizedBox(height: 6),

        // Ukupan pazar
        V3ContainerUtils.styledContainer(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          backgroundColor: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green.withValues(alpha: 0.5), width: 1.5),
          boxShadow: [
            BoxShadow(color: Colors.green.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4)),
          ],
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.account_balance_wallet, color: Colors.green[700], size: 22),
              const SizedBox(width: 10),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'UKUPAN PAZAR',
                    style: TextStyle(
                      color: Colors.green[800],
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    '${ukupnoPazar.toStringAsFixed(0)} RSD',
                    style: TextStyle(
                      color: Colors.green[900],
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Helper widget: kompaktni nav dugme h=40 (samo emoji)
// ─────────────────────────────────────────────
class _NavBtn extends StatelessWidget {
  const _NavBtn({
    required this.onTap,
    required this.child,
    this.color = Colors.blueGrey,
  });

  final VoidCallback onTap;
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
        ),
        child: Center(child: child),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Helper widget: dugme s badge brojevima
// ─────────────────────────────────────────────
class _BadgeBtn extends StatelessWidget {
  const _BadgeBtn({
    required this.onTap,
    required this.emoji,
    required this.color,
    required this.badgeCount,
  });

  final VoidCallback onTap;
  final String emoji;
  final Color color;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: color.withValues(alpha: badgeCount > 0 ? 0.9 : 0.6),
                width: 1.5,
              ),
            ),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
          ),
        ),
        if (badgeCount > 0)
          Positioned(
            right: 4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle),
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              child: Text(
                '$badgeCount',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
