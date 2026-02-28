import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../models/v2_registrovani_putnik.dart';
import 'realtime/v2_master_realtime_manager.dart';

/// Servis za upravljanje pošiljkama — tabela v2_posiljke
/// Kolone: id, ime, status, telefon, adresa_bc_id, adresa_vs_id, cena, created_at, updated_at
class V2PosiljkaService {
  static SupabaseClient get _supabase => supabase;

  // ---------------------------------------------------------------------------
  // 📖 ČITANJE
  // ---------------------------------------------------------------------------

  /// Dohvata sve aktivne pošiljke
  static Future<List<RegistrovaniPutnik>> getAktivne() async {
    try {
      final rows = await _supabase.from('v2_posiljke').select().eq('status', 'aktivan').order('ime');
      return rows.map((r) => _fromRow(r)).toList();
    } catch (e) {
      debugPrint('❌ [V2PosiljkaService] getAktivne error: $e');
      return [];
    }
  }

  /// Dohvata sve pošiljke (uključujući neaktivne)
  static Future<List<RegistrovaniPutnik>> getSve() async {
    try {
      final rows = await _supabase.from('v2_posiljke').select().order('ime');
      return rows.map((r) => _fromRow(r)).toList();
    } catch (e) {
      debugPrint('❌ [V2PosiljkaService] getSve error: $e');
      return [];
    }
  }

  /// Dohvata pošiljku po ID-u
  static Future<RegistrovaniPutnik?> getById(String id) async {
    try {
      final row = await _supabase.from('v2_posiljke').select().eq('id', id).maybeSingle();
      if (row == null) return null;
      return _fromRow(row);
    } catch (e) {
      debugPrint('❌ [V2PosiljkaService] getById error: $e');
      return null;
    }
  }

  /// Dohvata ime pošiljke po ID-u (brzo, samo ime kolona)
  static Future<String?> getImeById(String id) async {
    try {
      final row = await _supabase.from('v2_posiljke').select('ime').eq('id', id).maybeSingle();
      return row?['ime'] as String?;
    } catch (e) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // ✏️ KREIRANJE / AŽURIRANJE
  // ---------------------------------------------------------------------------

  /// Kreira novu pošiljku
  static Future<RegistrovaniPutnik?> create({
    required String ime,
    String? telefon,
    String? adresaBcId,
    String? adresaVsId,
    double? cena,
    String status = 'aktivan',
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final row = await _supabase
          .from('v2_posiljke')
          .insert({
            'ime': ime,
            'telefon': telefon,
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
      debugPrint('❌ [V2PosiljkaService] create error: $e');
      return null;
    }
  }

  /// Ažurira pošiljku
  static Future<bool> update(String id, Map<String, dynamic> updates) async {
    try {
      updates['updated_at'] = DateTime.now().toUtc().toIso8601String();
      await _supabase.from('v2_posiljke').update(updates).eq('id', id);
      return true;
    } catch (e) {
      debugPrint('❌ [V2PosiljkaService] update error: $e');
      return false;
    }
  }

  /// Menja status pošiljke (aktivan/neaktivan)
  static Future<bool> setStatus(String id, String status) async {
    return update(id, {'status': status});
  }

  /// Briše pošiljku (trajno)
  static Future<bool> delete(String id) async {
    try {
      await _supabase.from('v2_posiljke').delete().eq('id', id);
      return true;
    } catch (e) {
      debugPrint('❌ [V2PosiljkaService] delete error: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // 🔴 REALTIME STREAM
  // ---------------------------------------------------------------------------

  /// Stream aktivnih pošiljki (realtime)
  static Stream<List<RegistrovaniPutnik>> streamAktivne() {
    late final controller = StreamController<List<RegistrovaniPutnik>>.broadcast();

    Future<void> fetch() async {
      try {
        final rows = await _supabase.from('v2_posiljke').select().eq('status', 'aktivan').order('ime');
        if (!controller.isClosed) {
          controller.add(rows.map((r) => _fromRow(r)).toList());
        }
      } catch (e) {
        debugPrint('❌ [V2PosiljkaService] streamAktivne fetch error: $e');
      }
    }

    fetch();
    final sub = V2MasterRealtimeManager.instance.subscribe('v2_posiljke').listen((_) => fetch());
    controller.onCancel = () {
      sub.cancel();
      V2MasterRealtimeManager.instance.unsubscribe('v2_posiljke');
    };

    return controller.stream;
  }

  // ---------------------------------------------------------------------------
  // 🔧 HELPER
  // ---------------------------------------------------------------------------

  /// Konvertuje red iz v2_posiljke u RegistrovaniPutnik model
  static RegistrovaniPutnik _fromRow(Map<String, dynamic> r) {
    return RegistrovaniPutnik.fromMap({
      ...r,
      '_tabela': 'v2_posiljke',
    });
  }
}
