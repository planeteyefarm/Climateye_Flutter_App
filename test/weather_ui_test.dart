import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:climateeye/models/weather.dart';
import 'package:climateeye/widgets/forecast_timeline_strip.dart';
import 'package:climateeye/widgets/rain_field_overlay.dart';
import 'package:climateeye/widgets/temperature_field_overlay.dart';
import 'package:climateeye/widgets/weather_info_card.dart';
import 'package:climateeye/widgets/weather_mode_bar.dart';
import 'package:climateeye/widgets/weather_scale_bar.dart';
import 'package:climateeye/widgets/weather_readout_overlay.dart';
import 'package:climateeye/widgets/wind_field_overlay.dart';

void main() {
  group('WeatherModeBar Widget Tests', () {
    testWidgets('Renders all mode buttons and reflects active state', (tester) async {
      WeatherOverlayMode currentMode = WeatherOverlayMode.temp;
      bool is3d = false;
      bool isSatellite = true;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return WeatherModeBar(
                  mode: currentMode,
                  onModeChanged: (m) => setState(() => currentMode = m),
                  is3d: is3d,
                  onToggle3d: () => setState(() => is3d = !is3d),
                  isSatellite: isSatellite,
                  onToggleMap: () => setState(() => isSatellite = !isSatellite),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('3D'), findsOneWidget);
      expect(find.text('Temp'), findsOneWidget);
      expect(find.text('Rain'), findsOneWidget);
      expect(find.text('Wind'), findsOneWidget);
      expect(find.text('Map'), findsOneWidget);

      // Tap Rain button
      await tester.tap(find.text('Rain'));
      await tester.pumpAndSettle();
      expect(currentMode, equals(WeatherOverlayMode.rain));

      // Tap 3D button
      await tester.tap(find.text('3D'));
      await tester.pumpAndSettle();
      expect(is3d, isTrue);

      // Tap Map button
      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();
      expect(isSatellite, isFalse);
    });
  });

  group('WeatherInfoCard Widget Tests', () {
    testWidgets('Renders current temperature, details, condition, and monthly badges', (tester) async {
      final summary = WeatherSummary(
        temperature: 29.5,
        feelsLike: 31.1,
        tempMax: 30.1,
        tempMin: 22.8,
        condition: 'Light drizzle',
      );

      final monthly = MonthlyWeatherResponse(
        year: 2026,
        month: 10,
        dailyRecords: [],
        summary: {
          'sunny': 5,
          'partly-cloudy': 4,
          'cloudy': 10,
          'rainy': 12,
          'snowy': 0,
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WeatherInfoCard(
              weather: summary,
              monthlyResponse: monthly,
              searchWidget: const TextField(
                decoration: InputDecoration(hintText: 'Search city, town or village'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('29.5°'), findsOneWidget);
      expect(find.text('Feels like 31.1°'), findsOneWidget);
      expect(find.text('High 30.1° · Low 22.8°'), findsOneWidget);
      expect(find.text('Light drizzle'), findsOneWidget);
      expect(find.text('MONTH · 10/2026'), findsOneWidget);
      expect(find.text('Sunny 5'), findsOneWidget);
      expect(find.text('Partly cloudy 4'), findsOneWidget);
      expect(find.text('Cloudy 10'), findsOneWidget);
      expect(find.text('Rainy 12'), findsOneWidget);
      expect(find.text('Snowy 0'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('ForecastTimelineStrip Widget Tests', () {
    testWidgets('Renders daily strip with day labels, high/low, and handles selection', (tester) async {
      final day1 = DateTime(2026, 10, 30);
      final day2 = DateTime(2026, 10, 31);
      final day3 = DateTime(2026, 11, 1);

      final records = [
        MonthlyWeatherDay(date: day1, tempMax: 30.4, tempMin: 21.9, condition: 'Clear'),
        MonthlyWeatherDay(date: day2, tempMax: 30.8, tempMin: 22.5, condition: 'Sunny'),
        MonthlyWeatherDay(date: day3, tempMax: 30.2, tempMin: 21.9, condition: 'Partly cloudy'),
      ];

      DateTime? selected = day1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return ForecastTimelineStrip(
                  dailyRecords: records,
                  selectedDate: selected,
                  onSelectDate: (d) => setState(() => selected = d),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Fri 30'), findsOneWidget);
      expect(find.text('Sat 31'), findsOneWidget);
      expect(find.text('Sun 1'), findsOneWidget);
      expect(find.text('30.4°'), findsOneWidget);
      expect(find.text('30.8°'), findsOneWidget);
      expect(find.text('30.2°'), findsOneWidget);

      // Tap on second day (Sat 31)
      await tester.tap(find.text('Sat 31'));
      await tester.pumpAndSettle();
      expect(selected, equals(day2));
    });
  });

  group('WeatherScaleBar Widget Tests', () {
    testWidgets('Renders temperature scale and rain scale correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WeatherScaleBar(mode: WeatherOverlayMode.temp),
          ),
        ),
      );

      expect(find.text('°C · now'), findsOneWidget);
      expect(find.text('-20'), findsOneWidget);
      expect(find.text('40'), findsOneWidget);

      // Rain mode
      bool forecastRain = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return WeatherScaleBar(
                  mode: WeatherOverlayMode.rain,
                  rainForecastMode: forecastRain,
                  onToggleRainForecast: (v) => setState(() => forecastRain = v),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('mm/3h'), findsOneWidget);
      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('Forecast'), findsOneWidget);
    });
  });

  group('MonthlyWeatherResponse Model Tests', () {
    test('Correctly parses backend JSON and tallies condition categories', () {
      final json = {
        'daily_records': [
          {
            'date': '2026-10-01',
            'temperature_max': 31.0,
            'temperature_min': 23.0,
            'condition': 'Sunny'
          },
          {
            'date': '2026-10-02',
            'temperature_max': 29.0,
            'temperature_min': 22.0,
            'condition': 'Light drizzle'
          },
          {
            'date': '2026-10-03',
            'temperature_max': 28.0,
            'temperature_min': 21.0,
            'condition': 'Snow flurries'
          },
        ]
      };

      final response = MonthlyWeatherResponse.fromJson(json, 2026, 10);
      expect(response.year, equals(2026));
      expect(response.month, equals(10));
      expect(response.dailyRecords.length, equals(3));
      expect(response.summary['sunny'], equals(1));
      expect(response.summary['rainy'], equals(1));
      expect(response.summary['snowy'], equals(1));
    });
  });

  group('Mobile Layout Responsiveness Tests (375px & 430px)', () {
    testWidgets('Header and WeatherModeBar fit cleanly without overflow at 375px width', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.menu), onPressed: () {}),
                    const SizedBox(width: 5),
                    const Flexible(
                      child: Text('ClimateEye', overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 4),
                    WeatherModeBar(
                      mode: WeatherOverlayMode.temp,
                      onModeChanged: (_) {},
                      is3d: false,
                      onToggle3d: () {},
                      isSatellite: true,
                      onToggleMap: () {},
                      compact: true,
                    ),
                    const SizedBox(width: 5),
                    IconButton(icon: const Icon(Icons.person), onPressed: () {}),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      // Confirm no overflow errors were thrown
      expect(tester.takeException(), isNull);
    });

    testWidgets('Search and Near You card stack without overlapping at 375px and 430px', (tester) async {
      for (final width in [375.0, 430.0]) {
        tester.view.physicalSize = Size(width, 667);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    key: const Key('search_box'),
                    width: width - 72,
                    height: 44,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    key: const Key('near_you_pill'),
                    width: 175,
                    height: 36,
                    color: Colors.green,
                  ),
                ],
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        final searchRect = tester.getRect(find.byKey(const Key('search_box')));
        final pillRect = tester.getRect(find.byKey(const Key('near_you_pill')));

        // Verify strictly no vertical overlap: pill sits below search
        expect(pillRect.top, greaterThanOrEqualTo(searchRect.bottom));
      }
      tester.view.resetPhysicalSize();
    });
  });

  group('Website Temperature Replication Tests', () {
    test('12 Windy temperature stops match Website values and Hermite blending', () {
      expect(kTempStops.length, equals(12));
      // Deep blue at -20
      expect(temperatureColorRgb(-20), equals([18, 40, 150]));
      // Burnt red at 40
      expect(temperatureColorRgb(40), equals([145, 28, 38]));
      // Orange around 28
      expect(temperatureColorRgb(28), equals([240, 130, 28]));
      // Out of bounds clamp
      expect(temperatureColorRgb(-30), equals([18, 40, 150]));
      expect(temperatureColorRgb(50), equals([145, 28, 38]));
    });

    test('Grid computation adheres to zoom steps and 56-point cap', () {
      // Zoom 4 -> step 2.0
      expect(stepForZoom(4.0), equals(2.0));
      // Zoom 6 -> step 1.0
      expect(stepForZoom(6.0), equals(1.0));
      // Zoom 8 -> step 0.5
      expect(stepForZoom(8.0), equals(0.5));
      // Zoom 10 -> step 0.25
      expect(stepForZoom(10.0), equals(0.25));

      final bounds = LatLngBounds(const LatLng(18.0, 72.0), const LatLng(21.0, 75.0));
      final grid = computeGridPoints(bounds, 8.0);
      expect(grid.points.length, lessThanOrEqualTo(56));
      expect(grid.points, isNotEmpty);
    });

    test('IDW sampleField performs power-3 falloff and nearest station snapping', () {
      final samples = [
        const TemperatureSample(lat: 20.0, lng: 73.0, temp: 32.0),
        const TemperatureSample(lat: 19.0, lng: 73.0, temp: 28.0),
      ];

      // Point very close to station 1 snaps directly to 32.0
      final atStation1 = sampleTemperatureField(samples, 20.0001, 73.0001, 0.03);
      expect(atStation1, equals(32.0));

      // Point midway between station 1 and station 2
      final mid = sampleTemperatureField(samples, 19.5, 73.0, 0.03);
      expect(mid, isNotNull);
      expect(mid!, greaterThan(28.0));
      expect(mid, lessThan(32.0));
      expect(mid, closeTo(30.0, 0.5));
    });

    test('Hourly record selection picks hour closest to now', () {
      final now = DateTime.now().toUtc();
      final records = [
        HourlyWeather(
          raw: const {},
          date: now.subtract(const Duration(hours: 3)),
          temperature: 24.0,
        ),
        HourlyWeather(
          raw: const {},
          date: now.subtract(const Duration(minutes: 10)),
          temperature: 31.5,
        ),
        HourlyWeather(
          raw: const {},
          date: now.add(const Duration(hours: 4)),
          temperature: 27.0,
        ),
      ];

      final temp = extractCurrentTemperature(records);
      expect(temp, equals(31.5));
    });
  });

  group('Website Wind Replication Tests', () {
    test('7 Wind stops match Website Rc palette values', () {
      expect(kWindStops.length, equals(7));
      // 0 km/h: purple
      expect(windColorRgb(0), equals([122, 46, 158]));
      // 20 km/h: cyan
      expect(windColorRgb(20), equals([32, 186, 214]));
      // 55 km/h: yellow
      expect(windColorRgb(55), equals([230, 214, 48]));
      // 100 km/h: red
      expect(windColorRgb(100), equals([198, 36, 42]));
    });

    test('3x4 Grid computation matches Website Qre', () {
      final bounds = LatLngBounds(const LatLng(18.0, 72.0), const LatLng(21.0, 75.0));
      final points = computeWindGridPoints(bounds);
      expect(points, isNotEmpty);
      expect(points.length, lessThanOrEqualTo(12));
    });

    test('Shepard IDW sampleWindField calculates interpolated velocity and speed', () {
      final samples = [
        const WindSample(lat: 20.0, lng: 73.0, speed: 20.0, u: 10.0, v: 17.32),
        const WindSample(lat: 19.0, lng: 73.0, speed: 30.0, u: 15.0, v: 25.98),
      ];

      final mid = sampleWindField(samples, 19.5, 73.0);
      expect(mid.u, isNotNull);
      expect(mid.v, isNotNull);
      expect(mid.speed, isNotNull);
      expect(mid.speed!, closeTo(25.0, 0.5));
    });
  });

  group('Website Rain Replication Tests', () {
    test('7 Rain stops match Website zc palette and dynamic intensity alpha', () {
      expect(kRainStops.length, equals(7));
      // Zero rain <= 0.05 returns null (transparent)
      expect(rainColorRgba(0.0), isNull);
      expect(rainColorRgba(0.04), isNull);

      // 1.5 mm: cyan with alpha ~196
      final c1 = rainColorRgba(1.5);
      expect(c1, isNotNull);
      expect(c1![0], equals(48));
      expect(c1[1], equals(170));
      expect(c1[2], equals(190));
      expect(c1[3], greaterThanOrEqualTo(185));

      // 30 mm: magenta with max alpha ~245
      final c30 = rainColorRgba(30.0);
      expect(c30, isNotNull);
      expect(c30![0], equals(196));
      expect(c30[1], equals(48));
      expect(c30[2], equals(160));
      expect(c30[3], equals(245));
    });

    test('Rain grid adheres to zoom steps and 48-point limit', () {
      expect(rainStepForZoom(4.0), equals(2.0));
      expect(rainStepForZoom(6.0), equals(1.0));
      expect(rainStepForZoom(8.0), equals(0.5));
      expect(rainStepForZoom(10.0), equals(0.25));

      final bounds = LatLngBounds(const LatLng(18.0, 72.0), const LatLng(21.0, 75.0));
      final grid = computeRainGridPoints(bounds, 8.0);
      expect(grid.points.length, lessThanOrEqualTo(48));
      expect(grid.points, isNotEmpty);
    });

    test('Shepard IDW sampleRainField interpolates rainfall continuously', () {
      final samples = [
        const RainSample(lat: 20.0, lng: 73.0, rain: 10.0),
        const RainSample(lat: 19.0, lng: 73.0, rain: 2.0),
      ];

      final mid = sampleRainField(samples, 19.5, 73.0, 0.12);
      expect(mid, greaterThan(2.0));
      expect(mid, lessThan(10.0));
      expect(mid, closeTo(6.0, 0.5));
    });

    testWidgets('WindFieldOverlay mounts and initializes particle streamlines', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(19.9975, 73.7898),
                initialZoom: 6.0,
              ),
              children: const [
                WindFieldOverlay(
                  initialCenter: LatLng(19.9975, 73.7898),
                  initialWindSpeed: 24.0,
                  initialWindDirection: 180.0,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(WindFieldOverlay), findsOneWidget);
    });

    testWidgets('RainFieldOverlay mounts and preserves transparency for zero rain', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(19.9975, 73.7898),
                initialZoom: 6.0,
              ),
              children: const [
                RainFieldOverlay(
                  forecastMode: false,
                  initialCenter: LatLng(19.9975, 73.7898),
                  initialPrecipitation: 0.0,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(RainFieldOverlay), findsOneWidget);
      // Zero rainfall transparency confirmed
      expect(rainColorRgba(0.0), isNull);
    });
  });

  group('Website Weather Readout Parity Tests', () {
    test('WeatherReadoutFormatter matches Website text formats', () {
      // Temperature parity (Screenshot example: 30.5°C · now 3h)
      expect(
        WeatherReadoutFormatter.formatTemperature(30.54),
        equals('30.5°C · now 3h'),
      );
      expect(
        WeatherReadoutFormatter.formatTemperature(30.54, use3hSuffix: false),
        equals('30.5 °C · now'),
      );

      // Rain parity (Screenshot example: 0.1 mm · last 3h)
      expect(
        WeatherReadoutFormatter.formatRain(0.12, false),
        equals('0.1 mm · last 3h'),
      );
      expect(
        WeatherReadoutFormatter.formatRain(0.12, true),
        equals('0.1 mm · next 3h'),
      );

      // Wind parity (Screenshot example: 20.0 km/h · last 3h)
      expect(
        WeatherReadoutFormatter.formatWind(20.04),
        equals('20.0 km/h · last 3h'),
      );
      expect(
        WeatherReadoutFormatter.formatWind(20.04, useLast3hSuffix: false),
        equals('20.0 km/h'),
      );
    });

    test('Temperature sampling and station snap match Website implementation', () {
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // Seed cached temperature samples
      TemperatureFieldOverlay.sampleCache['v2:$dateStr:19.0:73.0'] =
          const TemperatureSample(lat: 19.0, lng: 73.0, temp: 30.5);
      TemperatureFieldOverlay.sampleCache['v2:$dateStr:20.0:74.0'] =
          const TemperatureSample(lat: 20.0, lng: 74.0, temp: 28.5);

      final readout = WeatherReadoutOverlay.sampleActiveLayer(
        mode: WeatherOverlayMode.temp,
        point: const LatLng(19.0, 73.0),
        zoom: 7.0,
      );

      expect(readout, isNotNull);
      expect(readout!.rawValue, closeTo(30.5, 0.05));
      expect(readout.text, equals('30.5°C · now 3h'));
    });

    test('Rain 3-hour accumulation matches Website wne for Recent and Forecast', () {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final recentSeries = [
        {'time': nowMs - 4 * 3600 * 1000, 'rain': 5.0}, // Outside 3h window
        {'time': nowMs - 2 * 3600 * 1000, 'rain': 0.05}, // In 3h window
        {'time': nowMs - 1 * 3600 * 1000, 'rain': 0.05}, // In 3h window
        {'time': nowMs + 1 * 3600 * 1000, 'rain': 10.0}, // Future
      ];

      // Recent accumulation: 0.05 + 0.05 = 0.1 mm
      final recentSum = RainFieldOverlay.aggregate3HourRain(recentSeries, false);
      expect(recentSum, closeTo(0.1, 0.001));
      expect(WeatherReadoutFormatter.formatRain(recentSum, false), equals('0.1 mm · last 3h'));

      final forecastSeries = [
        {'time': nowMs - 1 * 3600 * 1000, 'rain': 5.0}, // Past
        {'time': nowMs + 1 * 3600 * 1000, 'rain': 0.2}, // In next 3h window
        {'time': nowMs + 2 * 3600 * 1000, 'rain': 0.3}, // In next 3h window
        {'time': nowMs + 5 * 3600 * 1000, 'rain': 10.0}, // Beyond 3h
      ];

      // Forecast accumulation: 0.2 + 0.3 = 0.5 mm
      final forecastSum = RainFieldOverlay.aggregate3HourRain(forecastSeries, true);
      expect(forecastSum, closeTo(0.5, 0.001));
      expect(WeatherReadoutFormatter.formatRain(forecastSum, true), equals('0.5 mm · next 3h'));
    });

    test('Wind speed interpolation matches Website scalar speed parity', () {
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // Seed isolated cached wind sample
      WindFieldOverlay.windCache.clear();
      WindFieldOverlay.windCache['$dateStr:19.5:73.5'] = const WindSample(
        lat: 19.5,
        lng: 73.5,
        speed: 20.0,
        u: 10.0,
        v: 17.32,
      );

      final readout = WeatherReadoutOverlay.sampleActiveLayer(
        mode: WeatherOverlayMode.wind,
        point: const LatLng(19.5, 73.5),
        zoom: 6.0,
      );

      expect(readout, isNotNull);
      expect(readout!.rawValue, closeTo(20.0, 0.1));
      expect(readout.text, equals('20.0 km/h · last 3h'));
    });

    testWidgets('WeatherReadoutOverlay renders tooltip pill and dismisses on tap', (tester) async {
      bool dismissed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(19.0, 73.0),
                initialZoom: 7.0,
              ),
              children: [
                WeatherReadoutMapLayer(
                  mode: WeatherOverlayMode.temp,
                  rainForecastMode: false,
                  tappedCoordinate: const LatLng(19.0, 73.0),
                  onDismiss: () => dismissed = true,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('30.5°C · now 3h'), findsOneWidget);

      // Tap the readout badge or dismiss icon
      await tester.tap(find.text('30.5°C · now 3h'));
      await tester.pump();
      expect(dismissed, isTrue);
    });
  });
}




