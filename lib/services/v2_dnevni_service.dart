import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../models/registrovani_putnik.dart';
import 'realtime/v2_master_realtime_manager.dart';

/// Servis za upravljanje dnevnim putnicima — tabela v2_dnevni
/// Kolone: id, ime, status, telefon, telefon_2, adresa_bc_id, adresa_vs_id, cena, created_at, updated_at
class V2DnevniService {
  static SupabaseClient get _supabase => supabase;

  // ---------------------------------------------------------------------------
  // 📖 ČITANJE
  // ---------------------------------------------------------------------------

  /// Dohvata sve aktivne dnevne putnike
  static Future<List<RegistrovaniPutnik>> getAktivne() async {
    try {
      final rows = await _supabase.from('v2_dnevni').select().eq('status', 'aktivan').order('ime');
      return rows.map((r) => _fromRow(r)).toList();
    } catch (e) {
      debugPrint('❌ [V2DnevniService] getAktivne error: $e');
      return [];
    }
  }

  /// Dohvata sve dnevne putnike (uključujući neaktivne)
  static Future<List<RegistrovaniPutnik>> getSve() async {
    try {
      final rows = await _supabase.from('v2_dnevni').select().order('ime');
      return rows.map((r) => _fromRow(r)).toList();
    } catch (e) {
      debugPrint('❌ [V2DnevniService] getSve error: $e');
      return [];
    }
  }

  /// Dohvata dnevnog putnika po ID-u
  static Future<RegistrovaniPutnik?> getById(String id) async {
    try {
      final row = await _supabase.from('v2_dnevni').select().eq('id', id).maybeSingle();
      if (row == null) return null;
      return _fromRow(row);
    } catch (e) {
      debugPrint('❌ [V2DnevniService] getById error: $e');
      return null;
    }
  }

  /// Dohvata ime dnevnog putnika po ID-u
  static Future<String?> getImeById(String id) async {
    try {
      final row = await _supabase.from('v2_dnevni').select('ime').eq('id', id).maybeSingle();
      return row?['ime'] as String?;
    } catch (e) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // ✏️ KREIRANJE / AŽURIRANJE
  // ---------------------------------------------------------------------------

  /// Kreira novog dnevnog putnika
  static Future<RegistrovaniPutnik?> create({
    required String ime,
    String? telefon,
    String? telefon2,
    String? adresaBcId,
    String? adresaVsId,
    double? cena,
    String status = 'aktivan',
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final row = await _supabase
          .from('v2_dnevni')
          .insert({
            'ime': ime,
            'telefon': telefon,
            'telefon_2': telefon2,
            'adresa_bc_id': adresaBcId,
            'adresa_vs_id': adresaVsId,
            'cena': cena,
            'status': status,
            'created_at': now,
            'updated_at': now,
          })
          .select()
          .single();
      return _fromRow(row);
    } catch (e) {
      debugPrint('❌ [V2DnevniService] create error: $e');
      return null;
    }
  }

  /// Ažurira dnevnog putnika
  static Future<bool> update(String id, Map<String, dynamic> updates) async {
    try {
      updates['updated_at'] = DateTime.now().toUtc().toIso8601String();
      await _supabase.from('v2_dnevni').update(updates).eq('id', id);
      return true;
    } catch (e) {
      debugPrint('❌ [V2DnevniService] update error: $e');
      return false;
    }
  }

  /// Menja status dnevnog putnika (aktivan/neaktivan)
  static Future<bool> setStatus(String id, String status) async {
    return update(id, {'status': status});
  }

  /// Briše dnevnog putnika (trajno)
  static Future<bool> delete(String id) async {
    try {
      await _supabase.from('v2_dnevni').delete().eq('id', id);
      return true;
    } catch (e) {
      debugPrint('❌ [V2DnevniService] delete error: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // 🔴 REALTIME STREAM
  // ---------------------------------------------------------------------------

  /// Stream aktivnih dnevnih putnika (realtime)
  static Stream<List<RegistrovaniPutnik>> streamAktivne() {
    late final controller = StreamController<List<RegistrovaniPutnik>>.broadcast();

    Future<void> fetch() async {
      try {
        final rows = await _supabase.from('v2_dnevni').select().eq('status', 'aktivan').order('ime');
        if (!controller.isClosed) {
          controller.add(rows.map((r) => _fromRow(r)).toList());
        }
      } catch (e) {
        debugPrint('❌ [V2DnevniService] streamAktivne fetch error: $e');
      }
    }

    fetch();
    final sub = V2MasterRealtimeManager.instance.subscribe('v2_dnevni').listen((_) => fetch());
    controller.onCancel = () {
      sub.cancel();
      V2MasterRealtimeManager.instance.unsubscribe('v2_dnevni');
    };

    return controller.stream;
  }

  // ---------------------------------------------------------------------------
  // 🔧 HELPER
  // ---------------------------------------------------------------------------

  /// Konvertuje red iz v2_dnevni u RegistrovaniPutnik model
  static RegistrovaniPutnik _fromRow(Map<String, dynamic> r) {
    return RegistrovaniPutnik.fromMap({
      ...r,
      'tip': 'dnevni',
      'putnik_ime': r['ime'],
      'broj_telefona': r['telefon'],
      'broj_telefona_2': r['telefon_2'],
      'adresa_bela_crkva_id': r['adresa_bc_id'],
      'adresa_vrsac_id': r['adresa_vs_id'],
      'cena_po_danu': r['cena'],
    });
  }
}
