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

  /// Suma potrošnje (L) u [start, end) — server-side agregat, bez limita od 1000 redova.
  Future<double> sumPotrosnjaBetween({
    required String startIsoUtc,
    required String endIsoUtc,
  }) async {
    final rows = await supabase
        .from('v3_gorivo_istorija')
        .select('litri.sum()')
        .eq('vrsta', 'potrosnja')
        .gte('created_at', startIsoUtc)
        .lt('created_at', endIsoUtc);

    if (rows.isEmpty) return 0;
    final map = Map<String, dynamic>.from(rows.first as Map);
    final sum = map['sum'] ?? map['litri'];
    return (sum as num?)?.toDouble() ?? 0;
  }

  /// Fallback: redovi potrošnje (za starije klijente / debug). Preferirati [sumPotrosnjaBetween].
  Future<List<dynamic>> selectPotrosnjaBetween({
    required String startIsoUtc,
    required String endIsoUtc,
  }) {
    return supabase
        .from('v3_gorivo_istorija')
        .select('id, vrsta, litri, created_at')
        .eq('vrsta', 'potrosnja')
        .gte('created_at', startIsoUtc)
        .lt('created_at', endIsoUtc)
        .order('created_at', ascending: true);
  }
}
