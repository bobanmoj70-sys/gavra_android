import '../../../globals.dart';

class V3GorivoRepository {
  Future<List<dynamic>> selectFirst() {
    return supabase.from('v3_gorivo').select().limit(1);
  }

  Future<Map<String, dynamic>> insertReturning(Map<String, dynamic> payload) {
    return supabase.from('v3_gorivo').insert(payload).select().single();
  }

  Future<Map<String, dynamic>> updateByIdReturning(String id, Map<String, dynamic> payload) {
    return supabase.from('v3_gorivo').update(payload).eq('id', id).select().single();
  }

  /// Suma potrošnje (L) u [start, end) — RPC agregat, bez limita od 1000 redova.
  /// (PostgREST `.sum()` u select-u je isključen na projektu — PGRST123.)
  Future<double> sumPotrosnjaBetween({
    required String startIsoUtc,
    required String endIsoUtc,
  }) async {
    try {
      final res = await supabase.rpc(
        'v3_gorivo_sum_potrosnja',
        params: {'p_start': startIsoUtc, 'p_end': endIsoUtc},
      );
      return (res as num?)?.toDouble() ?? 0;
    } catch (_) {
      final rows = await selectPotrosnjaBetween(
        startIsoUtc: startIsoUtc,
        endIsoUtc: endIsoUtc,
      );
      var sum = 0.0;
      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        if (map['source'] == 'inicijalni_import') continue;
        final litri = map['litri'];
        if (litri is num) sum += litri;
      }
      return sum;
    }
  }

  /// Fallback: redovi potrošnje (za starije klijente / debug). Preferirati [sumPotrosnjaBetween].
  Future<List<dynamic>> selectPotrosnjaBetween({
    required String startIsoUtc,
    required String endIsoUtc,
  }) {
    return supabase
        .from('v3_gorivo_istorija')
        .select('id, vrsta, litri, source, created_at')
        .eq('vrsta', 'potrosnja')
        .gte('created_at', startIsoUtc)
        .lt('created_at', endIsoUtc)
        .order('created_at', ascending: true);
  }
}
