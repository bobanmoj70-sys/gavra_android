import 'package:flutter/foundation.dart';
import 'package:gavra_android/models/v3_gorivo.dart';
import 'package:gavra_android/services/realtime/v3_master_realtime_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class V3GorivoService {
  static final _supabase = Supabase.instance.client;

  /// Dohvata stanje pumpe iz cache-a (tabela: v3_pumpa_stanje)
  static V3PumpaStanje? getStanjeSync() {
    final cache = V3MasterRealtimeManager.instance.pumpaStanjeCache;
    if (cache.isEmpty) return null;
    return V3PumpaStanje.fromJson(cache.values.first);
  }

  /// Dohvata rezervoar iz cache-a (tabela: v3_pumpa_rezervoar)
  static V3PumpaRezervoar? getRezervoarSync() {
    final cache = V3MasterRealtimeManager.instance.pumpaRezervoarCache;
    if (cache.isEmpty) return null;
    return V3PumpaRezervoar.fromJson(cache.values.first);
  }

  static List<V3JavnaPumpaTocenje> getJavnaTocenjaSync() {
    final cache = V3MasterRealtimeManager.instance.pumpaJavnaTocenjaCache;
    if (cache.isEmpty) return const [];
    final list = cache.values.map(V3JavnaPumpaTocenje.fromJson).where((t) => t.aktivno).toList();
    list.sort((a, b) => b.datumVreme.compareTo(a.datumVreme));
    return list;
  }

  /// Stream koji emituje svaki put kad se gorivo promijeni
  static Stream<V3PumpaStanje?> streamStanje() {
    return V3MasterRealtimeManager.instance.v3StreamFromCache(
      tables: ['v3_pumpa_stanje'],
      build: getStanjeSync,
    );
  }

  static Stream<V3PumpaRezervoar?> streamRezervoar() {
    return V3MasterRealtimeManager.instance.v3StreamFromCache(
      tables: ['v3_pumpa_rezervoar'],
      build: getRezervoarSync,
    );
  }

  /// Ažurira trenutno stanje pumpe u bazi
  static Future<bool> updateStanje(String id, double novoStanje, double noviBrojac) async {
    try {
      await _supabase.from('v3_pumpa_stanje').update({
        'trenutno_stanje': novoStanje,
        'stanje_brojac_pistolj': noviBrojac,
      }).eq('id', id);

      return true;
    } catch (e) {
      debugPrint('[V3GorivoService] updateStanje error: $e');
      return false;
    }
  }

  /// Ažurira trenutni nivo rezervoara u bazi
  static Future<bool> updateRezervoar(String id, double novoLitara) async {
    try {
      await _supabase.from('v3_pumpa_rezervoar').update({
        'trenutno_litara': novoLitara,
      }).eq('id', id);

      return true;
    } catch (e) {
      debugPrint('[V3GorivoService] updateRezevoar error: $e');
      return false;
    }
  }
}
