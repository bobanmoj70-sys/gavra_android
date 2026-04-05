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
            row['aktivno'] != false &&
            row['tip'] == 'prihod' &&
            row['tip_akcije'] != null &&
            row['putnik_id']?.toString() == putnikId)
        .map((row) => V3UplataArhiva.fromJson(row))
        .toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(1970)).compareTo(a.createdAt ?? DateTime(1970)));
  }

  static List<V3UplataArhiva> getForPeriod({required int mesec, required int godina}) {
    final cache = V3MasterRealtimeManager.instance.getCache('v3_finansije');
    return cache.values
        .where((row) =>
            row['aktivno'] != false &&
            row['tip'] == 'prihod' &&
            row['mesec'] == mesec &&
            row['godina'] == godina &&
            row['tip_akcije'] != null)
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
        'vozac_id': zapis.vozacId.isEmpty ? null : zapis.vozacId,
        'tip': 'prihod',
        'putnik_id': zapis.putnikId,
        'putnik_ime_prezime': zapis.putnikImePrezime,
        'tip_akcije': zapis.tipAkcije,
        'vozac_ime_prezime': zapis.vozacImePrezime,
        'aktivno': zapis.aktivno,
        'created_by': zapis.createdBy,
        'updated_by': zapis.updatedBy,
      });
    } catch (e) {
      debugPrint('[V3UplateArhivaService] addZapis error: $e');
      rethrow;
    }
  }
}
