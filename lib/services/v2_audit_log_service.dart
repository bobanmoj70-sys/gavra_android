import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';

// ============================================================================
// V2AuditLogService — nepromjenljiv log svih akcija vozača i putnika
//
// TABELA: v2_audit_log
// PRAVILA:
//   - Samo INSERT, nikad UPDATE ni DELETE — audit log je historija, ne state
//   - Uvijek fire-and-forget (unawaited) osim kad je kritično da se sačeka
//   - Greške se gutaju tiho (logguju na debugPrint) — audit ne smije blokirati UI
//   - aktor_tip: 'vozac' | 'putnik' | 'admin'
//
// TIPOVI AKCIJA (tip kolona):
//   VOZAČ:
//     pokupljen            — vozač označi putnika pokupljenim
//     otkazano_vozac       — vozač otkaže putnika
//     naplata              — vozač naplati putnika
//     odobren_zahtev       — admin/vozač odobri zahtev u obradi
//     odbijen_zahtev       — admin/vozač odbije zahtev u obradi
//     dodat_putnik         — admin doda putnika na polazak
//     dodat_termin         — admin doda termin u raspored vozača
//     uklonjen_termin      — admin ukloni termin iz rasporeda
//     dodeljen_vozac       — admin dodijeli putnika vozaču
//     uklonjen_vozac       — admin ukloni putnika od vozača
//     bez_polaska_globalni — admin pritisne "Bez polaska" (bulk akcija)
//     promena_sifre        — vozač promijeni šifru
//   PUTNIK:
//     zahtev_poslan        — putnik pošalje zahtev za vožnju
//     zahtev_otkazan       — putnik otkaže zahtev
//     alternativa_prihvacena — putnik prihvati alternativno vreme
//     odsustvo_postavljeno — putnik postavi godišnji/bolovanje
//     odsustvo_uklonjeno   — putnik se vrati sa odsustva
//     putnik_logout        — putnik se odjavi iz aplikacije
//   UPLATA:
//     uplata_dodana        — uplata upisana u statistiku
// ============================================================================
class V2AuditLogService {
  V2AuditLogService._();

  static SupabaseClient get _db => supabase;

  /// Upiši audit zapis. Fire-and-forget — ne čeka odgovor.
  /// Koristi [logAndWait] samo kad je garantovano sekvencijalno izvršavanje kritično.
  static void log({
    required String tip,
    String? aktorId,
    String? aktorIme,
    String? aktorTip, // 'vozac' | 'putnik' | 'admin'
    String? putnikId,
    String? putnikIme,
    String? putnikTabela,
    String? dan,
    String? grad,
    String? vreme,
    String? polazakId,
    Map<String, dynamic>? staro,
    Map<String, dynamic>? novo,
    String? detalji,
  }) {
    // Fire-and-forget — ne await-ujemo, audit ne smije blokirati UI
    _insert(
      tip: tip,
      aktorId: aktorId,
      aktorIme: aktorIme,
      aktorTip: aktorTip,
      putnikId: putnikId,
      putnikIme: putnikIme,
      putnikTabela: putnikTabela,
      dan: dan,
      grad: grad,
      vreme: vreme,
      polazakId: polazakId,
      staro: staro,
      novo: novo,
      detalji: detalji,
    );
  }

  /// Ista kao [log] ali async — čeka potvrdu DB-a.
  /// Koristiti samo gdje redoslijed upisa mora biti garantovan.
  static Future<void> logAndWait({
    required String tip,
    String? aktorId,
    String? aktorIme,
    String? aktorTip,
    String? putnikId,
    String? putnikIme,
    String? putnikTabela,
    String? dan,
    String? grad,
    String? vreme,
    String? polazakId,
    Map<String, dynamic>? staro,
    Map<String, dynamic>? novo,
    String? detalji,
  }) =>
      _insert(
        tip: tip,
        aktorId: aktorId,
        aktorIme: aktorIme,
        aktorTip: aktorTip,
        putnikId: putnikId,
        putnikIme: putnikIme,
        putnikTabela: putnikTabela,
        dan: dan,
        grad: grad,
        vreme: vreme,
        polazakId: polazakId,
        staro: staro,
        novo: novo,
        detalji: detalji,
      );

  // ---------------------------------------------------------------------------
  // INTERN
  // ---------------------------------------------------------------------------

  static Future<void> _insert({
    required String tip,
    String? aktorId,
    String? aktorIme,
    String? aktorTip,
    String? putnikId,
    String? putnikIme,
    String? putnikTabela,
    String? dan,
    String? grad,
    String? vreme,
    String? polazakId,
    Map<String, dynamic>? staro,
    Map<String, dynamic>? novo,
    String? detalji,
  }) async {
    try {
      await _db.from('v2_audit_log').insert({
        'tip': tip,
        if (aktorId != null) 'aktor_id': aktorId,
        if (aktorIme != null) 'aktor_ime': aktorIme,
        if (aktorTip != null) 'aktor_tip': aktorTip,
        if (putnikId != null) 'putnik_id': putnikId,
        if (putnikIme != null) 'putnik_ime': putnikIme,
        if (putnikTabela != null) 'putnik_tabela': putnikTabela,
        if (dan != null) 'dan': dan,
        if (grad != null) 'grad': grad,
        if (vreme != null) 'vreme': vreme,
        if (polazakId != null) 'polazak_id': polazakId,
        if (staro != null) 'staro': staro,
        if (novo != null) 'novo': novo,
        if (detalji != null) 'detalji': detalji,
        // created_at: DB default (now())
      });
    } catch (e, st) {
      // Audit log ne smije rušiti app — tiho logguj
      debugPrint('[V2AuditLog] GREŠKA pri upisu (tip=$tip): $e\n$st');
    }
  }

  // ---------------------------------------------------------------------------
  // QUERY METODE — za buduće admin pregledanje historije
  // ---------------------------------------------------------------------------

  /// Dohvati posljednjih [limit] zapisa za putnika (najnoviji prvi).
  static Future<List<Map<String, dynamic>>> zahtevPutnika(
    String putnikId, {
    int limit = 50,
  }) async {
    try {
      final rows = await _db
          .from('v2_audit_log')
          .select('id, tip, aktor_ime, aktor_tip, dan, grad, vreme, staro, novo, detalji, created_at')
          .eq('putnik_id', putnikId)
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('[V2AuditLog] zahtevPutnika error: $e');
      return [];
    }
  }

  /// Dohvati posljednjih [limit] zapisa koje je uradio aktor (vozač/admin).
  static Future<List<Map<String, dynamic>>> zahtevAktora(
    String aktorId, {
    int limit = 50,
  }) async {
    try {
      final rows = await _db
          .from('v2_audit_log')
          .select('id, tip, putnik_ime, putnik_tabela, dan, grad, vreme, staro, novo, detalji, created_at')
          .eq('aktor_id', aktorId)
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('[V2AuditLog] zahtevAktora error: $e');
      return [];
    }
  }

  /// Dohvati posljednjih [limit] zapisa određenog tipa.
  static Future<List<Map<String, dynamic>>> zahtevTipa(
    String tip, {
    int limit = 100,
    DateTime? od,
    DateTime? do_,
  }) async {
    try {
      var query = _db
          .from('v2_audit_log')
          .select('id, tip, aktor_ime, putnik_ime, dan, grad, vreme, detalji, created_at')
          .eq('tip', tip);
      if (od != null) query = query.gte('created_at', od.toIso8601String());
      if (do_ != null) query = query.lte('created_at', do_.toIso8601String());
      final rows = await query.order('created_at', ascending: false).limit(limit);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('[V2AuditLog] zahtevTipa error: $e');
      return [];
    }
  }
}
