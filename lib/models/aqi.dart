import 'package:flutter/material.dart';

import '../utils/date_utils.dart';
import 'json_utils.dart';

enum HeightOption { ground0to3m, ambient3mAbove }

extension HeightOptionLabel on HeightOption {
  String get label =>
      this == HeightOption.ground0to3m ? '0–3 m (Ground)' : '3 m above (Ambient)';
}

/// Port of `extractDataByHeight` (src/utils/dataTransformers.js).
/// For ground level, every `<key>_0to3m` value replaces `<key>`.
Map<String, dynamic> extractDataByHeight(
    Map<String, dynamic> data, HeightOption height) {
  if (height == HeightOption.ambient3mAbove) return data;
  final result = Map<String, dynamic>.from(data);
  data.forEach((key, value) {
    if (key.endsWith('_0to3m')) {
      result[key.replaceAll('_0to3m', '')] = value;
    }
  });
  return result;
}

class AqiRecord {
  AqiRecord({
    required this.raw,
    this.date,
    this.aqi,
    this.pm25,
    this.pm10,
    this.co,
    this.no2,
    this.so2,
    this.o3,
    this.dataSource,
  });

  factory AqiRecord.fromJson(Map<String, dynamic> j) => AqiRecord(
        raw: j,
        date: parseApiDate(j['date']),
        aqi: toDouble(j['aqi']),
        pm25: toDouble(j['pm2_5']),
        pm10: toDouble(j['pm10']),
        co: toDouble(j['co']),
        no2: toDouble(j['no2']),
        so2: toDouble(j['so2']),
        o3: toDouble(j['o3']),
        dataSource: toStr(j['data_source']),
      );

  final Map<String, dynamic> raw;
  final DateTime? date;
  final double? aqi, pm25, pm10, co, no2, so2, o3;
  final String? dataSource;

  double? value(String key) => toDouble(raw[key]);
}

/// Pollutant keys and display labels used across the app.
const pollutantKeys = <String, String>{
  'pm2_5': 'PM2.5',
  'pm10': 'PM10',
  'no2': 'NO₂',
  'so2': 'SO₂',
  'o3': 'O₃',
  'co': 'CO',
};

class AqiCategory {
  const AqiCategory(this.label, this.color);
  final String label;
  final Color color;
}

/// Category bands from handover §5.1. Colours approximate the website's
/// gauge as seen in screenshots; exact hex values are not in the handover.
AqiCategory aqiCategory(double aqi) {
  if (aqi <= 50) return const AqiCategory('Good', Color(0xFF1ABC9C));
  if (aqi <= 100) return const AqiCategory('Moderate', Color(0xFFF39C12));
  if (aqi <= 150) return const AqiCategory('Poor', Color(0xFFE67E22));
  if (aqi <= 200) return const AqiCategory('Unhealthy', Color(0xFFE74C3C));
  if (aqi <= 300) return const AqiCategory('Severe', Color(0xFF9B59B6));
  return const AqiCategory('Hazardous', Color(0xFFC0392B));
}

/// Needle sweep in degrees over the 180° arc (handover §5.1). The website
/// draws Good on the left, so the gauge measures this angle from the left.
double aqiGaugeAngle(double aqi) {
  if (aqi < 0) return 0;
  if (aqi <= 50) return aqi / 50 * 30;
  if (aqi <= 100) return 30 + (aqi - 50) / 50 * 30;
  if (aqi <= 150) return 60 + (aqi - 100) / 50 * 30;
  if (aqi <= 200) return 90 + (aqi - 150) / 50 * 30;
  if (aqi <= 300) return 120 + (aqi - 200) / 100 * 30;
  final a = 150 + (aqi - 300) / 100 * 30;
  return a > 180 ? 180 : a;
}

/// Daily average AQI = round(sum / N) (handover §5.3).
int? roundedAverage(Iterable<double?> values) {
  final v = values.whereType<double>().toList();
  if (v.isEmpty) return null;
  return (v.reduce((a, b) => a + b) / v.length).round();
}
