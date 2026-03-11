import 'package:flutter/foundation.dart';

import '../globals.dart';
import 'v2_realtime_notification_service.dart';
import 'v2_weather_service.dart';

/// Servis za automatska upozorenja o opasnim vremenskim uslovima.
/// Šalje push notifikacije vozačima kada se očekuje:
/// - Sneg
/// - Ledena kiša (freezing rain)
/// - Nevreme (grmljavina)
/// - Gusta magla
class V2WeatherAlertService {
  V2WeatherAlertService._();

  /// Glavna funkcija - proverava prognozu i šalje upozorenje ako treba
  /// Poziva se na app startup (main.dart)
  static Future<void> checkAndSendWeatherAlerts() async {
    try {
      if (await _isAlertAlreadySentToday()) {
        return;
      }

      // Dohvati prognozu za oba grada paralelno
      final results = await Future.wait([
        V2WeatherService.getWeatherData('BC'),
        V2WeatherService.getWeatherData('VS'),
      ]);
      final bcWeather = results[0];
      final vsWeather = results[1];

      final alerts = <String>[];

      if (bcWeather != null) {
        final bcAlerts = _checkForDangerousWeather(bcWeather, 'Bela Crkva');
        alerts.addAll(bcAlerts);
      }

      if (vsWeather != null) {
        final vsAlerts = _checkForDangerousWeather(vsWeather, 'Vrsac');
        alerts.addAll(vsAlerts);
      }

      if (alerts.isEmpty) {
        return;
      }

      // Pošalji upozorenje vozacima
      await _sendWeatherAlert(alerts);

      // Oznaci da je poslato
      await _markAlertSent(alerts.join(', '));
    } catch (e) {
      debugPrint('[V2WeatherAlertService] checkAndSendWeatherAlerts greška: $e');
    }
  }

  /// Proverava da li prognoza sadrži opasne uslove
  static List<String> _checkForDangerousWeather(V2WeatherData weather, String grad) {
    final alerts = <String>[];
    final code = weather.dailyWeatherCode ?? weather.weatherCode;

    // Sneg (71-77, 85-86)
    if ((code >= 71 && code <= 77) || (code >= 85 && code <= 86)) {
      alerts.add('❄️ Sneg u $grad');
    }

    // Ledena kiša (56-57, 66-67) - posebno opasno
    if ((code >= 56 && code <= 57) || (code >= 66 && code <= 67)) {
      alerts.add('🌨️ Ledena kiša u $grad - OPREZ!');
    }

    // Nevreme/grmljavina (95-99)
    if (code >= 95 && code <= 99) {
      alerts.add('⚡ Nevreme u $grad');
    }

    // Gusta magla (45-48)
    if (code >= 45 && code <= 48) {
      alerts.add('🌫️ Gusta magla u $grad');
    }

    // Jaka kiša (65, 82) - samo najjaci intenzitet
    if (code == 65 || code == 82) {
      alerts.add('🌧️ Jaka kiša u $grad');
    }

    return alerts;
  }

  /// Proverava da li je upozorenje vec poslato danas
  static Future<bool> _isAlertAlreadySentToday() async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];

      final response = await supabase.from('v2_weather_alerts_log').select('id').eq('alert_date', today).maybeSingle();

      return response != null;
    } catch (e) {
      debugPrint('[V2WeatherAlertService] _isAlertAlreadySentToday greška: $e');
      // Ako tabela ne postoji, vrati false
      return false;
    }
  }

  /// Šalje push notifikaciju svim vozačima — tokeni se resolviraju server-side
  static Future<void> _sendWeatherAlert(List<String> alerts) async {
    try {
      await V2RealtimeNotificationService.sendPushNotification(
        title: '⚠️ Upozorenje - Vremenski uslovi',
        body: _createAlertMessage(alerts),
        broadcastVozaci: true,
        data: {
          'type': 'weather_alert',
          'alerts': alerts.join('|'),
        },
      );
    } catch (e) {
      debugPrint('[V2WeatherAlertService] _sendWeatherAlert greška: $e');
    }
  }

  /// Kreira tekst poruke za upozorenje
  static String _createAlertMessage(List<String> alerts) {
    final now = DateTime.now();
    final dateStr = '${now.day}.${now.month}.${now.year}';

    return '🚗 GAVRA 013 - $dateStr\n\n'
        'Ocekuju se loši vremenski uslovi:\n\n'
        '${alerts.map((a) => '• $a').join('\n')}\n\n'
        '⚠️ Vozite oprezno i prilagodite brzinu uslovima na putu!';
  }

  /// Oznaci da je upozorenje poslato danas
  static Future<void> _markAlertSent(String alertTypes) async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];

      await supabase.from('v2_weather_alerts_log').insert({
        'alert_date': today,
        'alert_types': alertTypes,
      });
    } catch (e) {
      debugPrint('[V2WeatherAlertService] _markAlertSent greška: $e');
    }
  }
}
