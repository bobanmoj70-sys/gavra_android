import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/v2_route_config.dart';
import '../globals.dart';
import '../utils/v2_grad_adresa_validator.dart';
import 'realtime/v2_master_realtime_manager.dart';

/// Servis za upravljanje kapacitetom polazaka.
/// Cache se čita direktno iz V2MasterRealtimeManager — nema vlastitog DB upita.
class V2KapacitetService {
  /// Vremena polazaka za Belu Crkvu (prema navBarType)
  static List<String> get bcVremena {
    final navType = navBarTypeNotifier.value;
    if (navType == 'praznici') {
      return RouteConfig.bcVremenaPraznici;
    } else if (navType == 'zimski') {
      return RouteConfig.bcVremenaZimski;
    } else {
      return RouteConfig.bcVremenaLetnji;
    }
  }

  /// Vremena polazaka za Vrsac (prema navBarType)
  static List<String> get vsVremena {
    final navType = navBarTypeNotifier.value;
    if (navType == 'praznici') {
      return RouteConfig.vsVremenaPraznici;
    } else if (navType == 'zimski') {
      return RouteConfig.vsVremenaZimski;
    } else {
      return RouteConfig.vsVremenaLetnji;
    }
  }

  /// Sva moguca vremena (zimska + letnja + praznicna) - za kapacitet tabelu
  static List<String> get svaVremenaBc {
    return {...RouteConfig.bcVremenaZimski, ...RouteConfig.bcVremenaLetnji, ...RouteConfig.bcVremenaPraznici}.toList();
  }

  static List<String> get svaVremenaVs {
    return {...RouteConfig.vsVremenaZimski, ...RouteConfig.vsVremenaLetnji, ...RouteConfig.vsVremenaPraznici}.toList();
  }

  /// Dohvati vremena za grad (sezonski)
  static List<String> getVremenaZaGrad(String grad) {
    if (grad == 'BC') {
      return bcVremena;
    } else if (grad == 'VS') {
      return vsVremena;
    }
    return bcVremena; // default
  }

  /// Dohvati sva moguca vremena za grad (obe sezone) - za kapacitet tabelu
  static List<String> getSvaVremenaZaGrad(String grad) {
    if (grad == 'BC') {
      return svaVremenaBc;
    } else if (grad == 'VS') {
      return svaVremenaVs;
    }
    return svaVremenaBc; // default
  }

  /// Admin: Promeni kapacitet za odredeni polazak (atomski upsert — nema race condition)
  static Future<bool> setKapacitet(String grad, String vreme, int maxMesta) async {
    try {
      await supabase.from('v2_kapacitet_polazaka').upsert(
        {'grad': grad, 'vreme': vreme, 'max_mesta': maxMesta},
        onConflict: 'grad,vreme',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Dohvati kapacitet za sve gradove — iz rm.kapacitetCache (nema DB upita).
  /// Format: {'BC': {'06:00': 8, '07:00': 10, ...}, 'VS': {...}}
  static Map<String, Map<String, int>> getKapacitet() {
    final rm = V2MasterRealtimeManager.instance;
    final result = <String, Map<String, int>>{'BC': {}, 'VS': {}};
    for (final row in rm.kapacitetCache.values) {
      final grad = row['grad'] as String? ?? '';
      final vreme = row['vreme'] as String? ?? '';
      final maxMesta = (row['max_mesta'] as int?) ?? 8;
      if (grad == 'BC' || grad == 'VS') {
        result[grad]![vreme] = maxMesta;
      }
    }
    return result;
  }

  /// Stream kapaciteta — emituje iz rm.kapacitetCache, nema DB upita
  static Stream<Map<String, Map<String, int>>> streamKapacitet() {
    final rm = V2MasterRealtimeManager.instance;
    final controller = StreamController<Map<String, Map<String, int>>>.broadcast();

    void emit() {
      if (!controller.isClosed) controller.add(getKapacitet());
    }

    controller.onListen = emit; // emituj tek kad listener postoji
    final sub = rm.subscribe('v2_kapacitet_polazaka').listen((_) => emit());
    controller.onCancel = () {
      sub.cancel();
      rm.unsubscribe('v2_kapacitet_polazaka');
    };
    return controller.stream;
  }

  /// Dohvati kapacitet za grad/vreme (čita iz rm.kapacitetCache — nema DB upita).
  /// Vraca default 8 ako nije dostupno.
  static int getKapacitetSync(String grad, String vreme) {
    final normalizedVreme = GradAdresaValidator.normalizeTime(vreme);
    final gradKey = grad == 'BC' ? 'BC' : 'VS';

    final rm = V2MasterRealtimeManager.instance;
    for (final row in rm.kapacitetCache.values) {
      final rowGrad = row['grad'] as String? ?? '';
      final rawVreme = row['vreme'] as String? ?? '';
      if (rowGrad == gradKey && GradAdresaValidator.normalizeTime(rawVreme) == normalizedVreme) {
        return (row['max_mesta'] as int?) ?? 8;
      }
    }
    return 8;
  }

  /// Inicijalizuj cache pri startu — sada je no-op jer rm vec ucitava kapacitetCache.
  static Future<void> initializeKapacitetCache() async {
    // rm.initialize() je vec ucitao kapacitetCache — nema posla ovde.
    if (kDebugMode) debugPrint('ℹ️ [V2KapacitetService] initializeKapacitetCache: no-op (rm handles cache)');
  }

  /// Zaustavi globalni listener — sada je no-op jer rm drzi kanal stalno.
  static void stopGlobalRealtimeListener() {
    // no-op: rm drzi v2_kapacitet_polazaka kanal stalno.
  }
}
