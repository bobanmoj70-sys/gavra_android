import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/v2_config_service.dart'; // Centralizovani kredencijali
import 'utils/v3_dan_helper.dart';

export 'utils/v3_dan_helper.dart';

/// Globalne varijable za Gavra Android
///
/// Ovaj fajl sadrzi globalne varijable koje se koriste kroz celu aplikaciju.
/// Kreiran je da bi se smanjilo coupling izmedju servisa i main.dart fajla.

/// Global navigator key za pristup navigation context-u iz servisa
/// Koristi se u:
/// - permission_service.dart - za prikaz dijaloga za dozvole
/// - notification_navigation_service.dart - za navigaciju iz notifikacija
/// - v2_local_notification_service.dart - za pristup context-u u background-u
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

/// NAV BAR TYPE - tip bottom navigation bara
/// 'zimski' = zimski raspored
/// 'letnji' = letnji raspored
/// 'praznici' = praznični raspored
/// 'custom' = ručno podešen raspored
final ValueNotifier<String> navBarTypeNotifier = ValueNotifier<String>('');

const Set<String> _allowedNavBarTypes = {'zimski', 'letnji', 'praznici', 'custom'};

DateTime? _parseSettingsDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String && value.trim().isNotEmpty) return DateTime.tryParse(value);
  return null;
}

/// Računa efektivni nav bar tip iz v3_app_settings.
///
/// Pravila:
/// - Ako postoji validan `nextType` i `effectiveAt` je prošao, vraća `nextType`.
/// - U suprotnom vraća validan `currentType`.
/// - Ako nijedan nije validan, vraća null.
String? resolveEffectiveNavBarType({
  required String? currentType,
  String? nextType,
  dynamic effectiveAt,
  DateTime? now,
}) {
  final current = currentType?.toLowerCase();
  final next = nextType?.toLowerCase();
  final effective = _parseSettingsDateTime(effectiveAt);
  final tsNow = now ?? DateTime.now();

  if (next != null && _allowedNavBarTypes.contains(next) && effective != null && !tsNow.isBefore(effective)) {
    return next;
  }

  if (current != null && _allowedNavBarTypes.contains(current)) {
    return current;
  }

  return null;
}

/// RASPORED NOTIFIER - vremena polazaka iz baze (v3_app_settings)
/// Ključevi: 'bc_zimski', 'vs_zimski', 'bc_letnji', 'vs_letnji', 'bc_praznici', 'vs_praznici', 'bc_custom', 'vs_custom'
/// Puni se pri startu i ažurira realtime kad admin promeni rasporede u bazi
final ValueNotifier<Map<String, List<String>>> rasporedNotifier = ValueNotifier<Map<String, List<String>>>({
  'bc_zimski': ['05:00', '06:00', '07:00', '08:00', '09:00', '11:00', '12:00', '13:00', '14:00', '15:30', '18:00'],
  'vs_zimski': ['06:00', '07:00', '08:00', '10:00', '11:00', '12:00', '13:00', '14:00', '15:30', '17:00', '19:00'],
  'bc_letnji': ['05:00', '06:00', '07:00', '08:00', '11:00', '12:00', '13:00', '14:00', '15:30', '18:00'],
  'vs_letnji': ['06:00', '07:00', '08:00', '10:00', '11:00', '12:00', '13:00', '14:00', '15:30', '18:00'],
  'bc_praznici': ['05:00', '06:00', '12:00', '13:00', '15:00'],
  'vs_praznici': ['06:00', '07:00', '13:00', '14:00', '15:30'],
  'bc_custom': [],
  'vs_custom': [],
});

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
    final dateIso = V3DanHelper.parseIsoDatePart((item['date'] ?? '').toString());
    if (dateIso.length != 10) continue;

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
  final normalizedDate = V3DanHelper.parseIsoDatePart(datumIso);
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
  final normalizedDay = V3DanHelper.normalizeToWorkdayFull(day, fallback: '');
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

/// Helper - vraća listu polazaka za grad i sezonu iz rasporedNotifier.
/// Kada je sezona `custom` i prosleđen je [day], čita iz dnevnog custom rasporeda.
List<String> getRasporedVremena(String grad, String sezona, {String? day}) {
  final normalizedGrad = grad.toLowerCase();
  final normalizedSezona = sezona.toLowerCase();

  if (day != null && day.trim().isNotEmpty) {
    final normalizedDay = V3DanHelper.normalizeToWorkdayFull(day, fallback: '');
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

  if (normalizedSezona == 'custom') {
    final cityMap = customRasporedByDayNotifier.value[normalizedGrad];

    if (day != null && day.trim().isNotEmpty) {
      final normalizedDay = V3DanHelper.normalizeToWorkdayFull(day, fallback: '');
      if (normalizedDay.isNotEmpty && cityMap != null) {
        final dayTimes = cityMap[normalizedDay];
        if (dayTimes != null && dayTimes.isNotEmpty) {
          return dayTimes;
        }
      }
    }

    return <String>[];
  }

  final key = '${grad.toLowerCase()}_${sezona.toLowerCase()}';
  return rasporedNotifier.value[key] ?? [];
}

/// ZIMSKI MOD - Proverava da li je zimski red voznje aktivan SADA
bool get isWinter => navBarTypeNotifier.value == 'zimski';

/// PRAZNICNI MOD - specijalni red voznje (DEPRECATED - koristi navBarTypeNotifier)
/// Kada je true, koristi se V2BottomNavBarPraznici sa smanjenim brojem polazaka
/// BC: 5:00, 6:00, 12:00, 13:00, 15:00
/// VS: 6:00, 7:00, 13:00, 14:00, 15:30
@Deprecated('Koristi navBarTypeNotifier umesto praznicniModNotifier')
final ValueNotifier<bool> praznicniModNotifier = ValueNotifier<bool>(false);

/// Helper za proveru prazničnog moda
@Deprecated('Koristi navBarTypeNotifier.value == "praznici" umesto isPraznicniMod')
bool get isPraznicniMod => praznicniModNotifier.value;

/// Globalna instanca Config Service
/// Centralizovano upravljanje svim kredencijalima i konfiguracijom
/// Koristi se u celoj aplikaciji za pristup kredencijalima
final V2ConfigService configService = V2ConfigService();

/// UPDATE INFO - informacije o obaveznom update-u
/// null = nema obaveznog update-a, ili još nije provereno
class V2UpdateInfo {
  final String latestVersion;
  final String storeUrl;
  final bool isForced; // true = korisnik mora da ažurira (u forced-only toku očekivano true)
  final bool isMaintenance;
  final String maintenanceTitle;
  final String maintenanceMessage;

  const V2UpdateInfo({
    required this.latestVersion,
    required this.storeUrl,
    required this.isForced,
    this.isMaintenance = false,
    this.maintenanceTitle = '',
    this.maintenanceMessage = '',
  });
}

/// Notifier koji se puni nakon provere verzije samo kada postoji obavezni update
final ValueNotifier<V2UpdateInfo?> updateInfoNotifier = ValueNotifier<V2UpdateInfo?>(null);
