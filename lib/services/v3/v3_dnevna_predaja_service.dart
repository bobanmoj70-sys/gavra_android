import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/v3_dnevna_predaja.dart';

class V3DnevnaPredajaService {
  static final _supabase = Supabase.instance.client;

  /// Dobavlja predaju za određenog vozača i datum.
  static Future<V3DnevnaPredaja?> getPredaja({
    required String vozacId,
    required DateTime datum,
  }) async {
    final dateStr = "${datum.year}-${datum.month.toString().padLeft(2, '0')}-${datum.day.toString().padLeft(2, '0')}";
    try {
      final res =
          await _supabase.from('v3_dnevna_predaja').select().eq('vozac_id', vozacId).eq('datum', dateStr).maybeSingle();

      if (res == null) return null;
      return V3DnevnaPredaja.fromJson(res);
    } catch (e) {
      return null;
    }
  }

  /// Snima ili ažurira dnevnu predaju.
  static Future<void> upsertPredaja(V3DnevnaPredaja predaja) async {
    final data = predaja.toJson();
    // remove id if empty for new records
    if (predaja.id.isEmpty) {
      data.remove('id');
    }

    await _supabase.from('v3_dnevna_predaja').upsert(data);
  }
}
