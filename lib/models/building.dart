import 'dart:math' as math;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'json_utils.dart';

/// Haversine distance in meters with Earth radius 6,371,000 m (same as Website).
double haversineMeters(LatLng p1, LatLng p2) {
  const r = 6371000.0;
  double toRad(double deg) => deg * math.pi / 180.0;

  final dLat = toRad(p2.latitude - p1.latitude);
  final dLng = toRad(p2.longitude - p1.longitude);

  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(toRad(p1.latitude)) *
          math.cos(toRad(p2.latitude)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);

  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return r * c;
}

/// Computes the arithmetic mean centroid of the polygon's outer ring,
/// excluding duplicate closing vertex where present (matching Website logic).
LatLng? computeRingCentroid(List<LatLng> ring) {
  if (ring.isEmpty) return null;
  final first = ring.first;
  final last = ring.last;
  final hasDuplicateClosing = ring.length > 1 &&
      (first.latitude - last.latitude).abs() < 1e-9 &&
      (first.longitude - last.longitude).abs() < 1e-9;
  final count = hasDuplicateClosing ? ring.length - 1 : ring.length;
  if (count <= 0) return null;

  double sumLat = 0.0;
  double sumLng = 0.0;
  for (int i = 0; i < count; i++) {
    sumLat += ring[i].latitude;
    sumLng += ring[i].longitude;
  }
  return LatLng(sumLat / count, sumLng / count);
}

/// Returns bounding box string "minLng,minLat,maxLng,maxLat" with 15% padding (matching Website).
String boundsForRadius(LatLng center, double radiusMeters) {
  final pad = radiusMeters * 1.15;
  const metersPerDegreeLat = 111320.0;
  final cosLat = math.max(0.2, math.cos(center.latitude * math.pi / 180.0));
  final dLat = pad / metersPerDegreeLat;
  final dLng = pad / (metersPerDegreeLat * cosLat);

  final minLng = center.longitude - dLng;
  final minLat = center.latitude - dLat;
  final maxLng = center.longitude + dLng;
  final maxLat = center.latitude + dLat;

  return '$minLng,$minLat,$maxLng,$maxLat';
}

/// Returns camera LatLngBounds fitting the radius circle with 5% padding.
LatLngBounds latLngBoundsForRadius(LatLng center, double radiusMeters) {
  final pad = radiusMeters * 1.05;
  const metersPerDegreeLat = 111320.0;
  final cosLat = math.max(0.2, math.cos(center.latitude * math.pi / 180.0));
  final dLat = pad / metersPerDegreeLat;
  final dLng = pad / (metersPerDegreeLat * cosLat);

  return LatLngBounds(
    LatLng(center.latitude - dLat, center.longitude - dLng),
    LatLng(center.latitude + dLat, center.longitude + dLng),
  );
}

/// Properties of a building footprint.
class BuildingProperties {
  const BuildingProperties({
    this.height,
    this.areaM2,
    this.detection,
    this.confidence,
    this.floors,
    this.heightSource,
  });

  factory BuildingProperties.fromJson(Map<String, dynamic> json) =>
      BuildingProperties(
        height: toDouble(json['height']),
        areaM2: toDouble(json['area_m2']),
        detection: toStr(json['detection']),
        confidence: toDouble(json['confidence']),
        floors: toDouble(json['floors'])?.toInt(),
        heightSource: toStr(json['height_source']),
      );

  final double? height;
  final double? areaM2;
  final String? detection;
  final double? confidence;
  final int? floors;
  final String? heightSource;
}

/// A parsed building feature containing polygon geometry and properties.
class BuildingFeature {
  BuildingFeature({
    required this.outerRing,
    required this.properties,
    required this.centroid,
    this.innerRings = const [],
  });

  static BuildingFeature? fromJson(Map<String, dynamic> featureMap) {
    final geom = featureMap['geometry'];
    if (geom is! Map<String, dynamic>) return null;
    final geomType = geom['type']?.toString();
    final rawCoords = geom['coordinates'];
    if (rawCoords is! List || rawCoords.isEmpty) return null;

    List<LatLng> outer = [];
    List<List<LatLng>> inners = [];

    if (geomType == 'Polygon') {
      if (rawCoords.isNotEmpty && rawCoords[0] is List) {
        outer = _parseRing(rawCoords[0] as List);
        for (int i = 1; i < rawCoords.length; i++) {
          if (rawCoords[i] is List) {
            inners.add(_parseRing(rawCoords[i] as List));
          }
        }
      }
    } else if (geomType == 'MultiPolygon') {
      // First polygon
      if (rawCoords.isNotEmpty && rawCoords[0] is List) {
        final poly = rawCoords[0] as List;
        if (poly.isNotEmpty && poly[0] is List) {
          outer = _parseRing(poly[0] as List);
        }
      }
    }

    if (outer.length < 3) return null;

    final centroid = computeRingCentroid(outer);
    if (centroid == null) return null;

    final propsMap = featureMap['properties'] is Map<String, dynamic>
        ? featureMap['properties'] as Map<String, dynamic>
        : const <String, dynamic>{};

    return BuildingFeature(
      outerRing: outer,
      innerRings: inners,
      properties: BuildingProperties.fromJson(propsMap),
      centroid: centroid,
    );
  }

  static List<LatLng> _parseRing(List rawRing) {
    final list = <LatLng>[];
    for (final pt in rawRing) {
      if (pt is List && pt.length >= 2) {
        final lng = toDouble(pt[0]);
        final lat = toDouble(pt[1]);
        if (lat != null && lng != null) {
          list.add(LatLng(lat, lng));
        }
      }
    }
    return list;
  }

  final List<LatLng> outerRing;
  final List<List<LatLng>> innerRings;
  final BuildingProperties properties;
  final LatLng centroid;

  /// Unique spatial key matching Website deduplication logic:
  /// "${detection}:${lng.toFixed(5)},${lat.toFixed(5)}"
  String get featureKey =>
      '${properties.detection ?? ''}:${centroid.longitude.toStringAsFixed(5)},${centroid.latitude.toStringAsFixed(5)}';
}

/// Collection of buildings loaded for a radius.
class BuildingCollection {
  const BuildingCollection({
    required this.features,
    required this.count,
    this.footprintCount,
    this.detectedCount,
    this.truncated = false,
    this.isPartial = false,
    this.note,
  });

  final List<BuildingFeature> features;
  final int count;
  final int? footprintCount;
  final int? detectedCount;
  final bool truncated;
  final bool isPartial;
  final String? note;

  bool get hasWarnings => truncated || isPartial || note != null;
}
