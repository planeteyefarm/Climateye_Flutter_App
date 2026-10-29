import 'package:climateeye/models/aqi.dart';
import 'package:climateeye/widgets/aqi_pollutant_donut.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('segment shares come from API values and sum to ~1', () {
    final record = AqiRecord.fromJson({
      'aqi': 110,
      'pm2_5': 40,
      'pm10': 20,
      'no2': 10,
      'so2': 10,
      'o3': 15,
      'co': 5,
    });
    final segs = AqiPollutantDonut.segmentsFor(record);
    expect(segs.length, 6);
    final sum = segs.fold<double>(0, (a, s) => a + s.share);
    expect(sum, closeTo(1.0, 1e-9));
    expect(segs.firstWhere((s) => s.key == 'pm2_5').share, closeTo(0.4, 1e-9));
  });

  test('zero / missing pollutants are omitted from segments', () {
    final record = AqiRecord.fromJson({
      'aqi': 50,
      'pm2_5': 10,
      'pm10': 0,
      'no2': null,
      'so2': 5,
    });
    final segs = AqiPollutantDonut.segmentsFor(record);
    expect(segs.map((s) => s.key), ['pm2_5', 'so2']);
  });

  testWidgets('donut shows centre AQI and status', (t) async {
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
      home: Scaffold(body: Center(child: AqiPollutantDonut(record: record))),
    ));
    expect(find.text('110'), findsOneWidget);
    expect(find.text('Poor'), findsOneWidget);
    expect(find.text('AQI'), findsWidgets);
  });

  testWidgets('distribution panel lists pollutants and footer', (t) async {
    final record = AqiRecord.fromJson({
      'aqi': 110,
      'pm2_5': 48,
      'pm10': 28,
      'no2': 20,
      'so2': 8,
      'o3': 16,
      'co': 12,
    });
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AqiPollutantDistributionPanel(record: record),
        ),
      ),
    ));
    for (final label in ['PM2.5', 'PM10', 'NO₂', 'SO₂', 'O₃', 'CO']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.textContaining('Air quality is'), findsOneWidget);
  });
}
