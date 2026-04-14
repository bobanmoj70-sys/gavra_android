import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class V3WeatherSnapshot {
  final String grad;
  final String icon;
  final String description;
  final double temperatureC;
  final int? precipitationProbability;
  final DateTime sourceTime;
  final DateTime fetchedAt;

  const V3WeatherSnapshot({
    required this.grad,
    required this.icon,
    required this.description,
    required this.temperatureC,
    required this.precipitationProbability,
    required this.sourceTime,
    required this.fetchedAt,
  });

  String get compactLabel {
    final temp = '${temperatureC.round()}°';
    final rain = precipitationProbability != null
        ? ' · ${precipitationProbability}%'
        : '';
    return '$icon $temp$rain';
  }
}

class V3WeatherService {
  V3WeatherService._();

  static const Duration _cacheTtl = Duration(minutes: 15);

  static final Map<String, _GradConfig> _gradConfig = <String, _GradConfig>{
    'BC': const _GradConfig(lat: 44.8973, lng: 21.4177, name: 'Bela Crkva'),
    'VS': const _GradConfig(lat: 45.1190, lng: 21.3030, name: 'Vršac'),
  };

  static final Map<String, V3WeatherSnapshot> _cache =
      <String, V3WeatherSnapshot>{};

  static Future<Map<String, V3WeatherSnapshot>> fetchBcVs(
      {bool forceRefresh = false}) async {
    final results = <String, V3WeatherSnapshot>{};
    for (final grad in _gradConfig.keys) {
      final snapshot = await fetchByGrad(grad, forceRefresh: forceRefresh);
      if (snapshot != null) {
        results[grad] = snapshot;
      }
    }
    return results;
  }

  static Future<V3WeatherSnapshot?> fetchByGrad(String grad,
      {bool forceRefresh = false}) async {
    final normalized = grad.trim().toUpperCase();
    final config = _gradConfig[normalized];
    if (config == null) return null;

    final now = DateTime.now();
    final cached = _cache[normalized];
    if (!forceRefresh &&
        cached != null &&
        now.difference(cached.fetchedAt) < _cacheTtl) {
      return cached;
    }

    try {
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': config.lat.toString(),
        'longitude': config.lng.toString(),
        'timezone': 'Europe/Belgrade',
        'forecast_days': '2',
        'current': 'temperature_2m,weather_code',
        'hourly': 'precipitation_probability',
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        debugPrint(
            '[V3WeatherService] status=${response.statusCode} body=${response.body}');
        return cached;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final current = data['current'];
      if (current is! Map<String, dynamic>) {
        return cached;
      }

      final currentTemp = (current['temperature_2m'] as num?)?.toDouble();
      final weatherCode = (current['weather_code'] as num?)?.toInt();
      final currentTimeRaw = current['time']?.toString();
      if (currentTemp == null ||
          weatherCode == null ||
          currentTimeRaw == null) {
        return cached;
      }

      final sourceTime = DateTime.tryParse(currentTimeRaw) ?? now;
      final precipProbability = _extractPrecipitation(data, currentTimeRaw);
      final weather = _mapWeatherCode(weatherCode);

      final snapshot = V3WeatherSnapshot(
        grad: normalized,
        icon: weather.icon,
        description: weather.description,
        temperatureC: currentTemp,
        precipitationProbability: precipProbability,
        sourceTime: sourceTime,
        fetchedAt: now,
      );

      _cache[normalized] = snapshot;
      return snapshot;
    } catch (e) {
      debugPrint('[V3WeatherService] fetchByGrad($normalized) error: $e');
      return cached;
    }
  }

  static int? _extractPrecipitation(
      Map<String, dynamic> data, String currentTimeRaw) {
    final hourly = data['hourly'];
    if (hourly is! Map<String, dynamic>) return null;

    final times = hourly['time'];
    final precip = hourly['precipitation_probability'];
    if (times is! List || precip is! List || times.isEmpty || precip.isEmpty)
      return null;

    final currentHour = currentTimeRaw.length >= 13
        ? currentTimeRaw.substring(0, 13)
        : currentTimeRaw;
    int index = times.indexWhere((t) {
      final value = t?.toString() ?? '';
      return value.length >= 13 && value.substring(0, 13) == currentHour;
    });

    if (index < 0) index = 0;
    if (index >= precip.length) return null;

    final value = precip[index];
    if (value is num) {
      return value.round().clamp(0, 100);
    }
    return null;
  }

  static _WeatherView _mapWeatherCode(int code) {
    if (code == 0) return const _WeatherView('☀️', 'Vedro');
    if (code == 1) return const _WeatherView('🌤️', 'Pretežno vedro');
    if (code == 2) return const _WeatherView('⛅', 'Delimično oblačno');
    if (code == 3) return const _WeatherView('☁️', 'Oblačno');
    if ({45, 48}.contains(code)) return const _WeatherView('🌫️', 'Magla');
    if ({51, 53, 55, 56, 57}.contains(code))
      return const _WeatherView('🌦️', 'Rominjanje');
    if ({61, 63, 65, 66, 67, 80, 81, 82}.contains(code))
      return const _WeatherView('🌧️', 'Kiša');
    if ({71, 73, 75, 77, 85, 86}.contains(code))
      return const _WeatherView('❄️', 'Sneg');
    if ({95, 96, 99}.contains(code)) return const _WeatherView('⛈️', 'Oluja');
    return const _WeatherView('🌡️', 'Vreme');
  }
}

class _GradConfig {
  final double lat;
  final double lng;
  final String name;

  const _GradConfig({
    required this.lat,
    required this.lng,
    required this.name,
  });
}

class _WeatherView {
  final String icon;
  final String description;

  const _WeatherView(this.icon, this.description);
}
