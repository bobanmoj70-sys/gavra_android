import 'dart:async';

import 'package:flutter/foundation.dart';

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
    unawaited(_insert(
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
    ));
  }

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
    final payload = {
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
    };
    debugPrint('[V2AuditLog] INSERT pokušaj tip=$tip payload=$payload');
    try {
      await supabase.from('v2_audit_log').insert(payload);
      debugPrint('[V2AuditLog] INSERT uspješno tip=$tip');
    } catch (e, st) {
      // Audit log ne smije rušiti app — tiho logguj
      debugPrint('[V2AuditLog] GREŠKA pri upisu (tip=$tip): $e\n$st');
    }
  }

}
