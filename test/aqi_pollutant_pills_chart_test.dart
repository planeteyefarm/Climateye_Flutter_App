Update my existing Flutter application, ClimateEye, to match the attached **Preferred Design 2** as closely as possible.

**IMPORTANT: Use Preferred Design 2 as the exact visual reference. Do not introduce a different layout or redesign.**

### 1. HISTORY & PREDICTION LAYOUT

Apply the same layout structure to both screens:

1. Page header.
2. Pollutant selection buttons.
3. Small AQI indicator, clearly visible and centered.
4. Complete graph container positioned BELOW the AQI indicator.
5. Best-time-to-visit recommendation below the graph.
6. History / Prediction navigation buttons.
7. Last 6 Hours / Next 6 Hours label.

### 2. AQI INDICATOR — CRITICAL
- Reuse the existing AQI circular indicator from the current-location screen.
- Display its actual fetched AQI value and status.
- Scale it down appropriately.
- Position it completely ABOVE the graph container.
- Keep the entire circle, including its progress arc and outline, clearly visible.
- Do not place it behind, inside, or underneath the graph.
- Do not create duplicate AQI calculations or hardcoded values.

### 3. GRAPH POSITIONING
- Move the entire graph container downward, below the AQI circle.
- Reduce its height appropriately to fit the available screen space.
- Keep all six hourly bars, connecting lines, data points, axis labels, and units readable.
- Prevent overlap with the AQI circle and recommendation banner.
- History must show the previous 6 hours.
- Prediction must show the next 6 hours.

### 4. VISUAL DESIGN
- Follow Preferred Design 2's colours, typography, spacing, borders, chart styling, and translucent panels.
- Keep the actual interactive OSM map as the full-screen background.
- Maintain clear contrast so all text, AQI values, chart elements, and buttons are easily readable.
- Remove the unwanted large decorative blue ring.
- Do not use unnecessary blur, excessive gradients, or opaque backgrounds that hide the map.

### 5. BEST-TIME RECOMMENDATION
Display a dynamic recommendation directly below the graph on both screens.

- History: Calculate using available historical readings from the previous 6 hours.
- Prediction: Calculate using available forecast readings from the next 6 hours.
- Consider relevant available pollutants.
- Do not hardcode times or invent recommendations when data is insufficient.

### 6. AQI PAGE — DO NOT MODIFY
Keep the AQI page as it currently is:
- Simple professional 2D donut/pie chart.
- Existing pollutant values and percentages.
- Relevant AQI information.
- No additional floating AQI circle.

### 7. MAP AND EXISTING FUNCTIONALITY
- Keep OpenStreetMap (OSM) as the default map.
- Keep Satellite view available through the existing map switcher.
- Preserve location detection, markers, zoom controls, APIs, real data, chart interactions, pollutant selection, and navigation.
- Do not replace the interactive map with a static image.
- Do not modify unrelated screens.

### 8. IMPLEMENTATION AND VERIFICATION
Inspect the existing Flutter widget tree and fix the actual positioning and layout issues.

Use responsive Flutter layouts (`Column`, `Expanded`, `Flexible`, `LayoutBuilder`, etc.) rather than arbitrary fixed positioning wherever appropriate.

Run and verify both History and Prediction screens.

**Final acceptance criteria:**
- AQI circle is completely visible ABOVE the graph.
- Graph container is completely BELOW the AQI circle.
- Recommendation is BELOW the graph.
- No unwanted decorative ring.
- No duplicated widgets or overlapping elements.
- All content is clearly readable.
- The interactive OSM map remains visible in the background.
- No layout overflow or runtime errors.

**FINAL INSTRUCTION: Reproduce Preferred Design 2 as closely as possible. Make actual changes in the existing Flutter code, not just a visual mockup.**import 'package:climateeye/widgets/aqi_pollutant_pills_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Design 16 pills show names only and select pollutant', (t) async {
    var selected = 'so2';
    final samples = [
      for (var i = 0; i < 6; i++)
        AqiHourSample(
          time: DateTime(2026, 10, 29, 10 + i),
          values: {
            'pm2_5': 10 + i.toDouble(),
            'pm10': 20,
            'no2': 5,
            'so2': 8.0 + i,
            'o3': 30,
            'co': 0.4,
          },
        ),
    ];

    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            return AqiPollutantPillsChart(
              isHistory: true,
              selectedKey: selected,
              onSelect: (k) => setState(() => selected = k),
              samples: samples,
              loading: false,
            );
          },
        ),
      ),
    ));

    for (final label in ['PM2.5', 'PM10', 'NO₂', 'SO₂', 'O₃', 'CO']) {
      expect(find.text(label), findsWidgets);
    }
    // Names only on pills — no live reading like "48" glued to pill label.
    expect(find.text('Last 6'), findsOneWidget);
    expect(find.text('Hours'), findsOneWidget);
    expect(find.text('µg/m³'), findsOneWidget);

    await t.tap(find.text('PM2.5').first);
    await t.pumpAndSettle();
    expect(selected, 'pm2_5');
  });

  testWidgets('prediction empty state when no samples', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AqiPollutantPillsChart(
          isHistory: false,
          selectedKey: 'o3',
          onSelect: (_) {},
          samples: const [],
          loading: false,
        ),
      ),
    ));
    expect(find.textContaining('No upcoming hourly'), findsOneWidget);
    expect(find.text('Next 6'), findsOneWidget);
  });

  testWidgets('History/Prediction toggle without time chips', (t) async {
    var history = true;

    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            return AqiPollutantPillsChart(
              isHistory: history,
              selectedKey: 'pm2_5',
              onSelect: (_) {},
              samples: const [],
              loading: false,
              onHistoryChanged: (v) => setState(() => history = v),
            );
          },
        ),
      ),
    ));

    expect(find.text('History'), findsOneWidget);
    expect(find.text('Prediction'), findsOneWidget);
    expect(find.text('6H'), findsNothing);
    expect(find.text('12H'), findsNothing);
    expect(find.text('24H'), findsNothing);
    expect(find.text('7D'), findsNothing);
    expect(find.text('Last 6'), findsOneWidget);

    await t.tap(find.text('Prediction'));
    await t.pumpAndSettle();
    expect(history, isFalse);
    expect(find.text('Next 6'), findsOneWidget);
  });

  testWidgets('BestTimeRecommendation identifies lowest pollution hour dynamically',
      (t) async {
    final samples = [
      AqiHourSample(time: DateTime(2026, 11, 2, 8), values: {'pm2_5': 45.0, 'pm10': 80.0}),
      AqiHourSample(time: DateTime(2026, 11, 2, 9), values: {'pm2_5': 38.0, 'pm10': 70.0}),
      AqiHourSample(time: DateTime(2026, 11, 2, 10), values: {'pm2_5': 12.0, 'pm10': 25.0}), // Cleanest!
      AqiHourSample(time: DateTime(2026, 11, 2, 11), values: {'pm2_5': 28.0, 'pm10': 50.0}),
      AqiHourSample(time: DateTime(2026, 11, 2, 12), values: {'pm2_5': 35.0, 'pm10': 60.0}),
      AqiHourSample(time: DateTime(2026, 11, 2, 13), values: {'pm2_5': 50.0, 'pm10': 90.0}),
    ];

    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AqiPollutantPillsChart(
          isHistory: false,
          selectedKey: 'pm2_5',
          onSelect: (_) {},
          samples: samples,
          loading: false,
        ),
      ),
    ));

    expect(
      find.text('Best time to visit: 10:00 AM — Air quality is expected to be better.'),
      findsOneWidget,
    );
  });

  testWidgets('BestTimeRecommendation updates when selected pollutant changes',
      (t) async {
    var selected = 'pm2_5';
    final samples = [
      // 9 AM has low PM2.5 but high O3
      AqiHourSample(time: DateTime(2026, 11, 2, 9), values: {'pm2_5': 10.0, 'o3': 120.0}),
      // 2 PM has high PM2.5 but low O3
      AqiHourSample(time: DateTime(2026, 11, 2, 14), values: {'pm2_5': 80.0, 'o3': 15.0}),
    ];

    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            return AqiPollutantPillsChart(
              isHistory: true,
              selectedKey: selected,
              onSelect: (k) => setState(() => selected = k),
              samples: samples,
              loading: false,
            );
          },
        ),
      ),
    ));

    // When PM2.5 is selected, 9:00 AM is recommended
    expect(find.textContaining('9:00 AM'), findsOneWidget);

    // Tap O3 pill
    await t.tap(find.text('O₃').first);
    await t.pumpAndSettle();

    // Now 2:00 PM is recommended because O3 is cleanest then
    expect(find.textContaining('2:00 PM'), findsOneWidget);
  });
}
