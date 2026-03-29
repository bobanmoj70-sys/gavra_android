import 'package:flutter/material.dart';

import '../globals.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v2_theme_manager.dart';
import '../services/v3/v3_dug_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_navigation_utils.dart';
import '../utils/v3_safe_text.dart';
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
  static final RegExp _versionPattern = RegExp(r'^\d+(\.\d+){1,3}$');

  @override
  void initState() {
    super.initState();
    _themeManager = V2ThemeManager();
  }

  bool _isValidVersion(String value) {
    return _versionPattern.hasMatch(value.trim());
  }

  bool _isValidUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  Future<Map<String, dynamic>> _loadUpdateSettings() async {
    try {
      final row = await supabase
          .from('v3_app_settings')
          .select(
            'latest_version_android, min_supported_version_android, force_update_android, store_url_android, '
            'latest_version_ios, min_supported_version_ios, force_update_ios, store_url_ios',
          )
          .eq('id', 'global')
          .maybeSingle();
      return row ?? <String, dynamic>{};
    } catch (e) {
      debugPrint('[AdminScreen] Greška pri učitavanju update settings: $e');
      return <String, dynamic>{};
    }
  }

  Future<void> _openUpdateVersionsEditor() async {
    final row = await _loadUpdateSettings();
    if (!mounted) return;

    final latestAndroidCtrl = TextEditingController(text: (row['latest_version_android'] ?? '').toString());
    final minAndroidCtrl = TextEditingController(text: (row['min_supported_version_android'] ?? '').toString());
    final urlAndroidCtrl = TextEditingController(text: (row['store_url_android'] ?? '').toString());

    final latestIosCtrl = TextEditingController(text: (row['latest_version_ios'] ?? '').toString());
    final minIosCtrl = TextEditingController(text: (row['min_supported_version_ios'] ?? '').toString());
    final urlIosCtrl = TextEditingController(text: (row['store_url_ios'] ?? '').toString());

    var forceAndroid = row['force_update_android'] == true;
    var forceIos = row['force_update_ios'] == true;
    var isSaving = false;
    final quickVersionCtrl = TextEditingController();

    Future<void> save(StateSetter setModalState, BuildContext modalContext) async {
      final latestAndroid = latestAndroidCtrl.text.trim();
      final minAndroidRaw = minAndroidCtrl.text.trim();
      final storeAndroid = urlAndroidCtrl.text.trim();

      final latestIosRaw = latestIosCtrl.text.trim();
      final minIosRaw = minIosCtrl.text.trim();
      final storeIos = urlIosCtrl.text.trim();

      final latestIos = latestIosRaw.isEmpty ? latestAndroid : latestIosRaw;

      final minAndroid = minAndroidRaw.isEmpty ? latestAndroid : minAndroidRaw;
      final minIos = minIosRaw.isEmpty ? latestIos : minIosRaw;

      String? error;

      if (!_isValidVersion(latestAndroid) || !_isValidVersion(minAndroid)) {
        error = 'Android verzija mora biti u formatu npr. 6.0.192';
      } else if (!_isValidVersion(latestIos) || !_isValidVersion(minIos)) {
        error = 'iOS verzija mora biti u formatu npr. 6.0.192';
      } else if (storeAndroid.isNotEmpty && !_isValidUrl(storeAndroid)) {
        error = 'Android Store URL nije validan';
      } else if (storeIos.isNotEmpty && !_isValidUrl(storeIos)) {
        error = 'iOS Store URL nije validan';
      }

      if (error != null) {
        ScaffoldMessenger.of(modalContext).showSnackBar(SnackBar(content: Text(error)));
        return;
      }

      setModalState(() => isSaving = true);
      try {
        await supabase.from('v3_app_settings').upsert({
          'id': 'global',
          'latest_version_android': latestAndroid,
          'min_supported_version_android': minAndroid,
          'force_update_android': forceAndroid,
          'store_url_android': storeAndroid,
          'latest_version_ios': latestIos,
          'min_supported_version_ios': minIos,
          'force_update_ios': forceIos,
          'store_url_ios': storeIos,
        });

        if (!mounted) return;
        Navigator.of(modalContext).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Update verzije sačuvane')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(modalContext).showSnackBar(
          SnackBar(content: Text('Greška pri čuvanju: $e')),
        );
      } finally {
        if (mounted) {
          setModalState(() => isSaving = false);
        }
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void applyQuickReleaseVersion() {
              final value = quickVersionCtrl.text.trim();
              if (!_isValidVersion(value)) {
                ScaffoldMessenger.of(modalContext).showSnackBar(
                  const SnackBar(content: Text('Unesi validnu verziju, npr. 6.0.192')),
                );
                return;
              }
              setModalState(() {
                latestAndroidCtrl.text = value;
                latestIosCtrl.text = value;
                minAndroidCtrl.text = value;
                minIosCtrl.text = value;
                forceAndroid = false;
                forceIos = false;
              });
            }

            void copyMinFromLatestAll() {
              setModalState(() {
                minAndroidCtrl.text = latestAndroidCtrl.text.trim();
                minIosCtrl.text = latestIosCtrl.text.trim();
              });
            }

            void forceOnAll() {
              setModalState(() {
                forceAndroid = true;
                forceIos = true;
              });
            }

            void forceOffAll() {
              setModalState(() {
                forceAndroid = false;
                forceIos = false;
              });
            }

            Widget section({
              required String title,
              required TextEditingController latest,
              required TextEditingController min,
              required TextEditingController store,
              required bool force,
              required ValueChanged<bool> onForceChanged,
            }) {
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: latest,
                      decoration: const InputDecoration(labelText: 'Latest version (npr. 6.0.192)'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: min,
                      decoration: const InputDecoration(labelText: 'Min supported version (prazno = latest)'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: store,
                      decoration: const InputDecoration(labelText: 'Store URL'),
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Force update'),
                      value: force,
                      onChanged: onForceChanged,
                    ),
                  ],
                ),
              );
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  top: 12,
                  bottom: MediaQuery.of(modalContext).viewInsets.bottom + 12,
                ),
                child: SizedBox(
                  height: MediaQuery.of(modalContext).size.height * 0.88,
                  child: Column(
                    children: [
                      const Text(
                        '🔄 Update verzije aplikacije',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: quickVersionCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Brza verzija za sve (npr. 6.0.192)',
                          helperText: 'Release svima: latest=min i force=off',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSaving ? null : applyQuickReleaseVersion,
                              child: const Text('Release svima'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSaving ? null : copyMinFromLatestAll,
                              child: const Text('Min = Latest (sve)'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSaving ? null : forceOnAll,
                              child: const Text('Force ON (sve)'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSaving ? null : forceOffAll,
                              child: const Text('Force OFF (sve)'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              section(
                                title: 'Android (Play Store)',
                                latest: latestAndroidCtrl,
                                min: minAndroidCtrl,
                                store: urlAndroidCtrl,
                                force: forceAndroid,
                                onForceChanged: (v) => setModalState(() => forceAndroid = v),
                              ),
                              section(
                                title: 'iOS (App Store)',
                                latest: latestIosCtrl,
                                min: minIosCtrl,
                                store: urlIosCtrl,
                                force: forceIos,
                                onForceChanged: (v) => setModalState(() => forceIos = v),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSaving ? null : () => Navigator.of(modalContext).pop(),
                              child: const Text('Otkaži'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isSaving ? null : () => save(setModalState, modalContext),
                              child: isSaving
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('Sačuvaj'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    latestAndroidCtrl.dispose();
    minAndroidCtrl.dispose();
    urlAndroidCtrl.dispose();
    latestIosCtrl.dispose();
    minIosCtrl.dispose();
    urlIosCtrl.dispose();
    quickVersionCtrl.dispose();
  }

  // ignore: unused_element
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
                  height: V3ContainerUtils.responsiveHeight(context, 4, intensity: 0.2),
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

  Map<String, int> _getUceniciBcVsSummary() {
    final grouped = _getUceniciSaDodeljenimVremenomDanasPoGradu();
    final bc = grouped['BC'] ?? const <String>[];
    final vsSet = (grouped['VS'] ?? const <String>[]).toSet();
    final bezVs = bc.where((ime) => !vsSet.contains(ime)).toList();

    return {
      'bcTotal': bc.length,
      'vsTotal': vsSet.length,
      'preostalo': bezVs.length,
    };
  }

  Map<String, List<String>> _getUceniciSaDodeljenimVremenomDanasPoGradu() {
    final rm = V3MasterRealtimeManager.instance;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final uceniciIds = rm.putniciCache.values
        .where((p) => (p['tip_putnika'] as String? ?? '').toLowerCase() == 'ucenik')
        .map((p) => p['id'] as String)
        .toSet();

    final bcNames = <String>{};
    final vsNames = <String>{};

    for (final r in rm.operativnaNedeljaCache.values) {
      final putnikId = r['putnik_id']?.toString();
      if (putnikId == null || !uceniciIds.contains(putnikId)) continue;
      if (r['aktivno'] != true) continue;

      final datumRaw = r['datum']?.toString();
      if (datumRaw == null || datumRaw.isEmpty) continue;
      final datum = DateTime.tryParse(datumRaw);
      if (datum == null) continue;
      final datumOnly = DateTime(datum.year, datum.month, datum.day);
      if (datumOnly != today) continue;

      final ime = (rm.putniciCache[putnikId]?['ime_prezime']?.toString() ?? '').trim();
      if (ime.isEmpty) continue;

      final grad = (r['grad']?.toString() ?? '').toUpperCase();
      if (grad == 'VS') {
        vsNames.add(ime);
        continue;
      }

      if (grad == 'BC') {
        if ((r['status_final']?.toString() ?? '') != 'odobreno') continue;
        final dodeljenoVreme = (r['dodeljeno_vreme']?.toString() ?? '').trim();
        if (dodeljenoVreme.isEmpty) continue;
        bcNames.add(ime);
      }
    }

    final bc = bcNames.toList()..sort();
    final vs = vsNames.toList()..sort();

    return {
      'BC': bc,
      'VS': vs,
    };
  }

  void _showUceniciDanasPopup(BuildContext context) {
    final grouped = _getUceniciSaDodeljenimVremenomDanasPoGradu();
    final bc = grouped['BC'] ?? const <String>[];
    final vsSet = (grouped['VS'] ?? const <String>[]).toSet();
    final bezVs = bc.where((ime) => !vsSet.contains(ime)).toList()..sort();

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colorScheme = theme.colorScheme;
        final onSurface = colorScheme.onSurface;

        return AlertDialog(
          backgroundColor: theme.dialogTheme.backgroundColor ?? colorScheme.surface,
          title: Text(
            'Učenici bez VS termina',
            style: theme.textTheme.titleMedium?.copyWith(
              color: onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Bez VS (${bezVs.length})',
                    style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    bezVs.isEmpty ? '— svi imaju VS termin —' : bezVs.join('\n'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: onSurface.withValues(alpha: 0.82),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Zatvori'),
            ),
          ],
        );
      },
    );
  }

  Map<String, int> _getDnevniBcVsSummary() {
    final grouped = _getDnevniSaDodeljenimVremenomDanasPoGradu();
    final bc = grouped['BC'] ?? const <String>[];
    final vsSet = (grouped['VS'] ?? const <String>[]).toSet();
    final bezVs = bc.where((ime) => !vsSet.contains(ime)).toList();

    return {
      'bcTotal': bc.length,
      'vsTotal': vsSet.length,
      'preostalo': bezVs.length,
    };
  }

  Map<String, List<String>> _getDnevniSaDodeljenimVremenomDanasPoGradu() {
    final rm = V3MasterRealtimeManager.instance;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final dnevniIds = rm.putniciCache.values
        .where((p) => (p['tip_putnika'] as String? ?? '').toLowerCase() == 'dnevni')
        .map((p) => p['id'] as String)
        .toSet();

    final bcNames = <String>{};
    final vsNames = <String>{};

    for (final r in rm.operativnaNedeljaCache.values) {
      final putnikId = r['putnik_id']?.toString();
      if (putnikId == null || !dnevniIds.contains(putnikId)) continue;
      if (r['aktivno'] != true) continue;

      final datumRaw = r['datum']?.toString();
      if (datumRaw == null || datumRaw.isEmpty) continue;
      final datum = DateTime.tryParse(datumRaw);
      if (datum == null) continue;
      final datumOnly = DateTime(datum.year, datum.month, datum.day);
      if (datumOnly != today) continue;

      final ime = (rm.putniciCache[putnikId]?['ime_prezime']?.toString() ?? '').trim();
      if (ime.isEmpty) continue;

      final grad = (r['grad']?.toString() ?? '').toUpperCase();
      if (grad == 'VS') {
        vsNames.add(ime);
        continue;
      }

      if (grad == 'BC') {
        if ((r['status_final']?.toString() ?? '') != 'odobreno') continue;
        final dodeljenoVreme = (r['dodeljeno_vreme']?.toString() ?? '').trim();
        if (dodeljenoVreme.isEmpty) continue;
        bcNames.add(ime);
      }
    }

    final bc = bcNames.toList()..sort();
    final vs = vsNames.toList()..sort();

    return {
      'BC': bc,
      'VS': vs,
    };
  }

  void _showDnevniDanasPopup(BuildContext context) {
    final grouped = _getDnevniSaDodeljenimVremenomDanasPoGradu();
    final bc = grouped['BC'] ?? const <String>[];
    final vsSet = (grouped['VS'] ?? const <String>[]).toSet();
    final bezVs = bc.where((ime) => !vsSet.contains(ime)).toList()..sort();

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colorScheme = theme.colorScheme;
        final onSurface = colorScheme.onSurface;

        return AlertDialog(
          backgroundColor: theme.dialogTheme.backgroundColor ?? colorScheme.surface,
          title: Text(
            'Dnevni bez VS termina',
            style: theme.textTheme.titleMedium?.copyWith(
              color: onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Bez VS (${bezVs.length})',
                    style: const TextStyle(color: Colors.deepOrangeAccent, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    bezVs.isEmpty ? '— svi imaju VS termin —' : bezVs.join('\n'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: onSurface.withValues(alpha: 0.82),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Zatvori'),
            ),
          ],
        );
      },
    );
  }

  /// Broj zahteva učenika na čekanju koje su učenici sami poslali
  int _getUceniciZahteviCount() {
    final rm = V3MasterRealtimeManager.instance;
    final uceniciIds = rm.putniciCache.values
        .where((p) => (p['tip_putnika'] as String? ?? '').toLowerCase() == 'ucenik')
        .map((p) => p['id'] as String)
        .toSet();

    return rm.zahteviCache.values.where((row) {
      if ((row['status']?.toString() ?? '') != 'obrada') return false;

      final putnikId = row['putnik_id']?.toString();
      if (putnikId == null || putnikId.isEmpty) return false;
      if (!uceniciIds.contains(putnikId)) return false;

      final createdBy = (row['created_by']?.toString() ?? '').trim();
      return createdBy.startsWith('putnik:');
    }).length;
  }

  int _getRadniciZahteviCount() {
    final rm = V3MasterRealtimeManager.instance;
    final radniciIds = rm.putniciCache.values
        .where((p) => (p['tip_putnika'] as String? ?? '').toLowerCase() == 'radnik')
        .map((p) => p['id'] as String)
        .toSet();

    return rm.zahteviCache.values.where((row) {
      if ((row['status']?.toString() ?? '') != 'obrada') return false;

      final putnikId = row['putnik_id']?.toString();
      if (putnikId == null || putnikId.isEmpty) return false;
      if (!radniciIds.contains(putnikId)) return false;

      final createdBy = (row['created_by']?.toString() ?? '').trim();
      return createdBy.startsWith('putnik:');
    }).length;
  }

  int _getZahteviCount() {
    final rm = V3MasterRealtimeManager.instance;
    return rm.zahteviCache.values.where((row) {
      if ((row['status']?.toString() ?? '') != 'obrada') return false;
      final putnikId = row['putnik_id']?.toString();
      if (putnikId == null || putnikId.isEmpty) return false;

      final putnik = rm.putniciCache[putnikId];
      final tip = (putnik?['tip_putnika'] as String? ?? '').toLowerCase();
      if (tip != 'dnevni') return false;

      final createdBy = (row['created_by']?.toString() ?? '').trim();
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
    return rm.zahteviCache.values.where((r) {
      if ((r['status']?.toString() ?? '') != 'obrada') return false;
      final putnikId = r['putnik_id']?.toString();
      if (putnikId == null || putnikId.isEmpty) return false;
      if (!posiljkaPutnici.contains(putnikId)) return false;

      final createdBy = (r['created_by']?.toString() ?? '').trim();
      return createdBy.startsWith('putnik:');
    }).length;
  }

  /// Učenici brojač: broj učenika bez VS termina danas.
  Widget _buildSaVsWidget(BuildContext context) {
    final stats = _getUceniciBcVsSummary();
    final bcTotal = stats['bcTotal'] ?? 0;
    final vsTotal = stats['vsTotal'] ?? 0;

    return GestureDetector(
      onTap: () => _showUceniciDanasPopup(context),
      child: Container(
        height: V3ContainerUtils.responsiveHeight(context, 50),
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
              '$bcTotal/$vsTotal',
              style: const TextStyle(
                color: Colors.orange,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Dnevni brojač: broj dnevnih putnika bez VS termina danas.
  Widget _buildDnevniSaVsWidget(BuildContext context) {
    final stats = _getDnevniBcVsSummary();
    final preostalo = stats['preostalo'] ?? 0;

    return GestureDetector(
      onTap: () => _showDnevniDanasPopup(context),
      child: Container(
        height: V3ContainerUtils.responsiveHeight(context, 50),
        decoration: BoxDecoration(
          color: Colors.deepOrange.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.7), width: 1.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$preostalo',
              style: const TextStyle(
                color: Colors.deepOrangeAccent,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: V3MasterRealtimeManager.instance.v3StreamFromCache<void>(
        tables: const ['v3_operativna_nedelja', 'v3_putnici', 'v3_zahtevi', 'v3_pin_zahtevi', 'v3_vozaci'],
        build: () {},
      ),
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
                    // 💺 Kapacitet termina
                    Expanded(
                      child: _NavBtn(
                        color: Colors.green,
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3KapacitetScreen(),
                        ),
                        child: const Text('💺', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 💹 Finasnije
                    Expanded(
                      child: _NavBtn(
                        color: Colors.indigo,
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3FinansijeScreen(),
                        ),
                        child: const Text('💹', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 🔧 Kolska knjga
                    Expanded(
                      child: _NavBtn(
                        color: Colors.brown,
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3OdrzavanjeScreen(),
                        ),
                        child: const Text('🔧', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 🔧 Raspored + dodatne opcije
                    Expanded(
                      child: ValueListenableBuilder<String>(
                        valueListenable: navBarTypeNotifier,
                        builder: (context, navType, _) {
                          const labels = {'zimski': '⚙️', 'letnji': '☀️', 'praznici': '🎉'};
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
                                    height: V3ContainerUtils.responsiveHeight(context, 28),
                                    child: Text('Tip rasporeda', style: TextStyle(color: Colors.white54, fontSize: 12)),
                                  ),
                                  const PopupMenuItem(
                                      value: 'zimski',
                                      child: Text('⚙️  Zimski', style: TextStyle(color: Colors.white))),
                                  const PopupMenuItem(
                                      value: 'letnji',
                                      child: Text('☀️  Ljetnji', style: TextStyle(color: Colors.white))),
                                  const PopupMenuItem(
                                      value: 'praznici',
                                      child: Text('🎉  Praznici', style: TextStyle(color: Colors.white))),
                                  const PopupMenuDivider(),
                                  const PopupMenuItem(
                                      value: '__vozaci__',
                                      child: Text('🚗  Vozači admin', style: TextStyle(color: Colors.white))),
                                ],
                              );
                              if (val == null) return;
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
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // ─── RED 2: Brojači (Učenici / Dnevni bez VS) ───
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Row(
                  children: [
                    Expanded(flex: 1, child: _buildSaVsWidget(context)),
                    const SizedBox(width: 6),
                    Expanded(flex: 1, child: _buildDnevniSaVsWidget(context)),
                  ],
                ),
              ),

              // ─── RED 3: Kalendar, Dnevnik, Putnici, Gorivo ───
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Row(
                  children: [
                    // 📅 Raspored
                    Expanded(
                      flex: 1,
                      child: _NavBtn(
                        color: Colors.blue,
                        height: V3ContainerUtils.responsiveHeight(context, 50),
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3AdminRasporedScreen(),
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '📅',
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
                    // Dnevnik naplate
                    Expanded(
                      flex: 1,
                      child: _NavBtn(
                        color: Colors.indigo,
                        height: V3ContainerUtils.responsiveHeight(context, 50),
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
                    // 👥 Putnici
                    Expanded(
                      flex: 1,
                      child: _NavBtn(
                        color: Colors.blueGrey,
                        height: V3ContainerUtils.responsiveHeight(context, 50),
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3PutniciScreen(),
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '👥',
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
                    // ⛽ Gorivo
                    Expanded(
                      flex: 1,
                      child: _NavBtn(
                        color: Colors.orange,
                        height: V3ContainerUtils.responsiveHeight(context, 50),
                        onTap: () => V3NavigationUtils.pushScreen<void>(
                          context,
                          const V3GorivoScreen(),
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '⛽',
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
                    Expanded(
                      flex: 1,
                      child: _NavBtn(
                        color: Colors.purple,
                        height: V3ContainerUtils.responsiveHeight(context, 50),
                        onTap: _openUpdateVersionsEditor,
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '🔄',
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
    // Dužnici = dnevni + pošiljke (naplata po pokupljenju)
    final dugovi = sveDugovi.where((d) => d.tipPutnika == 'dnevni' || d.tipPutnika == 'posiljka').toList();
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
            height: V3ContainerUtils.responsiveHeight(context, 56),
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
                  child: V3SafeText.userName(
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
            height: V3ContainerUtils.responsiveHeight(context, 52),
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
          height: V3ContainerUtils.responsiveHeight(context, 72),
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
    this.height,
  });

  final VoidCallback onTap;
  final Widget child;
  final Color color;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: height ?? V3ContainerUtils.responsiveHeight(context, 50),
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
            height: V3ContainerUtils.responsiveHeight(context, 50),
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
              constraints: BoxConstraints(
                minWidth: V3ContainerUtils.responsiveHeight(context, 20),
                minHeight: V3ContainerUtils.responsiveHeight(context, 20),
              ),
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
