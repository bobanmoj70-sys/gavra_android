import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import 'realtime/realtime_manager.dart';
import 'realtime_notification_service.dart';

/// 📨 Servis za upravljanje PIN zahtevima putnika
class PinZahtevService {
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
          await _supabase.from('pin_zahtevi').select().eq('putnik_id', putnikId).eq('status', 'ceka').maybeSingle();

      if (existing != null) {
        return true;
      }

      await _supabase.from('pin_zahtevi').insert({
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
    _pinZahteviSubscription = RealtimeManager.instance.subscribe('pin_zahtevi').listen((payload) async {
      debugPrint('🔔 [PinZahtevService] Primljena realtime promena: ${payload.eventType}');
      // Učitaj sve zahteve koji čekaju
      await _fetchAndEmitZahtevi();
    });

    // Učitaj početne podatke
    _fetchAndEmitZahtevi();
  }

  /// Dohvati zahteve iz baze i emituj na stream
  static Future<void> _fetchAndEmitZahtevi() async {
    try {
      final data = await _supabase.from('pin_zahtevi').select('''
        *,
        registrovani_putnici (
          id,
          putnik_ime,
          broj_telefona,
          tip
        )
      ''').eq('status', 'ceka').order('created_at');

      if (!_zahteviController.isClosed) {
        _zahteviController.add(List<Map<String, dynamic>>.from(data));
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
    RealtimeManager.instance.unsubscribe('pin_zahtevi');
  }

  static Future<int> brojZahtevaKojiCekaju() async {
    try {
      final response = await _supabase.from('pin_zahtevi').select('id').eq('status', 'ceka');

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
      final zahtev = await _supabase.from('pin_zahtevi').select('putnik_id').eq('id', zahtevId).single();

      final putnikId = zahtev['putnik_id'] as String;

      await _supabase.from('registrovani_putnici').update({'pin': pin}).eq('id', putnikId);

      await _supabase.from('pin_zahtevi').update({'status': 'odobren'}).eq('id', zahtevId);

      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> odbijZahtev(String zahtevId) async {
    try {
      await _supabase.from('pin_zahtevi').update({'status': 'odbijen'}).eq('id', zahtevId);

      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> imaZahtevKojiCeka(String putnikId) async {
    try {
      final response =
          await _supabase.from('pin_zahtevi').select('id').eq('putnik_id', putnikId).eq('status', 'ceka').maybeSingle();

      return response != null;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> azurirajEmail({
    required String putnikId,
    required String email,
  }) async {
    try {
      await _supabase.from('registrovani_putnici').update({'email': email}).eq('id', putnikId);

      return true;
    } catch (e) {
      return false;
    }
  }
}
