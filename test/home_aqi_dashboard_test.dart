import 'package:climateeye/models/aqi.dart';
import 'package:climateeye/widgets/dark_osm_tiles.dart';
import 'package:climateeye/widgets/home_aqi_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('themed GPS locating indicator', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: HomeGpsLocatingIndicator())),
    ));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byType(HomeGpsLocatingIndicator), findsOneWidget);
    expect(find.byIcon(Icons.location_on_rounded), findsOneWidget);
    expect(find.textContaining('Fetching your current location'), findsNothing);
  });

  testWidgets('GPS retry chip invokes callback', (t) async {
    var tapped = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeGpsRetryChip(onRetry: () => tapped = true),
      ),
    ));
    await t.tap(find.text('Retry location'));
    await t.pump();
    expect(tapped, isTrue);
  });

  testWidgets('Design 5 gauge shows category beneath circle', (t) async {
    final record = AqiRecord.fromJson({
      'aqi': 110,
      'pm2_5': 42.5,
      'pm10': 80,
      'no2': 18,
      'so2': 5,
      'o3': 22,
      'co': 0.4,
    });
    var tapped = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeAqiGauge(
          aqi: record.aqi,
          category: aqiCategory(record.aqi!),
          onTap: () => tapped = true,
          size: 150,
        ),
      ),
    ));
    expect(find.text('110'), findsOneWidget);
    expect(find.text('Poor'), findsOneWidget);
    // Category label uses near-black (not category colour).
    final cat = t.widget<Text>(find.text('Poor'));
    expect(cat.style?.color?.toARGB32(), 0xFF0F172A);
    expect(find.text('Tap for details'), findsOneWidget);
    await t.tap(find.text('110'));
    await t.pump();
    expect(tapped, isTrue);
  });

  testWidgets('History / Prediction bar invokes callbacks', (t) async {
    var history = false;
    var prediction = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeHistoryPredictionBar(
          onHistory: () => history = true,
          onPrediction: () => prediction = true,
        ),
      ),
    ));
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Prediction'), findsOneWidget);
    await t.tap(find.text('History'));
    await t.pump();
    expect(history, isTrue);
    await t.tap(find.text('Prediction'));
    await t.pump();
    expect(prediction, isTrue);
  });

  testWidgets('location name chip shows place outside the gauge', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: HomeLocationNameChip(name: 'Nashik, Maharashtra'),
      ),
    ));
    expect(find.text('Nashik, Maharashtra'), findsOneWidget);
    expect(find.byIcon(Icons.place_outlined), findsOneWidget);
  });

  testWidgets('phone viewport keeps six pollutants in one row', (t) async {
    final record = AqiRecord.fromJson({
      'aqi': 108,
      'pm2_5': 22.8,
      'pm10': 27.0,
      'no2': 1.6,
      'so2': 6.6,
      'o3': 143,
      'co': 196,
    });
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(390, 844)),
        child: Scaffold(
          body: Center(
            child: HomePollutantBar(record: record, placeName: 'Pune'),
          ),
        ),
      ),
    ));
    for (final label in ['PM2.5', 'PM10', 'NO₂', 'SO₂', 'O₃', 'CO']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byType(Wrap), findsNothing);
  });

  testWidgets('map gauge and bottom pollutant bar stay separate', (t) async {
    final record = AqiRecord.fromJson({
      'aqi': 110,
      'pm2_5': 42.5,
      'pm10': 80,
      'no2': 18,
      'so2': 5,
      'o3': 22,
      'co': 0.4,
    });
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            HomeAqiGauge(
              aqi: record.aqi,
              category: aqiCategory(record.aqi!),
              size: 150,
            ),
            HomePollutantBar(record: record, placeName: 'Nashik'),
          ],
        ),
      ),
    ));
    expect(find.byType(HomeAqiGauge), findsOneWidget);
    expect(find.text('110'), findsOneWidget);
    for (final label in ['PM2.5', 'PM10', 'NO₂', 'SO₂', 'O₃', 'CO']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byType(Wrap), findsNothing);
  });

  test('pollutant field list covers the six /aqi components', () {
    expect(kHomePollutantFields.map((e) => e.$1).toList(),
        ['pm2_5', 'pm10', 'no2', 'so2', 'o3', 'co']);
  });

  test('light OSM constants match Design 1/5 palette', () {
    expect(LightOsmTileLayer.background.toARGB32(), 0xFFE8EEF4);
    expect(LightOsmTileLayer.accent.toARGB32(), 0xFF14B8A6);
  });
}
