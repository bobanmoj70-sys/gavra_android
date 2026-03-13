import 'package:gavra_android/models/v3_gorivo.dart';
import 'package:gavra_android/services/realtime/v3_master_realtime_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class V3GorivoService {
  static final _supabase = Supabase.instance.client;

  /// Dobavlja stanje sa pumpe (V3 tabela: v3_gorivo_stanje)
  /// Samo jedan red u bazi.
  static V3GorivoStanje getStanjeSync() {
    final cache = V3MasterRealtimeManager.instance.getCache('v3_gorivo_stanje');
    if (cache.isEmpty) return V3GorivoStanje(kolicina: 0, updatedAt: DateTime.now());
    return V3GorivoStanje.fromJson(cache.values.first);
  }

  /// Dobavlja sva punjenja pumpe (V3 tabela: v3_gorivo_punjenja)
  static List<V3PumpaPunjenje> getPunjenjaSync() {
    final cache = V3MasterRealtimeManager.instance.getCache('v3_gorivo_punjenja');
    final list = cache.values.map((v) => V3PumpaPunjenje.fromJson(v)).toList();
    list.sort((a, b) => b.datum.compareTo(a.datum));
    return list;
  }

  /// Dobavlja sva točenja u vozila (V3 tabela: v3_gorivo_tocenja)
  static List<V3PumpaTocenje> getTocenjaSync() {
    final cache = V3MasterRealtimeManager.instance.getCache('v3_gorivo_tocenja');
    final list = cache.values.map((v) => V3PumpaTocenje.fromJson(v)).toList();
    list.sort((a, b) => b.datum.compareTo(a.datum));
    return list;
  }

  /// -- AKCIJE --

  /// Registruje punjenje pumpe (cisterna stigla)
  /// Povećava kolicinu u v3_gorivo_stanje
  static Future<void> addPunjenje(double kolicina, String dobavljac, String opis) async {
    // 1. Dodaj punjenje u tabelu
    await _supabase.from('v3_gorivo_punjenja').insert({
      'kolicina': kolicina,
      'dobavljac': dobavljac,
      'opis': opis,
      'datum': DateTime.now().toIso8601String(),
    });

    // 2. Ažuriraj stanje (pretpostavljamo da imamo proceduru ili read-modify-write)
    final stanje = getStanjeSync();
    await _supabase
        .from('v3_gorivo_stanje')
        .update({'kolicina': stanje.kolicina + kolicina, 'updated_at': DateTime.now().toIso8601String()}).match(
            {'id': 'default'}); // Pretpostavljamo id='default' za singleton red
  }

  /// Registruje točenje u vozilo
  /// Smanjuje kolicinu u v3_gorivo_stanje
  static Future<void> addTocenje(V3PumpaTocenje t) async {
    await _supabase.from('v3_gorivo_tocenja').insert(t.toJson());

    final stanje = getStanjeSync();
    await _supabase
        .from('v3_gorivo_stanje')
        .update({'kolicina': stanje.kolicina - t.kolicina, 'updated_at': DateTime.now().toIso8601String()}).match(
            {'id': 'default'});
  }
}
