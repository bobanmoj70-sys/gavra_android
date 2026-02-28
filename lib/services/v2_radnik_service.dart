import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../models/v2_registrovani_putnik.dart';
import 'realtime/v2_master_realtime_manager.dart';

/// Servis za upravljanje radnicima — tabela v2_radnici
/// Kolone: id, ime, status, telefon, telefon_2, adresa_bc_id, adresa_vs_id,
///         pin, email, cena_po_danu, broj_mesta, created_at, updated_at
class V2RadnikService {
  static SupabaseClient get _supabase => supabase;

  // ---------------------------------------------------------------------------
  // 📖 ČITANJE
  // ---------------------------------------------------------------------------

  /// Dohvata sve aktivne radnike
  static Future<List<RegistrovaniPutnik>> getAktivne() async {
    try {
      final rows = await _supabase.from('v2_radnici').select().eq('status', 'aktivan').order('ime');
      return rows.map((r) => _fromRow(r)).toList();
    } catch (e) {
      debugPrint('❌ [V2RadnikService] getAktivne error: $e');
      return [];
    }
  }

  /// Dohvata sve radnike (uključujući neaktivne)
  static Future<List<RegistrovaniPutnik>> getSve() async {
    try {
      final rows = await _supabase.from('v2_radnici').select().order('ime');
      return rows.map((r) => _fromRow(r)).toList();
    } catch (e) {
      debugPrint('❌ [V2RadnikService] getSve error: $e');
      return [];
    }
  }

  /// Dohvata radnika po ID-u
  static Future<RegistrovaniPutnik?> getById(String id) async {
    try {
      final row = await _supabase.from('v2_radnici').select().eq('id', id).maybeSingle();
      if (row == null) return null;
      return _fromRow(row);
    } catch (e) {
      debugPrint('❌ [V2RadnikService] getById error: $e');
      return null;
    }
  }

  /// Dohvata ime radnika po ID-u
  static Future<String?> getImeById(String id) async {
    try {
      final row = await _supabase.from('v2_radnici').select('ime').eq('id', id).maybeSingle();
      return row?['ime'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Pronalazi radnika po PIN-u (za autentifikaciju)
  static Future<RegistrovaniPutnik?> getByPin(String pin) async {
    try {
      final row = await _supabase.from('v2_radnici').select().eq('pin', pin).eq('status', 'aktivan').maybeSingle();
      if (row == null) return null;
      return _fromRow(row);
    } catch (e) {
      debugPrint('❌ [V2RadnikService] getByPin error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // ✏️ KREIRANJE / AŽURIRANJE
  // ---------------------------------------------------------------------------

  /// Kreira novog radnika
  static Future<RegistrovaniPutnik?> create({
    required String ime,
    String? telefon,
    String? telefon2,
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
          .from('v2_radnici')
          .insert({
            'ime': ime,
            'telefon': telefon,
            'telefon_2': telefon2,
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
      debugPrint('❌ [V2RadnikService] create error: $e');
      return null;
    }
  }

  /// Ažurira radnika
  static Future<bool> update(String id, Map<String, dynamic> updates) async {
    try {
      updates['updated_at'] = DateTime.now().toUtc().toIso8601String();
      await _supabase.from('v2_radnici').update(updates).eq('id', id);
      return true;
    } catch (e) {
      debugPrint('❌ [V2RadnikService] update error: $e');
      return false;
    }
  }

  /// Menja status radnika (aktivan/neaktivan)
  static Future<bool> setStatus(String id, String status) async {
    return update(id, {'status': status});
  }

  /// Briše radnika (trajno)
  static Future<bool> delete(String id) async {
    try {
      await _supabase.from('v2_radnici').delete().eq('id', id);
      return true;
    } catch (e) {
      debugPrint('❌ [V2RadnikService] delete error: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // 🔴 REALTIME STREAM
  // ---------------------------------------------------------------------------

  /// Stream aktivnih radnika (realtime)
  static Stream<List<RegistrovaniPutnik>> streamAktivne() {
    late final controller = StreamController<List<RegistrovaniPutnik>>.broadcast();

    Future<void> fetch() async {
      try {
        final rows = await _supabase.from('v2_radnici').select().eq('status', 'aktivan').order('ime');
        if (!controller.isClosed) {
          controller.add(rows.map((r) => _fromRow(r)).toList());
        }
      } catch (e) {
        debugPrint('❌ [V2RadnikService] streamAktivne fetch error: $e');
      }
    }

    fetch();
    final sub = V2MasterRealtimeManager.instance.subscribe('v2_radnici').listen((_) => fetch());
    controller.onCancel = () {
      sub.cancel();
      V2MasterRealtimeManager.instance.unsubscribe('v2_radnici');
    };

    return controller.stream;
  }

  // ---------------------------------------------------------------------------
  // 🔧 HELPER
  // ---------------------------------------------------------------------------

  /// Konvertuje red iz v2_radnici u RegistrovaniPutnik model
  static RegistrovaniPutnik _fromRow(Map<String, dynamic> r) {
    return RegistrovaniPutnik.fromMap({
      ...r,
      '_tabela': 'v2_radnici',
    });
  }
}
