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
  }) async {
    try {
      final existing =
          await _supabase.from('v2_pin_zahtevi').select().eq('putnik_id', putnikId).eq('status', 'ceka').maybeSingle();

      if (existing != null) {
        return true;
      }

      await _supabase.from('v2_pin_zahtevi').insert({
        'putnik_id': putnikId,
        'email': email,
        'telefon': telefon,
        'status': 'ceka',
      });

      // 🔔 Pošalji notifikaciju adminima
      await RealtimeNotificationService.sendNotificationToAdmins(
        title: '🔔 Novi zahtev za PIN',
        body: 'Putnik traži PIN za pristup aplikaciji',
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
    _pinZahteviSubscription = V2MasterRealtimeManager.instance.subscribe('v2_pin_zahtevi').listen((payload) async {
      debugPrint('🔔 [PinZahtevService] Primljena realtime promena: ${payload.eventType}');
      // Učitaj sve zahteve koji čekaju
      await _fetchAndEmitZahtevi();
    });

    // Učitaj početne podatke
    _fetchAndEmitZahtevi();
  }

  /// Dohvati zahteve iz baze i emituj na stream
  /// Putnik podaci se čitaju iz V2MasterRealtimeManager cache-a
  static Future<void> _fetchAndEmitZahtevi() async {
    try {
      final data = await _supabase
          .from('v2_pin_zahtevi')
          .select('id, putnik_id, putnik_tabela, email, telefon, status, created_at')
          .eq('status', 'ceka')
          .order('created_at');

      // Obogati svaki zahtev sa podacima putnika iz cache-a
      final enriched = (data as List).map((z) {
        final putnikId = z['putnik_id'] as String?;
        final putnikData = putnikId != null ? V2MasterRealtimeManager.instance.getPutnikById(putnikId) : null;
        return <String, dynamic>{
          ...Map<String, dynamic>.from(z as Map),
          'putnik_ime': putnikData?['ime'],
          'broj_telefona': putnikData?['telefon'],
          'tip': putnikData != null
              ? V2MasterRealtimeManager.instance.getIme(z['putnik_tabela'] as String? ?? '', putnikId ?? '')
              : null,
        };
      }).toList();

      if (!_zahteviController.isClosed) {
        _zahteviController.add(List<Map<String, dynamic>>.from(enriched));
      }
    } catch (e) {
      if (!_zahteviController.isClosed) {
        _zahteviController.addError(e);
      }
    }
  }

  /// Cleanup subscription
  static void dispose() {
    _pinZahteviSubscription?.cancel();
    _pinZahteviSubscription = null;
    V2MasterRealtimeManager.instance.unsubscribe('v2_pin_zahtevi');
  }

  static Future<int> brojZahtevaKojiCekaju() async {
    try {
      final response = await _supabase.from('v2_pin_zahtevi').select('id').eq('status', 'ceka');

      return (response as List).length;
    } catch (e) {
      return 0;
    }
  }

  static Future<bool> odobriZahtev({
    required String zahtevId,
    required String pin,
  }) async {
    try {
      final zahtev =
          await _supabase.from('v2_pin_zahtevi').select('putnik_id, putnik_tabela').eq('id', zahtevId).single();

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

  static Future<bool> imaZahtevKojiCeka(String putnikId) async {
    try {
      final response = await _supabase
          .from('v2_pin_zahtevi')
          .select('id')
          .eq('putnik_id', putnikId)
          .eq('status', 'ceka')
          .maybeSingle();

      return response != null;
    } catch (e) {
      return false;
    }
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
}
