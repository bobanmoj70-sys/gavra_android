import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Upravlja kredencijalima aplikacije (Supabase URL, keys, etc.)
/// Učitava iz .env fajla (prioritet), sa fallback-om na --dart-define varijable.
class V2ConfigService {
  static final V2ConfigService _instance = V2ConfigService._internal();
  factory V2ConfigService() => _instance;
  V2ConfigService._internal();

  String _supabaseUrl = '';
  String _supabaseAnonKey = '';
  Future<void>? _initFuture;

  /// Inicijalizuj osnovne kredencijale.
  /// Idempotentna i thread-safe — višestruki paralelni pozivi dijele isti Future.
  Future<void> initializeBasic() {
    return _initFuture ??= _doInitialize();
  }

  Future<void> _doInitialize() async {
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
  }

  /// Vraća Supabase URL. Bača [StateError] ako [initializeBasic] nije pozvan ili nije uspio.
  String getSupabaseUrl() {
    if (_initFuture == null || _supabaseUrl.isEmpty) {
      throw StateError('V2ConfigService nije inicijalizovan. Pozovi initializeBasic() prvo.');
    }
    return _supabaseUrl;
  }

  /// Vraća Supabase anon key. Bača [StateError] ako [initializeBasic] nije pozvan ili nije uspio.
  String getSupabaseAnonKey() {
    if (_initFuture == null || _supabaseAnonKey.isEmpty) {
      throw StateError('V2ConfigService nije inicijalizovan. Pozovi initializeBasic() prvo.');
    }
    return _supabaseAnonKey;
  }
}
