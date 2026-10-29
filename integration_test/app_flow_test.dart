import 'dart:io';
import 'dart:ui' as ui;

import 'package:climateeye/main.dart';
import 'package:climateeye/models/aqi.dart';
import 'package:climateeye/services/api_client.dart';
import 'package:climateeye/services/auth_service.dart';
import 'package:climateeye/services/location_service.dart';
import 'package:climateeye/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';

/// End-to-end: Login → Map → Draw area → Analyse → Live/Weekly dashboard,
/// against the real backend. Run: flutter test integration_test -d windows
///
/// Widget callbacks are invoked directly instead of synthesised pointer taps,
/// because desktop window scaling makes tap offsets unreliable in this runner.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpUntil(WidgetTester t, Finder f,
      {Duration timeout = const Duration(seconds: 90)}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 300));
      if (f.evaluate().isNotEmpty) return;
    }
    throw TestFailure('Timed out waiting for $f');
  }

  VoidCallback? buttonCallback(WidgetTester t, String label) {
    final btn = find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton || w is GradientButton));
    final w = t.widget(btn.first);
    if (w is GradientButton) return w.busy ? null : w.onPressed;
    return (w as ButtonStyleButton).onPressed;
  }

  Future<void> press(WidgetTester t, String label) async {
    final cb = buttonCallback(t, label);
    expect(cb, isNotNull, reason: '"$label" is disabled');
    cb!();
    await t.pump(const Duration(milliseconds: 300));
  }

  // The wide layout has a scrollable sidebar; target the dashboard list.
  ScrollableState mainScroll(WidgetTester t) {
    final states = [
      for (final e in find.byType(Scrollable).evaluate())
        if ((e as StatefulElement).state case final ScrollableState s
            when s.position.axis == Axis.vertical)
          s,
    ];
    states.sort((a, b) => b.position.maxScrollExtent.compareTo(a.position.maxScrollExtent));
    return states.first;
  }

  Future<void> scrollTo(WidgetTester t, Finder f) async {
    final s = mainScroll(t);
    s.position.jumpTo(0);
    await t.pump(const Duration(milliseconds: 200));
    while (f.evaluate().isEmpty && s.position.pixels < s.position.maxScrollExtent) {
      s.position.jumpTo(s.position.pixels + 300);
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(f, findsWidgets);
  }

  Future<void> chip(WidgetTester t, String label) async {
    final chips = find.ancestor(of: find.text(label), matching: find.byType(ChoiceChip));
    if (chips.evaluate().isNotEmpty) {
      t.widget<ChoiceChip>(chips.first).onSelected!(true);
    } else {
      // Analysis-screen mode tabs render upper-case labels inside an InkWell.
      final ink = find.ancestor(
          of: find.text(label.toUpperCase()), matching: find.byType(InkWell));
      t.widget<InkWell>(ink.first).onTap!();
    }
    await t.pump(const Duration(milliseconds: 300));
  }

  // Area tool tiles and sheet tabs are InkWells around a text label.
  Future<void> tap(WidgetTester t, String label) async {
    final ink = find.ancestor(of: find.text(label), matching: find.byType(InkWell));
    final cb = t.widget<InkWell>(ink.first).onTap;
    expect(cb, isNotNull, reason: '"$label" is disabled');
    cb!();
    await t.pump(const Duration(milliseconds: 300));
  }

  testWidgets('login, draw, analyse, dashboard', (t) async {
    final location = _FakeLocation();
    LocationService.instance = location;
    await AuthService.instance.logout();
    await t.pumpWidget(const ClimateEyeApp());
    await pumpUntil(t, find.text('Sign In'));

    await press(t, 'Sign In');
    expect(find.text('Please enter both username and password'), findsOneWidget);

    await t.enterText(find.byType(TextField).at(0), 'admin');
    await t.enterText(find.byType(TextField).at(1), 'nope');
    await press(t, 'Sign In');
    expect(find.text('Invalid username or password'), findsOneWidget);

    // Opening the map requests the location once and centres on the fix.
    location.result = const LocationResult.success(LatLng(28.6139, 77.2090));
    await t.enterText(find.byType(TextField).at(1), 'planeteye@2025');
    await press(t, 'Sign In');
    // After login the live AQI at the device location is shown over the map.
    await pumpUntil(t, find.text('MY LOCATION'));
    final locAqiSettled = find.byWidgetPredicate((w) =>
        w is Text &&
        (w.data == 'AQI unavailable' ||
            w.data == 'No AQI data' ||
            (w.data?.startsWith('Live AQI · ') ?? false)));
    await pumpUntil(t, locAqiSettled);
    expect(find.text('AQI unavailable'), findsNothing);
    final expectedAqi =
        AqiRecord.fromJson(await ApiClient.instance.fetchAqi(28.6139, 77.2090)).aqi;
    expect(expectedAqi, isNotNull);
    expect(find.text(expectedAqi!.round().toString()), findsWidgets);
    expect(find.text(aqiCategory(expectedAqi).label), findsWidgets);
    await t.pump(const Duration(seconds: 2));
    await _screenshot(t, 'map_location_aqi');
    // The analysis sheet starts collapsed so the map is unobstructed.
    await pumpUntil(t, find.byTooltip('Expand panel'));
    t.widget<IconButton>(
            find.ancestor(of: find.byTooltip('Expand panel'), matching: find.byType(IconButton)))
        .onPressed!();
    await t.pump(const Duration(milliseconds: 600));
    await pumpUntil(t, find.text('Draw Polygon'));
    expect(find.text('No area selected'), findsOneWidget);
    // Run Analysis must be disabled without geometry.
    expect(buttonCallback(t, 'Run Analysis'), isNull);

    await pumpUntil(t, find.text('Location found'));
    expect(location.calls, 1);
    final openCamera = t.widget<FlutterMap>(find.byType(FlutterMap)).mapController!.camera;
    expect(openCamera.center.latitude, closeTo(28.6139, 1e-6));
    expect(openCamera.center.longitude, closeTo(77.2090, 1e-6));
    expect(openCamera.zoom, 13);
    expect(find.text('Lat: 28.61390° | Long: 77.20900°'), findsOneWidget);
    expect(find.text('Download KML'), findsNothing);
    await t.pump(const Duration(seconds: 2));
    await _screenshot(t, 'map_initial');

    // Draw Area with permission granted: one request, camera moves there.
    location.result = const LocationResult.success(LatLng(19.0760, 72.8777));
    await tap(t, 'Draw Polygon');
    await t.pump(const Duration(milliseconds: 300));
    expect(location.calls, 2);
    final camera = t.widget<FlutterMap>(find.byType(FlutterMap)).mapController!.camera;
    expect(camera.center.latitude, closeTo(19.0760, 1e-6));
    expect(camera.center.longitude, closeTo(72.8777, 1e-6));
    expect(camera.zoom, 15);
    expect(find.text('Location found! You can now draw your area on the map.'), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    await _screenshot(t, 'map_drawing_located');
    await press(t, 'Cancel');
    expect(find.text('Download KML'), findsNothing);

    Future<void> drawTriangle() async {
      final map = t.widget<FlutterMap>(find.byType(FlutterMap));
      const pts = [LatLng(18.50, 73.80), LatLng(18.50, 73.90), LatLng(18.60, 73.85)];
      for (final p in pts) {
        map.options.onTap!(const TapPosition(Offset.zero, Offset.zero), p);
        await t.pump(const Duration(milliseconds: 200));
      }
      expect(find.textContaining('3 placed'), findsOneWidget);
      expect(find.text('Download KML'), findsNothing);
      await press(t, 'Finish');
      expect(find.text('Download KML'), findsOneWidget);
    }

    // Permission denied: message shown, manual drawing still works.
    location.result = const LocationResult.failure('Location permission was denied.');
    await tap(t, 'Draw Polygon');
    await t.pump(const Duration(milliseconds: 300));
    expect(location.calls, 3);
    expect(find.textContaining('Location permission was denied.'), findsOneWidget);
    await drawTriangle();

    // Clearing removes the action; drawing again requests location once more.
    await tap(t, 'Clear Area');
    expect(find.text('Download KML'), findsNothing);
    await tap(t, 'Draw Polygon');
    await t.pump(const Duration(milliseconds: 300));
    expect(location.calls, 4);
    await drawTriangle();
    // Centroid of closed ring [A,B,C,A] = mean of 4 points.
    expect(find.textContaining('Drawn area · centre 18.5250, 73.8375'), findsOneWidget);

    expect(find.text('Vertices'), findsOneWidget);
    await _screenshot(t, 'map_area_selected');
    await press(t, 'Run Analysis');
    await pumpUntil(t, find.text('Air Quality Index'));
    final gaugeLabel = RegExp(r'^(GOOD|MODERATE|POOR|UNHEALTHY|SEVERE|HAZARDOUS) \(\d+\)$');
    await pumpUntil(t,
        find.byWidgetPredicate((w) => w is Text && gaugeLabel.hasMatch(w.data ?? '')));
    expect(find.byIcon(Icons.error_outline), findsNothing,
        reason: 'live endpoints should not report errors');
    await t.pump(const Duration(seconds: 1));
    await _screenshot(t, 'live_air_quality_tab');
    // The Area tab summarises the same run in compact cards.
    await tap(t, 'Area');
    await pumpUntil(t, find.text('AQI & Pollutant Analysis'));
    expect(find.text('Detailed View'), findsOneWidget);
    expect(find.text('PM2.5'), findsWidgets);
    await t.pump(const Duration(seconds: 1));
    await _screenshot(t, 'area_overview');
    await scrollTo(t, find.text('Methane Analysis'));
    await _screenshot(t, 'area_overview_bottom');
    // The Results tab shows every section of the same analysis run.
    await tap(t, 'Results');
    await t.pump(const Duration(seconds: 1));
    await _screenshot(t, 'live_desktop_top');
    // Live mode has no altitude toggle and shows the raw `aqi` field.
    expect(find.text('3 m above (Ambient)'), findsNothing);
    expect(find.text('0–3 m (Ground)'), findsNothing);

    final desktopScroll = mainScroll(t);
    desktopScroll.position.jumpTo(desktopScroll.position.maxScrollExtent);
    await t.pump(const Duration(milliseconds: 500));
    await _screenshot(t, 'live_desktop_bottom');
    desktopScroll.position.jumpTo(0);
    await t.pump(const Duration(milliseconds: 300));

    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    await t.pump(const Duration(seconds: 1));
    await _screenshot(t, 'live_phone_top');
    final phoneScroll = mainScroll(t);
    phoneScroll.position.jumpTo(900);
    await t.pump(const Duration(milliseconds: 500));
    await _screenshot(t, 'live_phone_middle');
    phoneScroll.position.jumpTo(phoneScroll.position.maxScrollExtent);
    await t.pump(const Duration(milliseconds: 500));
    await _screenshot(t, 'live_phone_bottom');
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
    await t.pump(const Duration(seconds: 1));
    final scroll = mainScroll(t);
    scroll.position.jumpTo(0);
    await t.pump(const Duration(milliseconds: 300));

    for (final title in ['Pollutant Levels', 'Weather', 'MON', 'UV, Visibility & Pollutants',
        'AQI Analysis Report']) {
      var found = find.text(title).evaluate().isNotEmpty;
      while (!found && scroll.position.pixels < scroll.position.maxScrollExtent) {
        scroll.position.jumpTo(scroll.position.pixels + 300);
        await t.pump(const Duration(milliseconds: 200));
        found = find.text(title).evaluate().isNotEmpty;
      }
      expect(found, isTrue, reason: '$title card should render');
    }
    expect(find.text('No hourly records returned'), findsNothing);
    expect(find.text('No pollutant values in response'), findsNothing);
    expect(find.text('Generate Analysis'), findsOneWidget);
    expect(find.text('No analysis data available'), findsOneWidget);
    scroll.position.jumpTo(0);
    await t.pump(const Duration(milliseconds: 300));

    await chip(t, 'Weekly');
    await pumpUntil(t, find.text('DAILY AVERAGE'), timeout: const Duration(minutes: 3));
    expect(find.text('Past 7 Days'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
    await _screenshot(t, 'weekly_desktop_top');
    await scrollTo(t, find.text('AQI Trend'));
    await pumpUntil(t, find.text('Last 7 Days'));
    await t.pump(const Duration(seconds: 2));
    await _screenshot(t, 'weekly_desktop_chart');
    await scrollTo(t, find.text('Air Quality Index'));

    Future<void> openSection(String title) async {
      final ink = t.widget<InkWell>(
          find.ancestor(of: find.text(title), matching: find.byType(InkWell)).first);
      ink.onTap!();
      await t.pump(const Duration(milliseconds: 500));
    }

    Future<void> back() async {
      t.state<NavigatorState>(find.byType(Navigator).first).pop();
      await t.pump(const Duration(milliseconds: 500));
    }

    // AQI detail (weekly → /aqi/hourly/range)
    await openSection('Air Quality Index');
    await pumpUntil(t, find.text('AQI Analysis Results'));
    await pumpUntil(t, find.byWidgetPredicate((w) =>
            (w is Text && w.data == 'Parameter Trend') || w is ErrorBox || w is EmptyBox),
        timeout: const Duration(minutes: 2));
    await t.pump(const Duration(seconds: 1));
    await _screenshot(t, 'aqi_detail_weekly');
    expect(find.text('Parameter Trend'), findsOneWidget);
    await scrollTo(t, find.textContaining('Hourly Records ('));
    await back();

    // Weather detail: weekly opens the 7-day calendar.
    await openSection('Weather Conditions');
    await pumpUntil(t, find.text('Weather Analysis Results'));
    await t.pump(const Duration(seconds: 8));
    await _screenshot(t, 'weather_detail_weekly');
    await scrollTo(t, find.textContaining('Latest hour'));
    await scrollTo(t, find.textContaining('Hourly Weather ('));
    await back();

    // Monthly portal.
    await chip(t, 'Monthly');
    await pumpUntil(t, find.text('Past 30 Days'));
    await pumpUntil(t, find.text('DAILY AVERAGE'), timeout: const Duration(minutes: 4));
    await scrollTo(t, find.text('AQI Trend'));
    await pumpUntil(t, find.textContaining('Air Quality is'), timeout: const Duration(minutes: 4));
    await pumpUntil(t, find.text('Last 30 Days'));
    await t.pump(const Duration(seconds: 2));
    await _screenshot(t, 'monthly_desktop_chart');
  }, timeout: const Timeout(Duration(minutes: 6)));
}

/// Test double so permission outcomes and request counts are deterministic.
class _FakeLocation implements LocationService {
  int calls = 0;
  LocationResult result = const LocationResult.failure('not set');

  @override
  Future<LocationResult> currentLocation() async {
    calls++;
    return result;
  }
}

Future<void> _screenshot(WidgetTester t, String name) async {
  await t.runAsync(() async {
    final boundary = t.binding.rootElement!.renderObject!;
    final layer = boundary.debugLayer! as OffsetLayer;
    // The root layer already applies the device pixel ratio.
    final image = await layer.toImage(Offset.zero & t.view.physicalSize);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/screens/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}
