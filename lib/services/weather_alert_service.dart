import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import 'v2_push_token_service.dart';
import 'v2_realtime_notification_service.dart';
import 'weather_service.dart';

/// ??? Servis za automatska upozorenja o opasnim vremenskim uslovima
/// �alje push notifikacije vozacima kada se ocekuje:
/// - ?? Sneg
/// - ?? Ledena ki�a (freezing rain)
/// - ?? Nevreme (grmljavina)
/// - ??? Gusta magla
class WeatherAlertService {
  static SupabaseClient get _supabase => supabase;

  /// Glavna funkcija - proverava prognozu i �alje upozorenje ako treba
  /// Poziva se na app startup (main.dart)
  static Future<void> checkAndSendWeatherAlerts() async {
    try {
      // Proveri da li je vec poslato danas
      if (await _isAlertAlreadySentToday()) {
        if (kDebugMode) {
          debugPrint('?? [WeatherAlert] Upozorenje vec poslato danas');
        }
        return;
      }

      // Dohvati prognozu za oba grada
      final bcWeather = await WeatherService.getWeatherData('BC');
      final vsWeather = await WeatherService.getWeatherData('VS');

      // Proveri da li ima opasnih uslova
      final alerts = <String>[];

      // Proveri Bela Crkva
      if (bcWeather != null) {
        final bcAlerts = _checkForDangerousWeather(bcWeather, 'Bela Crkva');
        alerts.addAll(bcAlerts);
      }

      // Proveri Vrsac
      if (vsWeather != null) {
        final vsAlerts = _checkForDangerousWeather(vsWeather, 'Vrsac');
        alerts.addAll(vsAlerts);
      }

      if (alerts.isEmpty) {
        if (kDebugMode) {
          debugPrint('? [WeatherAlert] Nema opasnih vremenskih uslova');
        }
        return;
      }

      // Po�alji upozorenje vozacima
      await _sendWeatherAlert(alerts);

      // Oznaci da je poslato
      await _markAlertSent(alerts.join(', '));

      if (kDebugMode) {
        debugPrint('?? [WeatherAlert] Poslato upozorenje: ${alerts.join(', ')}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('? [WeatherAlert] Gre�ka: $e');
    }
  }

  /// Proverava da li prognoza sadr�i opasne uslove
  static List<String> _checkForDangerousWeather(WeatherData weather, String grad) {
    final alerts = <String>[];
    final code = weather.dailyWeatherCode ?? weather.weatherCode;

    // ?? SNEG (71-77, 85-86)
    if ((code >= 71 && code <= 77) || (code >= 85 && code <= 86)) {
      alerts.add('?? Sneg u $grad');
    }

    // ?? LEDENA KI�A (56-57, 66-67) - POSEBNO OPASNO
    if ((code >= 56 && code <= 57) || (code >= 66 && code <= 67)) {
      alerts.add('?? Ledena ki�a u $grad - OPREZ!');
    }

    // ?? NEVREME/GRMLJAVINA (95-99)
    if (code >= 95 && code <= 99) {
      alerts.add('?? Nevreme u $grad');
    }

    // ??? GUSTA MAGLA (45-48)
    if (code >= 45 && code <= 48) {
      alerts.add('??? Gusta magla u $grad');
    }

    // ??? JAKA KI�A (65, 82) - samo najjaci intenzitet
    if (code == 65 || code == 82) {
      alerts.add('??? Jaka ki�a u $grad');
    }

    return alerts;
  }

  /// Proverava da li je upozorenje vec poslato danas
  static Future<bool> _isAlertAlreadySentToday() async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final response = await _supabase
          .from('v2_weather_alerts_log')
          .select('id')
          .eq('alert_date', today.toIso8601String().split('T')[0])
          .maybeSingle();

      return response != null;
    } catch (e) {
      // Ako tabela ne postoji, vrati false
      if (kDebugMode) {
        debugPrint('?? [WeatherAlert] Gre�ka pri proveri loga: $e');
      }
      return false;
    }
  }

  /// �alje push notifikaciju svim vozacima
  static Future<void> _sendWeatherAlert(List<String> alerts) async {
    try {
      // Dohvati tokene svih vozaca
      final vozacTokens = await PushTokenService.getTokensForVozaci();

      if (vozacTokens.isEmpty) {
        if (kDebugMode) debugPrint('?? [WeatherAlert] Nema vozackih tokena');
        return;
      }

      // Kreiraj poruku
      final title = '?? Upozorenje - Vremenski uslovi';
      final body = _createAlertMessage(alerts);

      // Po�alji push
      await RealtimeNotificationService.sendPushNotification(
        title: title,
        body: body,
        tokens: vozacTokens.map((t) => {'token': t['token']!, 'provider': t['provider']!}).toList(),
        data: {
          'type': 'weather_alert',
          'alerts': alerts.join('|'),
        },
      );

      if (kDebugMode) {
        debugPrint('? [WeatherAlert] Poslato ${vozacTokens.length} vozacima');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('? [WeatherAlert] Gre�ka pri slanju: $e');
    }
  }

  /// Kreira tekst poruke za upozorenje
  static String _createAlertMessage(List<String> alerts) {
    final now = DateTime.now();
    final dateStr = '${now.day}.${now.month}.${now.year}';

    return '?? GAVRA 013 - $dateStr\n\n'
        'Ocekuju se lo�i vremenski uslovi:\n\n'
        '${alerts.map((a) => '� $a').join('\n')}\n\n'
        '?? Vozite oprezno i prilagodite brzinu uslovima na putu!';
  }

  /// Oznaci da je upozorenje poslato danas
  static Future<void> _markAlertSent(String alertTypes) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      await _supabase.from('v2_weather_alerts_log').insert({
        'alert_date': today.toIso8601String().split('T')[0],
        'alert_types': alertTypes,
      });
    } catch (e) {
      if (kDebugMode) debugPrint('? [WeatherAlert] Gre�ka pri upisu loga: $e');
    }
  }
}
