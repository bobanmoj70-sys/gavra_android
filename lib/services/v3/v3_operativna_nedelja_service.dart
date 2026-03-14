import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'v3_kapacitet_service.dart';

class V3OperativnaNedeljaEntry {
  final String id;
  final String? izvorTip;
  final String izvorId;
  final String putnikId;
  final String? imePrezime;
  final DateTime datum;
  final String? grad;
  final String? vreme;
  final String? statusFinal;
  final String? finansijeFinal;
  final Map<String, dynamic> detaljiAkcije;
  final bool aktivno;
  final DateTime? createdAt;
  final int brojMesta;
  final String? zeljenoVreme;
  final String? dodeljivoVreme;
  final DateTime? vremePokupljen;
  final double iznosNaplacen;
  final DateTime? vremePlacen;
  final String naplataStatus;
  final String? vozacId;

  V3OperativnaNedeljaEntry({
    required this.id,
    this.izvorTip,
    required this.izvorId,
    required this.putnikId,
    this.imePrezime,
    required this.datum,
    this.grad,
    this.vreme,
    this.statusFinal,
    this.finansijeFinal,
    this.detaljiAkcije = const {},
    this.aktivno = true,
    this.createdAt,
    this.brojMesta = 1,
    this.zeljenoVreme,
    this.dodeljivoVreme,
    this.vremePokupljen,
    this.iznosNaplacen = 0,
    this.vremePlacen,
    this.naplataStatus = 'nije_placeno',
    this.vozacId,
  });

  factory V3OperativnaNedeljaEntry.fromJson(Map<String, dynamic> json) {
    return V3OperativnaNedeljaEntry(
      id: json['id'] as String? ?? '',
      izvorTip: json['izvor_tip'] as String?,
      izvorId: json['izvor_id'] as String? ?? '',
      putnikId: json['putnik_id'] as String? ?? '',
      imePrezime: json['ime_prezime'] as String?,
      datum: json['datum'] != null ? DateTime.parse(json['datum'] as String) : DateTime.now(),
      grad: json['grad'] as String?,
      vreme: json['vreme'] as String?,
      statusFinal: json['status_final'] as String?,
      finansijeFinal: json['finansije_final'] as String?,
      detaljiAkcije: json['detalji_akcije'] as Map<String, dynamic>? ?? {},
      aktivno: json['aktivno'] as bool? ?? true,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
      brojMesta: (json['broj_mesta'] as num?)?.toInt() ?? 1,
      zeljenoVreme: json['zeljeno_vreme'] as String?,
      dodeljivoVreme: json['dodeljeno_vreme'] as String?,
      vremePokupljen: json['vreme_pokupljen'] != null ? DateTime.tryParse(json['vreme_pokupljen'] as String) : null,
      iznosNaplacen: (json['iznos_naplacen'] as num?)?.toDouble() ?? 0,
      vremePlacen: json['vreme_placen'] != null ? DateTime.tryParse(json['vreme_placen'] as String) : null,
      naplataStatus: json['naplata_status'] as String? ?? 'nije_placeno',
      vozacId: json['vozac_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'izvor_tip': izvorTip,
      'izvor_id': izvorId,
      'putnik_id': putnikId,
      'ime_prezime': imePrezime,
      'datum': datum.toIso8601String().split('T')[0],
      'grad': grad,
      'vreme': vreme,
      'status_final': statusFinal,
      'finansije_final': finansijeFinal,
      'detalji_akcije': detaljiAkcije,
      'aktivno': aktivno,
      if (zeljenoVreme != null) 'zeljeno_vreme': zeljenoVreme,
      if (dodeljivoVreme != null) 'dodeljeno_vreme': dodeljivoVreme,
      if (vremePokupljen != null) 'vreme_pokupljen': vremePokupljen!.toIso8601String(),
      'iznos_naplacen': iznosNaplacen,
      if (vremePlacen != null) 'vreme_placen': vremePlacen!.toIso8601String(),
      'naplata_status': naplataStatus,
      if (vozacId != null) 'vozac_id': vozacId,
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
            r['grad'] == grad &&
            r['vreme'] == vreme &&
            r['datum'].toString() == datumStr &&
            r['aktivno'] == true &&
            r['status_final'] != 'otkazano' &&
            r['status_final'] != 'odbijeno')
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

  static List<V3OperativnaNedeljaEntry> getOperativnaNedeljaByDanAndGrad(String danAbbr, String grad) {
    final cache = V3MasterRealtimeManager.instance.operativnaNedeljaCache.values;
    // Filtriramo po danu u sedmici (izvlačimo iz datuma) i gradu
    return cache
        .where((r) {
          final datumStr = r['datum'] as String?;
          if (datumStr == null) return false;
          final datum = DateTime.tryParse(datumStr);
          if (datum == null) return false;

          // Mapiranje weekday u abbr
          const abbrs = ['pon', 'uto', 'sre', 'cet', 'pet', 'sub', 'ned'];
          final targetAbbr = abbrs[datum.weekday - 1];

          return targetAbbr == danAbbr && r['grad'] == grad;
        })
        .map((r) => V3OperativnaNedeljaEntry.fromJson(r))
        .toList();
  }

  static Stream<List<V3OperativnaNedeljaEntry>> streamOperativnaNedeljaByDanAndGrad(String danAbbr, String grad) {
    return V3MasterRealtimeManager.instance.v3StreamFromCache(
      tables: ['v3_operativna_nedelja'],
      build: () => getOperativnaNedeljaByDanAndGrad(danAbbr, grad),
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

  /// Čita kapacitet vozila (default po gradu) iz v3_app_settings.
  static int getKapacitetVozila(String grad, String vreme, DateTime datum) {
    return V3KapacitetService.getKapacitetSyncValue(grad, vreme);
  }

  /// Čita broj zauzetih mesta — suma broj_mesta aktivnih zapisa u v3_operativna_nedelja za grad/vreme/datum.
  static int getZauzetaMesta(String grad, String vreme, DateTime datum) {
    final zapisi = getOperativnaNedeljaByFilter(grad: grad, vreme: vreme, datum: datum);
    return zapisi.fold(0, (sum, e) => sum + e.brojMesta);
  }

  /// Čita broj slobodnih mesta za dati grad/vreme/datum.
  /// slobodna = kapacitet_vozila - zauzetaMesta (min 0).
  static int getSlobodnaMesta(String grad, String vreme, DateTime datum) {
    final kapacitet = getKapacitetVozila(grad, vreme, datum);
    final zauzeto = getZauzetaMesta(grad, vreme, datum);
    return (kapacitet - zauzeto).clamp(0, kapacitet);
  }

  /// Stream koji emituje [kapacitetVozila, zauzetaMesta, slobodnaMesta] za dati termin.
  static Stream<({int kapacitet, int zauzeto, int slobodna})> streamMesta({
    required String grad,
    required String vreme,
    required DateTime datum,
  }) {
    return V3MasterRealtimeManager.instance.v3StreamFromCache(
      tables: ['v3_operativna_nedelja', 'v3_app_settings'],
      build: () {
        final kapacitet = getKapacitetVozila(grad, vreme, datum);
        final zauzeto = getZauzetaMesta(grad, vreme, datum);
        final slobodna = (kapacitet - zauzeto).clamp(0, kapacitet);
        return (kapacitet: kapacitet, zauzeto: zauzeto, slobodna: slobodna);
      },
    );
  }
}
