import '../../models/v3_dnevna_predaja.dart';
import '../../utils/v3_dan_helper.dart';
import '../../utils/v3_date_utils.dart';
import 'repositories/v3_finansije_repository.dart';

class V3DnevnaPredajaService {
  static final V3FinansijeRepository _repo = V3FinansijeRepository();
  static const _kategorija = 'dnevna_predaja';
  static const _tip = 'prihod';

  /// Dobavlja predaju za određenog vozača i datum.
  static Future<V3DnevnaPredaja?> getPredaja({
    required String vozacId,
    required DateTime datum,
  }) async {
    final dayStart = V3DanHelper.dateOnly(datum);
    final dayEnd = dayStart.add(const Duration(days: 1));
    try {
      final res = await _repo.getLatestByCriteria(
        tip: _tip,
        kategorija: _kategorija,
        vozacId: vozacId,
        dayStartIso: dayStart.toIso8601String(),
        dayEndIso: dayEnd.toIso8601String(),
      );

      if (res == null) return null;
      final createdAt = V3DateUtils.parseTs(res['created_at'] as String?);
      final datumPredaje = createdAt ?? dayStart;
      final predaoIznos = (res['iznos'] as num?)?.toDouble() ?? 0;

      return V3DnevnaPredaja(
        id: (res['id'] as String?) ?? '',
        vozacId: res['naplatio_vozac_id'] as String?,
        datum: V3DanHelper.dateOnly(datumPredaje),
        predaoIznos: predaoIznos,
        createdAt: createdAt,
        updatedAt: V3DateUtils.parseTs(res['updated_at'] as String?),
      );
    } catch (e) {
      return null;
    }
  }

  /// Snima ili ažurira dnevnu predaju.
  static Future<void> upsertPredaja(V3DnevnaPredaja predaja) async {
    final dayStart = V3DanHelper.dateOnly(predaja.datum);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final existing = await _repo.getLatestByCriteria(
      tip: _tip,
      kategorija: _kategorija,
      vozacId: predaja.vozacId ?? '',
      dayStartIso: dayStart.toIso8601String(),
      dayEndIso: dayEnd.toIso8601String(),
      selectColumns: 'id',
    );

    final baseData = {
      'naziv': 'Dnevna predaja',
      'kategorija': _kategorija,
      'iznos': predaja.predaoIznos,
      'isplata_iz': 'predaja',
      'ponavljaj_mesecno': false,
      'mesec': predaja.datum.month,
      'godina': predaja.datum.year,
      'naplatio_vozac_id': predaja.vozacId,
      'tip': _tip,
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (existing != null && existing['id'] != null) {
      await _repo.updateById(existing['id'] as String, baseData);
      return;
    }

    final insertData = {
      ...baseData,
      'id': predaja.id.isEmpty ? null : predaja.id,
      'created_at': dayStart.toIso8601String(),
      'created_by': null,
      'updated_by': null,
    };

    await _repo.insert(insertData);
  }
}
