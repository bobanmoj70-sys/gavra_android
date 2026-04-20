import 'package:flutter/foundation.dart';

import '../../models/v3_dug.dart';
import '../../utils/v3_status_filters.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'v3_finansije_service.dart';
import 'v3_vozac_service.dart';

/// V3DugService - Upravljanje dugovima/naplatama.
/// Dugovi se izvlače iz operativnih vožnji, a status naplate iz v3_finansije.
class V3DugService {
  V3DugService._();

  static Map<String, Map<String, dynamic>> _latestNaplataByOperativnaId(V3MasterRealtimeManager rm) {
    final finansije = rm.getCache('v3_finansije').values;
    final byOperativna = <String, Map<String, dynamic>>{};

    for (final row in finansije) {
      if (row['tip']?.toString() != 'prihod') continue;
      if ((row['kategorija']?.toString().toLowerCase() ?? '') != 'operativna_naplata') continue;
      final operativnaId = row['operativna_id']?.toString() ?? '';
      if (operativnaId.isEmpty) continue;

      final existing = byOperativna[operativnaId];
      if (existing == null) {
        byOperativna[operativnaId] = row;
        continue;
      }

      final existingTs = DateTime.tryParse(existing['created_at']?.toString() ?? '') ?? DateTime(2000);
      final currentTs = DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime(2000);
      if (currentTs.isAfter(existingTs)) {
        byOperativna[operativnaId] = row;
      }
    }

    return byOperativna;
  }

  /// Vraca sve nenaplacene operacije kao listu dugova.
  /// Samo za dnevne putnike i posiljke koji su pokupljeni — oni placaju po pokupljenju.
  /// Radnik/ucenik imaju mjesecni sistem (placeni_mesec/godina).
  static List<V3Dug> getDugovi() {
    final rm = V3MasterRealtimeManager.instance;
    final cache = rm.operativnaNedeljaCache;
    final latestNaplataByOperativna = _latestNaplataByOperativnaId(rm);
    final dugovi = <V3Dug>[];
    for (final row in cache.values) {
      final operativnaId = row['id']?.toString() ?? '';
      final naplata = operativnaId.isEmpty ? null : latestNaplataByOperativna[operativnaId];
      final isPlaceno = naplata != null;
      if (isPlaceno) continue;
      final isPokupljen = V3StatusFilters.isPokupljenAt(row['pokupljen_at']);
      if (!isPokupljen) continue;
      final putnikId = row['created_by'] as String? ?? '';
      final putnikData = rm.putniciCache[putnikId];
      if (putnikData == null) continue;
      final tip = putnikData['tip_putnika'] as String? ?? 'dnevni';
      // Samo dnevni i posiljka imaju dugovanje po pokupljenju
      if (tip != 'dnevni' && tip != 'posiljka') continue;
      try {
        final pickupVozacId = row['pokupljen_by'] as String? ?? '';
        final vozacData = pickupVozacId.isNotEmpty ? rm.vozaciCache[pickupVozacId] : null;
        final rowWithDriver = Map<String, dynamic>.from(row);
        rowWithDriver['pokupljen_by'] = pickupVozacId;
        rowWithDriver['vozac_ime'] = vozacData?['ime_prezime'] as String? ?? '';
        rowWithDriver['naplacen_at'] = naplata?['created_at'];
        dugovi.add(V3Dug.fromOperacija(rowWithDriver, putnikData: putnikData));
      } catch (_) {}
    }
    dugovi.sort((a, b) => b.datum.compareTo(a.datum));
    return dugovi;
  }

  static Stream<List<V3Dug>> streamDugovi() => V3MasterRealtimeManager.instance.v3StreamFromRevisions(
        tables: ['v3_operativna_nedelja', 'v3_auth', 'v3_finansije'],
        build: () => getDugovi(),
      );

  static Future<void> markAsPaid(String operacijaId, {required double iznos}) async {
    if (iznos <= 0) {
      throw ArgumentError('Iznos naplate mora biti veći od nule.');
    }
    try {
      final currentVozacId = V3VozacService.currentVozac?.id;
      if (currentVozacId == null || currentVozacId.isEmpty) {
        throw StateError('Vozač nije ulogovan.');
      }

      final rm = V3MasterRealtimeManager.instance;
      final operacija = rm.operativnaNedeljaCache[operacijaId];
      if (operacija == null) {
        throw StateError('Operacija nije pronađena: $operacijaId');
      }

      final putnikId = operacija['created_by']?.toString() ?? '';
      if (putnikId.isEmpty) {
        throw StateError('Putnik nije definisan za operaciju: $operacijaId');
      }

      final datumIso = operacija['datum']?.toString();
      final datum = DateTime.tryParse(datumIso ?? '') ?? DateTime.now();

      await V3FinansijeService.sacuvajOperativnuNaplatu(
        operativnaId: operacijaId,
        putnikId: putnikId,
        naplacenoBy: currentVozacId,
        iznos: iznos,
        datum: datum,
      );
    } catch (e) {
      debugPrint('[V3DugService] markAsPaid error: $e');
      rethrow;
    }
  }
}
