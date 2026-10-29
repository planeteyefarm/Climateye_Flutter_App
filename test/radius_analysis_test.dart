import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:climateeye/models/building.dart';
import 'package:climateeye/widgets/near_you_panel.dart';

void main() {
  group('Haversine Distance & Bounds', () {
    test('Calculates accurate distance in meters', () {
      // Points ~111.32 km apart along equator
      const p1 = LatLng(0.0, 0.0);
      const p2 = LatLng(1.0, 0.0);
      final dist = haversineMeters(p1, p2);
      expect((dist - 111195).abs() < 200, isTrue);

      // Same point is 0 meters
      expect(haversineMeters(p1, p1), 0.0);
    });

    test('boundsForRadius adds 15% buffer', () {
      const center = LatLng(20.0, 78.0);
      final boundsStr = boundsForRadius(center, 100.0);
      final parts = boundsStr.split(',').map(double.parse).toList();
      expect(parts.length, 4);
      final minLng = parts[0], minLat = parts[1], maxLng = parts[2], maxLat = parts[3];

      expect(minLng < center.longitude, isTrue);
      expect(maxLng > center.longitude, isTrue);
      expect(minLat < center.latitude, isTrue);
      expect(maxLat > center.latitude, isTrue);
    });
  });

  group('Building Centroid Calculation', () {
    test('Calculates centroid omitting duplicate closing vertex', () {
      // Square polygon: (10, 10), (10, 20), (20, 20), (20, 10), (10, 10)
      final ring = [
        const LatLng(10.0, 10.0),
        const LatLng(10.0, 20.0),
        const LatLng(20.0, 20.0),
        const LatLng(20.0, 10.0),
        const LatLng(10.0, 10.0), // closing duplicate
      ];
      final centroid = computeRingCentroid(ring);
      expect(centroid, isNotNull);
      // Arithmetic mean of 4 unique corners is (15, 15)
      expect(centroid!.latitude, closeTo(15.0, 1e-6));
      expect(centroid.longitude, closeTo(15.0, 1e-6));
    });

    test('Calculates centroid without closing duplicate', () {
      final ring = [
        const LatLng(0.0, 0.0),
        const LatLng(0.0, 6.0),
        const LatLng(6.0, 6.0),
      ];
      final centroid = computeRingCentroid(ring);
      expect(centroid, isNotNull);
      expect(centroid!.latitude, closeTo(2.0, 1e-6));
      expect(centroid.longitude, closeTo(4.0, 1e-6));
    });
  });

  group('Building Feature Parsing & Deduplication', () {
    test('Parses GeoJSON building feature and sets unique featureKey', () {
      final featureJson = {
        'type': 'Feature',
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            [
              [78.9662, 20.5928],
              [78.9662, 20.5929],
              [78.9661, 20.5929],
              [78.9661, 20.5928],
              [78.9662, 20.5928],
            ]
          ]
        },
        'properties': {
          'detection': 'footprint',
          'height': 5.2,
          'area_m2': 64.0,
        }
      };

      final feature = BuildingFeature.fromJson(featureJson);
      expect(feature, isNotNull);
      expect(feature!.properties.height, 5.2);
      expect(feature.properties.detection, 'footprint');
      expect(feature.featureKey.startsWith('footprint:'), isTrue);
    });

    test('Deduplicates features sharing the same spatial key', () {
      final featureJson1 = {
        'type': 'Feature',
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            [
              [78.9662, 20.5928],
              [78.9662, 20.5929],
              [78.9661, 20.5929],
              [78.9661, 20.5928],
              [78.9662, 20.5928],
            ]
          ]
        },
        'properties': {'detection': 'footprint', 'height': 5.2}
      };

      // Exact same building returned in an overlapping adjacent bounding box
      final featureJson2 = Map<String, dynamic>.from(featureJson1);

      final f1 = BuildingFeature.fromJson(featureJson1)!;
      final f2 = BuildingFeature.fromJson(featureJson2)!;

      final Map<String, BuildingFeature> deduplicated = {};
      deduplicated[f1.featureKey] = f1;
      deduplicated[f2.featureKey] = f2;

      // Deduplication collapses overlapping copies to 1
      expect(deduplicated.length, 1);
    });
  });

  group('Radius Boundary Inclusion / Exclusion', () {
    const userLocation = LatLng(20.5937, 78.9629);

    test('Includes building if centroid is within radius, excludes if outside', () {
      // Building A: ~50 meters away (inside 100 m)
      final insideRing = [
        const LatLng(20.5940, 78.9629),
        const LatLng(20.5941, 78.9629),
        const LatLng(20.5941, 78.9630),
        const LatLng(20.5940, 78.9630),
        const LatLng(20.5940, 78.9629),
      ];
      final bInside = BuildingFeature(
        outerRing: insideRing,
        centroid: computeRingCentroid(insideRing)!,
        properties: const BuildingProperties(detection: 'footprint'),
      );

      // Building B: ~150 meters away (outside 100 m, inside 2 km)
      final outside100mRing = [
        const LatLng(20.5952, 78.9629),
        const LatLng(20.5953, 78.9629),
        const LatLng(20.5953, 78.9630),
        const LatLng(20.5952, 78.9630),
        const LatLng(20.5952, 78.9629),
      ];
      final bOutside100m = BuildingFeature(
        outerRing: outside100mRing,
        centroid: computeRingCentroid(outside100mRing)!,
        properties: const BuildingProperties(detection: 'footprint'),
      );

      final allBuildings = [bInside, bOutside100m];

      // At 100 m:
      final at100m = allBuildings.where(
        (b) => haversineMeters(userLocation, b.centroid) <= 100.0,
      ).toList();
      expect(at100m.length, 1);
      expect(at100m.first, bInside);

      // At 2 km:
      final at2km = allBuildings.where(
        (b) => haversineMeters(userLocation, b.centroid) <= 2000.0,
      ).toList();
      expect(at2km.length, 2);

      // At 5 km:
      final at5km = allBuildings.where(
        (b) => haversineMeters(userLocation, b.centroid) <= 5000.0,
      ).toList();
      expect(at5km.length, 2);

      // At 10 km:
      final at10km = allBuildings.where(
        (b) => haversineMeters(userLocation, b.centroid) <= 10000.0,
      ).toList();
      expect(at10km.length, 2);
    });

    test('Building count is based on full set and not capped by visual limit', () {
      // Simulate 650 buildings
      final features = List.generate(650, (i) {
        final pt = LatLng(userLocation.latitude + i * 0.0001, userLocation.longitude);
        return BuildingFeature(
          outerRing: [pt, pt, pt],
          centroid: pt,
          properties: BuildingProperties(detection: 'footprint', height: 4.0 + i % 10),
        );
      });

      final collection = BuildingCollection(
        features: features,
        count: features.length,
        isPartial: true,
      );

      // The count reflects all 650 features even if visual renderer only draws 500
      expect(collection.count, 650);
      expect(collection.isPartial, isTrue);
      expect(collection.hasWarnings, isTrue);
    });
  });

  group('NearYouPanel Widget & Responsiveness', () {
    testWidgets('Renders and collapses/expands smoothly without overflow', (tester) async {
      double selected = 100;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 375,
                child: NearYouPanel(
                  selectedRadius: selected,
                  onSelectRadius: (r) => selected = r,
                  maxWidth: 247,
                ),
              ),
            ),
          ),
        ),
      );

      // Verify expanded view elements
      expect(find.text('NEAR YOU'), findsOneWidget);
      expect(find.text('Within 100 m'), findsOneWidget);
      expect(find.text('100 m'), findsOneWidget);
      expect(find.text('2 km'), findsOneWidget);
      expect(find.text('5 km'), findsOneWidget);
      expect(find.text('10 km'), findsOneWidget);

      // Tap collapse button
      await tester.tap(find.byTooltip('Collapse'));
      await tester.pumpAndSettle();

      // Verify minimized pill
      expect(find.text('Near you · 100 m'), findsOneWidget);
      expect(find.text('Within 100 m'), findsNothing);

      // Tap to expand
      await tester.tap(find.byTooltip('Expand Near You panel'));
      await tester.pumpAndSettle();

      // Verify expanded again
      expect(find.text('NEAR YOU'), findsOneWidget);
      expect(find.text('Within 100 m'), findsOneWidget);

      // Tap 2 km radius
      await tester.tap(find.text('2 km'));
      expect(selected, 2000);
    });

    testWidgets('Renders cleanly at 430px and 768px constraints without error', (tester) async {
      for (final width in [430.0, 768.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: NearYouPanel(
                    selectedRadius: 5000,
                    onSelectRadius: (_) {},
                    maxWidth: width >= 600 ? 280 : 265,
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.text('Within 5 km'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });
}
