import 'dart:async';

import '../../../globals.dart';

class V3RealtimeBootstrapRepository {
  static const Duration _requestTimeout = Duration(seconds: 15);

  Future<List<dynamic>> fetchInitialData() async {
    final results = await Future.wait([
      _withTimeout('v3_adrese', supabase.from('v3_adrese').select()),
      _withTimeout('v3_auth', supabase.from('v3_auth').select()),
      _withTimeout('v3_vozila', supabase.from('v3_vozila').select()),
      _withTimeout(
        'v3_zahtevi',
        supabase.from('v3_zahtevi').select(
            'id, datum, grad, trazeni_polazak_at, status, polazak_at, koristi_sekundarnu, adresa_override_id, alternativa_pre_at, alternativa_posle_at, created_at, updated_at, created_by, scheduled_at'),
      ),
      _withTimeout('v3_gorivo', supabase.from('v3_gorivo').select()),
      _withTimeout('v3_finansije', supabase.from('v3_finansije').select()),
      _withTimeout('v3_racuni', supabase.from('v3_racuni').select()),
      _withTimeout('v3_operativna_nedelja', supabase.from('v3_operativna_nedelja').select()),
      _withTimeout('v3_kapacitet_slots', supabase.from('v3_kapacitet_slots').select()),
      _withTimeout('v3_app_settings', supabase.from('v3_app_settings').select()),
    ]);

    return results;
  }

  Future<dynamic> _withTimeout(String table, Future<dynamic> future) async {
    try {
      return await future.timeout(_requestTimeout);
    } on TimeoutException {
      throw TimeoutException('Timeout while loading $table', _requestTimeout);
    }
  }
}
