import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import 'realtime/v2_master_realtime_manager.dart';

/// Model za jedan red iz vozac_raspored tabele.
///
/// Čuva per-termin raspored: koji vozač vozi cijeli termin (dan+grad+vreme).
/// Per-V2Putnik individualna dodjela čuva se u vozac_putnik tabeli (VozacPutnikService).
class V2VozacRasporedEntry {
  final String dan;
  final String grad;
  final String vreme;

  /// UUID vozača iz tabele vozaci.id — primarni identifikator
  final String vozacId;

  const V2VozacRasporedEntry({
    required this.dan,
    required this.grad,
    required this.vreme,
    required this.vozacId,
  });

  factory V2VozacRasporedEntry.fromMap(Map<String, dynamic> map) {
    return V2VozacRasporedEntry(
      dan: map['dan']?.toString() ?? '',
      grad: map['grad']?.toString() ?? '',
      vreme: map['vreme']?.toString() ?? '',
      vozacId: map['vozac_id']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'dan': dan,
        'grad': grad,
        'vreme': vreme,
        'vozac_id': vozacId,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is V2VozacRasporedEntry &&
          runtimeType == other.runtimeType &&
          dan == other.dan &&
          grad == other.grad &&
          vreme == other.vreme &&
          vozacId == other.vozacId;

  @override
  int get hashCode => Object.hash(dan, grad, vreme, vozacId);
}

/// Servis za učitavanje i upravljanje vozac_raspored tabelom
class V2VozacRasporedService {
  V2VozacRasporedService._();

  static SupabaseClient get _supabase => supabase;
  static V2MasterRealtimeManager get _rm => V2MasterRealtimeManager.instance;

  static List<V2VozacRasporedEntry> loadAll() {
    return _rm.rasporedCache.values.map((row) => V2VozacRasporedEntry.fromMap(row)).toList();
  }

  static Future<void> upsert(V2VozacRasporedEntry entry) async {
    try {
      final row = await _supabase
          .from('v2_vozac_raspored')
          .upsert(entry.toMap(), onConflict: 'dan,grad,vreme')
          .select()
          .single();
      _rm.upsertToCache('v2_vozac_raspored', row);
    } catch (e) {
      debugPrint('[V2VozacRasporedService] Greška u upsert(): $e');
    }
  }

  static Future<void> deleteTermin({
    required String dan,
    required String grad,
    required String vreme,
    required String vozacId,
  }) async {
    try {
      await _supabase
          .from('v2_vozac_raspored')
          .delete()
          .eq('dan', dan)
          .eq('grad', grad)
          .eq('vreme', vreme)
          .eq('vozac_id', vozacId);
      // Ukloni iz cache-a sve redove koji odgovaraju terminu
      final toRemove = _rm.rasporedCache.entries
          .where((e) =>
              e.value['dan'] == dan &&
              e.value['grad'] == grad &&
              e.value['vreme'] == vreme &&
              e.value['vozac_id']?.toString() == vozacId)
          .map((e) => e.key)
          .toList();
      for (final id in toRemove) {
        _rm.removeFromCache('v2_vozac_raspored', id);
      }
    } catch (e) {
      debugPrint('[V2VozacRasporedService] Greška u deleteTermin(): $e');
    }
  }
}
