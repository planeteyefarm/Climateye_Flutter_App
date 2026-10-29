import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

/// Builds a KML document containing a single polygon from [vertices]
/// (in drawing order). The ring is closed by appending the first vertex
/// only when the last one differs from it.
String buildPolygonKml(List<LatLng> vertices, {String name = 'Drawn Area'}) {
  if (vertices.length < 3) {
    throw ArgumentError('A polygon needs at least 3 vertices');
  }
  final ring = List<LatLng>.from(vertices);
  if (ring.first != ring.last) ring.add(ring.first);
  final coordinates =
      ring.map((p) => '${p.longitude},${p.latitude},0').join('\n');

  final b = XmlBuilder()..processing('xml', 'version="1.0" encoding="UTF-8"');
  b.element('kml', namespaces: {'http://www.opengis.net/kml/2.2': null}, nest: () {
    b.element('Document', nest: () {
      b.element('name', nest: name);
      b.element('Placemark', nest: () {
        b.element('name', nest: name);
        b.element('Polygon', nest: () {
          b.element('outerBoundaryIs', nest: () {
            b.element('LinearRing', nest: () {
              b.element('coordinates', nest: coordinates);
            });
          });
        });
      });
    });
  });
  return b.buildDocument().toXmlString(pretty: true);
}

/// `climateeye_area_YYYYMMDD_HHmmss.kml`
String kmlFileName(DateTime time) =>
    'climateeye_area_${DateFormat('yyyyMMdd_HHmmss').format(time)}.kml';
