import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../models/registrovani_putnik.dart';
import 'realtime/v2_master_realtime_manager.dart';

/// Servis za upravljanje učenicima — tabela v2_ucenici
/// Kolone: id, ime, status, telefon, telefon_oca, telefon_majke,
///         adresa_bc_id, adresa_vs_id, pin, email, cena_po_danu, broj_mesta,
///         created_at, updated_at
class V2UcenikService {
  static SupabaseClient get _supabase => supabase;

  // ---------------------------------------------------------------------------
  // 📖 ČITANJE
  // ---------------------------------------------------------------------------

  /// Dohvata sve aktivne učenike
  static Future<List<RegistrovaniPutnik>> getAktivne() async {
    try {
      final rows = await _supabase.from('v2_ucenici').select().eq('status', 'aktivan').order('ime');
      return rows.map((r) => _fromRow(r)).toList();
    } catch (e) {
      debugPrint('❌ [V2UcenikService] getAktivne error: $e');
      return [];
    }
  }

  /// Dohvata sve učenike (uključujući neaktivne)
  static Future<List<RegistrovaniPutnik>> getSve() async {
    try {
      final rows = await _supabase.from('v2_ucenici').select().order('ime');
      return rows.map((r) => _fromRow(r)).toList();
    } catch (e) {
      debugPrint('❌ [V2UcenikService] getSve error: $e');
      return [];
    }
  }

  /// Dohvata učenika po ID-u
  static Future<RegistrovaniPutnik?> getById(String id) async {
    try {
      final row = await _supabase.from('v2_ucenici').select().eq('id', id).maybeSingle();
      if (row == null) return null;
      return _fromRow(row);
    } catch (e) {
      debugPrint('❌ [V2UcenikService] getById error: $e');
      return null;
    }
  }

  /// Dohvata ime učenika po ID-u
  static Future<String?> getImeById(String id) async {
    try {
      final row = await _supabase.from('v2_ucenici').select('ime').eq('id', id).maybeSingle();
      return row?['ime'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Pronalazi učenika po PIN-u (za autentifikaciju)
  static Future<RegistrovaniPutnik?> getByPin(String pin) async {
    try {
      final row = await _supabase.from('v2_ucenici').select().eq('pin', pin).eq('status', 'aktivan').maybeSingle();
      if (row == null) return null;
      return _fromRow(row);
    } catch (e) {
      debugPrint('❌ [V2UcenikService] getByPin error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // ✏️ KREIRANJE / AŽURIRANJE
  // ---------------------------------------------------------------------------

  /// Kreira novog učenika
  static Future<RegistrovaniPutnik?> create({
    required String ime,
    String? telefon,
    String? telefonOca,
    String? telefonMajke,
    String? adresaBcId,
    String? adresaVsId,
    String? pin,
    String? email,
    double? cenaPosDanu,
    int? brojMesta,
    String status = 'aktivan',
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final row = await _supabase
          .from('v2_ucenici')
          .insert({
            'ime': ime,
            'telefon': telefon,
            'telefon_oca': telefonOca,
            'telefon_majke': telefonMajke,
            'adresa_bc_id': adresaBcId,
            'adresa_vs_id': adresaVsId,
            'pin': pin,
            'email': email,
            'cena_po_danu': cenaPosDanu,
            'broj_mesta': brojMesta,
            'status': status,
            'created_at': now,
            'updated_at': now,
          })
          .select()
          .single();
      return _fromRow(row);
    } catch (e) {
      debugPrint('❌ [V2UcenikService] create error: $e');
      return null;
    }
  }

  /// Ažurira učenika
  static Future<bool> update(String id, Map<String, dynamic> updates) async {
    try {
      updates['updated_at'] = DateTime.now().toUtc().toIso8601String();
      await _supabase.from('v2_ucenici').update(updates).eq('id', id);
      return true;
    } catch (e) {
      debugPrint('❌ [V2UcenikService] update error: $e');
      return false;
    }
  }

  /// Menja status učenika (aktivan/neaktivan)
  static Future<bool> setStatus(String id, String status) async {
    return update(id, {'status': status});
  }

  /// Briše učenika (trajno)
  static Future<bool> delete(String id) async {
    try {
      await _supabase.from('v2_ucenici').delete().eq('id', id);
      return true;
    } catch (e) {
      debugPrint('❌ [V2UcenikService] delete error: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // 🔴 REALTIME STREAM
  // ---------------------------------------------------------------------------

  /// Stream aktivnih učenika (realtime)
  static Stream<List<RegistrovaniPutnik>> streamAktivne() {
    late final controller = StreamController<List<RegistrovaniPutnik>>.broadcast();

    Future<void> fetch() async {
      try {
        final rows = await _supabase.from('v2_ucenici').select().eq('status', 'aktivan').order('ime');
        if (!controller.isClosed) {
          controller.add(rows.map((r) => _fromRow(r)).toList());
        }
      } catch (e) {
        debugPrint('❌ [V2UcenikService] streamAktivne fetch error: $e');
      }
    }

    fetch();
    final sub = V2MasterRealtimeManager.instance.subscribe('v2_ucenici').listen((_) => fetch());
    controller.onCancel = () {
      sub.cancel();
      V2MasterRealtimeManager.instance.unsubscribe('v2_ucenici');
    };

    return controller.stream;
  }

  // ---------------------------------------------------------------------------
  // 🔧 HELPER
  // ---------------------------------------------------------------------------

  /// Konvertuje red iz v2_ucenici u RegistrovaniPutnik model
  static RegistrovaniPutnik _fromRow(Map<String, dynamic> r) {
    return RegistrovaniPutnik.fromMap({
      ...r,
      'tip': 'ucenik',
      'putnik_ime': r['ime'],
      'broj_telefona': r['telefon'],
      // učenici imaju telefon_oca i telefon_majke — mapiramo oca kao primarni drugi
      'broj_telefona_2': r['telefon_oca'] ?? r['telefon_majke'],
      'adresa_bela_crkva_id': r['adresa_bc_id'],
      'adresa_vrsac_id': r['adresa_vs_id'],
      // cena_po_danu i broj_mesta su isti nazivi — direktno se proslede
    });
  }
}
