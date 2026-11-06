import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/api_config.dart';
import '../models/aqi.dart';
import '../models/building.dart';
import '../models/methane.dart';
import '../models/weather.dart';
import '../utils/date_utils.dart';

class ApiException implements Exception {
  ApiException(this.endpoint, this.message, {this.statusCode});

  final String endpoint;
  final String message;
  final int? statusCode;

  @override
  String toString() =>
      '$endpoint failed${statusCode != null ? ' (HTTP $statusCode)' : ''}: $message';
}

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  static final ApiClient instance = ApiClient();

  final http.Client _client;

  Future<dynamic> _post(String path, Map<String, dynamic> body,
      {bool sanitize = false}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    return _send(path, () => _client.post(uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body)), sanitize: sanitize);
  }

  Future<dynamic> _get(String path, [Map<String, String>? query]) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path')
        .replace(queryParameters: query);
    return _send(path, () => _client.get(uri));
  }

  Future<dynamic> _send(String path, Future<http.Response> Function() call,
      {bool sanitize = false}) async {
    http.Response res;
    try {
      res = await call().timeout(ApiConfig.timeout);
    } on TimeoutException {
      throw ApiException(path, 'Request timed out');
    } catch (e) {
      throw ApiException(path, 'Network error: $e');
    }
    var text = res.body;
    if (sanitize) {
      text = text
          .replaceAll(RegExp(r':\s*NaN'), ': null')
          .replaceAll(RegExp(r':\s*-?Infinity'), ': null');
    }
    dynamic decoded;
    try {
      decoded = text.isEmpty ? null : jsonDecode(text);
    } catch (_) {
      if (res.statusCode >= 400) {
        throw ApiException(path, _truncate(text), statusCode: res.statusCode);
      }
      throw ApiException(path, 'Malformed JSON response',
          statusCode: res.statusCode);
    }
    if (res.statusCode >= 400) {
      var msg = _truncate(text);
      if (decoded is Map && decoded['error'] != null) {
        msg = decoded['error'].toString();
        final details = decoded['details'];
        if (details != null && !details.toString().contains('backend logs')) {
          msg = '$msg — ${_truncate(details.toString())}';
        }
      }
      throw ApiException(path, msg, statusCode: res.statusCode);
    }
    return decoded;
  }

  String _truncate(String s) => s.length > 200 ? '${s.substring(0, 200)}…' : s;

  Map<String, dynamic> _asMap(String path, dynamic data) {
    if (data is Map<String, dynamic>) return data;
    throw ApiException(path, 'Unexpected response format');
  }

  List<Map<String, dynamic>> _records(String path, dynamic data, String key) {
    final map = _asMap(path, data);
    final list = map[key];
    if (list == null) return [];
    if (list is! List) throw ApiException(path, '"$key" is not a list');
    return list.whereType<Map<String, dynamic>>().toList();
  }

  Map<String, dynamic> _point(double lat, double lng) =>
      {'latitude': lat, 'longitude': lng};

  /// Raw AQI summary map; height selection is applied by the caller.
  /// Live mode omits [date], as the website does.
  Future<Map<String, dynamic>> fetchAqi(double lat, double lng,
      [DateTime? date]) async {
    final data = await _post(ApiConfig.aqi,
        {..._point(lat, lng), if (date != null) 'date': ymd(date)});
    return _asMap(ApiConfig.aqi, data);
  }

  Future<WeatherSummary> fetchWeather(double lat, double lng,
      [DateTime? date]) async {
    final data = await _post(ApiConfig.weather,
        {..._point(lat, lng), if (date != null) 'date': ymd(date)});
    return WeatherSummary.fromJson(_asMap(ApiConfig.weather, data));
  }

  /// Raw hourly AQI records; height selection is applied by the caller.
  Future<List<Map<String, dynamic>>> fetchHourlyAqi(
      double lat, double lng, DateTime date) async {
    final data = await _post(
        ApiConfig.aqiHourly, {..._point(lat, lng), 'date': ymd(date)});
    return _records(ApiConfig.aqiHourly, data, 'hourly_records');
  }

  Future<List<Map<String, dynamic>>> fetchHourlyAqiRange(
      double lat, double lng, DateTime start, DateTime end) async {
    final data = await _post(ApiConfig.aqiHourlyRange, {
      ..._point(lat, lng),
      'start_date': ymd(start),
      'end_date': ymd(end),
    });
    return _records(ApiConfig.aqiHourlyRange, data, 'hourly_records');
  }

  Future<List<HourlyWeather>> fetchHourlyWeather(
      double lat, double lng, DateTime date) async {
    final data = await _post(
        ApiConfig.weatherHourly, {..._point(lat, lng), 'date': ymd(date)});
    return _records(ApiConfig.weatherHourly, data, 'hourly_records')
        .map(HourlyWeather.fromJson)
        .toList();
  }

  Future<Map<String, dynamic>> fetchRainForecast(double lat, double lng) async {
    return await _post(ApiConfig.weatherRainForecast, _point(lat, lng));
  }

  Future<List<MonthlyWeatherDay>> fetchMonthlyWeather(
      double lat, double lng, int year, int month) async {
    final data = await _post(ApiConfig.weatherMonthly,
        {..._point(lat, lng), 'year': year, 'month': month},
        sanitize: true);
    return _records(ApiConfig.weatherMonthly, data, 'daily_records')
        .map(MonthlyWeatherDay.fromJson)
        .toList();
  }

  Future<MonthlyWeatherResponse> fetchMonthlyWeatherFull(
      double lat, double lng, int year, int month) async {
    final data = await _post(ApiConfig.weatherMonthly,
        {..._point(lat, lng), 'year': year, 'month': month},
        sanitize: true);
    final map = _asMap(ApiConfig.weatherMonthly, data);
    return MonthlyWeatherResponse.fromJson(map, year, month);
  }

  Future<String> fetchAqiAnalysis(
      double lat, double lng, DateTime date) async {
    final data = await _post(
        ApiConfig.aqiAnalyze, {..._point(lat, lng), 'date': ymd(date)});
    final analysis = _asMap(ApiConfig.aqiAnalyze, data)['analysis'];
    if (analysis is! String || analysis.trim().isEmpty) {
      throw ApiException(ApiConfig.aqiAnalyze, 'Response has no analysis text');
    }
    return analysis;
  }

  Future<MethaneCatalog> fetchMethaneCatalog() async {
    final data = await _get(ApiConfig.methane);
    return MethaneCatalog.fromJson(_asMap(ApiConfig.methane, data));
  }

  Future<List<MethanePlume>> fetchMethanePlumes(
      String bounds, DateTime start, DateTime end) async {
    final data = await _get(ApiConfig.methanePlumes, {
      'bounds': bounds,
      'start_date': ymd(start),
      'end_date': ymd(end),
    });
    final geojson = _asMap(ApiConfig.methanePlumes, data)['geojson'];
    final features = geojson is Map ? geojson['features'] : null;
    if (features is! List) return [];
    return features
        .whereType<Map<String, dynamic>>()
        .map(MethanePlume.fromFeature)
        .whereType<MethanePlume>()
        .toList();
  }

  Future<MethaneTiles> fetchMethaneTiles(
      String bounds, DateTime start, DateTime end) async {
    final data = await _get(ApiConfig.methaneTiles, {
      'bounds': bounds,
      'start_date': ymd(start),
      'end_date': ymd(end),
    });
    return MethaneTiles.fromJson(_asMap(ApiConfig.methaneTiles, data));
  }

  /// Fetches raw building footprints for a bounding box: "minLng,minLat,maxLng,maxLat"
  Future<Map<String, dynamic>> fetchBuildingsBox(String bounds) async {
    final data = await _get(ApiConfig.buildings, {'bounds': bounds});
    return _asMap(ApiConfig.buildings, data);
  }

  /// Fetches, chunks, deduplicates, and filters buildings within [radiusMeters]
  /// around [center] using the Website's exact Haversine centroid rule.
  Future<BuildingCollection> fetchBuildingsForRadius({
    required LatLng center,
    required double radiusMeters,
  }) async {
    final boundsStr = boundsForRadius(center, radiusMeters);
    final parts = boundsStr.split(',').map(double.tryParse).toList();
    if (parts.length != 4 || parts.any((p) => p == null)) {
      throw ApiException(ApiConfig.buildings, 'Invalid radius bounds');
    }

    final minLng = parts[0]!;
    final minLat = parts[1]!;
    final maxLng = parts[2]!;
    final maxLat = parts[3]!;

    final midLat = ((minLat + maxLat) / 2) * math.pi / 180.0;
    final widthKm = ((maxLng - minLng) * 111.32 * math.cos(midLat)).abs();
    final heightKm = ((maxLat - minLat) * 110.574).abs();
    final areaKm2 = widthKm * heightKm;

    final List<String> cellBoxes = [];
    if (areaKm2 <= 2.5) {
      cellBoxes.add(boundsStr);
    } else {
      final int cols = areaKm2 > 300 ? 5 : (areaKm2 > 50 ? 4 : 3);
      final int rows = cols;
      final dLng = (maxLng - minLng) / cols;
      final dLat = (maxLat - minLat) / rows;

      for (int r = 0; r < rows; r++) {
        final cMinLat = minLat + r * dLat;
        final cMaxLat = (r == rows - 1) ? maxLat : cMinLat + dLat;
        for (int c = 0; c < cols; c++) {
          final cMinLng = minLng + c * dLng;
          final cMaxLng = (c == cols - 1) ? maxLng : cMinLng + dLng;
          cellBoxes.add('$cMinLng,$cMinLat,$cMaxLng,$cMaxLat');
        }
      }
    }

    final Map<String, BuildingFeature> deduplicated = {};
    bool anyTruncated = false;
    bool isPartial = false;
    String? note;

    const concurrency = 4;
    for (int i = 0; i < cellBoxes.length; i += concurrency) {
      final batch = cellBoxes.sublist(i, math.min(i + concurrency, cellBoxes.length));
      final responses = await Future.wait(batch.map((box) async {
        try {
          return await fetchBuildingsBox(box);
        } on ApiException catch (e) {
          if (e.statusCode == 404) {
            note = 'Building footprints unavailable for this region';
            return null;
          }
          isPartial = true;
          return null;
        } catch (_) {
          isPartial = true;
          return null;
        }
      }));

      for (final resp in responses) {
        if (resp == null) continue;
        if (resp['truncated'] == true) anyTruncated = true;
        final geojson = resp['geojson'];
        if (geojson is Map && geojson['features'] is List) {
          for (final f in geojson['features']) {
            if (f is Map<String, dynamic>) {
              final feature = BuildingFeature.fromJson(f);
              if (feature != null) {
                // Deduplicate by featureKey
                deduplicated[feature.featureKey] = feature;
              }
            }
          }
        }
      }
    }

    // Filter strictly by centroid distance <= radiusMeters (Website rule)
    final insideRadius = deduplicated.values.where((b) {
      return haversineMeters(center, b.centroid) <= radiusMeters;
    }).toList();

    return BuildingCollection(
      features: insideRadius,
      count: insideRadius.length,
      truncated: anyTruncated,
      isPartial: isPartial,
      note: note,
    );
  }

  /// Reverse place-name lookup → `"City, State"` (or city alone).
  ///
  /// Open-Meteo `/v1/search` is forward-only and often returns nothing for
  /// lat/lng, which left the map badge blank. Resolve via BigDataCloud
  /// (CORS-friendly), then Nominatim, then a best-effort Open-Meteo probe.
  Future<String?> fetchPlaceName(double lat, double lng) async {
    final fromBigData = await _reverseViaBigDataCloud(lat, lng);
    if (fromBigData != null) return fromBigData;
    final fromNominatim = await _reverseViaNominatim(lat, lng);
    if (fromNominatim != null) return fromNominatim;
    return _reverseViaOpenMeteoSearch(lat, lng);
  }

  Future<String?> _reverseViaBigDataCloud(double lat, double lng) async {
    try {
      final uri = Uri.parse(ApiConfig.reverseGeocode).replace(queryParameters: {
        'latitude': lat.toString(),
        'longitude': lng.toString(),
        'localityLanguage': 'en',
      });
      final res = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      if (data is! Map) return null;
      return _composePlaceName(
        city: data['city']?.toString() ?? data['locality']?.toString(),
        state: data['principalSubdivision']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> _reverseViaNominatim(double lat, double lng) async {
    try {
      final uri = Uri.parse(ApiConfig.nominatimReverse).replace(queryParameters: {
        'lat': lat.toString(),
        'lon': lng.toString(),
        'format': 'json',
        'zoom': '10',
        'addressdetails': '1',
      });
      final res = await _client
          .get(uri, headers: const {
            // Nominatim requires a valid identifying User-Agent.
            'User-Agent': 'ClimateEye/1.0 (https://climateye-apis.up.railway.app)',
            'Accept-Language': 'en',
          })
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      if (data is! Map) return null;
      final address = data['address'];
      if (address is! Map) return null;
      final city = address['city']?.toString() ??
          address['town']?.toString() ??
          address['village']?.toString() ??
          address['municipality']?.toString() ??
          address['county']?.toString();
      final state = address['state']?.toString();
      return _composePlaceName(city: city, state: state);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _reverseViaOpenMeteoSearch(double lat, double lng) async {
    try {
      // Last-resort probe; Open-Meteo search is not a true reverse geocoder.
      final uri = Uri.parse(
          '${ApiConfig.geocoding}?name=&latitude=$lat&longitude=$lng&count=1');
      final res = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      final results = data is Map ? data['results'] : null;
      if (results is List && results.isNotEmpty && results.first is Map) {
        final r = results.first as Map;
        return _composePlaceName(
          city: r['name']?.toString(),
          state: r['admin1']?.toString(),
        );
      }
    } catch (_) {}
    return null;
  }

  /// Builds `"City, State"` when both are present and distinct.
  static String? _composePlaceName({String? city, String? state}) {
    final c = city?.trim();
    final s = state?.trim();
    if (c == null || c.isEmpty) {
      if (s == null || s.isEmpty) return null;
      return s;
    }
    if (s != null && s.isNotEmpty && s != c) return '$c, $s';
    return c;
  }

  /// Forward place search for the map search bar (same Open-Meteo endpoint).
  Future<List<PlaceResult>> searchPlaces(String query) async {
    final uri = Uri.parse(ApiConfig.geocoding).replace(queryParameters: {
      'name': query,
      'count': '6',
      'language': 'en',
      'format': 'json',
    });
    final res = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw ApiException(ApiConfig.geocoding, 'Search failed', statusCode: res.statusCode);
    }
    final data = jsonDecode(res.body);
    final results = data is Map ? data['results'] : null;
    if (results is! List) return const [];
    return [
      for (final r in results.whereType<Map>())
        if (r['latitude'] is num && r['longitude'] is num)
          PlaceResult(
            name: r['name']?.toString() ?? 'Unnamed place',
            region: [r['admin1'], r['country']]
                .whereType<Object>()
                .map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .join(', '),
            latitude: (r['latitude'] as num).toDouble(),
            longitude: (r['longitude'] as num).toDouble(),
          ),
    ];
  }
}

class PlaceResult {
  const PlaceResult({
    required this.name,
    required this.region,
    required this.latitude,
    required this.longitude,
  });
  final String name, region;
  final double latitude, longitude;
}

/// Parses a list of raw AQI maps into typed records after height selection.
List<AqiRecord> toAqiRecords(
        List<Map<String, dynamic>> raw, HeightOption height) =>
    raw.map((r) => AqiRecord.fromJson(extractDataByHeight(r, height))).toList();
