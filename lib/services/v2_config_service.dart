import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Upravlja kredencijalima aplikacije (Supabase URL, keys, etc.)
/// Učitava iz .env fajla (prioritet), sa fallback-om na --dart-define varijable.
class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  String _supabaseUrl = '';
  String _supabaseAnonKey = '';
  bool _initialized = false;

  /// Inicijalizuj osnovne kredencijale.
  /// Idempotentna — drugi poziv je no-op ako je već inicijalizovano.
  Future<void> initializeBasic() async {
    if (_initialized) return;

    // Pokušaj učitati .env fajl; u produkciji možda ne postoji — to je OK
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // .env nije pronađen ili nije dodan u assets — nastavlja sa --dart-define
    }

    // Prioritet: .env, fallback: --dart-define
    _supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
    _supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

    if (_supabaseUrl.isEmpty) {
      _supabaseUrl = const String.fromEnvironment('SUPABASE_URL', defaultValue: '');
    }
    if (_supabaseAnonKey.isEmpty) {
      _supabaseAnonKey = const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
    }

    if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
      throw Exception('Osnovni kredencijali nisu postavljeni. '
          'Postavite SUPABASE_URL i SUPABASE_ANON_KEY u .env fajlu ili kao --dart-define varijable.');
    }

    _initialized = true;
  }

  /// Vraća Supabase URL. Baca [StateError] ako [initializeBasic] nije pozvan.
  String getSupabaseUrl() {
    if (!_initialized) throw StateError('ConfigService nije inicijalizovan. Pozovi initializeBasic() prvo.');
    return _supabaseUrl;
  }

  /// Vraća Supabase anon key. Baca [StateError] ako [initializeBasic] nije pozvan.
  String getSupabaseAnonKey() {
    if (!_initialized) throw StateError('ConfigService nije inicijalizovan. Pozovi initializeBasic() prvo.');
    return _supabaseAnonKey;
  }
}
