/// Model za log vremenskih upozorenja (v2_weather_alerts_log tabela)
class V2WeatherAlertLog {
  final int id;
  final DateTime alertDate;
  final String? alertTypes;
  final DateTime? createdAt;

  V2WeatherAlertLog({
    required this.id,
    required this.alertDate,
    this.alertTypes,
    this.createdAt,
  });

  factory V2WeatherAlertLog.fromJson(Map<String, dynamic> json) {
    return V2WeatherAlertLog(
      id: (json['id'] as num).toInt(),
      alertDate: DateTime.parse(json['alert_date'] as String),
      alertTypes: json['alert_types'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'alert_date': alertDate.toIso8601String().split('T')[0],
      'alert_types': alertTypes,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is V2WeatherAlertLog && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
