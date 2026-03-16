import 'package:flutter/foundation.dart';

import '../../globals.dart';
import '../realtime/v3_master_realtime_manager.dart';

class V3OperativnaNedeljaEntry {
  final String id;
  final String izvorId;
  final String putnikId;
  final String? imePrezime;
  final DateTime datum;
  final String? grad;
  final String? vreme;
  final String? statusFinal;
  final bool aktivno;
  final DateTime? createdAt;
  final int brojMesta;
  final String? zeljenoVreme;
  final String? dodeljivoVreme;
  final DateTime? vremePokupljen;
  final double iznosNaplacen;
  final DateTime? vremePlacen;
  final String naplataStatus;
  final String? pokupljenVozacId;
  final String? naplatioVozacId;
  final String? otkazaoVozacId;
  final int? maxMesta;

  V3OperativnaNedeljaEntry({
    required this.id,
    required this.izvorId,
    required this.putnikId,
    this.imePrezime,
    required this.datum,
    this.grad,
    this.vreme,
    this.statusFinal,
    this.aktivno = true,
    this.createdAt,
    this.brojMesta = 1,
    this.zeljenoVreme,
    this.dodeljivoVreme,
    this.vremePokupljen,
    this.iznosNaplacen = 0,
    this.vremePlacen,
    this.naplataStatus = 'nije_placeno',
    this.pokupljenVozacId,
    this.naplatioVozacId,
    this.otkazaoVozacId,
    this.maxMesta,
  });

  factory V3OperativnaNedeljaEntry.fromJson(Map<String, dynamic> json) {
    return V3OperativnaNedeljaEntry(
      id: json['id'] as String? ?? '',
      izvorId: json['izvor_id'] as String? ?? '',
      putnikId: json['putnik_id'] as String? ?? '',
      imePrezime: json['ime_prezime'] as String?,
      datum: json['datum'] != null ? DateTime.parse(json['datum'] as String) : DateTime.now(),
      grad: json['grad'] as String?,
      vreme: json['vreme'] as String?,
      statusFinal: json['status_final'] as String?,
      aktivno: json['aktivno'] as bool? ?? true,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
      brojMesta: (json['broj_mesta'] as num?)?.toInt() ?? 1,
      zeljenoVreme: json['zeljeno_vreme'] as String?,
      dodeljivoVreme: json['dodeljeno_vreme'] as String?,
      vremePokupljen: json['vreme_pokupljen'] != null ? DateTime.tryParse(json['vreme_pokupljen'] as String) : null,
      iznosNaplacen: (json['iznos_naplacen'] as num?)?.toDouble() ?? 0,
      vremePlacen: json['vreme_placen'] != null ? DateTime.tryParse(json['vreme_placen'] as String) : null,
      naplataStatus: json['naplata_status'] as String? ?? 'nije_placeno',
      pokupljenVozacId: json['pokupljen_vozac_id'] as String?,
      naplatioVozacId: json['naplatio_vozac_id'] as String?,
      otkazaoVozacId: json['otkazao_vozac_id'] as String?,
      maxMesta: (json['max_mesta'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'izvor_id': izvorId,
      'putnik_id': putnikId,
      'ime_prezime': imePrezime,
      'datum': datum.toIso8601String().split('T')[0],
      'grad': grad,
      'vreme': vreme,
      'status_final': statusFinal,
      'aktivno': aktivno,
      if (zeljenoVreme != null) 'zeljeno_vreme': zeljenoVreme,
      if (dodeljivoVreme != null) 'dodeljeno_vreme': dodeljivoVreme,
      if (vremePokupljen != null) 'vreme_pokupljen': vremePokupljen!.toIso8601String(),
      'iznos_naplacen': iznosNaplacen,
      if (vremePlacen != null) 'vreme_placen': vremePlacen!.toIso8601String(),
      'naplata_status': naplataStatus,
      if (pokupljenVozacId != null) 'pokupljen_vozac_id': pokupljenVozacId,
      if (naplatioVozacId != null) 'naplatio_vozac_id': naplatioVozacId,
      if (otkazaoVozacId != null) 'otkazao_vozac_id': otkazaoVozacId,
      if (maxMesta != null) 'max_mesta': maxMesta,
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

  static List<V3OperativnaNedeljaEntry> getOperativnaNedeljaByDanAndGrad(String danAbbr, String grad) {
    final cache = V3MasterRealtimeManager.instance.operativnaNedeljaCache.values;

    // Tekuća sedmica: pon–ned
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));

    return cache
        .where((r) {
          final datumStr = r['datum'] as String?;
          if (datumStr == null) return false;
          final datum = DateTime.tryParse(datumStr);
          if (datum == null) return false;

          // Samo tekuća sedmica
          final d = DateTime(datum.year, datum.month, datum.day);
          if (d.isBefore(monday) || d.isAfter(sunday)) return false;

          final targetAbbr = V3DanHelper.abbr(datum);

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

  /// Vraća sve zapise za dati grad za celu nedelju (bez filtera po danu).
  static List<V3OperativnaNedeljaEntry> getOperativnaNedeljaByGrad(String grad) {
    final cache = V3MasterRealtimeManager.instance.operativnaNedeljaCache.values;
    return cache.where((r) => r['grad'] == grad).map((r) => V3OperativnaNedeljaEntry.fromJson(r)).toList();
  }

  /// Stream koji emituje sve zapise za dati grad za celu nedelju.
  static Stream<List<V3OperativnaNedeljaEntry>> streamOperativnaNedeljaByGrad(String grad) {
    return V3MasterRealtimeManager.instance.v3StreamFromCache(
      tables: ['v3_operativna_nedelja'],
      build: () => getOperativnaNedeljaByGrad(grad),
    );
  }

  /// Vraća sve zapise za tačan datum i grad iz cache-a.
  static List<V3OperativnaNedeljaEntry> getOperativnaNedeljaByDatumAndGrad(String datumIso, String grad) {
    final cache = V3MasterRealtimeManager.instance.operativnaNedeljaCache.values;
    return cache
        .where((r) {
          final rDatum = (r['datum'] as String? ?? '').split('T')[0];
          return rDatum == datumIso && r['grad'] == grad;
        })
        .map((r) => V3OperativnaNedeljaEntry.fromJson(r))
        .toList();
  }

  /// Stream koji emituje zapise za tačan datum i grad.
  static Stream<List<V3OperativnaNedeljaEntry>> streamOperativnaNedeljaByDatumAndGrad(String datumIso, String grad) {
    return V3MasterRealtimeManager.instance.v3StreamFromCache(
      tables: ['v3_operativna_nedelja'],
      build: () => getOperativnaNedeljaByDatumAndGrad(datumIso, grad),
    );
  }

  /// Vraća sve zapise za tačan datum (svi gradovi).
  static List<V3OperativnaNedeljaEntry> getOperativnaNedeljaByDatum(String datumIso) {
    final cache = V3MasterRealtimeManager.instance.operativnaNedeljaCache.values;
    return cache
        .where((r) {
          final rDatum = (r['datum'] as String? ?? '').split('T')[0];
          return rDatum == datumIso;
        })
        .map((r) => V3OperativnaNedeljaEntry.fromJson(r))
        .toList();
  }

  /// Stream koji emituje sve zapise za tačan datum (svi gradovi).
  static Stream<List<V3OperativnaNedeljaEntry>> streamOperativnaNedeljaByDatum(String datumIso) {
    return V3MasterRealtimeManager.instance.v3StreamFromCache(
      tables: ['v3_operativna_nedelja'],
      build: () => getOperativnaNedeljaByDatum(datumIso),
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

  static Future<void> updateNaplata({
    required String id,
    required double iznos,
    String? naplatioVozacId,
  }) async {
    try {
      await supabase.from('v3_operativna_nedelja').update({
        'naplata_status': 'placeno',
        'iznos_naplacen': iznos,
        'vreme_placen': DateTime.now().toIso8601String(),
        if (naplatioVozacId != null) 'naplatio_vozac_id': naplatioVozacId,
      }).eq('id', id);
    } catch (e) {
      debugPrint('[V3OperativnaNedeljaService] updateNaplata error: $e');
      rethrow;
    }
  }

  /// Čita max_mesta za dati grad/vreme/datum iz v3_kapacitet_slots cache-a.
  /// Vraća null ako slot nije pronađen.
  static int? getKapacitetVozila(String grad, String vreme, DateTime datum) {
    final cache = V3MasterRealtimeManager.instance.kapacitetSlotsCache.values;
    final datumStr = datum.toIso8601String().split('T')[0];
    for (final r in cache) {
      if (r['grad'] == grad &&
          r['vreme'].toString().substring(0, 5) == vreme &&
          r['datum'].toString().startsWith(datumStr) &&
          r['aktivno'] == true) {
        return (r['max_mesta'] as num?)?.toInt();
      }
    }
    return null;
  }

  /// Čita broj zauzetih mesta — suma broj_mesta zapisa sa statusom koji zauzima mjesto.
  /// Filtrira: aktivno=true i status_final IN (obrada, odobreno, pokupljen).
  static int getZauzetaMesta(String grad, String vreme, DateTime datum) {
    const aktivniStatusi = {'obrada', 'odobreno', 'pokupljen'};
    final zapisi = getOperativnaNedeljaByFilter(grad: grad, vreme: vreme, datum: datum);
    return zapisi.where((e) => aktivniStatusi.contains(e.statusFinal)).fold(0, (sum, e) => sum + e.brojMesta);
  }

  /// Čita broj slobodnih mesta za dati grad/vreme/datum.
  /// slobodna = max_mesta - zauzetaMesta (min 0).
  /// Vraća null ako max_mesta nije postavljeno.
  static int? getSlobodnaMesta(String grad, String vreme, DateTime datum) {
    final kapacitet = getKapacitetVozila(grad, vreme, datum);
    if (kapacitet == null) return null;
    final zauzeto = getZauzetaMesta(grad, vreme, datum);
    return (kapacitet - zauzeto).clamp(0, kapacitet);
  }

  /// Stream koji emituje [kapacitet, zauzeto, slobodna] za dati termin.
  static Stream<({int? kapacitet, int zauzeto, int? slobodna})> streamMesta({
    required String grad,
    required String vreme,
    required DateTime datum,
  }) {
    return V3MasterRealtimeManager.instance.v3StreamFromCache(
      tables: ['v3_operativna_nedelja'],
      build: () {
        final kapacitet = getKapacitetVozila(grad, vreme, datum);
        final zauzeto = getZauzetaMesta(grad, vreme, datum);
        final slobodna = kapacitet != null ? (kapacitet - zauzeto).clamp(0, kapacitet) : null;
        return (kapacitet: kapacitet, zauzeto: zauzeto, slobodna: slobodna);
      },
    );
  }
}
