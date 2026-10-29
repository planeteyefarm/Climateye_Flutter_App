import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../utils/date_utils.dart';
import 'json_utils.dart';

class MethaneLegend {
  MethaneLegend({this.min, this.max, this.palette = const [], this.title, this.unit});

  factory MethaneLegend.fromJson(dynamic j) {
    if (j is! Map) return MethaneLegend();
    final palette = (j['palette'] is List ? j['palette'] as List : const [])
        .map((e) => parseHexColor(e.toString()))
        .whereType<Color>()
        .toList();
    return MethaneLegend(
      min: toDouble(j['min']),
      max: toDouble(j['max']),
      palette: palette,
      title: toStr(j['title']),
      unit: toStr(j['unit']),
    );
  }

  final double? min, max;
  final List<Color> palette;
  final String? title, unit;
}

class MethaneCatalog {
  MethaneCatalog({this.coverageStart, this.coverageEnd, this.legend, this.attribution});

  factory MethaneCatalog.fromJson(Map<String, dynamic> j) {
    final cov = j['coverage'] is Map ? j['coverage'] as Map : const {};
    return MethaneCatalog(
      coverageStart: parseApiDate(cov['start']),
      coverageEnd: parseApiDate(cov['end']),
      legend: MethaneLegend.fromJson(j['legend']),
      attribution: toStr(j['attribution']),
    );
  }

  final DateTime? coverageStart, coverageEnd;
  final MethaneLegend? legend;
  final String? attribution;
}

class MethaneTiles {
  MethaneTiles({this.tileUrl, required this.legend, this.attribution, this.count});

  factory MethaneTiles.fromJson(Map<String, dynamic> j) => MethaneTiles(
        tileUrl: toStr(j['tile_url']),
        legend: MethaneLegend.fromJson(j['legend']),
        attribution: toStr(j['attribution']),
        count: toDouble(j['count'])?.toInt(),
      );

  final String? tileUrl;
  final MethaneLegend legend;
  final String? attribution;
  final int? count;
}

class MethanePlume {
  MethanePlume({
    required this.id,
    required this.point,
    this.enhancement,
    this.confidence,
    this.observedAt,
    this.windSpeed,
    this.windDirection,
    this.plumeLenMax,
  });

  static MethanePlume? fromFeature(Map<String, dynamic> f) {
    final geom = f['geometry'];
    if (geom is! Map || geom['type'] != 'Point') return null;
    final c = geom['coordinates'];
    if (c is! List || c.length < 2) return null;
    final lng = toDouble(c[0]), lat = toDouble(c[1]);
    if (lat == null || lng == null) return null;
    final p = f['properties'] is Map ? f['properties'] as Map : const {};
    return MethanePlume(
      id: f['id']?.toString() ?? '$lat,$lng',
      point: LatLng(lat, lng),
      enhancement: toDouble(p['methane_enhancement_ppm_m']),
      confidence: toStr(p['confidence']),
      observedAt: toStr(p['observed_at']),
      windSpeed: toDouble(p['wind_speed_m_s']),
      windDirection: toDouble(p['wind_direction_deg']),
      plumeLenMax: toDouble(p['plume_len_max']),
    );
  }

  final String id;
  final LatLng point;
  final double? enhancement, windSpeed, windDirection, plumeLenMax;
  final String? confidence, observedAt;
}

Color? parseHexColor(String hex) {
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}
