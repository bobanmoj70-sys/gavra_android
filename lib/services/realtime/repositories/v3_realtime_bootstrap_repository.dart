import 'dart:async';

import '../../../globals.dart';

class V3RealtimeBootstrapRepository {
  static const Duration _requestTimeout = Duration(seconds: 10);
  static const Duration _bootstrapTimeout = Duration(seconds: 15);

  Future<List<dynamic>> fetchInitialData() {
    return Future.wait([
      _withTimeout('v3_adrese', supabase.from('v3_adrese').select().eq('aktivno', true)),
      _withTimeout('v3_vozaci', supabase.from('v3_vozaci').select().eq('aktivno', true)),
      _withTimeout('v3_vozila', supabase.from('v3_vozila').select().eq('aktivno', true)),
      _withTimeout('v3_putnici', supabase.from('v3_putnici').select().eq('aktivno', true)),
      _withTimeout(
        'v3_zahtevi',
        supabase
            .from('v3_zahtevi')
            .select(
                'id, putnik_id, datum, grad, zeljeno_vreme, broj_mesta, status, napomena, dodeljeno_vreme, koristi_sekundarnu, adresa_id_override, alt_vreme_pre, alt_vreme_posle, alt_napomena, aktivno, created_at, updated_at, created_by, scheduled_at')
            .eq('aktivno', true),
      ),
      _withTimeout('v3_gorivo', supabase.from('v3_gorivo').select().eq('aktivno', true)),
      _withTimeout('v3_gorivo_promene', supabase.from('v3_gorivo_promene').select()),
      _withTimeout('v3_vozac_lokacije', supabase.from('v3_vozac_lokacije').select()),
      _withTimeout('v3_finansije', supabase.from('v3_finansije').select().eq('aktivno', true)),
      _withTimeout('v3_racuni', supabase.from('v3_racuni').select().eq('aktivno', true)),
      _withTimeout('v3_racuni_arhiva', supabase.from('v3_racuni_arhiva').select().eq('aktivno', true)),
      _withTimeout('v3_operativna_nedelja', supabase.from('v3_operativna_nedelja').select()),
      _withTimeout('v3_gps_trip_state', supabase.from('v3_gps_trip_state').select()),
      _withTimeout('v3_trip_stops', supabase.from('v3_trip_stops').select()),
      _withTimeout('v3_kapacitet_slots', supabase.from('v3_kapacitet_slots').select().eq('aktivno', true)),
      _withTimeout('v3_app_settings', supabase.from('v3_app_settings').select()),
    ]).timeout(_bootstrapTimeout);
  }

  Future<dynamic> _withTimeout(String table, Future<dynamic> future) async {
    try {
      return await future.timeout(_requestTimeout);
    } on TimeoutException {
      throw TimeoutException('Timeout while loading $table', _requestTimeout);
    }
  }
}
