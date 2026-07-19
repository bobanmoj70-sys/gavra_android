import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Konfiguracija za komunikaciju sa ml-service backendom (OSRM proxy + neuronska mreža).
class MlConfig {
  static String get baseUrl {
    final url = dotenv.env['ML_BASE_URL']?.trim() ?? '';
    if (url.isEmpty) {
      throw Exception(
        '[MlConfig] ML_BASE_URL nije definisan u .env fajlu. '
        'Dodaj ML_BASE_URL=http://IP:PORT u .env.',
      );
    }
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  static String get apiKey => dotenv.env['ML_API_KEY']?.trim() ?? '';

  static Map<String, String> headers() => {
        'Content-Type': 'application/json',
        'X-API-Key': apiKey,
      };
}
