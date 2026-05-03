import 'dart:async';

import '../../../globals.dart';

class V3RealtimeBootstrapRepository {
  static const Duration _requestTimeout = Duration(seconds: 15);
  static const Duration _criticalRequestTimeout = Duration(seconds: 20);

  Future<List<dynamic>> fetchInitialData() async {
    final results = <dynamic>[];

    results.add(
      await _fetchTableRows(
        table: 'v3_adrese',
        query: () => supabase.from('v3_adrese').select(),
      ),
    );
    results.add(
      await _fetchTableRows(
        table: 'v3_auth',
        query: () => supabase.from('v3_auth').select(),
        timeout: _criticalRequestTimeout,
        retries: 3,
        requiredTable: true,
      ),
    );
    results.add(
      await _fetchTableRows(
        table: 'v3_vozila',
        query: () => supabase.from('v3_vozila').select(),
      ),
    );
    results.add(
      await _fetchTableRows(
        table: 'v3_zahtevi',
        query: () => supabase.from('v3_zahtevi').select(
            'id, datum, grad, trazeni_polazak_at, status, polazak_at, koristi_sekundarnu, adresa_override_id, alternativa_pre_at, alternativa_posle_at, created_at, updated_at, created_by, scheduled_at'),
      ),
    );
    results.add(
      await _fetchTableRows(
        table: 'v3_gorivo',
        query: () => supabase.from('v3_gorivo').select(),
      ),
    );
    results.add(
      await _fetchTableRows(
        table: 'v3_finansije',
        query: () => supabase.from('v3_finansije').select(),
      ),
    );
    results.add(
      await _fetchTableRows(
        table: 'v3_racuni',
        query: () => supabase.from('v3_racuni').select(),
      ),
    );
    results.add(
      await _fetchTableRows(
        table: 'v3_operativna_nedelja',
        query: () => supabase.from('v3_operativna_nedelja').select(),
      ),
    );
    results.add(
      await _fetchTableRows(
        table: 'v3_kapacitet_slots',
        query: () => supabase.from('v3_kapacitet_slots').select(),
      ),
    );
    results.add(
      await _fetchTableRows(
        table: 'v3_app_settings',
        query: () => supabase.from('v3_app_settings').select(),
        timeout: _criticalRequestTimeout,
        retries: 3,
        requiredTable: true,
      ),
    );

    return results;
  }

  Future<List<dynamic>> _fetchTableRows({
    required String table,
    required Future<dynamic> Function() query,
    Duration timeout = _requestTimeout,
    int retries = 1,
    bool requiredTable = false,
  }) async {
    Object? lastError;

    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        final response = await query().timeout(timeout);
        if (response is List) {
          return response.cast<dynamic>();
        }
        return <dynamic>[];
      } catch (e) {
        lastError = e;
      }

      if (attempt < retries) {
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      }
    }

    if (requiredTable) {
      if (lastError is TimeoutException) {
        throw TimeoutException('Timeout while loading $table', timeout);
      }
      throw StateError('Failed while loading $table: $lastError');
    }

    return <dynamic>[];
  }
}
