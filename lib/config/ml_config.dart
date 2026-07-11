import 'package:flutter_dotenv/flutter_dotenv.dart';

class MlConfig {
  static String get baseUrl {
    final url = dotenv.maybeGet('ML_BASE_URL')?.trim();
    if (url == null || url.isEmpty) {
      throw StateError(
        '[MlConfig] ML_BASE_URL nije definisan u .env fajlu. '
        'Postavi ga na adresu AI servera, npr. http://IP_ADRESA:8000',
      );
    }
    return url;
  }

  static String get apiKey {
    return dotenv.maybeGet('ML_API_KEY')?.trim() ?? '';
  }

  /// Generiše ili vraća postojeći ID sesije za AI chat.
  /// Pozivati jednom po životnom veku aplikacije (npr. iz main.dart).
  static String? _sessionId;

  static String get sessionId {
    _sessionId ??= '${DateTime.now().millisecondsSinceEpoch}-${apiKey.hashCode}';
    return _sessionId!;
  }

  static void setSessionId(String id) {
    _sessionId = id;
  }

  static Map<String, String> headers({String? sessionId}) {
    final key = apiKey;
    return {
      'Content-Type': 'application/json',
      if (key.isNotEmpty) 'X-API-Key': key,
      'X-Session-ID': sessionId ?? MlConfig.sessionId,
    };
  }
}
