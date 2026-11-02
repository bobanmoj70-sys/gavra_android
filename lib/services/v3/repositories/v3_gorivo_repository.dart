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

  /// Dnevni prosek potrošnje po radnim danima (pon–pet) — RPC agregat.
  /// Vraća jedan red: prosek_litri, radnih_dana, ukupno_litri.
  Future<dynamic> selectDnevniProsek() {
    return supabase.rpc('v3_gorivo_dnevni_prosek');
  }

  /// Dnevni prosek uplata za gorivo (RSD) po radnim danima — RPC agregat.
  /// Vraća jedan red: prosek_rsd, radnih_dana, ukupno_rsd.
  Future<dynamic> selectDnevniProsekUplata() {
    return supabase.rpc('v3_gorivo_dnevni_prosek_uplata');
  }

  /// Najraniji created_at evidentiranog sipanja/potrošnje (bez inicijalnog importa).
  Future<String?> selectPrviDatumGoriva() async {
    final rows = await supabase
        .from('v3_gorivo_istorija')
        .select('created_at')
        .inFilter('vrsta', ['potrosnja', 'dopuna'])
        .or('source.is.null,source.neq.inicijalni_import')
        .order('created_at', ascending: true)
        .limit(1);
    if (rows.isEmpty) return null;
    return rows.first['created_at']?.toString();
  }

  /// Fallback za [selectDnevniProsek]: svi redovi potrošnje, straničeno.
  Future<List<dynamic>> selectPotrosnjaSve({int pageSize = 1000, int maxPages = 30}) async {
    final all = <dynamic>[];
    for (var page = 0; page < maxPages; page++) {
      final rows = await supabase
          .from('v3_gorivo_istorija')
          .select('litri, source, created_at')
          .eq('vrsta', 'potrosnja')
          .order('created_at', ascending: true)
          .range(page * pageSize, (page + 1) * pageSize - 1);
      all.addAll(rows);
      if (rows.length < pageSize) break;
    }
    return all;
  }

  /// Fallback za [selectDnevniProsekUplata]: svi redovi uplata, straničeno.
  Future<List<dynamic>> selectUplateSve({int pageSize = 1000, int maxPages = 30}) async {
    final all = <dynamic>[];
    for (var page = 0; page < maxPages; page++) {
      final rows = await supabase
          .from('v3_gorivo_istorija')
          .select('dug_promena')
          .eq('vrsta', 'uplata')
          .order('created_at', ascending: true)
          .range(page * pageSize, (page + 1) * pageSize - 1);
      all.addAll(rows);
      if (rows.length < pageSize) break;
    }
    return all;
  }

  /// Istorija dopuna, uplata i korekcija duga, najnovije prvo.
  Future<List<dynamic>> selectDopuneIUplate({int limit = 100}) {
    return supabase
        .from('v3_gorivo_istorija')
        .select('id, vrsta, litri, cena_po_litru, dug_promena, napomena, source, created_at')
        .inFilter('vrsta', ['dopuna', 'uplata', 'korekcija'])
        .order('created_at', ascending: false)
        .limit(limit);
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
