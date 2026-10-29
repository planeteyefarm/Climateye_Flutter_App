import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/api_client.dart';
import '../utils/date_utils.dart';

class RainSample {
  const RainSample({
    required this.lat,
    required this.lng,
    required this.rain,
  });

  final double lat;
  final double lng;
  final double? rain;
}

class RainStop {
  const RainStop(this.mm, this.r, this.g, this.b);
  final double mm;
  final int r;
  final int g;
  final int b;
}

/// 7-stop rainfall ramp matching Website zc array:
/// 0.0 mm: [20, 90, 130] -> 1.5: [48, 170, 190] -> 3.0: [40, 168, 120] ->
/// 7.0: [72, 196, 64] -> 10.0: [200, 210, 48] -> 20.0: [236, 160, 36] -> 30.0: [196, 48, 160]
const List<RainStop> kRainStops = [
  RainStop(0.0, 20, 90, 130),
  RainStop(1.5, 48, 170, 190),
  RainStop(3.0, 40, 168, 120),
  RainStop(7.0, 72, 196, 64),
  RainStop(10.0, 200, 210, 48),
  RainStop(20.0, 236, 160, 36),
  RainStop(30.0, 196, 48, 160),
];

List<int>? rainColorRgba(double? mm) {
  if (mm == null || mm <= 0.05) return null;
  final value = mm.clamp(0.0, 30.0);
  int index = 1;
  while (index < kRainStops.length && kRainStops[index].mm < value) {
    index++;
  }
  final start = kRainStops[index - 1];
  final end = kRainStops[math.min(index, kRainStops.length - 1)];
  final t = end.mm == start.mm ? 0.0 : (value - start.mm) / (end.mm - start.mm);

  final r = (start.r + (end.r - start.r) * t).round().clamp(0, 255);
  final g = (start.g + (end.g - start.g) * t).round().clamp(0, 255);
  final b = (start.b + (end.b - start.b) * t).round().clamp(0, 255);

  // Dynamic alpha based on rainfall intensity matching Website:
  // Math.round(185 + Math.min(1, Y / 8) * 60) -> 185 to 245 (~73% to 96%)
  final alpha = (185 + (value / 8.0).clamp(0.0, 1.0) * 60.0).round().clamp(185, 245);
  return [r, g, b, alpha];
}

double rainStepForZoom(double zoom) {
  if (zoom < 5) return 2.0;
  if (zoom < 7) return 1.0;
  if (zoom < 9) return 0.5;
  return 0.25;
}

class RainGridResult {
  const RainGridResult(this.points, this.step);
  final List<LatLng> points;
  final double step;
}

/// Viewport-aligned grid matching Website kA function (capped at 48 points).
RainGridResult computeRainGridPoints(LatLngBounds bounds, double zoom) {
  double step = rainStepForZoom(zoom);
  const maxPoints = 48;

  List<LatLng> build(double cell) {
    final south = ((bounds.south / cell).round() - 1) * cell;
    final north = ((bounds.north / cell).round() + 1) * cell;
    final west = ((bounds.west / cell).round() - 1) * cell;
    final east = ((bounds.east / cell).round() + 1) * cell;
    final points = <LatLng>[];
    final seen = <String>{};

    for (double lat = south; lat <= north + cell * 0.01; lat += cell) {
      for (double lng = west; lng <= east + cell * 0.01; lng += cell) {
        final p = LatLng((lat * 1000).round() / 1000, (lng * 1000).round() / 1000);
        final key = '${p.latitude}:${p.longitude}';
        if (seen.add(key)) {
          points.add(p);
        }
      }
    }
    return points;
  }

  var points = build(step);
  while (points.length > maxPoints && step < 4.0) {
    step *= 2.0;
    points = build(step);
  }
  if (points.length > maxPoints) {
    final stride = (points.length / maxPoints).ceil();
    points = [
      for (int i = 0; i < points.length; i++)
        if (i % stride == 0) points[i]
    ];
    if (points.length > maxPoints) {
      points = points.sublist(0, maxPoints);
    }
  }
  return RainGridResult(points, step);
}

/// Shepard's IDW spatial interpolation matching Website MA function:
/// weight = 1 / (dLat^2 + (dLng * cosLat)^2 + smoothing)
double sampleRainField(
  List<RainSample> field,
  double lat,
  double lng,
  double smoothing,
) {
  if (field.isEmpty) return 0.0;
  final cosLat = math.cos((lat * math.pi) / 180.0);
  double sum = 0.0;
  double weightTotal = 0.0;

  for (final p in field) {
    if (p.rain == null) continue;
    final dLat = lat - p.lat;
    final dLng = (lng - p.lng) * cosLat;
    final w = 1.0 / (dLat * dLat + dLng * dLng + smoothing);
    sum += p.rain! * w;
    weightTotal += w;
  }

  return weightTotal > 0.0 ? sum / weightTotal : 0.0;
}

class RainFieldOverlay extends StatefulWidget {
  const RainFieldOverlay({
    super.key,
    required this.forecastMode,
    this.selectedDate,
    this.initialCenter,
    this.initialPrecipitation,
  });

  final bool forecastMode; // true = Forecast (next 3h), false = Recent (last 3h)
  final DateTime? selectedDate;
  final LatLng? initialCenter;
  final double? initialPrecipitation;

  static Map<String, List<Map<String, dynamic>>> get rainSeriesCache =>
      _RainFieldOverlayState._rainSeriesCache;

  /// Aggregates 3-hour precipitation accumulation matching Website wne function.
  static double aggregate3HourRain(List<Map<String, dynamic>> series, bool isForecast) {
    if (series.isEmpty) return 0.0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    const windowMs = 3 * 60 * 60 * 1000; // 3 hours in ms

    double sum = 0.0;
    bool hasInWindow = false;
    double? nearestVal;
    int minDistance = 1 << 60;

    for (final record in series) {
      final time = record['time'] as int;
      final rain = (record['rain'] as num).toDouble();

      if (!isForecast) {
        // Recent: last 3 hours (time <= nowMs)
        if (time > nowMs) continue;
        final d = nowMs - time;
        if (d < minDistance) {
          minDistance = d;
          nearestVal = rain;
        }
        if (time >= nowMs - windowMs) {
          sum += rain;
          hasInWindow = true;
        }
      } else {
        // Forecast: next 3 hours (time > nowMs)
        if (time <= nowMs) continue;
        final d = time - nowMs;
        if (d < minDistance) {
          minDistance = d;
          nearestVal = rain;
        }
        if (d <= windowMs) {
          sum += rain;
          hasInWindow = true;
        }
      }
    }

    return hasInWindow ? sum : (nearestVal ?? 0.0);
  }

  /// Samples the rain field at [lat], [lng] using active grid samples.
  static double? sampleAt(
    double lat,
    double lng, {
    required bool forecastMode,
    DateTime? selectedDate,
    double zoom = 5.0,
  }) {
    final step = rainStepForZoom(zoom);
    final smoothing = math.max(0.04, step * step / 8.0);
    final modeStr = forecastMode ? 'forecast' : 'recent';
    final dateStr = ymd(selectedDate ?? DateTime.now());
    final prefix = '$modeStr:$dateStr:';
    final samples = <RainSample>[];
    for (final entry in _RainFieldOverlayState._rainSeriesCache.entries) {
      if (entry.key.startsWith(prefix) && entry.value.isNotEmpty) {
        final rainVal = aggregate3HourRain(entry.value, forecastMode);
        final parts = entry.key.split(':');
        if (parts.length >= 4) {
          final sLat = double.tryParse(parts[2]);
          final sLng = double.tryParse(parts[3]);
          if (sLat != null && sLng != null) {
            samples.add(RainSample(lat: sLat, lng: sLng, rain: rainVal));
          }
        }
      }
    }
    if (samples.isEmpty) return null;
    return sampleRainField(samples, lat, lng, smoothing);
  }

  @override
  State<RainFieldOverlay> createState() => _RainFieldOverlayState();
}

class _RainFieldOverlayState extends State<RainFieldOverlay> {
  static final Map<String, List<Map<String, dynamic>>> _rainSeriesCache = {};
  int _generation = 0;
  Timer? _debounceTimer;

  ui.Image? _rainImage;
  LatLngBounds? _renderedBounds;
  LatLngBounds? _lastScheduledBounds;
  double? _lastScheduledZoom;
  bool _lastForecastMode = false;
  bool _isRendering = false;

  @override
  void initState() {
    super.initState();
    _lastForecastMode = widget.forecastMode;
    _seedInitial();

    // Load initial grid immediately on mount after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadGrid();
    });
  }

  @override
  void didUpdateWidget(RainFieldOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.forecastMode != widget.forecastMode ||
        oldWidget.selectedDate != widget.selectedDate ||
        oldWidget.initialPrecipitation != widget.initialPrecipitation) {
      _lastForecastMode = widget.forecastMode;
      _seedInitial();
      _scheduleGridLoad();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _generation++;
    _rainImage?.dispose();
    super.dispose();
  }

  void _seedInitial() {
    final center = widget.initialCenter;
    final precip = widget.initialPrecipitation;
    if (center != null && precip != null) {
      final modeStr = widget.forecastMode ? 'forecast' : 'recent';
      final dateStr = ymd(widget.selectedDate ?? DateTime.now());
      final key = '$modeStr:$dateStr:${center.latitude}:${center.longitude}';
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      _rainSeriesCache[key] = [
        {'time': nowMs, 'rain': precip}
      ];
    }
  }

  void _scheduleGridLoad() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), _loadGrid);
  }

  /// Calculates 3-hour precipitation accumulation matching Website wne function.
  double _aggregate3HourRain(List<Map<String, dynamic>> series, bool isForecast) {
    if (series.isEmpty) return 0.0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    const windowMs = 3 * 60 * 60 * 1000; // 3 hours in ms

    double sum = 0.0;
    bool hasInWindow = false;
    double? nearestVal;
    int minDistance = 1 << 60;

    for (final record in series) {
      final time = record['time'] as int;
      final rain = (record['rain'] as num).toDouble();

      if (!isForecast) {
        // Recent: last 3 hours (time <= nowMs)
        if (time > nowMs) continue;
        final d = nowMs - time;
        if (d < minDistance) {
          minDistance = d;
          nearestVal = rain;
        }
        if (time >= nowMs - windowMs) {
          sum += rain;
          hasInWindow = true;
        }
      } else {
        // Forecast: next 3 hours (time > nowMs)
        if (time <= nowMs) continue;
        final d = time - nowMs;
        if (d < minDistance) {
          minDistance = d;
          nearestVal = rain;
        }
        if (d <= windowMs) {
          sum += rain;
          hasInWindow = true;
        }
      }
    }

    return hasInWindow ? sum : (nearestVal ?? 0.0);
  }

  List<RainSample> _extractSamples(LatLngBounds bounds, double pad) {
    final modeStr = widget.forecastMode ? 'forecast' : 'recent';
    final dateStr = ymd(widget.selectedDate ?? DateTime.now());
    final prefix = '$modeStr:$dateStr:';

    final south = bounds.south - pad;
    final north = bounds.north + pad;
    final west = bounds.west - pad;
    final east = bounds.east + pad;

    final samples = <RainSample>[];
    final allForMode = <RainSample>[];

    for (final entry in _rainSeriesCache.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final parts = entry.key.split(':');
      if (parts.length < 4) continue;
      final lat = double.tryParse(parts[2]);
      final lng = double.tryParse(parts[3]);
      if (lat == null || lng == null) continue;

      final rain = _aggregate3HourRain(entry.value, widget.forecastMode);
      final s = RainSample(lat: lat, lng: lng, rain: rain);
      allForMode.add(s);

      if (lat >= south && lat <= north && lng >= west && lng <= east) {
        samples.add(s);
      }
    }

    if (samples.length < 3 && allForMode.isNotEmpty) {
      return allForMode;
    }
    return samples;
  }

  Future<void> _loadGrid() async {
    if (!mounted) return;
    final camera = MapCamera.of(context);
    final bounds = camera.visibleBounds;
    final zoom = camera.zoom;
    final targetDate = widget.selectedDate ?? DateTime.now();
    final dateStr = ymd(targetDate);
    final isForecast = widget.forecastMode;
    final modeStr = isForecast ? 'forecast' : 'recent';

    final id = ++_generation;
    final grid = computeRainGridPoints(bounds, zoom);
    final step = grid.step;

    final existing = _extractSamples(bounds, math.max(step * 3.0, 5.0));
    if (existing.isNotEmpty) {
      _renderRainMap(camera, existing, step, id);
    }

    final uniquePoints = <LatLng>[];
    final seen = <String>{};
    for (final p in grid.points) {
      final key = '$modeStr:$dateStr:${p.latitude}:${p.longitude}';
      if (seen.add(key) && !_rainSeriesCache.containsKey(key)) {
        uniquePoints.add(p);
      }
    }

    if (uniquePoints.isNotEmpty) {
      int cursor = 0;
      Future<void> worker() async {
        while (cursor < uniquePoints.length) {
          if (!mounted || _generation != id) return;
          final point = uniquePoints[cursor++];
          final key = '$modeStr:$dateStr:${point.latitude}:${point.longitude}';
          if (_rainSeriesCache.containsKey(key)) continue;

          try {
            final series = <Map<String, dynamic>>[];
            if (isForecast) {
              // Forecast: call /weather/rain-forecast
              final json = await ApiClient.instance.fetchRainForecast(
                point.latitude,
                point.longitude,
              );
              if (!mounted || _generation != id) return;

              final hourly = json['hourly'] as Map<String, dynamic>?;
              final times = (hourly?['time'] as List?)?.cast<String>() ?? [];
              final rains = (hourly?['rain'] as List?)?.map((x) => (x as num).toDouble()).toList() ?? [];
              final len = math.min(times.length, rains.length);

              for (int i = 0; i < len; i++) {
                final timeStr = times[i];
                final dt = parseApiDate(timeStr)?.toUtc() ??
                    DateTime.tryParse(timeStr.endsWith('Z') ? timeStr : '${timeStr}Z')?.toUtc();
                if (dt != null) {
                  series.add({'time': dt.millisecondsSinceEpoch, 'rain': rains[i]});
                }
              }
            } else {
              // Recent: call /weather/hourly
              final hourly = await ApiClient.instance.fetchHourlyWeather(
                point.latitude,
                point.longitude,
                targetDate,
              );
              if (!mounted || _generation != id) return;

              for (final r in hourly) {
                final ms = r.date?.toUtc().millisecondsSinceEpoch;
                final precip = r.precipitation;
                if (ms != null && precip != null) {
                  series.add({'time': ms, 'rain': precip});
                }
              }
            }

            series.sort((a, b) => (a['time'] as int).compareTo(b['time'] as int));

            if (_rainSeriesCache.length > 320) {
              _rainSeriesCache.remove(_rainSeriesCache.keys.first);
            }
            _rainSeriesCache[key] = series;
          } catch (_) {
            if (!mounted || _generation != id) return;
            if (_rainSeriesCache.length > 320) {
              _rainSeriesCache.remove(_rainSeriesCache.keys.first);
            }
            _rainSeriesCache[key] = [];
          }

          // Progressive rendering as sample points stream in
          if (cursor % 6 == 0 && mounted && _generation == id) {
            final intermediate = _extractSamples(bounds, math.max(step * 3.0, 5.0));
            if (intermediate.isNotEmpty) {
              _renderRainMap(camera, intermediate, step, id);
            }
          }
        }
      }

      await Future.wait([worker(), worker(), worker(), worker()]);
    }

    if (!mounted || _generation != id) return;
    final fresh = _extractSamples(bounds, math.max(step * 3.0, 5.0));
    if (fresh.isNotEmpty) {
      _renderRainMap(camera, fresh, step, id);
    }
  }

  void _renderRainMap(
    MapCamera camera,
    List<RainSample> samples,
    double step,
    int id,
  ) {
    if (_isRendering) return;
    _isRendering = true;

    final size = camera.size;
    if (size.width <= 0 || size.height <= 0) {
      _isRendering = false;
      return;
    }

    // Square texel high-resolution buffer matching Website 220x140 aspect ratio
    const int bufferW = 240;
    final int bufferH = (bufferW * (size.height / size.width)).round().clamp(140, 480);
    final smoothing = math.max(0.04, step * step / 8.0);

    final bounds = camera.visibleBounds;
    final double north = bounds.north;
    final double south = bounds.south;
    final double west = bounds.west;
    final double east = bounds.east;
    final double dLat = (north - south) / bufferH;
    final double dLng = (east - west) / bufferW;

    final validSamples = samples.where((s) => s.rain != null).toList();
    final pixels = Uint8List(bufferW * bufferH * 4);

    if (validSamples.isNotEmpty) {
      for (int py = 0; py < bufferH; py++) {
        final lat = north - (py + 0.5) * dLat;
        final cosLat = math.cos((lat * math.pi) / 180.0);
        final rowOffset = py * bufferW * 4;

        for (int px = 0; px < bufferW; px++) {
          final lng = west + (px + 0.5) * dLng;
          double sum = 0.0;
          double weightTotal = 0.0;

          for (int i = 0; i < validSamples.length; i++) {
            final p = validSamples[i];
            final dy = lat - p.lat;
            final dx = (lng - p.lng) * cosLat;
            final w = 1.0 / (dy * dy + dx * dx + smoothing);
            sum += p.rain! * w;
            weightTotal += w;
          }

          final rainVal = weightTotal > 0.0 ? sum / weightTotal : 0.0;
          final color = rainColorRgba(rainVal);
          final idx = rowOffset + px * 4;

          if (color != null) {
            pixels[idx] = color[0];
            pixels[idx + 1] = color[1];
            pixels[idx + 2] = color[2];
            pixels[idx + 3] = color[3];
          } else {
            pixels[idx + 3] = 0;
          }
        }
      }
    }

    ui.decodeImageFromPixels(
      pixels,
      bufferW,
      bufferH,
      ui.PixelFormat.rgba8888,
      (image) {
        _isRendering = false;
        if (!mounted || _generation != id) {
          image.dispose();
          return;
        }
        setState(() {
          _rainImage?.dispose();
          _rainImage = image;
          _renderedBounds = bounds;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);

    final bounds = camera.visibleBounds;
    final zoom = camera.zoom;
    final bool boundsMoved = _lastScheduledBounds == null ||
        _lastScheduledZoom != zoom ||
        _lastForecastMode != widget.forecastMode ||
        (_lastScheduledBounds!.south - bounds.south).abs() > 0.4 ||
        (_lastScheduledBounds!.west - bounds.west).abs() > 0.4;

    if (boundsMoved) {
      _lastScheduledBounds = bounds;
      _lastScheduledZoom = zoom;
      _lastForecastMode = widget.forecastMode;
      _scheduleGridLoad();
    }

    if (_rainImage == null) {
      return const SizedBox.shrink();
    }

    return SizedBox.expand(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _RainRasterPainter(
            image: _rainImage,
            imageBounds: _renderedBounds,
            camera: camera,
            globalAlpha: 0.90,
          ),
        ),
      ),
    );
  }
}

class _RainRasterPainter extends CustomPainter {
  _RainRasterPainter({
    required this.image,
    required this.imageBounds,
    required this.camera,
    required this.globalAlpha,
  });

  final ui.Image? image;
  final LatLngBounds? imageBounds;
  final MapCamera camera;
  final double globalAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    if (image == null) return;
    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..color = Color.fromRGBO(255, 255, 255, globalAlpha);

    Rect destRect;
    if (imageBounds != null) {
      final nw = camera.latLngToScreenOffset(imageBounds!.northWest);
      final se = camera.latLngToScreenOffset(imageBounds!.southEast);
      destRect = Rect.fromPoints(nw, se);
    } else {
      destRect = Rect.fromLTWH(0, 0, size.width, size.height);
    }

    canvas.drawImageRect(
      image!,
      Rect.fromLTWH(0, 0, image!.width.toDouble(), image!.height.toDouble()),
      destRect,
      paint,
    );
  }

  @override
  bool shouldRepaint(_RainRasterPainter old) =>
      old.image != image ||
      old.imageBounds != imageBounds ||
      old.camera.center != camera.center ||
      old.camera.zoom != camera.zoom;
}
