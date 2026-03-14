import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../globals.dart';

/// V3AuditLogService — nepromjenljiv log svih akcija vozača i putnika.
/// TABELA: v2_audit_log (koristimo istu tabelu za kontinuitet)
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
    String? dan,
    String? grad,
    String? vreme,
    String? polazakId,
    Map<String, dynamic>? staro,
    Map<String, dynamic>? novo,
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
      dan: dan,
      grad: grad,
      vreme: vreme,
      polazakId: polazakId,
      staro: staro,
      novo: novo,
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

    try {
      await supabase.from('v2_audit_log').insert(payload);
      debugPrint('[V3AuditLog] INSERT uspješno tip=$tip');
    } catch (e, st) {
      debugPrint('[V3AuditLog] GREŠKA pri upisu (tip=$tip): $e\n$st');
    }
  }
}
