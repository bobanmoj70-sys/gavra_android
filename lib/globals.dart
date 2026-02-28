?import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/v2_config_service.dart'; // ?? Centralizovani kredencijali

/// �YO� GLOBALNE VARIJABLE ZA GAVRA ANDROID
///
/// Ovaj fajl sadrži globalne varijable koje se koriste kroz celu aplikaciju.
/// Kreiran je da bi se smanjilo coupling izme�'u servisa i main.dart fajla.

/// Global navigator key za pristup navigation context-u iz servisa
/// Koristi se u:
/// - permission_service.dart - za prikaz dijaloga za dozvole
/// - notification_navigation_service.dart - za navigaciju iz notifikacija
/// - v2_local_notification_service.dart - za pristup context-u u background-u
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Globalna instanca Supabase klijenta
/// Koristi se u svim servisima umesto kreiranja novih instanci
/// �Y>�️ Koristi GETTER da izbegneš crash pri library load-u pre Supabase.initialize()
SupabaseClient get supabase => Supabase.instance.client;

/// �Y>�️ Provera da li je Supabase spreman za rad (da ne bi pucao call stack)
bool get isSupabaseReady {
  try {
    Supabase.instance.client;
    return true;
  } catch (e) {
    if (kDebugMode) {
      // Izbegavamo previše spama ali logujemo problem jednom
      debugPrint('�s�️ [Globals] Supabase client NOT ready: $e');
    }
    return false;
  }
}

/// �YsO NAV BAR TYPE - tip bottom navigation bara
/// 'zimski' = zimski raspored
/// 'letnji' = letnji raspored
/// 'praznici' = praznični raspored
final ValueNotifier<String> navBarTypeNotifier = ValueNotifier<String>('letnji');

/// �"️ ZIMSKI MOD - Proverava da li je zimski red vožnje aktivan SADA
bool get isWinter => navBarTypeNotifier.value == 'zimski';

/// �YZ" PRAZNI�ONI MOD - specijalni red vožnje (DEPRECATED - koristi navBarTypeNotifier)
/// Kada je true, koristi se BottomNavBarPraznici sa smanjenim brojem polazaka
/// BC: 5:00, 6:00, 12:00, 13:00, 15:00
/// VS: 6:00, 7:00, 13:00, 14:00, 15:30
final ValueNotifier<bool> praznicniModNotifier = ValueNotifier<bool>(false);

/// Helper za proveru prazničnog moda
bool get isPraznicniMod => praznicniModNotifier.value;

/// �Y"� GLOBALNA INSTANCA CONFIG SERVICE
/// Centralizovano upravljanje svim kredencijalima i konfiguracijom
/// Koristi se u celoj aplikaciji za pristup kredencijalima
final ConfigService configService = ConfigService();

/// �Y"" UPDATE INFO - informacije o dostupnom update-u
/// null = nema update-a, ili još nije provereno
class UpdateInfo {
  final String latestVersion;
  final String storeUrl;
  final bool isForced; // true = korisnik mora da ažurira, false = opciono

  const UpdateInfo({
    required this.latestVersion,
    required this.storeUrl,
    required this.isForced,
  });
}

/// Notifier koji se puni u AppSettingsService nakon provere verzije
final ValueNotifier<UpdateInfo?> updateInfoNotifier = ValueNotifier<UpdateInfo?>(null);
