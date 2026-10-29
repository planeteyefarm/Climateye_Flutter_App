import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

/// A polygon area of interest stored as a single GeoJSON-style ring.
class AreaGeometry {
  AreaGeometry(this.ring);

  /// Vertices in order. Drawn areas are closed (last == first); KML rings
  /// are kept exactly as written in the file.
  final List<LatLng> ring;

  bool get isValid => _distinctVertices >= 3;

  int get _distinctVertices =>
      ring.map((p) => '${p.latitude},${p.longitude}').toSet().length;

  /// Number of distinct vertices (display only).
  int get vertexCount => _distinctVertices;

  /// Approximate geodesic area in km² on a spherical Earth (display only;
  /// no request or analysis uses it).
  double get areaKm2 {
    if (ring.length < 3) return 0;
    const r = 6371.0088;
    double rad(double d) => d * math.pi / 180;
    var sum = 0.0;
    for (var i = 0; i < ring.length; i++) {
      final a = ring[i], b = ring[(i + 1) % ring.length];
      sum += rad(b.longitude - a.longitude) *
          (2 + math.sin(rad(a.latitude)) + math.sin(rad(b.latitude)));
    }
    return (sum * r * r / 2).abs();
  }

  /// Centroid = arithmetic mean of ring coordinates (src/services/api.js#L6-L24).
  LatLng get centroid {
    final lat = ring.map((p) => p.latitude).reduce((a, b) => a + b) / ring.length;
    final lng = ring.map((p) => p.longitude).reduce((a, b) => a + b) / ring.length;
    return LatLng(lat, lng);
  }

  /// "minLng,minLat,maxLng,maxLat" (boundsFromGeometry).
  String get boundsString {
    final lats = ring.map((p) => p.latitude);
    final lngs = ring.map((p) => p.longitude);
    double mn(Iterable<double> v) => v.reduce((a, b) => a < b ? a : b);
    double mx(Iterable<double> v) => v.reduce((a, b) => a > b ? a : b);
    return '${mn(lngs)},${mn(lats)},${mx(lngs)},${mx(lats)}';
  }

  static AreaGeometry fromVertices(List<LatLng> vertices) {
    final ring = List<LatLng>.from(vertices);
    if (ring.isNotEmpty && ring.first != ring.last) ring.add(ring.first);
    return AreaGeometry(ring);
  }
}

class KmlParseException implements Exception {
  KmlParseException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Parses a KML (text) or KMZ (zip) file into a polygon ring.
/// Follows Dashboard.jsx#L363-L393: first `coordinates` node, split on
/// whitespace, each tuple "lng,lat[,alt]".
AreaGeometry parseKmlOrKmz(String fileName, Uint8List bytes) {
  String kmlText;
  if (fileName.toLowerCase().endsWith('.kmz')) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final kmlFile = archive.files.firstWhere(
      (f) => f.isFile && f.name.toLowerCase().endsWith('.kml'),
      orElse: () => throw KmlParseException('No .kml file found inside KMZ'),
    );
    kmlText = utf8.decode(kmlFile.content as List<int>, allowMalformed: true);
  } else {
    kmlText = utf8.decode(bytes, allowMalformed: true);
  }

  XmlDocument doc;
  try {
    doc = XmlDocument.parse(kmlText);
  } catch (e) {
    throw KmlParseException('Invalid KML/XML: $e');
  }
  final coordNode = doc.findAllElements('coordinates').firstOrNull;
  if (coordNode == null) {
    throw KmlParseException('No <coordinates> element found in file');
  }
  final points = <LatLng>[];
  for (final tuple in coordNode.innerText.trim().split(RegExp(r'\s+'))) {
    final parts = tuple.split(',');
    if (parts.length < 2) continue;
    final lng = double.tryParse(parts[0]);
    final lat = double.tryParse(parts[1]);
    if (lat == null || lng == null) continue;
    points.add(LatLng(lat, lng));
  }
  // Keep the tuples exactly as written so the centroid averages the same
  // points as the website's parser (no closing point is added).
  final geom = AreaGeometry(points);
  if (!geom.isValid) {
    throw KmlParseException('KML coordinates do not form a polygon (need ≥3 points)');
  }
  return geom;
}
