import 'package:flutter/foundation.dart';
import 'package:gavra_android/models/v3_gorivo.dart';
import 'package:gavra_android/services/realtime/v3_master_realtime_manager.dart';

import 'repositories/v3_gorivo_repository.dart';

class V3GorivoService {
  static final V3GorivoRepository _repo = V3GorivoRepository();

  /// Dohvata stanje pumpe iz cache-a (tabela: v3_gorivo)
  static V3PumpaStanje? getStanjeSync() {
    final cache = V3MasterRealtimeManager.instance.gorivoCache;
    if (cache.isEmpty) return null;
    return V3PumpaStanje.fromJson(cache.values.first);
  }

  /// Dohvata rezervoar iz cache-a (tabela: v3_gorivo)
  static V3PumpaRezervoar? getRezervoarSync() {
    final cache = V3MasterRealtimeManager.instance.gorivoCache;
    if (cache.isEmpty) return null;
    return V3PumpaRezervoar.fromJson(cache.values.first);
  }

  /// Stream koji emituje svaki put kad se gorivo promijeni
  static Stream<V3PumpaStanje?> streamStanje() {
    return V3MasterRealtimeManager.instance.v3StreamFromRevisions(
      tables: ['v3_gorivo'],
      build: getStanjeSync,
    );
  }

  static Stream<V3PumpaRezervoar?> streamRezervoar() {
    return V3MasterRealtimeManager.instance.v3StreamFromRevisions(
      tables: ['v3_gorivo'],
      build: getRezervoarSync,
    );
  }

  /// Ažurira trenutno stanje pumpe u bazi
  static Future<bool> updateStanje(String id, double novoStanje, double noviBrojac) async {
    try {
      await _repo.updateById(id, {
        'trenutno_stanje_litri': novoStanje,
        'brojac_pistolj_litri': noviBrojac,
        'updated_at': DateTime.now().toIso8601String(),
      });

      return true;
    } catch (e) {
      debugPrint('[V3GorivoService] updateStanje error: $e');
      return false;
    }
  }

  /// Ažurira trenutni nivo rezervoara u bazi
  static Future<bool> updateRezervoar(String id, double novoLitara) async {
    try {
      await _repo.updateById(id, {
        'trenutno_stanje_litri': novoLitara,
        'updated_at': DateTime.now().toIso8601String(),
      });

      return true;
    } catch (e) {
      debugPrint('[V3GorivoService] updateRezevoar error: $e');
      return false;
    }
  }
}
