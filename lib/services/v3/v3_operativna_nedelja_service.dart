import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../realtime/v3_master_realtime_manager.dart';

class V3OperativnaNedeljaEntry {
  final String id;
  final String? izvorTip;
  final String izvorId;
  final String putnikId;
  final DateTime datum;
  final String? grad;
  final String? vreme;
  final String? statusFinal;
  final String? finansijeFinal;
  final Map<String, dynamic> detaljiAkcije;
  final bool aktivno;
  final DateTime? createdAt;

  V3OperativnaNedeljaEntry({
    required this.id,
    this.izvorTip,
    required this.izvorId,
    required this.putnikId,
    required this.datum,
    this.grad,
    this.vreme,
    this.statusFinal,
    this.finansijeFinal,
    this.detaljiAkcije = const {},
    this.aktivno = true,
    this.createdAt,
  });

  factory V3OperativnaNedeljaEntry.fromJson(Map<String, dynamic> json) {
    return V3OperativnaNedeljaEntry(
      id: json['id'] as String? ?? '',
      izvorTip: json['izvor_tip'] as String?,
      izvorId: json['izvor_id'] as String? ?? '',
      putnikId: json['putnik_id'] as String? ?? '',
      datum: json['datum'] != null ? DateTime.parse(json['datum'] as String) : DateTime.now(),
      grad: json['grad'] as String?,
      vreme: json['vreme'] as String?,
      statusFinal: json['status_final'] as String?,
      finansijeFinal: json['finansije_final'] as String?,
      detaljiAkcije: json['detalji_akcije'] as Map<String, dynamic>? ?? {},
      aktivno: json['aktivno'] as bool? ?? true,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'izvor_tip': izvorTip,
      'izvor_id': izvorId,
      'putnik_id': putnikId,
      'datum': datum.toIso8601String().split('T')[0],
      'grad': grad,
      'vreme': vreme,
      'status_final': statusFinal,
      'finansije_final': finansijeFinal,
      'detalji_akcije': detaljiAkcije,
      'aktivno': aktivno,
    };
  }
}

class V3OperativnaNedeljaService {
  V3OperativnaNedeljaService._();

  static List<V3OperativnaNedeljaEntry> getOperativnaNedeljaByFilter({
    required String grad,
    required String vreme,
    required DateTime datum,
  }) {
    final cache = V3MasterRealtimeManager.instance.operativnaNedeljaCache.values;
    final datumStr = datum.toIso8601String().split('T')[0];

    return cache
        .where((r) =>
            r['grad'] == grad && r['vreme'] == vreme && r['datum'].toString() == datumStr && r['aktivno'] == true)
        .map((r) => V3OperativnaNedeljaEntry.fromJson(r))
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id)); // Default sort
  }

  static Stream<List<V3OperativnaNedeljaEntry>> streamOperativnaNedeljaByFilter({
    required String grad,
    required String vreme,
    required DateTime datum,
  }) {
    return V3MasterRealtimeManager.instance.v3StreamFromCache(
      tables: ['v3_operativna_nedelja'],
      build: () => getOperativnaNedeljaByFilter(grad: grad, vreme: vreme, datum: datum),
    );
  }

  static Future<void> updateStatus({
    required String id,
    required String status,
  }) async {
    try {
      // V3 Arhitektura: Fire and Forget (Realtime će odraditi sync preko updated_at)
      await supabase.from('v3_operativna_nedelja').update({
        'status_final': status,
      }).eq('id', id);
    } catch (e) {
      debugPrint('[V3OperativnaNedeljaService] Update status error: $e');
      rethrow;
    }
  }
}
