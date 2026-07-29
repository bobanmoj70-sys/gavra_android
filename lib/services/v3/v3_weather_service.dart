import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../utils/v3_belgrade_time.dart';

class V3WeatherSnapshot {
  final String grad;
  final String icon;
  final IconData iconData;
  final Color iconColor;
  final String description;
  final double temperatureC;
  final int? precipitationProbability;
  final DateTime sourceTime;
  final DateTime fetchedAt;

  const V3WeatherSnapshot({
    required this.grad,
    required this.icon,
    required this.iconData,
    required this.iconColor,
    required this.description,
    required this.temperatureC,
    required this.precipitationProbability,
    required this.sourceTime,
    required this.fetchedAt,
  });

  String get compactLabel {
    final temp = '${temperatureC.round()}°';
    final rain = precipitationProbability != null ? ' · ${precipitationProbability}%' : '';
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

  static final Map<String, V3WeatherSnapshot> _cache = <String, V3WeatherSnapshot>{};

  static Future<Map<String, V3WeatherSnapshot>> fetchBcVs({bool forceRefresh = false}) async {
    final results = <String, V3WeatherSnapshot>{};
    for (final grad in _gradConfig.keys) {
      final snapshot = await fetchByGrad(grad, forceRefresh: forceRefresh);
      if (snapshot != null) {
        results[grad] = snapshot;
      }
    }
    return results;
  }

  static Future<V3WeatherSnapshot?> fetchByGrad(String grad, {bool forceRefresh = false}) async {
    final normalized = grad.trim().toUpperCase();
    final config = _gradConfig[normalized];
    if (config == null) return null;

    final now = V3BelgradeTime.now();
    final cached = _cache[normalized];
    if (!forceRefresh && cached != null && now.difference(cached.fetchedAt) < _cacheTtl) {
      return cached;
    }

    // Pokušaj do 2 puta (prvi pokušaj + 1 retry) jer hladan start aplikacije
    // ili privremeno spora mreža čest je uzrok da se ikonica ne učita.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
          'latitude': config.lat.toString(),
          'longitude': config.lng.toString(),
          'timezone': 'Europe/Belgrade',
          'forecast_days': '2',
          'current': 'temperature_2m,weather_code,is_day',
          'hourly': 'precipitation_probability',
        });

        final response = await http.get(uri).timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) {
          debugPrint('[V3WeatherService] status=${response.statusCode} body=${response.body}');
          if (attempt == 0) {
            await Future.delayed(const Duration(seconds: 2));
            continue;
          }
          return cached;
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final current = data['current'];
        if (current is! Map<String, dynamic>) {
          if (attempt == 0) {
            await Future.delayed(const Duration(seconds: 2));
            continue;
          }
          return cached;
        }

        final currentTemp = (current['temperature_2m'] as num?)?.toDouble();
        final weatherCode = (current['weather_code'] as num?)?.toInt();
        final currentTimeRaw = current['time']?.toString();
        if (currentTemp == null || weatherCode == null || currentTimeRaw == null) {
          if (attempt == 0) {
            await Future.delayed(const Duration(seconds: 2));
            continue;
          }
          return cached;
        }

        final isDayValue = current['is_day'];
        final isDay = isDayValue is num ? isDayValue.toInt() != 0 : true;

        final sourceTime = V3BelgradeTime.parseTs(currentTimeRaw) ?? now;
        final precipProbability = _extractPrecipitation(data, currentTimeRaw);
        final weather = _mapWeatherCode(weatherCode, isDay);

        final snapshot = V3WeatherSnapshot(
          grad: normalized,
          icon: weather.icon,
          iconData: weather.iconData,
          iconColor: weather.iconColor,
          description: weather.description,
          temperatureC: currentTemp,
          precipitationProbability: precipProbability,
          sourceTime: sourceTime,
          fetchedAt: now,
        );

        _cache[normalized] = snapshot;
        return snapshot;
      } catch (e) {
        debugPrint('[V3WeatherService] fetchByGrad($normalized) attempt=$attempt error: $e');
        if (attempt == 0) {
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        return cached;
      }
    }
    return cached;
  }

  static int? _extractPrecipitation(Map<String, dynamic> data, String currentTimeRaw) {
    final hourly = data['hourly'];
    if (hourly is! Map<String, dynamic>) return null;

    final times = hourly['time'];
    final precip = hourly['precipitation_probability'];
    if (times is! List || precip is! List || times.isEmpty || precip.isEmpty) return null;

    final currentHour = currentTimeRaw.length >= 13 ? currentTimeRaw.substring(0, 13) : currentTimeRaw;
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

  static _WeatherView _mapWeatherCode(int code, bool isDay) {
    if (code == 0) {
      return isDay
          ? const _WeatherView('☀️', 'Vedro', Icons.wb_sunny_rounded, Color(0xFFFFC107))
          : const _WeatherView('🌙', 'Vedro', Icons.nightlight_round, Color(0xFFB0BEC5));
    }
    if (code == 1) {
      return isDay
          ? const _WeatherView('🌤️', 'Pretežno vedro', Icons.wb_twilight, Color(0xFFFFB300))
          : const _WeatherView('🌙', 'Pretežno vedro', Icons.nightlight_round, Color(0xFFB0BEC5));
    }
    if (code == 2) {
      return isDay
          ? const _WeatherView('⛅', 'Delimično oblačno', Icons.cloud_queue_rounded, Color(0xFFCFD8DC))
          : const _WeatherView('☁️', 'Delimično oblačno', Icons.cloud_rounded, Color(0xFF90A4AE));
    }
    if (code == 3) return const _WeatherView('☁️', 'Oblačno', Icons.cloud_rounded, Color(0xFF90A4AE));
    if ({45, 48}.contains(code)) return const _WeatherView('🌫️', 'Magla', Icons.foggy, Color(0xFFB0BEC5));
    if ({51, 53, 55, 56, 57}.contains(code)) {
      return const _WeatherView('🌦️', 'Rominjanje', Icons.grain_rounded, Color(0xFF64B5F6));
    }
    if ({61, 63, 65, 66, 67, 80, 81, 82}.contains(code)) {
      return const _WeatherView('🌧️', 'Kiša', Icons.water_drop_rounded, Color(0xFF42A5F5));
    }
    if ({71, 73, 75, 77, 85, 86}.contains(code)) {
      return const _WeatherView('❄️', 'Sneg', Icons.ac_unit_rounded, Color(0xFF80DEEA));
    }
    if ({95, 96, 99}.contains(code)) {
      return const _WeatherView('⛈️', 'Oluja', Icons.thunderstorm_rounded, Color(0xFFFFCA28));
    }
    return const _WeatherView('🌡️', 'Vreme', Icons.thermostat_rounded, Colors.white);
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
  final IconData iconData;
  final Color iconColor;

  const _WeatherView(this.icon, this.description, this.iconData, this.iconColor);
}
