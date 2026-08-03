import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// App credentials from `.env` (shared Android + iOS Flutter asset).
class AppConfigService {
  bool _initialized = false;

  Future<void> initializeBasic() async {
    if (_initialized) return;
    try {
      await dotenv.load(fileName: '.env');
      _initialized = true;
      debugPrint('[AppConfigService] .env loaded');
    } catch (e) {
      debugPrint('[AppConfigService] .env load failed: $e');
    }
  }

  String getSupabaseUrl() {
    final url = dotenv.maybeGet('SUPABASE_URL') ?? '';
    if (url.isEmpty) {
      debugPrint('[AppConfigService] SUPABASE_URL missing in .env');
    }
    return url;
  }

  String getSupabaseAnonKey() {
    final key = dotenv.maybeGet('SUPABASE_ANON_KEY') ?? '';
    if (key.isEmpty) {
      debugPrint('[AppConfigService] SUPABASE_ANON_KEY missing in .env');
    }
    return key;
  }

  bool get isInitialized => _initialized;
}
