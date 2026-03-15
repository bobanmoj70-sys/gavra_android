import 'package:flutter/material.dart';

import '../../globals.dart';
import '../../models/v3_vozac.dart';
import '../realtime/v3_master_realtime_manager.dart';

/// Service for V3 drivers (`v3_vozaci`).
class V3VozacService {
  V3VozacService._();

  static V3Vozac? currentVozac;

  static List<V3Vozac> getAllVozaci() {
    final cache = V3MasterRealtimeManager.instance.vozaciCache.values;
    return cache.map((r) => V3Vozac.fromJson(r)).toList()..sort((a, b) => a.imePrezime.compareTo(b.imePrezime));
  }

  static Stream<List<V3Vozac>> streamVozaci() => V3MasterRealtimeManager.instance.v3StreamFromCache(
        tables: ['v3_vozaci'],
        build: () => getAllVozaci(),
      );

  static V3Vozac? getVozacById(String id) {
    final data = V3MasterRealtimeManager.instance.vozaciCache[id];
    return data != null ? V3Vozac.fromJson(data) : null;
  }

  static V3Vozac? getVozacByName(String name) {
    final cache = V3MasterRealtimeManager.instance.vozaciCache.values;
    try {
      final match = cache.firstWhere(
        (r) => r['ime_prezime'].toString().toLowerCase() == name.toLowerCase(),
      );
      return V3Vozac.fromJson(match);
    } catch (_) {
      return null;
    }
  }

  static Future<void> addUpdateVozac(V3Vozac vozac) async {
    try {
      if (vozac.id.isNotEmpty) {
        // Edit — ne diramo push_token
        await supabase.from('v3_vozaci').update({
          'ime_prezime': vozac.imePrezime,
          'telefon_1': vozac.telefon1,
          'telefon_2': vozac.telefon2,
          'email': vozac.email,
          'sifra': vozac.sifra,
          'boja': vozac.boja,
          'aktivno': vozac.aktivno,
        }).eq('id', vozac.id);
      } else {
        // Add — insert novog vozača (bez push_token, dobija ga pri prvom loginu)
        await supabase.from('v3_vozaci').insert({
          'ime_prezime': vozac.imePrezime,
          'telefon_1': vozac.telefon1,
          'telefon_2': vozac.telefon2,
          'email': vozac.email,
          'sifra': vozac.sifra,
          'boja': vozac.boja,
          'aktivno': vozac.aktivno,
        });
      }
    } catch (e) {
      debugPrint('[V3VozacService] Error: $e');
      rethrow;
    }
  }

  static Future<void> deactivateVozac(String id) async {
    try {
      await supabase.from('v3_vozaci').update({'aktivno': false}).eq('id', id);
    } catch (e) {
      debugPrint('[V3VozacService] Deactivate error: $e');
      rethrow;
    }
  }

  /// Vraća boju vozača raspoređenog za dati dan/grad/vreme.
  /// [danPuni] — puni naziv dana (npr. 'Ponedeljak'), konvertuje se u ISO datum tekuće sedmice.
  static Color? getVozacColorForTermin(String danPuni, String grad, String vreme) {
    final datumIso = V3DanHelper.datumIsoZaDanPuni(danPuni);
    if (datumIso.isEmpty) return null;

    final rm = V3MasterRealtimeManager.instance;
    try {
      final termin = rm.rasporedTerminCache.values.firstWhere(
        (r) =>
            (r['datum'] as String?)?.split('T')[0] == datumIso &&
            r['grad']?.toString().toUpperCase() == grad.toUpperCase() &&
            r['vreme']?.toString() == vreme &&
            r['aktivno'] == true,
      );
      final vozacId = termin['vozac_id']?.toString();
      if (vozacId == null) return null;
      final vozac = rm.vozaciCache[vozacId];
      final hex = vozac?['boja']?.toString();
      if (hex == null || hex.isEmpty) return null;
      final clean = hex.replaceFirst('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return null;
    }
  }
}
