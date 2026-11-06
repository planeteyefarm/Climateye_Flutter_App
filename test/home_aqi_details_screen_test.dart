import 'package:climateeye/models/aqi.dart';
import 'package:climateeye/screens/home_aqi_details_screen.dart';
import 'package:climateeye/widgets/aqi_pollutant_donut.dart';
import 'package:climateeye/widgets/aqi_pollutant_pills_chart.dart';
import 'package:climateeye/widgets/home_aqi_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sampleRecord = AqiRecord.fromJson({
    'aqi': 82,
    'pm2_5': 27.0,
    'pm10': 27.9,
    'no2': 10.7,
    'so2': 12.3,
    'o3': 79.0,
    'co': 334.0,
  });

  testWidgets('AQI overview mode displays only pollutant distribution and donut',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeAqiDetailsScreen(
          latitude: 19.9975,
          longitude: 73.7898,
          mode: HomeAqiDetailsMode.overview,
          initialRecord: sampleRecord,
          isSatellite: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify AQI screen elements are present
    expect(find.byType(AqiPollutantDonut), findsOneWidget);
    expect(find.byType(AqiPollutantDistributionPanel), findsOneWidget);
    expect(find.text('82'), findsOneWidget);
    expect(find.text('Moderate'), findsOneWidget);
    expect(find.text('Pollutant Distribution'), findsOneWidget);

    // STRICT RULE: No HomeAqiGauge or pills chart on AQI screen
    expect(find.byType(HomeAqiGauge), findsNothing);
    expect(find.byType(AqiPollutantPillsChart), findsNothing);
  });

  testWidgets('History mode displays History title, location, AQI gauge above graph, and chart',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeAqiDetailsScreen(
          latitude: 19.9975,
          longitude: 73.7898,
          mode: HomeAqiDetailsMode.history,
          initialRecord: sampleRecord,
          placeName: 'Nashik, Maharashtra',
          isSatellite: true,
        ),
      ),
    );
    await tester.pump();

    // Verify History chart elements are present
    expect(find.byType(AqiPollutantPillsChart), findsOneWidget);
    expect(find.text('History'), findsWidgets);
    expect(find.text('Nashik, Maharashtra'), findsOneWidget);

    // Verify HomeAqiGauge is present and positioned strictly ABOVE the graph
    expect(find.byType(HomeAqiGauge), findsOneWidget);
    final aqiTop = tester.getTopLeft(find.byType(HomeAqiGauge)).dy;
    final graphTitleTop = tester.getTopLeft(find.text('Last 6 Hours')).dy;
    expect(aqiTop < graphTitleTop, isTrue);

    // Verify Donut panel is NOT present on History screen
    expect(find.byType(AqiPollutantDonut), findsNothing);
    expect(find.byType(AqiPollutantDistributionPanel), findsNothing);
  });

  testWidgets('Prediction mode displays Prediction title, location, AQI gauge above graph, and chart',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeAqiDetailsScreen(
          latitude: 19.9975,
          longitude: 73.7898,
          mode: HomeAqiDetailsMode.prediction,
          initialRecord: sampleRecord,
          placeName: 'Nashik, Maharashtra',
          isSatellite: true,
        ),
      ),
    );
    await tester.pump();

    // Verify Prediction chart elements are present
    expect(find.byType(AqiPollutantPillsChart), findsOneWidget);
    expect(find.text('Prediction'), findsWidgets);
    expect(find.text('Nashik, Maharashtra'), findsOneWidget);

    // Verify HomeAqiGauge is present and positioned strictly ABOVE the graph
    expect(find.byType(HomeAqiGauge), findsOneWidget);
    final aqiTop = tester.getTopLeft(find.byType(HomeAqiGauge)).dy;
    final graphTitleTop = tester.getTopLeft(find.text('Next 6 Hours')).dy;
    expect(aqiTop < graphTitleTop, isTrue);

    // Verify Donut panel is NOT present on Prediction screen
    expect(find.byType(AqiPollutantDonut), findsNothing);
    expect(find.byType(AqiPollutantDistributionPanel), findsNothing);
  });
}
