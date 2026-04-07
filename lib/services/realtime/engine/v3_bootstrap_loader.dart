import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../globals.dart';
import '../repositories/v3_realtime_bootstrap_repository.dart';
import 'v3_table_registry.dart';

class V3BootstrapLoader {
  V3BootstrapLoader({
    required V3RealtimeBootstrapRepository repository,
    SupabaseClient? client,
  })  : _repository = repository,
        _client = client ?? supabase;

  final V3RealtimeBootstrapRepository _repository;
  final SupabaseClient _client;

  Future<Map<String, List<dynamic>>> loadFull() async {
    final results = await _repository.fetchInitialData();
    return <String, List<dynamic>>{
      'v3_adrese': (results[0] as List).cast<dynamic>(),
      'v3_vozaci': (results[1] as List).cast<dynamic>(),
      'v3_putnici': (results[2] as List).cast<dynamic>(),
      'v3_vozila': (results[3] as List).cast<dynamic>(),
      'v3_zahtevi': (results[4] as List).cast<dynamic>(),
      'v3_gorivo': (results[5] as List).cast<dynamic>(),
      'v3_gorivo_promene': (results[6] as List).cast<dynamic>(),
      'v3_vozac_lokacije': (results[7] as List).cast<dynamic>(),
      'v3_finansije': (results[8] as List).cast<dynamic>(),
      'v3_racuni': (results[9] as List).cast<dynamic>(),
      'v3_racuni_arhiva': (results[10] as List).cast<dynamic>(),
      'v3_operativna_nedelja': (results[11] as List).cast<dynamic>(),
      'v3_kapacitet_slots': (results[12] as List).cast<dynamic>(),
      'v3_app_settings': (results[13] as List).cast<dynamic>(),
    };
  }

  Future<List<Map<String, dynamic>>> loadDelta({
    required String table,
    required DateTime since,
  }) async {
    dynamic response;
    final iso = since.toUtc().toIso8601String();

    switch (table) {
      case 'v3_adrese':
      case 'v3_vozila':
      case 'v3_gorivo':
      case 'v3_finansije':
      case 'v3_racuni':
      case 'v3_racuni_arhiva':
      case 'v3_kapacitet_slots':
        response = await _client.from(table).select().gte('updated_at', iso);
        break;
      case 'v3_vozaci':
        response = await _client
            .from('v3_auth')
            .select('auth_id, ime, telefon, telefon_2, boja, push_token, aktivno, created_at, updated_at, tip')
            .eq('tip', 'vozac')
            .gte('updated_at', iso);
        break;
      case 'v3_putnici':
        response = await _client
            .from('v3_auth')
            .select(
                'auth_id, ime, telefon, telefon_2, tip, adresa_bc_id, adresa_vs_id, adresa_bc_id_2, adresa_vs_id_2, cena_po_danu, cena_po_pokupljenju, push_token, push_token_2, aktivno, created_at, updated_at')
            .neq('tip', 'vozac')
            .gte('updated_at', iso);
        break;
      case 'v3_zahtevi':
        response = await _client
            .from('v3_zahtevi')
            .select(
                'id, putnik_id:created_by, datum, grad, zeljeno_vreme, broj_mesta, status, napomena:alt_napomena, dodeljeno_vreme, koristi_sekundarnu, adresa_id_override, alt_vreme_pre, alt_vreme_posle, alt_napomena, aktivno, created_at, updated_at, created_by, scheduled_at')
            .gte('updated_at', iso);
        break;
      case 'v3_gorivo_promene':
      case 'v3_vozac_lokacije':
      case 'v3_operativna_nedelja':
      case 'v3_app_settings':
        response = await _client.from(table).select().gte('updated_at', iso);
        break;
      default:
        return <Map<String, dynamic>>[];
    }

    if (response is! List) return <Map<String, dynamic>>[];

    final rows = response.whereType<Map<String, dynamic>>().map(Map<String, dynamic>.from).toList(growable: false);
    if (table == 'v3_vozaci') {
      return rows.map(_mapAuthToLegacyVozac).toList(growable: false);
    }
    if (table == 'v3_putnici') {
      return rows.map(_mapAuthToLegacyPutnik).toList(growable: false);
    }

    return rows;
  }

  Map<String, dynamic> _mapAuthToLegacyVozac(Map<String, dynamic> row) {
    return <String, dynamic>{
      'id': row['auth_id'],
      'ime_prezime': row['ime'],
      'telefon_1': row['telefon'],
      'telefon_2': row['telefon_2'],
      'boja': row['boja'],
      'push_token': row['push_token'],
      'aktivno': row['aktivno'] ?? true,
      'created_at': row['created_at'],
      'updated_at': row['updated_at'],
    };
  }

  Map<String, dynamic> _mapAuthToLegacyPutnik(Map<String, dynamic> row) {
    return <String, dynamic>{
      'id': row['auth_id'],
      'ime_prezime': row['ime'],
      'telefon_1': row['telefon'],
      'telefon_2': row['telefon_2'],
      'tip_putnika': row['tip'],
      'adresa_bc_id': row['adresa_bc_id'],
      'adresa_vs_id': row['adresa_vs_id'],
      'adresa_bc_id_2': row['adresa_bc_id_2'],
      'adresa_vs_id_2': row['adresa_vs_id_2'],
      'cena_po_danu': row['cena_po_danu'],
      'cena_po_pokupljenju': row['cena_po_pokupljenju'],
      'push_token': row['push_token'],
      'push_token_2': row['push_token_2'],
      'aktivno': row['aktivno'] ?? true,
      'created_at': row['created_at'],
      'updated_at': row['updated_at'],
    };
  }

  Future<Map<String, List<Map<String, dynamic>>>> loadDeltaAll(Map<String, DateTime?> watermarks) async {
    final out = <String, List<Map<String, dynamic>>>{};

    for (final table in V3RealtimeTableRegistry.defaults) {
      final since = watermarks[table.name];
      if (since == null) continue;

      final deltaRows = await loadDelta(table: table.name, since: since);
      if (deltaRows.isNotEmpty) {
        out[table.name] = deltaRows;
      }
    }

    return out;
  }
}
