import 'dart:convert';
import 'dart:typed_data';

import 'package:climateeye/models/aqi.dart';
import 'package:climateeye/services/auth_service.dart';
import 'package:climateeye/utils/geo_utils.dart';
import 'package:climateeye/utils/kml_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

void main() {
  group('AQI gauge angle', () {
    test('band boundaries', () {
      expect(aqiGaugeAngle(0), 0);
      expect(aqiGaugeAngle(50), 30);
      expect(aqiGaugeAngle(100), 60);
      expect(aqiGaugeAngle(150), 90);
      expect(aqiGaugeAngle(200), 120);
      expect(aqiGaugeAngle(300), 150);
      expect(aqiGaugeAngle(400), 180);
      expect(aqiGaugeAngle(900), 180);
    });
    test('categories', () {
      expect(aqiCategory(42).label, 'Good');
      expect(aqiCategory(105).label, 'Poor');
      expect(aqiCategory(356).label, 'Hazardous');
    });
  });

  test('height transform replaces base keys with _0to3m values', () {
    final raw = {'aqi': 105, 'aqi_0to3m': 356, 'pm2_5': 37.1, 'pm2_5_0to3m': 125.82};
    final ground = extractDataByHeight(raw, HeightOption.ground0to3m);
    expect(ground['aqi'], 356);
    expect(ground['pm2_5'], 125.82);
    final ambient = extractDataByHeight(raw, HeightOption.ambient3mAbove);
    expect(ambient['aqi'], 105);
  });

  test('rounded average', () {
    expect(roundedAverage([1, 2, null, 2]), 2);
    expect(roundedAverage([]), null);
  });

  test('centroid and bounds', () {
    final g = AreaGeometry.fromVertices(
        const [LatLng(0, 0), LatLng(0, 2), LatLng(2, 2), LatLng(2, 0)]);
    expect(g.isValid, true);
    expect(g.ring.length, 5);
    expect(g.boundsString, '0.0,0.0,2.0,2.0');
  });

  test('KML parsing', () {
    const kml = '''<?xml version="1.0"?><kml><Placemark><Polygon><outerBoundaryIs>
<LinearRing><coordinates>73.8,18.5,0 73.9,18.5,0 73.9,18.6,0 73.8,18.5,0</coordinates>
</LinearRing></outerBoundaryIs></Polygon></Placemark></kml>''';
    final g = parseKmlOrKmz('a.kml', Uint8List.fromList(utf8.encode(kml)));
    expect(g.ring.first, const LatLng(18.5, 73.8));
    expect(g.isValid, true);
    expect(() => parseKmlOrKmz('b.kml', Uint8List.fromList(utf8.encode('<kml/>'))),
        throwsA(isA<KmlParseException>()));
  });

  group('KML export', () {
    const a = LatLng(18.5, 73.8), b = LatLng(18.5, 73.9), c = LatLng(18.6, 73.85);

    List<String> coords(String kml) => XmlDocument.parse(kml)
        .findAllElements('coordinates')
        .single
        .innerText
        .trim()
        .split(RegExp(r'\s+'));

    test('structure, lng,lat,0 order and closing vertex', () {
      final kml = buildPolygonKml(const [a, b, c]);
      final doc = XmlDocument.parse(kml);
      expect(doc.rootElement.name.local, 'kml');
      final ring = doc
          .findAllElements('Document')
          .single
          .findAllElements('Placemark')
          .single
          .findAllElements('Polygon')
          .single
          .findAllElements('outerBoundaryIs')
          .single
          .findAllElements('LinearRing')
          .single;
      expect(ring.findElements('coordinates'), hasLength(1));
      expect(doc.findAllElements('name').first.innerText, 'Drawn Area');
      expect(coords(kml), ['73.8,18.5,0', '73.9,18.5,0', '73.85,18.6,0', '73.8,18.5,0']);
    });

    test('already-closed ring is not closed twice', () {
      final ring = AreaGeometry.fromVertices(const [a, b, c]).ring;
      expect(coords(buildPolygonKml(ring)), hasLength(4));
    });

    test('round-trips through the KML parser', () {
      final kml = buildPolygonKml(const [a, b, c]);
      final g = parseKmlOrKmz('x.kml', Uint8List.fromList(utf8.encode(kml)));
      expect(g.ring, const [a, b, c, a]);
    });

    test('file name', () {
      expect(kmlFileName(DateTime(2026, 10, 12, 9, 5, 7)),
          'climateeye_area_20261012_090507.kml');
    });
  });

  test('login rejects wrong credentials', () async {
    expect(await AuthService.instance.login('admin', 'wrong'), false);
  });
}
