import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/config_service.dart'; // ðŸ” Centralizovani kredencijali

/// ðŸŒ GLOBALNE VARIJABLE ZA GAVRA ANDROID
///
/// Ovaj fajl sadrÅ¾i globalne varijable koje se koriste kroz celu aplikaciju.
/// Kreiran je da bi se smanjilo coupling izmeÄ‘u servisa i main.dart fajla.

/// Global navigator key za pristup navigation context-u iz servisa
/// Koristi se u:
/// - permission_service.dart - za prikaz dijaloga za dozvole
/// - notification_navigation_service.dart - za navigaciju iz notifikacija
/// - v2_v2_local_notification_service.dart - za pristup context-u u background-u
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Globalna instanca Supabase klijenta
/// Koristi se u svim servisima umesto kreiranja novih instanci
/// ðŸ›¡ï¸ Koristi GETTER da izbegneÅ¡ crash pri library load-u pre Supabase.initialize()
SupabaseClient get supabase => Supabase.instance.client;

/// ðŸ›¡ï¸ Provera da li je Supabase spreman za rad (da ne bi pucao call stack)
bool get isSupabaseReady {
  try {
    Supabase.instance.client;
    return true;
  } catch (e) {
    if (kDebugMode) {
      // Izbegavamo previÅ¡e spama ali logujemo problem jednom
      debugPrint('âš ï¸ [Globals] Supabase client NOT ready: $e');
    }
    return false;
  }
}

/// ðŸšŒ NAV BAR TYPE - tip bottom navigation bara
/// 'zimski' = zimski raspored
/// 'letnji' = letnji raspored
/// 'praznici' = prazniÄni raspored
final ValueNotifier<String> navBarTypeNotifier = ValueNotifier<String>('letnji');

/// â„ï¸ ZIMSKI MOD - Proverava da li je zimski red voÅ¾nje aktivan SADA
bool get isWinter => navBarTypeNotifier.value == 'zimski';

/// ðŸŽ„ PRAZNIÄŒNI MOD - specijalni red voÅ¾nje (DEPRECATED - koristi navBarTypeNotifier)
/// Kada je true, koristi se BottomNavBarPraznici sa smanjenim brojem polazaka
/// BC: 5:00, 6:00, 12:00, 13:00, 15:00
/// VS: 6:00, 7:00, 13:00, 14:00, 15:30
final ValueNotifier<bool> praznicniModNotifier = ValueNotifier<bool>(false);

/// Helper za proveru prazniÄnog moda
bool get isPraznicniMod => praznicniModNotifier.value;

/// ðŸ” GLOBALNA INSTANCA CONFIG SERVICE
/// Centralizovano upravljanje svim kredencijalima i konfiguracijom
/// Koristi se u celoj aplikaciji za pristup kredencijalima
final ConfigService configService = ConfigService();

/// ðŸ”„ UPDATE INFO - informacije o dostupnom update-u
/// null = nema update-a, ili joÅ¡ nije provereno
class UpdateInfo {
  final String latestVersion;
  final String storeUrl;
  final bool isForced; // true = korisnik mora da aÅ¾urira, false = opciono

  const UpdateInfo({
    required this.latestVersion,
    required this.storeUrl,
    required this.isForced,
  });
}

/// Notifier koji se puni u AppSettingsService nakon provere verzije
final ValueNotifier<UpdateInfo?> updateInfoNotifier = ValueNotifier<UpdateInfo?>(null);


