import '../utils/date_utils.dart';
import 'json_utils.dart';

class WeatherSummary {
  WeatherSummary({
    this.date,
    this.temperature,
    this.feelsLike,
    this.humidity,
    this.windSpeed,
    this.precipitation,
    this.uvIndex,
    this.uvIndexMax,
    this.visibility,
    this.condition,
    this.icon,
    this.tempMax,
    this.tempMin,
  });

  factory WeatherSummary.fromJson(Map<String, dynamic> j) {
    final daily = j['daily'] is Map ? j['daily'] as Map : const {};
    return WeatherSummary(
      date: parseApiDate(j['date']),
      temperature: toDouble(j['temperature']),
      feelsLike: toDouble(j['feels_like']),
      humidity: toDouble(j['humidity']),
      windSpeed: toDouble(j['wind_speed']),
      precipitation: toDouble(j['precipitation']) ?? toDouble(j['precipitation_mm']),
      uvIndex: toDouble(j['uv_index']),
      uvIndexMax: toDouble(j['uv_index_max']),
      visibility: toDouble(j['visibility']),
      condition: toStr(j['condition']),
      icon: toStr(j['icon']),
      tempMax: toDouble(daily['temp_max']),
      tempMin: toDouble(daily['temp_min']),
    );
  }

  final DateTime? date;
  final double? temperature, feelsLike, humidity, windSpeed, precipitation, uvIndex;
  final double? uvIndexMax, visibility;
  final String? condition, icon;
  final double? tempMax, tempMin;
}

class HourlyWeather {
  HourlyWeather({
    required this.raw,
    this.date,
    this.temperature,
    this.feelsLike,
    this.humidity,
    this.windSpeed,
    this.windDirection,
    this.windDirectionCardinal,
    this.windGusts,
    this.uvIndex,
    this.precipitation,
    this.cloudCover,
    this.visibility,
    this.pressure,
    this.condition,
    this.dataSource,
  });

  factory HourlyWeather.fromJson(Map<String, dynamic> j) => HourlyWeather(
        raw: j,
        date: parseApiDate(j['date']),
        temperature: toDouble(j['temperature']),
        feelsLike: toDouble(j['feels_like']),
        humidity: toDouble(j['humidity']),
        windSpeed: toDouble(j['wind_speed']),
        windDirection: toDouble(j['wind_direction']),
        windDirectionCardinal: toStr(j['wind_direction_cardinal']),
        windGusts: toDouble(j['wind_gusts']),
        uvIndex: toDouble(j['uv_index']),
        precipitation: toDouble(j['precipitation']),
        cloudCover: toDouble(j['cloud_cover']),
        visibility: toDouble(j['visibility']),
        pressure: toDouble(j['pressure']),
        condition: toStr(j['condition']),
        dataSource: toStr(j['data_source']),
      );

  final Map<String, dynamic> raw;
  final DateTime? date;
  final double? temperature, feelsLike, humidity, windSpeed, windDirection;
  final String? windDirectionCardinal;
  final double? windGusts, uvIndex, precipitation, cloudCover, visibility, pressure;
  final String? condition, dataSource;
}

class MonthlyWeatherDay {
  MonthlyWeatherDay({
    this.date,
    this.condition,
    this.icon,
    this.category,
    this.precipitation,
    this.tempMax,
    this.tempMin,
  });

  factory MonthlyWeatherDay.fromJson(Map<String, dynamic> j) => MonthlyWeatherDay(
        date: parseApiDate(j['date']),
        condition: toStr(j['condition']),
        icon: toStr(j['icon']),
        category: toStr(j['category']),
        precipitation: toDouble(j['precipitation']),
        tempMax: toDouble(j['temperature_max']),
        tempMin: toDouble(j['temperature_min']),
      );

  final DateTime? date;
  final String? condition, icon, category;
  final double? precipitation, tempMax, tempMin;
}

class MonthlyWeatherResponse {
  MonthlyWeatherResponse({
    required this.year,
    required this.month,
    required this.dailyRecords,
    required this.summary,
  });

  factory MonthlyWeatherResponse.fromJson(Map<String, dynamic> j, int year, int month) {
    final daily = (j['daily_records'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MonthlyWeatherDay.fromJson)
        .toList();

    final Map<String, int> sum = {
      'sunny': 0,
      'partly-cloudy': 0,
      'cloudy': 0,
      'rainy': 0,
      'snowy': 0,
    };

    if (j['summary'] is Map) {
      final s = j['summary'] as Map;
      sum['sunny'] = (s['sunny'] as num?)?.toInt() ?? 0;
      sum['partly-cloudy'] = (s['partly-cloudy'] as num?)?.toInt() ?? 0;
      sum['cloudy'] = (s['cloudy'] as num?)?.toInt() ?? 0;
      sum['rainy'] = (s['rainy'] as num?)?.toInt() ?? 0;
      sum['snowy'] = (s['snowy'] as num?)?.toInt() ?? 0;
    } else {
      for (final day in daily) {
        final cat = day.category ?? categoryFromCondition(day.condition);
        if (sum.containsKey(cat)) {
          sum[cat] = (sum[cat] ?? 0) + 1;
        }
      }
    }

    return MonthlyWeatherResponse(
      year: year,
      month: month,
      dailyRecords: daily,
      summary: sum,
    );
  }

  final int year;
  final int month;
  final List<MonthlyWeatherDay> dailyRecords;
  final Map<String, int> summary;
}

String categoryFromCondition(String? condition) {
  final text = (condition ?? '').toLowerCase();
  if (text.contains('snow')) return 'snowy';
  if (text.contains('rain') || text.contains('drizzle') || text.contains('thunder')) return 'rainy';
  if (text.contains('partly') || text.contains('mainly')) return 'partly-cloudy';
  if (text.contains('clear') || text.contains('sun')) return 'sunny';
  return 'cloudy';
}
