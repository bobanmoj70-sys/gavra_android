import 'package:flutter/foundation.dart';

import '../../models/v3_uplata_arhiva.dart';
import '../realtime/v3_master_realtime_manager.dart';
import 'repositories/v3_finansije_repository.dart';

class V3UplateArhivaService {
  V3UplateArhivaService._();
  static final V3FinansijeRepository _repo = V3FinansijeRepository();

  static List<V3UplataArhiva> getByPutnik(String putnikId) {
    final cache = V3MasterRealtimeManager.instance.getCache('v3_finansije');
    return cache.values
        .where((row) =>
            row['tip'] == 'prihod' && row['kategorija'] == 'voznja' && row['created_by']?.toString() == putnikId)
        .map((row) => V3UplataArhiva.fromJson(row))
        .toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(1970)).compareTo(a.createdAt ?? DateTime(1970)));
  }

  static List<V3UplataArhiva> getForPeriod({required int mesec, required int godina}) {
    final cache = V3MasterRealtimeManager.instance.getCache('v3_finansije');
    return cache.values
        .where((row) =>
            row['tip'] == 'prihod' && row['mesec'] == mesec && row['godina'] == godina && row['kategorija'] == 'voznja')
        .map((row) => V3UplataArhiva.fromJson(row))
        .toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(1970)).compareTo(a.createdAt ?? DateTime(1970)));
  }

  static Stream<List<V3UplataArhiva>> streamByPutnik(String putnikId) {
    return V3MasterRealtimeManager.instance.v3StreamFromRevisions(
      tables: ['v3_finansije'],
      build: () => getByPutnik(putnikId),
    );
  }

  static Future<void> addZapis(V3UplataArhiva zapis) async {
    try {
      await _repo.insert({
        'naziv': 'Uplata: ${zapis.putnikImePrezime} (${zapis.zaMesec}/${zapis.zaGodinu})',
        'kategorija': 'voznja',
        'iznos': zapis.iznos,
        'isplata_iz': 'putnici_arhiva',
        'ponavljaj_mesecno': false,
        'mesec': zapis.zaMesec,
        'godina': zapis.zaGodinu,
        'naplatio_vozac_id': zapis.vozacId.isEmpty ? null : zapis.vozacId,
        'tip': 'prihod',
        'created_by': (zapis.createdBy != null && zapis.createdBy!.isNotEmpty) ? zapis.createdBy : zapis.putnikId,
        'putnik_ime': zapis.putnikImePrezime,
        'vozac_ime': zapis.vozacImePrezime,
        'updated_by': zapis.updatedBy,
      });
    } catch (e) {
      debugPrint('[V3UplateArhivaService] addZapis error: $e');
      rethrow;
    }
  }
}
