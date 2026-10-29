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

class WindSample {
  const WindSample({
    required this.lat,
    required this.lng,
    required this.speed,
    required this.u,
    required this.v,
  });

  final double lat;
  final double lng;
  final double? speed;
  final double? u;
  final double? v;
}

class WindStop {
  const WindStop(this.speed, this.r, this.g, this.b);
  final double speed;
  final int r;
  final int g;
  final int b;
}

/// 7-stop wind palette ported directly from Website Rc array:
/// 0 km/h: purple -> 10: blue -> 20: cyan -> 35: green -> 55: yellow -> 70: orange -> 100: red
const List<WindStop> kWindStops = [
  WindStop(0, 122, 46, 158),
  WindStop(10, 58, 74, 204),
  WindStop(20, 32, 186, 214),
  WindStop(35, 54, 196, 96),
  WindStop(55, 230, 214, 48),
  WindStop(70, 236, 132, 32),
  WindStop(100, 198, 36, 42),
];

List<int>? windColorRgb(double? speed) {
  if (speed == null) return null;
  final value = speed.clamp(0.0, 100.0);
  int index = 1;
  while (index < kWindStops.length && kWindStops[index].speed < value) {
    index++;
  }
  final start = kWindStops[index - 1];
  final end = kWindStops[math.min(index, kWindStops.length - 1)];
  final t = end.speed == start.speed ? 0.0 : (value - start.speed) / (end.speed - start.speed);
  return [
    (start.r + (end.r - start.r) * t).round().clamp(0, 255),
    (start.g + (end.g - start.g) * t).round().clamp(0, 255),
    (start.b + (end.b - start.b) * t).round().clamp(0, 255),
  ];
}

/// Computes 3x4 viewport-aligned grid matching Website Qre function.
List<LatLng> computeWindGridPoints(LatLngBounds bounds) {
  final south = bounds.south;
  final north = bounds.north;
  final west = bounds.west;
  final east = bounds.east;
  final step = math.max(north - south, east - west) > 20.0 ? 2.0 : 1.0;
  final points = <LatLng>[];
  final seen = <String>{};

  for (int u = 0; u < 3; u++) {
    for (int c = 0; c < 4; c++) {
      final lat = ((south + (u + 0.5) * (north - south) / 3.0) / step).round() * step;
      final lng = ((west + (c + 0.5) * (east - west) / 4.0) / step).round() * step;
      final p = LatLng((lat * 1000).round() / 1000, (lng * 1000).round() / 1000);
      final key = '${p.latitude}:${p.longitude}';
      if (seen.add(key)) {
        points.add(p);
      }
    }
  }
  return points;
}

class InterpolatedWind {
  const InterpolatedWind({this.u, this.v, this.speed});
  final double? u;
  final double? v;
  final double? speed;
}

/// Shepard's IDW spatial interpolation matching Website yy function.
InterpolatedWind sampleWindField(List<WindSample> field, double lat, double lng) {
  if (field.isEmpty) return const InterpolatedWind();
  final cosLat = math.cos(lat * math.pi / 180.0);
  double uSum = 0, vSum = 0, speedSum = 0;
  double uWeight = 0, speedWeight = 0;

  for (final p in field) {
    final dLat = lat - p.lat;
    final dLng = (lng - p.lng) * cosLat;
    final w = 1.0 / (dLat * dLat + dLng * dLng + 0.25);
    final spd = p.speed ?? (p.u != null && p.v != null ? math.sqrt(p.u! * p.u! + p.v! * p.v!) : null);
    if (p.u != null && p.v != null) {
      uSum += p.u! * w;
      vSum += p.v! * w;
      uWeight += w;
    }
    if (spd != null) {
      speedSum += spd * w;
      speedWeight += w;
    }
  }

  return InterpolatedWind(
    u: uWeight > 0 ? uSum / uWeight : null,
    v: uWeight > 0 ? vSum / uWeight : null,
    speed: speedWeight > 0 ? speedSum / speedWeight : null,
  );
}

/// Wind particle matching Website simulation parameters.
class WindParticle {
  WindParticle({
    required this.lat,
    required this.lng,
    required this.x,
    required this.y,
    required this.age,
    required this.life,
    required this.scale,
  }) : u = 0, v = 0, trail = [];

  double lat;
  double lng;
  double x;
  double y;
  double age;
  double life;
  double scale;
  double u;
  double v;
  final List<Offset> trail;

  void reset(LatLngBounds bounds, MapCamera camera, math.Random rnd) {
    lat = bounds.south + rnd.nextDouble() * (bounds.north - bounds.south);
    lng = bounds.west + rnd.nextDouble() * (bounds.east - bounds.west);
    final pt = camera.latLngToScreenOffset(LatLng(lat, lng));
    x = pt.dx;
    y = pt.dy;
    age = rnd.nextDouble() * 0.4;
    life = 0.55 + rnd.nextDouble() * 0.70;
    scale = 0.70 + rnd.nextDouble() * 0.55;
    u = 0;
    v = 0;
    trail.clear();
  }
}

class WindFieldOverlay extends StatefulWidget {
  const WindFieldOverlay({
    super.key,
    this.selectedDate,
    this.initialCenter,
    this.initialWindSpeed,
    this.initialWindDirection,
  });

  final DateTime? selectedDate;
  final LatLng? initialCenter;
  final double? initialWindSpeed;
  final double? initialWindDirection;

  static Map<String, WindSample> get windCache => _WindFieldOverlayState._windCache;

  /// Samples the wind field at [lat], [lng] using active grid samples.
  static double? sampleAt(
    double lat,
    double lng, {
    DateTime? selectedDate,
  }) {
    final dateStr = ymd(selectedDate ?? DateTime.now());
    final prefix = '$dateStr:';
    final samples = <WindSample>[];
    for (final entry in _WindFieldOverlayState._windCache.entries) {
      if (entry.key.startsWith(prefix) && entry.value.speed != null) {
        samples.add(entry.value);
      }
    }
    if (samples.isEmpty) return null;
    final sampled = sampleWindField(samples, lat, lng);
    return sampled.speed ??
        (sampled.u != null && sampled.v != null
            ? math.sqrt(sampled.u! * sampled.u! + sampled.v! * sampled.v!)
            : null);
  }

  @override
  State<WindFieldOverlay> createState() => _WindFieldOverlayState();
}

class _WindFieldOverlayState extends State<WindFieldOverlay>
    with SingleTickerProviderStateMixin {
  static final Map<String, WindSample> _windCache = {};
  final math.Random _rnd = math.Random();

  late AnimationController _animController;
  int _generation = 0;
  Timer? _debounceTimer;

  List<WindParticle> _particles = [];
  List<WindSample> _activeSamples = [];
  ui.Image? _speedRasterImage;
  LatLngBounds? _rasterBounds;
  LatLngBounds? _lastScheduledBounds;
  double? _lastScheduledZoom;
  bool _isRasterRendering = false;
  int _lastTickMs = 0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_onTick);
    _animController.repeat();

    _seedInitial();
    _lastTickMs = DateTime.now().millisecondsSinceEpoch;

    // Load initial grid immediately on mount after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadGrid();
    });
  }

  @override
  void didUpdateWidget(WindFieldOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate ||
        oldWidget.initialWindSpeed != widget.initialWindSpeed ||
        oldWidget.initialWindDirection != widget.initialWindDirection) {
      _seedInitial();
      _scheduleGridLoad();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _generation++;
    _animController.dispose();
    _speedRasterImage?.dispose();
    super.dispose();
  }

  void _seedInitial() {
    final center = widget.initialCenter;
    final speed = widget.initialWindSpeed;
    final dir = widget.initialWindDirection;
    if (center != null && speed != null) {
      final dateStr = ymd(widget.selectedDate ?? DateTime.now());
      final key = '$dateStr:${center.latitude}:${center.longitude}';
      final rad = dir != null ? ((dir + 180) % 360) * math.pi / 180.0 : 0.0;
      final sample = WindSample(
        lat: center.latitude,
        lng: center.longitude,
        speed: speed,
        u: speed * math.sin(rad),
        v: speed * math.cos(rad),
      );
      _windCache[key] = sample;
      if (_activeSamples.isEmpty) {
        _activeSamples = [sample];
      }
    }
  }

  void _scheduleGridLoad() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), _loadGrid);
  }

  void _onTick() {
    if (!mounted || _particles.isEmpty) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    double dt = (nowMs - _lastTickMs) / 1000.0;
    _lastTickMs = nowMs;
    dt = dt.clamp(0.008, 0.033);

    final camera = MapCamera.of(context);
    final bounds = camera.visibleBounds;
    final size = camera.size;
    final samples = _activeSamples;

    for (final p in _particles) {
      if (samples.isEmpty) {
        p.reset(bounds, camera, _rnd);
        continue;
      }

      final sampled = sampleWindField(samples, p.lat, p.lng);
      if (sampled.u == null || sampled.v == null) {
        p.reset(bounds, camera, _rnd);
        continue;
      }

      // Inertia smoothing: 1 - exp(-dt * 4.5)
      final inertia = 1.0 - math.exp(-dt * 4.5);
      p.u += (sampled.u! - p.u) * inertia;
      p.v += (sampled.v! - p.v) * inertia;
      final speed = math.sqrt(p.u * p.u + p.v * p.v);

      if (speed < 0.08) {
        p.reset(bounds, camera, _rnd);
        continue;
      }

      final stepW = (18.0 + speed * 1.35).clamp(24.0, 72.0) * p.scale;
      final dx = (p.u / speed) * stepW * dt;
      final dy = -(p.v / speed) * stepW * dt;

      p.x += dx;
      p.y += dy;
      p.age += dt / p.life;

      if (p.x < -20 || p.y < -20 || p.x > size.width + 20 || p.y > size.height + 20 || p.age >= 1.0) {
        p.reset(bounds, camera, _rnd);
        continue;
      }

      final latLng = camera.screenOffsetToLatLng(Offset(p.x, p.y));
      p.lat = latLng.latitude;
      p.lng = latLng.longitude;

      p.trail.add(Offset(p.x, p.y));
      if (p.trail.length > 28) {
        p.trail.removeAt(0);
      }
    }

    setState(() {});
  }

  Future<void> _loadGrid() async {
    if (!mounted) return;
    final camera = MapCamera.of(context);
    final bounds = camera.visibleBounds;
    final targetDate = widget.selectedDate ?? DateTime.now();
    final dateStr = ymd(targetDate);

    final id = ++_generation;
    final gridPoints = computeWindGridPoints(bounds);

    final currentSamples = <WindSample>[];
    final allForDate = <WindSample>[];
    final prefix = '$dateStr:';

    for (final entry in _windCache.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final s = entry.value;
      if (s.speed == null) continue;
      allForDate.add(s);
      if (s.lat >= bounds.south - 2 && s.lat <= bounds.north + 2 &&
          s.lng >= bounds.west - 2 && s.lng <= bounds.east + 2) {
        currentSamples.add(s);
      }
    }

    if (currentSamples.isNotEmpty) {
      _activeSamples = currentSamples;
      _renderSpeedRaster(camera, currentSamples, id);
    } else if (allForDate.isNotEmpty) {
      _activeSamples = allForDate;
      _renderSpeedRaster(camera, allForDate, id);
    }

    final uniquePoints = <LatLng>[];
    final seen = <String>{};
    for (final p in gridPoints) {
      final key = '$dateStr:${p.latitude}:${p.longitude}';
      if (seen.add(key) && !_windCache.containsKey(key)) {
        uniquePoints.add(p);
      }
    }

    if (uniquePoints.isNotEmpty) {
      int cursor = 0;
      Future<void> worker() async {
        while (cursor < uniquePoints.length) {
          if (!mounted || _generation != id) return;
          final point = uniquePoints[cursor++];
          final key = '$dateStr:${point.latitude}:${point.longitude}';
          if (_windCache.containsKey(key)) continue;

          try {
            final hourly = await ApiClient.instance.fetchHourlyWeather(
              point.latitude,
              point.longitude,
              targetDate,
            );
            if (!mounted || _generation != id) return;

            final now = DateTime.now();
            final nowMs = targetDate.isAfter(now)
                ? targetDate.add(const Duration(hours: 12)).millisecondsSinceEpoch
                : now.millisecondsSinceEpoch;

            HourlyWeather? best;
            int? bestDist;
            for (final r in hourly) {
              final ms = r.date?.toUtc().millisecondsSinceEpoch;
              if (ms == null || ms > nowMs + 30 * 60 * 1000) continue;
              final d = (nowMs - ms).abs();
              if (bestDist == null || d < bestDist) {
                bestDist = d;
                best = r;
              }
            }

            final speed = best?.windSpeed ?? (hourly.isNotEmpty ? hourly.first.windSpeed : null);
            final dir = best?.windDirection ?? (hourly.isNotEmpty ? hourly.first.windDirection : null);

            double? u;
            double? v;
            if (speed != null) {
              final a = dir != null ? ((dir + 180) % 360) * math.pi / 180.0 : 0.0;
              u = speed * math.sin(a);
              v = speed * math.cos(a);
            }

            if (_windCache.length > 120) {
              _windCache.remove(_windCache.keys.first);
            }
            _windCache[key] = WindSample(
              lat: point.latitude,
              lng: point.longitude,
              speed: speed,
              u: u,
              v: v,
            );
          } catch (_) {
            if (!mounted || _generation != id) return;
            if (_windCache.length > 120) {
              _windCache.remove(_windCache.keys.first);
            }
            _windCache[key] = WindSample(
              lat: point.latitude,
              lng: point.longitude,
              speed: null,
              u: null,
              v: null,
            );
          }
        }
      }

      await Future.wait([worker(), worker(), worker(), worker()]);
    }

    if (!mounted || _generation != id) return;
    final freshSamples = <WindSample>[];
    for (final entry in _windCache.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final s = entry.value;
      if (s.speed == null) continue;
      freshSamples.add(s);
    }

    if (freshSamples.isNotEmpty) {
      _activeSamples = freshSamples;
      _renderSpeedRaster(camera, freshSamples, id);
    }
  }

  void _renderSpeedRaster(
    MapCamera camera,
    List<WindSample> samples,
    int id,
  ) {
    if (_isRasterRendering) return;
    _isRasterRendering = true;

    final size = camera.size;
    if (size.width <= 0 || size.height <= 0) {
      _isRasterRendering = false;
      return;
    }

    const int bufferW = 160;
    final int bufferH = (bufferW * (size.height / size.width)).round().clamp(90, 320);

    final bounds = camera.visibleBounds;
    final double north = bounds.north;
    final double south = bounds.south;
    final double west = bounds.west;
    final double east = bounds.east;
    final double dLat = (north - south) / bufferH;
    final double dLng = (east - west) / bufferW;

    final pixels = Uint8List(bufferW * bufferH * 4);

    for (int py = 0; py < bufferH; py++) {
      final lat = north - (py + 0.5) * dLat;
      final rowOffset = py * bufferW * 4;

      for (int px = 0; px < bufferW; px++) {
        final lng = west + (px + 0.5) * dLng;
        final interpolated = sampleWindField(samples, lat, lng);
        final color = windColorRgb(interpolated.speed);
        final idx = rowOffset + px * 4;

        if (color != null) {
          pixels[idx] = color[0];
          pixels[idx + 1] = color[1];
          pixels[idx + 2] = color[2];
          pixels[idx + 3] = 214; // Vibrant background speed field (84%) matching Website
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
        _isRasterRendering = false;
        if (!mounted || _generation != id) {
          image.dispose();
          return;
        }
        setState(() {
          _speedRasterImage?.dispose();
          _speedRasterImage = image;
          _rasterBounds = bounds;
        });
      },
    );
  }

  void _ensureParticles(MapCamera camera) {
    final size = camera.size;
    if (size.width <= 0 || size.height <= 0) return;
    final targetCount = (size.width * size.height / 2200).round().clamp(300, 600);
    final bounds = camera.visibleBounds;

    if (_particles.length != targetCount) {
      _particles = List.generate(targetCount, (_) {
        final p = WindParticle(
          lat: 0,
          lng: 0,
          x: 0,
          y: 0,
          age: 0,
          life: 1,
          scale: 1,
        );
        p.reset(bounds, camera, _rnd);
        return p;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    _ensureParticles(camera);

    final bounds = camera.visibleBounds;
    final zoom = camera.zoom;
    final bool boundsMoved = _lastScheduledBounds == null ||
        _lastScheduledZoom != zoom ||
        (_lastScheduledBounds!.south - bounds.south).abs() > 0.4 ||
        (_lastScheduledBounds!.west - bounds.west).abs() > 0.4;

    if (boundsMoved) {
      _lastScheduledBounds = bounds;
      _lastScheduledZoom = zoom;
      _scheduleGridLoad();
    }

    return SizedBox.expand(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _WindFieldPainter(
            rasterImage: _speedRasterImage,
            rasterBounds: _rasterBounds,
            camera: camera,
            particles: _particles,
          ),
        ),
      ),
    );
  }
}

class _WindFieldPainter extends CustomPainter {
  _WindFieldPainter({
    required this.rasterImage,
    required this.rasterBounds,
    required this.camera,
    required this.particles,
  });

  final ui.Image? rasterImage;
  final LatLngBounds? rasterBounds;
  final MapCamera camera;
  final List<WindParticle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw background wind speed raster
    if (rasterImage != null && rasterBounds != null) {
      final nw = camera.latLngToScreenOffset(rasterBounds!.northWest);
      final se = camera.latLngToScreenOffset(rasterBounds!.southEast);
      final destRect = Rect.fromPoints(nw, se);

      final paint = Paint()
        ..filterQuality = FilterQuality.high
        ..color = const Color.fromRGBO(255, 255, 255, 0.88);

      canvas.drawImageRect(
        rasterImage!,
        Rect.fromLTWH(0, 0, rasterImage!.width.toDouble(), rasterImage!.height.toDouble()),
        destRect,
        paint,
      );
    }

    // 2. Draw animated streamline particle trails
    for (final p in particles) {
      final trail = p.trail;
      if (trail.length < 2) continue;

      final baseAlpha = (math.sin(p.age * math.pi) * 0.90).clamp(0.0, 1.0);
      final len = trail.length;

      for (int i = 1; i < len; i++) {
        final p1 = trail[i - 1];
        final p2 = trail[i];
        final segAlpha = ((i / len) * baseAlpha).clamp(0.0, 1.0);
        final strokeWidth = 1.0 + (i / len) * 1.6;

        canvas.drawLine(
          p1,
          p2,
          Paint()
            ..color = Color.fromRGBO(255, 255, 255, segAlpha)
            ..strokeWidth = strokeWidth
            ..strokeCap = StrokeCap.round,
        );
      }

      if (trail.isNotEmpty && baseAlpha > 0.15) {
        final head = trail.last;
        canvas.drawCircle(
          head,
          1.5,
          Paint()..color = Color.fromRGBO(255, 255, 255, (baseAlpha * 1.1).clamp(0.0, 1.0)),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_WindFieldPainter old) => true; // Continuously animated 60fps
}
