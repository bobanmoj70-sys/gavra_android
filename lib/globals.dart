import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config_service.dart';
import 'services/v3/v3_app_settings_state.dart';
import 'utils/v3_belgrade_time.dart';
import 'utils/v3_dan_helper.dart';

export 'utils/v3_dan_helper.dart';

void initDanHelperGlobals() {
  V3DanHelper.getGlobalOperativnaNedeljaStart = () => V3AppSettingsState.instance.activeWeekStartValue;
  V3DanHelper.getGlobalOperativnaNedeljaEnd = () => V3AppSettingsState.instance.activeWeekEndValue;
}

/// Globalne varijable za Gavra Android
///
/// Ovaj fajl sadrzi globalne varijable koje se koriste kroz celu aplikaciju.
/// Kreiran je da bi se smanjilo coupling izmedju servisa i main.dart fajla.

/// Global navigator key for navigation context from services / notification taps.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Globalna instanca Supabase klijenta
/// Koristi se u svim servisima umesto kreiranja novih instanci
/// > Koristi GETTER da izbegneš crash pri library load-u pre Supabase.initialize()
SupabaseClient get supabase => Supabase.instance.client;

/// > Provera da li je Supabase spreman za rad (da ne bi pucao call stack)
bool get isSupabaseReady {
  try {
    Supabase.instance.client;
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> ensureSupabaseReady() async {
  if (isSupabaseReady) {
    debugPrint('[ensureSupabaseReady] Already ready');
    return true;
  }

  try {
    debugPrint('[ensureSupabaseReady] Initializing config...');
    await configService.initializeBasic();
    debugPrint('[ensureSupabaseReady] Config initialized: ${configService.isInitialized}');

    if (isSupabaseReady) return true;

    final url = configService.getSupabaseUrl().trim();
    final anonKey = configService.getSupabaseAnonKey().trim();
    debugPrint('[ensureSupabaseReady] URL empty: ${url.isEmpty}, AnonKey empty: ${anonKey.isEmpty}');

    if (url.isEmpty || anonKey.isEmpty) {
      debugPrint('[ensureSupabaseReady] Missing credentials!');
      return false;
    }

    debugPrint('[ensureSupabaseReady] Initializing Supabase...');
    await Supabase.initialize(url: url, anonKey: anonKey);
    debugPrint('[ensureSupabaseReady] Supabase initialized: $isSupabaseReady');
    return isSupabaseReady;
  } catch (e) {
    debugPrint('[ensureSupabaseReady] Error: $e');
    return isSupabaseReady;
  }
}

/// NAV BAR TYPE - tip bottom navigation bara
/// Podržan je isključivo `custom` raspored.
final ValueNotifier<String> navBarTypeNotifier = ValueNotifier<String>('custom');

const List<String> _customWorkdayNames = ['Ponedeljak', 'Utorak', 'Sreda', 'Cetvrtak', 'Petak'];

Map<String, List<String>> _emptyCustomDayMap() => {
      for (final day in _customWorkdayNames) day: <String>[],
    };

/// CUSTOM RASPORED PO DANIMA - vremena polazaka za radne dane
/// Struktura: {'bc': {'Ponedeljak': [...], ...}, 'vs': {'Ponedeljak': [...], ...}}
final ValueNotifier<Map<String, Map<String, List<String>>>> customRasporedByDayNotifier =
    ValueNotifier<Map<String, Map<String, List<String>>>>({
  'bc': _emptyCustomDayMap(),
  'vs': _emptyCustomDayMap(),
});

/// NERADNI DANI - lista pravila iz v3_app_settings.neradni_dani
/// Očekivani format svakog unosa:
/// {"date":"yyyy-MM-dd", "scope":"all|bc|vs", "reason":"..."}
final ValueNotifier<List<Map<String, String>>> neradniDaniNotifier = ValueNotifier<List<Map<String, String>>>([]);

String _normalizeNeradanScope(String? raw) {
  final scope = (raw ?? 'all').trim().toLowerCase();
  if (scope == 'bc' || scope == 'vs') return scope;
  return 'all';
}

List<Map<String, String>> _parseNeradniDani(dynamic raw) {
  if (raw is! List) return <Map<String, String>>[];

  final out = <Map<String, String>>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final parsed = V3BelgradeTime.parseDatum((item['date'] ?? '').toString().trim());
    if (parsed == null) continue;
    final dateIso = V3BelgradeTime.toIsoDate(parsed);

    out.add({
      'date': dateIso,
      'scope': _normalizeNeradanScope(item['scope']?.toString()),
      'reason': (item['reason'] ?? '').toString().trim(),
    });
  }

  return out;
}

void applyNeradniDaniFromSettings(dynamic raw) {
  neradniDaniNotifier.value = _parseNeradniDani(raw);
}

String? getNeradanDanRazlog({
  required String datumIso,
  String? grad,
}) {
  final normalizedDate = datumIso.trim();
  if (normalizedDate.length != 10) return null;

  final normalizedGrad = (grad ?? '').trim().toLowerCase();
  for (final rule in neradniDaniNotifier.value) {
    if (rule['date'] != normalizedDate) continue;

    final scope = _normalizeNeradanScope(rule['scope']);
    final scopeMatches = scope == 'all' || (normalizedGrad.isNotEmpty && scope == normalizedGrad);
    if (!scopeMatches) continue;

    final reason = (rule['reason'] ?? '').trim();
    return reason.isEmpty ? 'Neradan dan' : reason;
  }

  return null;
}

String? getNeradanDanRazlogZaDan({
  required String day,
  String? grad,
  DateTime? anchor,
}) {
  final normalizedDay = V3DanHelper.normalizeToWorkdayFull(day);
  if (normalizedDay.isEmpty) return null;

  final datumIso = V3DanHelper.datumIsoZaDanPuniUTekucojSedmici(
    normalizedDay,
    anchor: anchor ?? V3DanHelper.schedulingWeekAnchor(),
  );
  if (datumIso.isEmpty) return null;
  return getNeradanDanRazlog(datumIso: datumIso, grad: grad);
}

bool isNeradanDan({
  required String datumIso,
  String? grad,
}) {
  return getNeradanDanRazlog(datumIso: datumIso, grad: grad) != null;
}

/// INFO BANNER - jedna admin-kontrolisana poruka prikazana kroz V3InfoBanner.
/// Očekivani format iz v3_app_settings.info_banner:
/// {
///   "enabled": true,
///   "title": "Obaveštenje",
///   "message": "...",
///   "color": "amber|blue|red|green",
///   "audience": ["svi"] | ["putnici"] | ["vozaci"] | ["radnici"] | ["ucenici"] | kombinacija
/// }
class V3InfoBannerData {
  final bool enabled;
  final String title;
  final String message;
  final String color;
  final List<String> audience;

  const V3InfoBannerData({
    this.enabled = false,
    this.title = '',
    this.message = '',
    this.color = 'amber',
    this.audience = const ['svi'],
  });

  bool get isVisible => enabled && title.trim().isNotEmpty && message.trim().isNotEmpty;
}

final ValueNotifier<V3InfoBannerData> infoBannerNotifier = ValueNotifier<V3InfoBannerData>(const V3InfoBannerData());

List<String> _parseInfoBannerAudience(dynamic raw) {
  if (raw == null) return const ['svi'];
  if (raw is List) {
    final list = raw.map((e) => e.toString().trim().toLowerCase()).where((s) => s.isNotEmpty).toList();
    return list.isEmpty ? const ['svi'] : List.unmodifiable(list);
  }
  final single = raw.toString().trim().toLowerCase();
  return single.isEmpty ? const ['svi'] : List.unmodifiable([single]);
}

V3InfoBannerData _parseInfoBanner(dynamic raw) {
  if (raw is! Map) return const V3InfoBannerData();

  final enabled = raw['enabled'] == true;
  final title = (raw['title'] ?? '').toString().trim();
  final message = (raw['message'] ?? '').toString().trim();
  final color = (raw['color'] ?? 'amber').toString().trim().toLowerCase();

  return V3InfoBannerData(
    enabled: enabled,
    title: title,
    message: message,
    color: color.isEmpty ? 'amber' : color,
    audience: _parseInfoBannerAudience(raw['audience']),
  );
}

void applyInfoBannerFromSettings(dynamic raw) {
  infoBannerNotifier.value = _parseInfoBanner(raw);
}

/// Helper - vraća listu polazaka za grad iz dnevnog custom rasporeda.
/// Parametar [sezona] je zadržan samo radi kompatibilnosti pozivaoca.
List<String> getRasporedVremena(String grad, String sezona, {String? day}) {
  final normalizedGrad = grad.toLowerCase();

  if (day != null && day.trim().isNotEmpty) {
    final normalizedDay = V3DanHelper.normalizeToWorkdayFull(day);
    if (normalizedDay.isNotEmpty) {
      final datumIso = V3DanHelper.datumIsoZaDanPuniUTekucojSedmici(
        normalizedDay,
        anchor: V3DanHelper.schedulingWeekAnchor(),
      );
      if (datumIso.isNotEmpty && isNeradanDan(datumIso: datumIso, grad: normalizedGrad)) {
        return <String>[];
      }
    }
  }

  final cityMap = customRasporedByDayNotifier.value[normalizedGrad];

  if (day != null && day.trim().isNotEmpty) {
    final normalizedDay = V3DanHelper.normalizeToWorkdayFull(day);
    if (normalizedDay.isNotEmpty && cityMap != null) {
      final dayTimes = cityMap[normalizedDay];
      if (dayTimes != null && dayTimes.isNotEmpty) {
        return dayTimes;
      }
    }
  }

  return <String>[];
}

/// Globalna instanca Config Service — .env kredencijali (Android + iOS)
final AppConfigService configService = AppConfigService();

enum V3StartupPhase {
  booting,
  dbReady,
  realtimeReady,
  degraded,
}

final ValueNotifier<V3StartupPhase> startupPhaseNotifier = ValueNotifier<V3StartupPhase>(V3StartupPhase.booting);

/// Forced update / maintenance banner payload
class AppUpdateInfo {
  final String latestVersion;
  final String storeUrl;
  final bool isForced;
  final bool isMaintenance;
  final String maintenanceTitle;
  final String maintenanceMessage;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.storeUrl,
    required this.isForced,
    this.isMaintenance = false,
    this.maintenanceTitle = '',
    this.maintenanceMessage = '',
  });
}

/// Notifier koji se puni nakon provere verzije samo kada postoji obavezni update
final ValueNotifier<AppUpdateInfo?> updateInfoNotifier = ValueNotifier<AppUpdateInfo?>(null);

/// APP SETTINGS ACTIVE WEEK START NOTIFIER - runtime izvor istine iz `v3_app_settings`.
/// Sadrži početak (Ponedeljak) operativne sedmice isključivo iz baze.
ValueNotifier<DateTime?> get appSettingsActiveWeekStartNotifier => V3AppSettingsState.instance.activeWeekStart;

/// APP SETTINGS ACTIVE WEEK END NOTIFIER - runtime izvor istine iz `v3_app_settings`.
/// Sadrži kraj operativne sedmice isključivo iz baze.
ValueNotifier<DateTime?> get appSettingsActiveWeekEndNotifier => V3AppSettingsState.instance.activeWeekEnd;

/// Koliko dugo se poslednji ETA red čuva u bazi kada vozač prestane da šalje
/// tickove (npr. ugasio app). Putnik i dalje vidi poslednju poznatu ETA.
/// Uskladiti sa tracking prozorom T-15..T+40 (55 min) i
/// ETA_RETENTION_SECONDS u v3-compute-eta edge funkciji.
///
/// NAPOMENA: putnički UI (V3VremeDolaskaWidget) NE koristi starost computed_at
/// za sakrivanje ETA — prikazuje poslednju ETA dok traje tracking prozor
/// termina i dok putnik nije pokupljen/otkazan.
const Duration etaRetentionDuration = Duration(minutes: 55);

/// PRIVREMENI TEST FLAG - kada je true, klik na "Start" NEĆE poslati push
/// notifikaciju putnicima da je vozač krenuo. Koristi se za lično testiranje
/// OSRM/ETA logike bez lažnog obaveštavanja putnika.
/// VAŽNO: Vrati na `false` pre puštanja u produkciju!
const bool kDisableDriverStartPushForTesting = false;
