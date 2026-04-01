import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/v2_config_service.dart'; // Centralizovani kredencijali

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
final ValueNotifier<String> navBarTypeNotifier = ValueNotifier<String>('');

/// RASPORED NOTIFIER - vremena polazaka iz baze (v3_app_settings)
/// Ključevi: 'bc_zimski', 'vs_zimski', 'bc_letnji', 'vs_letnji', 'bc_praznici', 'vs_praznici'
/// Puni se pri startu i ažurira realtime kad admin promeni rasporede u bazi
final ValueNotifier<Map<String, List<String>>> rasporedNotifier = ValueNotifier<Map<String, List<String>>>({
  'bc_zimski': ['05:00', '06:00', '07:00', '08:00', '09:00', '11:00', '12:00', '13:00', '14:00', '15:30', '18:00'],
  'vs_zimski': ['06:00', '07:00', '08:00', '10:00', '11:00', '12:00', '13:00', '14:00', '15:30', '17:00', '19:00'],
  'bc_letnji': ['05:00', '06:00', '07:00', '08:00', '11:00', '12:00', '13:00', '14:00', '15:30', '18:00'],
  'vs_letnji': ['06:00', '07:00', '08:00', '10:00', '11:00', '12:00', '13:00', '14:00', '15:30', '18:00'],
  'bc_praznici': ['05:00', '06:00', '12:00', '13:00', '15:00'],
  'vs_praznici': ['06:00', '07:00', '13:00', '14:00', '15:30'],
});

/// Helper - vraća listu polazaka za grad i sezonu iz rasporedNotifier
List<String> getRasporedVremena(String grad, String sezona) {
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

  const V2UpdateInfo({
    required this.latestVersion,
    required this.storeUrl,
    required this.isForced,
  });
}

/// Notifier koji se puni nakon provere verzije samo kada postoji obavezni update
final ValueNotifier<V2UpdateInfo?> updateInfoNotifier = ValueNotifier<V2UpdateInfo?>(null);
