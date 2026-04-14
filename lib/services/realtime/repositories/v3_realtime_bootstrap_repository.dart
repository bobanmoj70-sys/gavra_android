import 'dart:async';

import '../../../globals.dart';

class V3RealtimeBootstrapRepository {
  static const Duration _requestTimeout = Duration(seconds: 10);
  static const Duration _bootstrapTimeout = Duration(seconds: 15);

  Future<List<dynamic>> fetchInitialData() async {
    final results = await Future.wait([
      _withTimeout('v3_adrese', supabase.from('v3_adrese').select()),
      _withTimeout(
        'v3_auth_vozaci',
        supabase
            .from('v3_auth')
            .select(
                'id, ime, telefon, telefon_2, boja, push_token, created_at, updated_at, tip')
            .eq('tip', 'vozac'),
      ),
      _withTimeout(
        'v3_auth_putnici',
        supabase
            .from('v3_auth')
            .select(
                'id, ime, telefon, telefon_2, tip, adresa_primary_bc_id, adresa_primary_vs_id, adresa_secondary_bc_id, adresa_secondary_vs_id, cena_po_danu, cena_po_pokupljenju, push_token, push_token_2, created_at, updated_at')
            .neq('tip', 'vozac'),
      ),
      _withTimeout('v3_vozila', supabase.from('v3_vozila').select()),
      _withTimeout(
        'v3_zahtevi',
        supabase.from('v3_zahtevi').select(
            'id, datum, grad, trazeni_polazak_at, broj_mesta, status, polazak_at, koristi_sekundarnu, adresa_override_id, alternativa_pre_at, alternativa_posle_at, created_at, updated_at, created_by, scheduled_at'),
      ),
      _withTimeout('v3_gorivo', supabase.from('v3_gorivo').select()),
      _withTimeout(
          'v3_vozac_lokacije', supabase.from('v3_vozac_lokacije').select()),
      _withTimeout('v3_finansije', supabase.from('v3_finansije').select()),
      _withTimeout('v3_racuni', supabase.from('v3_racuni').select()),
      _withTimeout('v3_operativna_nedelja',
          supabase.from('v3_operativna_nedelja').select()),
      _withTimeout(
          'v3_kapacitet_slots', supabase.from('v3_kapacitet_slots').select()),
      _withTimeout(
          'v3_app_settings', supabase.from('v3_app_settings').select()),
    ]).timeout(_bootstrapTimeout);

    final vozaciRaw = (results[1] as List).cast<dynamic>();
    final vozaciMapped = vozaciRaw
        .whereType<Map<String, dynamic>>()
        .map(_mapAuthToLegacyVozac)
        .toList(growable: false);
    final putniciRaw = (results[2] as List).cast<dynamic>();
    final putniciMapped = putniciRaw
        .whereType<Map<String, dynamic>>()
        .map(_mapAuthToLegacyPutnik)
        .toList(growable: false);

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
    ];
  }

  Map<String, dynamic> _mapAuthToLegacyVozac(Map<String, dynamic> row) {
    return <String, dynamic>{
      'id': row['id'],
      'ime_prezime': row['ime'],
      'telefon_1': row['telefon'],
      'telefon_2': row['telefon_2'],
      'boja': row['boja'],
      'push_token': row['push_token'],
      'created_at': row['created_at'],
      'updated_at': row['updated_at'],
    };
  }

  Map<String, dynamic> _mapAuthToLegacyPutnik(Map<String, dynamic> row) {
    return <String, dynamic>{
      'id': row['id'],
      'ime_prezime': row['ime'],
      'telefon_1': row['telefon'],
      'telefon_2': row['telefon_2'],
      'tip_putnika': row['tip'],
      'adresa_bc_id': row['adresa_primary_bc_id'],
      'adresa_vs_id': row['adresa_primary_vs_id'],
      'adresa_bc_id_2': row['adresa_secondary_bc_id'],
      'adresa_vs_id_2': row['adresa_secondary_vs_id'],
      'cena_po_danu': row['cena_po_danu'],
      'cena_po_pokupljenju': row['cena_po_pokupljenju'],
      'push_token': row['push_token'],
      'push_token_2': row['push_token_2'],
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
