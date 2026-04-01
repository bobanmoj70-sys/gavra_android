import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../../models/v3_dug.dart';
import '../realtime/v3_master_realtime_manager.dart';

/// V3DugService - Upravljanje dugovima/naplatama iz v3_operativna_nedelja.
/// Tabela v3_dugovi ne postoji - dugovi se prate kroz naplata_status u v3_operativna_nedelja.
class V3DugService {
  V3DugService._();

  /// Vraca sve nenaplacene operacije kao listu dugova.
  /// Samo za dnevne putnike i posiljke koji su pokupljeni — oni placaju po pokupljenju.
  /// Radnik/ucenik imaju mjesecni sistem (placeni_mesec/godina).
  static List<V3Dug> getDugovi() {
    final rm = V3MasterRealtimeManager.instance;
    final cache = rm.operativnaNedeljaCache;
    final dugovi = <V3Dug>[];
    for (final row in cache.values) {
      final naplataSt = row['naplata_status'] as String? ?? 'nije_placeno';
      if (naplataSt != 'nije_placeno') continue;
      final isPokupljen = row['pokupljen'] == true;
      if (!isPokupljen) continue;
      final putnikId = row['putnik_id'] as String? ?? '';
      final putnikData = rm.putniciCache[putnikId];
      if (putnikData == null) continue;
      final tip = putnikData['tip_putnika'] as String? ?? 'dnevni';
      // Samo dnevni i posiljka imaju dugovanje po pokupljenju
      if (tip != 'dnevni' && tip != 'posiljka') continue;
      try {
        final pickupVozacId = (row['pokupljen_vozac_id'] ?? row['vozac_id']) as String? ?? '';
        final vozacData = pickupVozacId.isNotEmpty ? rm.vozaciCache[pickupVozacId] : null;
        final rowWithDriver = Map<String, dynamic>.from(row);
        rowWithDriver['vozac_id'] = pickupVozacId;
        rowWithDriver['vozac_ime'] = vozacData?['ime_prezime'] as String? ?? '';
        dugovi.add(V3Dug.fromOperacija(rowWithDriver, putnikData: putnikData));
      } catch (_) {}
    }
    dugovi.sort((a, b) => b.datum.compareTo(a.datum));
    return dugovi;
  }

  static Stream<List<V3Dug>> streamDugovi() => V3MasterRealtimeManager.instance.v3StreamFromCache(
        tables: ['v3_operativna_nedelja', 'v3_putnici', 'v3_vozaci'],
        build: () => getDugovi(),
      );

  static Future<void> markAsPaid(String operacijaId, {double iznos = 0}) async {
    try {
      // V3 Arhitektura: Fire and Forget (Realtime će odraditi sync preko updated_at)
      await supabase.from('v3_operativna_nedelja').update({
        'naplata_status': 'placeno',
        'iznos_naplacen': iznos,
        'vreme_placen': DateTime.now().toIso8601String(),
      }).eq('id', operacijaId);
    } catch (e) {
      debugPrint('[V3DugService] markAsPaid error: $e');
      rethrow;
    }
  }
}
