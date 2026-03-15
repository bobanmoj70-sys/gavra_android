import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../globals.dart';

/// V3AuditLogService — nepromjenljiv log svih akcija vozača i putnika.
/// TABELA: v3_audit_log
class V3AuditLogService {
  V3AuditLogService._();

  /// Upiši audit zapis. Fire-and-forget — ne čeka odgovor.
  static void log({
    required String tip,
    String? aktorId,
    String? aktorIme,
    String? aktorTip, // 'vozac' | 'putnik' | 'admin'
    String? putnikId,
    String? putnikIme,
    String? putnikTabela,
    String? datumIso, // ISO date string, npr. '2026-03-15'
    String? grad,
    String? vreme,
    String? polazakId,
    String? detalji,
  }) {
    unawaited(_insert(
      tip: tip,
      aktorId: aktorId,
      aktorIme: aktorIme,
      aktorTip: aktorTip,
      putnikId: putnikId,
      putnikIme: putnikIme,
      putnikTabela: putnikTabela,
      datumIso: datumIso,
      grad: grad,
      vreme: vreme,
      polazakId: polazakId,
      detalji: detalji,
    ));
  }

  static Future<void> _insert({
    required String tip,
    String? aktorId,
    String? aktorIme,
    String? aktorTip,
    String? putnikId,
    String? putnikIme,
    String? putnikTabela,
    String? datumIso,
    String? grad,
    String? vreme,
    String? polazakId,
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
      if (datumIso != null) 'datum': datumIso,
      if (grad != null) 'grad': grad,
      if (vreme != null) 'vreme': vreme,
      if (polazakId != null) 'polazak_id': polazakId,
      if (detalji != null) 'detalji': detalji,
    };

    try {
      await supabase.from('v3_audit_log').insert(payload);
      debugPrint('[V3AuditLog] INSERT uspješno tip=$tip');
    } catch (e, st) {
      debugPrint('[V3AuditLog] GREŠKA pri upisu (tip=$tip): $e\n$st');
    }
  }
}
