import '../../../globals.dart';

class V3RealtimeBootstrapRepository {
  Future<List<dynamic>> fetchInitialData() {
    return Future.wait([
      supabase.from('v3_adrese').select().eq('aktivno', true),
      supabase.from('v3_vozaci').select().eq('aktivno', true),
      supabase.from('v3_vozila').select().eq('aktivno', true),
      supabase.from('v3_putnici').select().eq('aktivno', true),
      supabase
          .from('v3_zahtevi')
          .select(
              'id, putnik_id, datum, grad, zeljeno_vreme, broj_mesta, status, napomena, dodeljeno_vreme, koristi_sekundarnu, adresa_id_override, alt_vreme_pre, alt_vreme_posle, alt_napomena, aktivno, created_at, updated_at, created_by, scheduled_at')
          .eq('aktivno', true),
      supabase.from('v3_gorivo').select().eq('aktivno', true),
      supabase.from('v3_gorivo_promene').select(),
      supabase.from('v3_vozac_lokacije').select(),
      supabase.from('v3_finansije').select().eq('aktivno', true),
      supabase.from('v3_pin_zahtevi').select().eq('status', 'ceka'),
      supabase.from('v3_operativna_nedelja').select(),
      supabase.from('v3_gps_trip_state').select(),
      supabase.from('v3_trip_stops').select(),
      supabase.from('v3_kapacitet_slots').select().eq('aktivno', true),
      supabase.from('v3_app_settings').select(),
    ]);
  }
}
