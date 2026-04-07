import 'dart:async';

import '../../../globals.dart';

class V3RealtimeBootstrapRepository {
  static const Duration _requestTimeout = Duration(seconds: 10);
  static const Duration _bootstrapTimeout = Duration(seconds: 15);

  Future<List<dynamic>> fetchInitialData() async {
    final results = await Future.wait([
      _withTimeout('v3_adrese', supabase.from('v3_adrese').select().eq('aktivno', true)),
      _withTimeout(
        'v3_vozaci',
        supabase
            .from('v3_auth')
            .select('auth_id, ime, telefon, telefon_2, boja, push_token, aktivno, created_at, updated_at, tip')
            .eq('tip', 'vozac')
            .eq('aktivno', true),
      ),
      _withTimeout(
        'v3_putnici',
        supabase
            .from('v3_auth')
            .select(
                'auth_id, ime, telefon, telefon_2, tip, adresa_bc_id, adresa_vs_id, adresa_bc_id_2, adresa_vs_id_2, cena_po_danu, cena_po_pokupljenju, push_token, push_token_2, aktivno, created_at, updated_at')
            .neq('tip', 'vozac')
            .eq('aktivno', true),
      ),
      _withTimeout('v3_vozila', supabase.from('v3_vozila').select().eq('aktivno', true)),
      _withTimeout(
        'v3_zahtevi',
        supabase
            .from('v3_zahtevi')
            .select(
                'id, putnik_id:created_by, datum, grad, zeljeno_vreme, broj_mesta, status, napomena:alt_napomena, dodeljeno_vreme, koristi_sekundarnu, adresa_id_override, alt_vreme_pre, alt_vreme_posle, alt_napomena, aktivno, created_at, updated_at, created_by, scheduled_at')
            .eq('aktivno', true),
      ),
      _withTimeout('v3_gorivo', supabase.from('v3_gorivo').select().eq('aktivno', true)),
      _withTimeout('v3_gorivo_promene', supabase.from('v3_gorivo_promene').select()),
      _withTimeout('v3_vozac_lokacije', supabase.from('v3_vozac_lokacije').select()),
      _withTimeout('v3_finansije', supabase.from('v3_finansije').select().eq('aktivno', true)),
      _withTimeout('v3_racuni', supabase.from('v3_racuni').select().eq('aktivno', true)),
      _withTimeout('v3_racuni_arhiva', supabase.from('v3_racuni_arhiva').select().eq('aktivno', true)),
      _withTimeout('v3_operativna_nedelja', supabase.from('v3_operativna_nedelja').select()),
      _withTimeout('v3_kapacitet_slots', supabase.from('v3_kapacitet_slots').select().eq('aktivno', true)),
      _withTimeout('v3_app_settings', supabase.from('v3_app_settings').select()),
    ]).timeout(_bootstrapTimeout);

    final vozaciRaw = (results[1] as List).cast<dynamic>();
    final vozaciMapped = vozaciRaw.whereType<Map<String, dynamic>>().map(_mapAuthToLegacyVozac).toList(growable: false);
    final putniciRaw = (results[2] as List).cast<dynamic>();
    final putniciMapped =
        putniciRaw.whereType<Map<String, dynamic>>().map(_mapAuthToLegacyPutnik).toList(growable: false);

    return <dynamic>[
      results[0],
      vozaciMapped,
      putniciMapped,
      results[3],
      results[4],
      results[5],
      results[6],
      results[7],
      results[8],
      results[9],
      results[10],
      results[11],
      results[12],
      results[13],
    ];
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

  Future<dynamic> _withTimeout(String table, Future<dynamic> future) async {
    try {
      return await future.timeout(_requestTimeout);
    } on TimeoutException {
      throw TimeoutException('Timeout while loading $table', _requestTimeout);
    }
  }
}
