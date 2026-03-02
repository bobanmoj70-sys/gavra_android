import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import 'realtime/v2_master_realtime_manager.dart';
import 'v2_realtime_notification_service.dart';

/// 📨 Servis za upravljanje PIN zahtevima putnika
class V2PinZahtevService {
  static SupabaseClient get _supabase => supabase;

  static StreamSubscription<PostgresChangePayload>? _pinZahteviSubscription;
  static final StreamController<List<Map<String, dynamic>>> _zahteviController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  static Future<bool> posaljiZahtev({
    required String putnikId,
    required String email,
    required String telefon,
    String? putnikTabela,
  }) async {
    try {
      final existing = await _supabase
          .from('v2_pin_zahtevi')
          .select('id')
          .eq('putnik_id', putnikId)
          .eq('status', 'ceka')
          .maybeSingle();

      if (existing != null) {
        return true;
      }

      await _supabase.from('v2_pin_zahtevi').insert({
        'putnik_id': putnikId,
        'email': email,
        'telefon': telefon,
        'status': 'ceka',
        if (putnikTabela != null) 'putnik_tabela': putnikTabela,
      });

      // 🔔 Pošalji notifikaciju adminima
      await RealtimeNotificationService.sendNotificationToAdmins(
        title: '🔔 Novi zahtev za PIN',
        body: 'V2Putnik traži PIN za pristup aplikaciji',
        data: {'type': 'pin_zahtev', 'putnik_id': putnikId},
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  /// 🛰️ REALTIME STREAM: Prati nove zahteve za PIN
  static Stream<List<Map<String, dynamic>>> streamZahteviKojiCekaju() {
    // Inicijalizuj subscription ako ne postoji
    if (_pinZahteviSubscription == null) {
      _startRealtimeListener();
    }

    return _zahteviController.stream;
  }

  /// Pokreni realtime listener koristeći RealtimeManager
  static void _startRealtimeListener() {
    _pinZahteviSubscription = V2MasterRealtimeManager.instance.subscribe('v2_pin_zahtevi').listen((payload) {
      debugPrint('🔔 [PinZahtevService] Primljena realtime promena: ${payload.eventType}');
      _fetchAndEmitZahtevi();
    });

    // Učitaj početne podatke
    _fetchAndEmitZahtevi();
  }

  /// Emituj zahteve koji čekaju iz pinCache — nema DB upita
  static void _fetchAndEmitZahtevi() {
    final rm = V2MasterRealtimeManager.instance;
    final zahtevi = rm.pinCache.values.where((z) => z['status'] == 'ceka').toList()
      ..sort((a, b) {
        final ca = a['created_at'] as String? ?? '';
        final cb = b['created_at'] as String? ?? '';
        return ca.compareTo(cb);
      });

    final enriched = zahtevi.map((z) {
      final putnikId = z['putnik_id'] as String?;
      final putnikData = putnikId != null ? rm.getPutnikById(putnikId) : null;
      return <String, dynamic>{
        ...Map<String, dynamic>.from(z),
        'putnik_ime': putnikData?['ime'],
        'broj_telefona': putnikData?['telefon'],
        'tip': _tabelaToTip(z['putnik_tabela'] as String? ?? ''),
      };
    }).toList();

    if (!_zahteviController.isClosed) {
      _zahteviController.add(enriched);
    }
  }

  /// Cleanup subscription
  static void dispose() {
    _pinZahteviSubscription?.cancel();
    _pinZahteviSubscription = null;
    V2MasterRealtimeManager.instance.unsubscribe('v2_pin_zahtevi');
  }

  static int brojZahtevaKojiCekaju() {
    return V2MasterRealtimeManager.instance.pinCache.values.where((z) => z['status'] == 'ceka').length;
  }

  static Future<bool> odobriZahtev({
    required String zahtevId,
    required String pin,
  }) async {
    try {
      final zahtev = V2MasterRealtimeManager.instance.pinCache[zahtevId];
      if (zahtev == null) return false;

      final putnikId = zahtev['putnik_id'] as String;
      final putnikTabela = zahtev['putnik_tabela'] as String? ?? '';

      // UPDATE pin na pravoj v2_ tabeli
      if (putnikTabela.isNotEmpty) {
        await _supabase.from(putnikTabela).update({'pin': pin}).eq('id', putnikId);
      }

      await _supabase.from('v2_pin_zahtevi').update({'status': 'odobren'}).eq('id', zahtevId);

      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> odbijZahtev(String zahtevId) async {
    try {
      await _supabase.from('v2_pin_zahtevi').update({'status': 'odbijen'}).eq('id', zahtevId);

      return true;
    } catch (e) {
      return false;
    }
  }

  static bool imaZahtevKojiCeka(String putnikId) {
    return V2MasterRealtimeManager.instance.pinCache.values
        .any((z) => z['putnik_id'] == putnikId && z['status'] == 'ceka');
  }

  static Future<bool> azurirajEmail({
    required String putnikId,
    required String putnikTabela,
    required String email,
  }) async {
    try {
      if (putnikTabela.isNotEmpty) {
        await _supabase.from(putnikTabela).update({'email': email}).eq('id', putnikId);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  static String _tabelaToTip(String tabela) {
    switch (tabela) {
      case 'v2_radnici':
        return 'radnik';
      case 'v2_ucenici':
        return 'ucenik';
      case 'v2_dnevni':
        return 'dnevni';
      case 'v2_posiljke':
        return 'posiljka';
      default:
        return tabela;
    }
  }
}
