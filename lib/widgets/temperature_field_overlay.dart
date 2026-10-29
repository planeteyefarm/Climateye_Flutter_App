import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/weather.dart';
import '../services/api_client.dart';
import '../utils/date_utils.dart';

/// Represents a single sampled geographic coordinate and its temperature.
class TemperatureSample {
  const TemperatureSample({
    required this.lat,
    required this.lng,
    required this.temp,
  });

  final double lat;
  final double lng;
  final double? temp;
}

/// 12 temperature stops ported directly from Website TemperatureFieldMap.jsx.
/// Windy-style ramp: deep blue -> cyan -> green -> yellow -> orange -> burnt red.
class TempStop {
  const TempStop(this.temp, this.r, this.g, this.b);
  final double temp;
  final int r;
  final int g;
  final int b;
}

const List<TempStop> kTempStops = [
  TempStop(-20, 18, 40, 150),
  TempStop(-10, 36, 100, 210),
  TempStop(0, 48, 170, 230),
  TempStop(5, 40, 200, 195),
  TempStop(10, 55, 205, 95),
  TempStop(15, 150, 220, 45),
  TempStop(20, 235, 225, 40),
  TempStop(24, 245, 185, 30),
  TempStop(28, 240, 130, 28),
  TempStop(32, 230, 80, 28),
  TempStop(36, 200, 40, 32),
  TempStop(40, 145, 28, 38),
];

/// Smooth Hermite blending matching the Website:
/// blend = t * t * (3 - 2 * t)
List<int>? temperatureColorRgb(double? temperature) {
  if (temperature == null) return null;
  final value = temperature.clamp(-20.0, 40.0);
  int index = 1;
  while (index < kTempStops.length && kTempStops[index].temp < value) {
    index++;
  }
  final start = kTempStops[index - 1];
  final end = kTempStops[math.min(index, kTempStops.length - 1)];
  final t = end.temp == start.temp ? 0.0 : (value - start.temp) / (end.temp - start.temp);
  final blend = t * t * (3.0 - 2.0 * t);
  return [
    (start.r + (end.r - start.r) * blend).round().clamp(0, 255),
    (start.g + (end.g - start.g) * blend).round().clamp(0, 255),
    (start.b + (end.b - start.b) * blend).round().clamp(0, 255),
  ];
}

double snapCoord(double value, double step) => (value / step).round() * step;

double stepForZoom(double zoom) {
  if (zoom < 5) return 2.0;
  if (zoom < 7) return 1.0;
  if (zoom < 9) return 0.5;
  return 0.25;
}

class GridResult {
  const GridResult(this.points, this.step);
  final List<LatLng> points;
  final double step;
}

/// Generates a viewport-aligned grid of sample points matching the Website.
GridResult computeGridPoints(LatLngBounds bounds, double zoom) {
  double step = stepForZoom(zoom);
  const maxPoints = 56;

  List<LatLng> build(double cell) {
    final south = snapCoord(bounds.south, cell) - cell;
    final north = snapCoord(bounds.north, cell) + cell;
    final west = snapCoord(bounds.west, cell) - cell;
    final east = snapCoord(bounds.east, cell) + cell;
    final points = <LatLng>[];
    final seen = <String>{};

    for (double lat = south; lat <= north + cell * 0.01; lat += cell) {
      for (double lng = west; lng <= east + cell * 0.01; lng += cell) {
        final p = LatLng(
          (lat * 1000).round() / 1000,
          (lng * 1000).round() / 1000,
        );
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
  return GridResult(points, step);
}

/// Sharp Inverse Distance Weighting (IDW) matching the Website:
/// Power-3 falloff with cosine latitude correction. Smooth continuous blending without
/// hard-cutoff snapping in raster generation, preserving exact station values.
double? sampleTemperatureField(
  List<TemperatureSample> field,
  double lat,
  double lng,
  double soft, {
  bool snapToNearest = false,
}) {
  if (field.isEmpty) return null;
  final cosLat = math.cos((lat * math.pi) / 180.0);
  double? nearest;
  double nearestDist = double.infinity;
  double temperature = 0.0;
  double weightTotal = 0.0;

  for (final point in field) {
    if (point.temp == null) continue;
    final dLat = lat - point.lat;
    final dLng = (lng - point.lng) * cosLat;
    final dist2 = dLat * dLat + dLng * dLng;
    final dist = math.sqrt(dist2);
    if (dist < nearestDist) {
      nearestDist = dist;
      nearest = point.temp;
    }
    // Power-3 falloff
    final ds = dist + soft;
    final weight = 1.0 / (ds * ds * ds);
    temperature += point.temp! * weight;
    weightTotal += weight;
  }

  if (weightTotal == 0.0) return null;
  // Snap when within station measurement threshold or explicit snap requested
  if (nearest != null && (nearestDist < 0.005 || (snapToNearest && nearestDist < soft * 2.5))) {
    return nearest;
  }
  return temperature / weightTotal;
}

/// Ported date/hour matcher matching Website's currentTemperature.
double? extractCurrentTemperature(
  List<HourlyWeather> records, {
  DateTime? targetDate,
}) {
  final nowMs = targetDate != null
      ? (targetDate.isAfter(DateTime.now())
          ? targetDate.add(const Duration(hours: 12)).millisecondsSinceEpoch
          : targetDate.millisecondsSinceEpoch)
      : DateTime.now().millisecondsSinceEpoch;

  double? bestTemp;
  int? bestDistance;

  for (final record in records) {
    final temp = record.temperature;
    if (temp == null) continue;
    final timeMs = record.date?.toUtc().millisecondsSinceEpoch;
    if (timeMs == null) continue;
    if (timeMs > nowMs + 30 * 60 * 1000) continue;
    final distance = (nowMs - timeMs).abs();
    if (bestDistance == null || distance < bestDistance) {
      bestDistance = distance;
      bestTemp = temp;
    }
  }
  return bestTemp ?? (records.isNotEmpty ? records.first.temperature : null);
}

/// Continuous full-map raster temperature field matching the Website's TemperatureFieldMap.
class TemperatureFieldOverlay extends StatefulWidget {
  const TemperatureFieldOverlay({
    super.key,
    this.selectedDate,
    this.initialCenter,
    this.initialTemperature,
  });

  final DateTime? selectedDate;
  final LatLng? initialCenter;
  final double? initialTemperature;

  static Map<String, TemperatureSample> get sampleCache =>
      _TemperatureFieldOverlayState._sampleCache;

  /// Samples the temperature field at [lat], [lng] using active grid samples.
  static double? sampleAt(
    double lat,
    double lng, {
    DateTime? selectedDate,
    double zoom = 5.0,
  }) {
    final step = stepForZoom(zoom);
    final soft = math.max(0.012, step * 0.08);
    final dateStr = ymd(selectedDate ?? DateTime.now());
    final prefix = 'v2:$dateStr:';
    final samples = <TemperatureSample>[];
    for (final entry in _TemperatureFieldOverlayState._sampleCache.entries) {
      if (entry.key.startsWith(prefix) && entry.value.temp != null) {
        samples.add(entry.value);
      }
    }
    if (samples.isEmpty) return null;
    return sampleTemperatureField(samples, lat, lng, soft, snapToNearest: true);
  }

  @override
  State<TemperatureFieldOverlay> createState() => _TemperatureFieldOverlayState();
}

class _TemperatureFieldOverlayState extends State<TemperatureFieldOverlay> {
  static final Map<String, TemperatureSample> _sampleCache = {};
  int _generation = 0;
  Timer? _debounceTimer;

  ui.Image? _heatImage;
  bool _isRendering = false;
  LatLngBounds? _lastRenderedBounds;
  double _lastRenderedZoom = -1;
  DateTime? _lastDate;

  @override
  void initState() {
    super.initState();
    _seedInitial();
  }

  @override
  void didUpdateWidget(TemperatureFieldOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate ||
        oldWidget.initialTemperature != widget.initialTemperature) {
      _seedInitial();
      _scheduleGridLoad();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _generation++;
    super.dispose();
  }

  void _seedInitial() {
    final center = widget.initialCenter;
    final temp = widget.initialTemperature;
    if (center != null && temp != null) {
      final dateStr = ymd(widget.selectedDate ?? DateTime.now());
      final key = 'v2:$dateStr:${center.latitude}:${center.longitude}';
      _sampleCache[key] = TemperatureSample(
        lat: center.latitude,
        lng: center.longitude,
        temp: temp,
      );
    }
  }

  void _scheduleGridLoad() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), _loadGrid);
  }

  List<TemperatureSample> _pointsNearView(LatLngBounds bounds, double pad) {
    final dateStr = ymd(widget.selectedDate ?? DateTime.now());
    final south = bounds.south - pad;
    final north = bounds.north + pad;
    final west = bounds.west - pad;
    final east = bounds.east + pad;
    final prefix = 'v2:$dateStr:';

    final samples = <TemperatureSample>[];
    final allForDate = <TemperatureSample>[];

    for (final entry in _sampleCache.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final s = entry.value;
      if (s.temp == null) continue;
      allForDate.add(s);
      if (s.lat >= south && s.lat <= north && s.lng >= west && s.lng <= east) {
        samples.add(s);
      }
    }

    // Ensure seamless regional coverage across both land and sea without edge voids
    if (samples.length < 3 && allForDate.isNotEmpty) {
      return allForDate;
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

    final id = ++_generation;
    final grid = computeGridPoints(bounds, zoom);
    final step = grid.step;

    // Render immediately from available cached samples for responsive UI
    final existingSamples = _pointsNearView(bounds, math.max(step * 3.0, 5.0));
    if (existingSamples.isNotEmpty) {
      _renderHeatMap(camera, existingSamples, step, id);
    }

    final uniquePoints = <LatLng>[];
    final seen = <String>{};
    for (final p in grid.points) {
      final key = 'v2:$dateStr:${p.latitude}:${p.longitude}';
      if (seen.add(key) && !_sampleCache.containsKey(key)) {
        uniquePoints.add(p);
      }
    }

    if (uniquePoints.isNotEmpty) {
      int cursor = 0;
      Future<void> worker() async {
        while (cursor < uniquePoints.length) {
          if (!mounted || _generation != id) return;
          final point = uniquePoints[cursor++];
          final key = 'v2:$dateStr:${point.latitude}:${point.longitude}';
          if (_sampleCache.containsKey(key)) continue;

          try {
            final hourly = await ApiClient.instance.fetchHourlyWeather(
              point.latitude,
              point.longitude,
              targetDate,
            );
            if (!mounted || _generation != id) return;
            final temp = extractCurrentTemperature(hourly, targetDate: targetDate);
            if (_sampleCache.length > 280) {
              _sampleCache.remove(_sampleCache.keys.first);
            }
            _sampleCache[key] = TemperatureSample(
              lat: point.latitude,
              lng: point.longitude,
              temp: temp,
            );
          } catch (_) {
            if (!mounted || _generation != id) return;
            if (_sampleCache.length > 280) {
              _sampleCache.remove(_sampleCache.keys.first);
            }
            _sampleCache[key] = TemperatureSample(
              lat: point.latitude,
              lng: point.longitude,
              temp: null,
            );
          }
        }
      }

      await Future.wait([worker(), worker(), worker(), worker()]);
    }

    if (!mounted || _generation != id) return;
    final samples = _pointsNearView(bounds, math.max(step * 3.0, 5.0));
    if (samples.isNotEmpty) {
      _renderHeatMap(camera, samples, step, id);
    }
  }

  void _renderHeatMap(
    MapCamera camera,
    List<TemperatureSample> samples,
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

    // High resolution raster buffer maintaining exact screen aspect ratio with square texels
    const int bufferW = 320;
    final int bufferH = (bufferW * (size.height / size.width)).round().clamp(160, 640);
    // Smooth blending parameter matching Website
    final soft = math.max(0.06, step * 0.35);

    final bounds = camera.visibleBounds;
    final double north = bounds.north;
    final double south = bounds.south;
    final double west = bounds.west;
    final double east = bounds.east;
    final double dLat = (north - south) / bufferH;
    final double dLng = (east - west) / bufferW;

    final validSamples = samples.where((s) => s.temp != null).toList();
    if (validSamples.isEmpty) {
      _isRendering = false;
      return;
    }

    final pixels = Uint8List(bufferW * bufferH * 4);

    for (int py = 0; py < bufferH; py++) {
      final lat = north - (py + 0.5) * dLat;
      final cosLat = math.cos((lat * math.pi) / 180.0);
      final rowOffset = py * bufferW * 4;

      for (int px = 0; px < bufferW; px++) {
        final lng = west + (px + 0.5) * dLng;

        double temperature = 0.0;
        double weightTotal = 0.0;
        double nearestDist = double.infinity;
        double? nearest;

        for (int i = 0; i < validSamples.length; i++) {
          final p = validSamples[i];
          final dy = lat - p.lat;
          final dx = (lng - p.lng) * cosLat;
          final dist = math.sqrt(dy * dy + dx * dx);
          if (dist < nearestDist) {
            nearestDist = dist;
            nearest = p.temp;
          }
          final ds = dist + soft;
          final weight = 1.0 / (ds * ds * ds);
          temperature += p.temp! * weight;
          weightTotal += weight;
        }

        double? temp;
        if (weightTotal > 0.0) {
          if (nearest != null && nearestDist < 0.005) {
            temp = nearest;
          } else {
            temp = temperature / weightTotal;
          }
        }

        final color = temperatureColorRgb(temp);
        final idx = rowOffset + px * 4;

        if (color != null) {
          pixels[idx] = color[0];
          pixels[idx + 1] = color[1];
          pixels[idx + 2] = color[2];
          pixels[idx + 3] = 200; // ~78% pixel alpha matching Website
        } else {
          pixels[idx + 3] = 0;
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
          _heatImage?.dispose();
          _heatImage = image;
          _lastRenderedBounds = bounds;
          _lastRenderedZoom = camera.zoom;
          _lastDate = widget.selectedDate;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);

    // If bounds, zoom, or date changed, debounce reload
    if (_lastRenderedBounds == null ||
        _lastRenderedZoom != camera.zoom ||
        _lastDate != widget.selectedDate ||
        (_lastRenderedBounds != null &&
            ((_lastRenderedBounds!.south - camera.visibleBounds.south).abs() > 0.35 ||
             (_lastRenderedBounds!.west - camera.visibleBounds.west).abs() > 0.35))) {
      _scheduleGridLoad();
    }

    if (_heatImage == null) {
      return const SizedBox.shrink();
    }

    return SizedBox.expand(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _HeatRasterPainter(
            image: _heatImage,
            imageBounds: _lastRenderedBounds,
            camera: camera,
            globalAlpha: 0.88,
          ),
        ),
      ),
    );
  }
}

class _HeatRasterPainter extends CustomPainter {
  _HeatRasterPainter({
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
  bool shouldRepaint(_HeatRasterPainter old) =>
      old.image != image ||
      old.imageBounds != imageBounds ||
      old.camera.center != camera.center ||
      old.camera.zoom != camera.zoom;
}
