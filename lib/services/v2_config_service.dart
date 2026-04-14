import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Centralizovani servis za upravljanje kredencijalima i konfiguracijom aplikacije.
/// Čita kredencijale iz .env fajla (flutter_dotenv).
class V2ConfigService {
  bool _initialized = false;

  /// Inicijalizacija — učitava .env fajl
  Future<void> initializeBasic() async {
    if (_initialized) return;
    try {
      await dotenv.load(fileName: '.env');
      _initialized = true;
      debugPrint('[V2ConfigService] .env učitan uspješno');
    } catch (e) {
      debugPrint('[V2ConfigService] Greška pri učitavanju .env: $e');
      // Nastavljamo i sa praznim env — Supabase će prijaviti grešku pri init
    }
  }

  /// Supabase URL
  String getSupabaseUrl() {
    final url = dotenv.maybeGet('SUPABASE_URL') ?? '';
    if (url.isEmpty) {
      debugPrint('[V2ConfigService] ⚠️ SUPABASE_URL nije definisan u .env');
    }
    return url;
  }

  /// Supabase Anon Key
  String getSupabaseAnonKey() {
    final key = dotenv.maybeGet('SUPABASE_ANON_KEY') ?? '';
    if (key.isEmpty) {
      debugPrint(
          '[V2ConfigService] ⚠️ SUPABASE_ANON_KEY nije definisan u .env');
    }
    return key;
  }

  /// Provjera da li je inicijalizovan
  bool get isInitialized => _initialized;
}
