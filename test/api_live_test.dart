@Tags(['live'])
library;

import 'package:climateeye/models/aqi.dart';
import 'package:climateeye/services/api_client.dart';
import 'package:climateeye/utils/geo_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Hits the real ClimateEye backend. Run with: flutter test --tags live
void main() {
  final api = ApiClient.instance;
  const lat = 18.52, lng = 73.85;
  final date = DateTime.now().subtract(const Duration(days: 1));
  const timeout = Timeout(Duration(minutes: 2));

  test('POST /aqi parses and height transform applies', () async {
    final raw = await api.fetchAqi(lat, lng, date);
    final ambient = AqiRecord.fromJson(raw);
    final ground = AqiRecord.fromJson(extractDataByHeight(raw, HeightOption.ground0to3m));
    expect(ambient.aqi, isNotNull);
    expect(ground.aqi, raw['aqi_0to3m']);
    // ignore: avoid_print
    print('aqi ambient=${ambient.aqi} ground=${ground.aqi} pm2_5=${ambient.pm25}');
  }, timeout: timeout);

  test('POST /weather', () async {
    final w = await api.fetchWeather(lat, lng, date);
    expect(w.temperature, isNotNull);
    // ignore: avoid_print
    print('weather temp=${w.temperature} cond=${w.condition}');
  }, timeout: timeout);

  test('POST /aqi/hourly and /weather/hourly', () async {
    final a = await api.fetchHourlyAqi(lat, lng, date);
    final w = await api.fetchHourlyWeather(lat, lng, date);
    expect(a, isNotEmpty);
    expect(w, isNotEmpty);
    expect(w.first.date, isNotNull);
    // ignore: avoid_print
    print('hourly aqi=${a.length} weather=${w.length}');
  }, timeout: timeout);

  test('POST /aqi/hourly/range', () async {
    final r = await api.fetchHourlyAqiRange(
        lat, lng, date.subtract(const Duration(days: 6)), date);
    expect(r.length, greaterThan(24));
    // ignore: avoid_print
    print('range records=${r.length}');
  }, timeout: timeout);

  test('POST /weather/monthly (sanitized)', () async {
    // Current month currently fails server-side (Open-Meteo end_date range),
    // so verify against the previous month.
    final prev = DateTime(date.year, date.month - 1);
    final m = await api.fetchMonthlyWeather(lat, lng, prev.year, prev.month);
    expect(m, isNotEmpty);
    // ignore: avoid_print
    print('monthly days=${m.length}');
  }, timeout: timeout);

  test('POST /aqi/analyze', () async {
    final t = await api.fetchAqiAnalysis(lat, lng, date);
    expect(t, isNotEmpty);
    // ignore: avoid_print
    print('analysis chars=${t.length}: ${t.substring(0, t.length.clamp(0, 120))}');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('GET /methane, /methane/plumes, /methane/tiles', () async {
    final c = await api.fetchMethaneCatalog();
    expect(c.coverageEnd, isNotNull);
    final g = AreaGeometry.fromVertices(
        const [LatLng(20, 50), LatLng(20, 60), LatLng(30, 60), LatLng(30, 50)]);
    final start = DateTime(2025, 1, 1);
    final plumes = await api.fetchMethanePlumes(g.boundsString, start, c.coverageEnd!);
    final tiles = await api.fetchMethaneTiles(g.boundsString, start, c.coverageEnd!);
    expect(tiles.tileUrl, contains('{z}'));
    // ignore: avoid_print
    print('coverage=${c.coverageStart}..${c.coverageEnd} plumes=${plumes.length} '
        'legendColors=${tiles.legend.palette.length}');
  }, timeout: timeout);

  test('out-of-coverage methane request surfaces backend error', () async {
    expect(
      () => api.fetchMethanePlumes('73.8,18.5,73.9,18.6', DateTime(2026, 9, 1), DateTime(2026, 10, 1)),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 400)),
    );
  }, timeout: timeout);

  test('geocoding place name (may be null)', () async {
    final n = await api.fetchPlaceName(lat, lng);
    // ignore: avoid_print
    print('place name=$n');
  }, timeout: timeout);
}
