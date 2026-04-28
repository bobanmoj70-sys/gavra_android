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
      'v3_auth': (results[1] as List).cast<dynamic>(),
      'v3_vozila': (results[2] as List).cast<dynamic>(),
      'v3_zahtevi': (results[3] as List).cast<dynamic>(),
      'v3_gorivo': (results[4] as List).cast<dynamic>(),
      'v3_finansije': (results[5] as List).cast<dynamic>(),
      'v3_racuni': (results[6] as List).cast<dynamic>(),
      'v3_operativna_nedelja': (results[7] as List).cast<dynamic>(),
      'v3_kapacitet_slots': (results[8] as List).cast<dynamic>(),
      'v3_app_settings': (results[9] as List).cast<dynamic>(),
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
      case 'v3_kapacitet_slots':
        response = await _client.from(table).select().gte('updated_at', iso);
        break;
      case 'v3_finansije':
        response = await _client.from(table).select().gte('updated_at', iso);
        break;
      case 'v3_racuni':
      case 'v3_gorivo':
      case 'v3_app_settings':
        response = await _client.from(table).select().gte('updated_at', iso);
        break;
      case 'v3_auth':
        response = await _client.from('v3_auth').select().gte('updated_at', iso);
        break;
      case 'v3_zahtevi':
        response = await _client
            .from('v3_zahtevi')
            .select(
                'id, datum, grad, trazeni_polazak_at, broj_mesta, status, polazak_at, koristi_sekundarnu, adresa_override_id, alternativa_pre_at, alternativa_posle_at, created_at, updated_at, created_by, scheduled_at')
            .gte('updated_at', iso);
        break;
      case 'v3_operativna_nedelja':
        response = await _client.from(table).select().gte('updated_at', iso);
        break;
      default:
        return <Map<String, dynamic>>[];
    }

    if (response is! List) return <Map<String, dynamic>>[];

    return response.whereType<Map<String, dynamic>>().map(Map<String, dynamic>.from).toList(growable: false);
  }

  Future<Map<String, List<Map<String, dynamic>>>> loadDeltaAll(Map<String, DateTime?> watermarks) async {
    final tables = V3RealtimeTableRegistry.defaults.where((t) => watermarks[t.name] != null).toList(growable: false);

    if (tables.isEmpty) return {};

    final results = await Future.wait(
      tables.map((t) => loadDelta(table: t.name, since: watermarks[t.name]!)),
    );

    final out = <String, List<Map<String, dynamic>>>{};
    for (var i = 0; i < tables.length; i++) {
      if (results[i].isNotEmpty) {
        out[tables[i].name] = results[i];
      }
    }
    return out;
  }
}
