import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/weather.dart';
import '../services/api_client.dart';
import '../utils/date_utils.dart';
import 'rain_field_overlay.dart';
import 'temperature_field_overlay.dart';
import 'weather_mode_bar.dart';
import 'wind_field_overlay.dart';

/// Formatter utilities matching the Website's exact readout text formatting.
class WeatherReadoutFormatter {
  /// Formats temperature matching Website parity with `now 3h` suffix.
  static String formatTemperature(double temp, {bool use3hSuffix = true}) {
    final formatted = temp.toStringAsFixed(1);
    return use3hSuffix ? '$formatted°C · now 3h' : '$formatted °C · now';
  }

  /// Formats rainfall matching Website parity with `last 3h` or `next 3h` suffix.
  static String formatRain(double rain, bool isForecast) {
    final formatted = rain.toStringAsFixed(1);
    final suffix = isForecast ? 'next 3h' : 'last 3h';
    return '$formatted mm · $suffix';
  }

  /// Formats wind speed matching Website parity with `last 3h` suffix.
  static String formatWind(double speed, {bool useLast3hSuffix = true}) {
    final formatted = speed.toStringAsFixed(1);
    return useLast3hSuffix ? '$formatted km/h · last 3h' : '$formatted km/h';
  }
}

/// Result of evaluating weather reading at a coordinate.
class WeatherReadoutValue {
  const WeatherReadoutValue({
    required this.text,
    required this.rawValue,
    required this.coordinate,
    this.isLoading = false,
    this.isError = false,
  });

  final String text;
  final double? rawValue;
  final LatLng coordinate;
  final bool isLoading;
  final bool isError;
}

/// Interactive weather readout overlay matching the Website's `.regional-wind-tip`.
///
/// On Desktop / Web: Follows mouse cursor movement over the map.
/// On Touch / Mobile: Renders an anchored pin and badge at the tapped map location.
class WeatherReadoutOverlay extends StatefulWidget {
  const WeatherReadoutOverlay({
    super.key,
    required this.mode,
    required this.camera,
    this.rainForecastMode = false,
    this.selectedDate,
    this.tappedCoordinate,
    this.hoverCoordinate,
    this.hoverScreenPosition,
    this.onDismiss,
  });

  final WeatherOverlayMode mode;
  final MapCamera camera;
  final bool rainForecastMode;
  final DateTime? selectedDate;
  final LatLng? tappedCoordinate;
  final LatLng? hoverCoordinate;
  final Offset? hoverScreenPosition;
  final VoidCallback? onDismiss;

  /// Synchronously samples the active weather layer at [point].
  static WeatherReadoutValue? sampleActiveLayer({
    required WeatherOverlayMode mode,
    required LatLng point,
    required double zoom,
    bool rainForecastMode = false,
    DateTime? selectedDate,
  }) {
    if (mode == WeatherOverlayMode.none) return null;

    if (mode == WeatherOverlayMode.temp) {
      final val = TemperatureFieldOverlay.sampleAt(
        point.latitude,
        point.longitude,
        selectedDate: selectedDate,
        zoom: zoom,
      );
      if (val != null) {
        return WeatherReadoutValue(
          text: WeatherReadoutFormatter.formatTemperature(val),
          rawValue: val,
          coordinate: point,
        );
      }
    } else if (mode == WeatherOverlayMode.rain) {
      final val = RainFieldOverlay.sampleAt(
        point.latitude,
        point.longitude,
        forecastMode: rainForecastMode,
        selectedDate: selectedDate,
        zoom: zoom,
      );
      if (val != null) {
        return WeatherReadoutValue(
          text: WeatherReadoutFormatter.formatRain(val, rainForecastMode),
          rawValue: val,
          coordinate: point,
        );
      }
    } else if (mode == WeatherOverlayMode.wind) {
      final val = WindFieldOverlay.sampleAt(
        point.latitude,
        point.longitude,
        selectedDate: selectedDate,
      );
      if (val != null) {
        return WeatherReadoutValue(
          text: WeatherReadoutFormatter.formatWind(val),
          rawValue: val,
          coordinate: point,
        );
      }
    }

    return null;
  }

  @override
  State<WeatherReadoutOverlay> createState() => _WeatherReadoutOverlayState();
}

class _WeatherReadoutOverlayState extends State<WeatherReadoutOverlay> {
  WeatherReadoutValue? _currentValue;
  int _requestId = 0;
  Timer? _fetchDebounce;

  @override
  void initState() {
    super.initState();
    _evaluateReading();
  }

  @override
  void didUpdateWidget(WeatherReadoutOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode ||
        oldWidget.rainForecastMode != widget.rainForecastMode ||
        oldWidget.selectedDate != widget.selectedDate ||
        oldWidget.tappedCoordinate != widget.tappedCoordinate ||
        oldWidget.hoverCoordinate != widget.hoverCoordinate ||
        oldWidget.camera.zoom != widget.camera.zoom) {
      _evaluateReading();
    }
  }

  @override
  void dispose() {
    _fetchDebounce?.cancel();
    super.dispose();
  }

  LatLng? get _activeCoordinate =>
      widget.hoverCoordinate ?? widget.tappedCoordinate;

  void _evaluateReading() {
    final coord = _activeCoordinate;
    if (coord == null || widget.mode == WeatherOverlayMode.none) {
      _currentValue = null;
      return;
    }

    // 1. Try instantaneous in-memory evaluation
    final immediate = WeatherReadoutOverlay.sampleActiveLayer(
      mode: widget.mode,
      point: coord,
      zoom: widget.camera.zoom,
      rainForecastMode: widget.rainForecastMode,
      selectedDate: widget.selectedDate,
    );

    if (immediate != null) {
      setState(() => _currentValue = immediate);
      return;
    }

    // 2. If not yet in cache, schedule asynchronous fetch with race-condition protection
    setState(() {
      _currentValue = WeatherReadoutValue(
        text: 'Loading…',
        rawValue: null,
        coordinate: coord,
        isLoading: true,
      );
    });

    _fetchDebounce?.cancel();
    _fetchDebounce = Timer(const Duration(milliseconds: 250), () {
      _fetchFallback(coord);
    });
  }

  Future<void> _fetchFallback(LatLng coord) async {
    final id = ++_requestId;
    final date = widget.selectedDate ?? DateTime.now();
    final dateStr = ymd(date);
    final lat = (coord.latitude * 1000).round() / 1000;
    final lng = (coord.longitude * 1000).round() / 1000;

    try {
      if (widget.mode == WeatherOverlayMode.temp) {
        final weather = await ApiClient.instance.fetchHourlyWeather(lat, lng, date);
        if (!mounted || id != _requestId) return;
        final temp = extractCurrentTemperature(weather, targetDate: date);
        if (temp != null) {
          final key = 'v2:$dateStr:$lat:$lng';
          TemperatureFieldOverlay.sampleCache[key] = TemperatureSample(
            lat: lat,
            lng: lng,
            temp: temp,
          );
          if (mounted && id == _requestId) {
            setState(() {
              _currentValue = WeatherReadoutValue(
                text: WeatherReadoutFormatter.formatTemperature(temp),
                rawValue: temp,
                coordinate: coord,
              );
            });
          }
        }
      } else if (widget.mode == WeatherOverlayMode.rain) {
        if (widget.rainForecastMode) {
          final res = await ApiClient.instance.fetchRainForecast(lat, lng);
          if (!mounted || id != _requestId) return;
          final series = parseRainForecast(res);
          final key = 'forecast:$dateStr:$lat:$lng';
          RainFieldOverlay.rainSeriesCache[key] = series;
          final rainVal = RainFieldOverlay.aggregate3HourRain(series, true);
          if (mounted && id == _requestId) {
            setState(() {
              _currentValue = WeatherReadoutValue(
                text: WeatherReadoutFormatter.formatRain(rainVal, true),
                rawValue: rainVal,
                coordinate: coord,
              );
            });
          }
        } else {
          final weather = await ApiClient.instance.fetchHourlyWeather(lat, lng, date);
          if (!mounted || id != _requestId) return;
          final series = parseHourlyRainSeries(weather);
          final key = 'recent:$dateStr:$lat:$lng';
          RainFieldOverlay.rainSeriesCache[key] = series;
          final rainVal = RainFieldOverlay.aggregate3HourRain(series, false);
          if (mounted && id == _requestId) {
            setState(() {
              _currentValue = WeatherReadoutValue(
                text: WeatherReadoutFormatter.formatRain(rainVal, false),
                rawValue: rainVal,
                coordinate: coord,
              );
            });
          }
        }
      } else if (widget.mode == WeatherOverlayMode.wind) {
        final weather = await ApiClient.instance.fetchHourlyWeather(lat, lng, date);
        if (!mounted || id != _requestId) return;
        final latest = extractLatestWind(weather);
        if (latest != null && latest.speed != null) {
          final key = '$dateStr:$lat:$lng';
          WindFieldOverlay.windCache[key] = latest;
          if (mounted && id == _requestId) {
            setState(() {
              _currentValue = WeatherReadoutValue(
                text: WeatherReadoutFormatter.formatWind(latest.speed!),
                rawValue: latest.speed,
                coordinate: coord,
              );
            });
          }
        }
      }
    } catch (_) {
      if (mounted && id == _requestId) {
        setState(() {
          _currentValue = WeatherReadoutValue(
            text: 'Data unavailable',
            rawValue: null,
            coordinate: coord,
            isError: true,
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == WeatherOverlayMode.none) return const SizedBox.shrink();

    final value = _currentValue;
    if (value == null) return const SizedBox.shrink();

    // Determine screen position
    Offset screenPoint;
    bool isHover = false;

    if (widget.hoverCoordinate != null && widget.hoverScreenPosition != null) {
      screenPoint = widget.hoverScreenPosition!;
      isHover = true;
    } else if (widget.tappedCoordinate != null) {
      screenPoint = widget.camera.latLngToScreenOffset(widget.tappedCoordinate!);
    } else {
      return const SizedBox.shrink();
    }

    final viewSize = widget.camera.size;
    const badgeWidth = 145.0;
    const badgeHeight = 32.0;

    // Position 14px right, 14px down (Website parity ne.x+14, ne.y+14)
    double left = screenPoint.dx + 14;
    double top = screenPoint.dy + 14;

    // Clamp inside viewport
    if (left + badgeWidth > viewSize.width - 12) {
      left = math.max(12.0, screenPoint.dx - badgeWidth - 14);
    }
    if (top + badgeHeight > viewSize.height - 60) {
      top = math.max(60.0, screenPoint.dy - badgeHeight - 14);
    }

    return Stack(
      children: [
        // Pin dot at tapped location (when tapped)
        if (!isHover && widget.tappedCoordinate != null)
          Positioned(
            left: screenPoint.dx - 6,
            top: screenPoint.dy - 6,
            child: IgnorePointer(
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF0A0E27),
                    width: 2.5,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Floating tooltip badge matching Website .regional-wind-tip
        Positioned(
          left: left,
          top: top,
          child: GestureDetector(
            onTap: widget.onDismiss,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(10, 14, 39, 0.90),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18),
                  width: 1,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x59000000),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (value.isLoading) ...[
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    value.text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  if (!isHover && widget.onDismiss != null) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.close,
                      size: 13,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Helper to parse rain series from open-meteo response.
List<Map<String, dynamic>> parseRainForecast(Map<String, dynamic> json) {
  final hourly = json['hourly'] as Map<String, dynamic>?;
  if (hourly == null) return [];
  final times = (hourly['time'] as List?) ?? [];
  final rains = (hourly['rain'] as List?) ?? [];
  final series = <Map<String, dynamic>>[];
  final count = math.min(times.length, rains.length);
  for (int i = 0; i < count; i++) {
    final timeStr = times[i]?.toString() ?? '';
    final dt = DateTime.tryParse(timeStr.endsWith('Z') ? timeStr : '${timeStr}Z');
    final r = (rains[i] as num?)?.toDouble();
    if (dt != null && r != null) {
      series.add({'time': dt.millisecondsSinceEpoch, 'rain': r});
    }
  }
  return series;
}

/// Helper to parse rain series from HourlyWeather list.
List<Map<String, dynamic>> parseHourlyRainSeries(List<HourlyWeather> records) {
  final series = <Map<String, dynamic>>[];
  for (final rec in records) {
    final dt = rec.date;
    final precip = rec.precipitation;
    if (dt != null && precip != null) {
      series.add({'time': dt.millisecondsSinceEpoch, 'rain': precip});
    }
  }
  series.sort((a, b) => (a['time'] as int).compareTo(b['time'] as int));
  return series;
}

/// Helper to extract latest wind observation at or before now.
WindSample? extractLatestWind(List<HourlyWeather> records) {
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  HourlyWeather? bestRecord;
  int? bestTime;

  for (final rec in records) {
    final dt = rec.date;
    if (dt == null) continue;
    final t = dt.millisecondsSinceEpoch;
    if (t > nowMs) continue;
    if (bestTime == null || t >= bestTime) {
      bestTime = t;
      bestRecord = rec;
    }
  }

  if (bestRecord == null) return null;
  final speed = bestRecord.windSpeed;
  final dir = bestRecord.windDirection;
  if (speed == null) return null;
  final rad = dir != null ? ((dir + 180) % 360) * math.pi / 180.0 : 0.0;
  return WindSample(
    lat: 0,
    lng: 0,
    speed: speed,
    u: speed * math.sin(rad),
    v: speed * math.cos(rad),
  );
}

/// A Map layer widget that can be placed inside [FlutterMap.children]
/// to automatically obtain [MapCamera] from context.
class WeatherReadoutMapLayer extends StatelessWidget {
  const WeatherReadoutMapLayer({
    super.key,
    required this.mode,
    required this.rainForecastMode,
    this.selectedDate,
    this.tappedCoordinate,
    this.hoverCoordinate,
    this.hoverScreenPosition,
    this.onDismiss,
  });

  final WeatherOverlayMode mode;
  final bool rainForecastMode;
  final DateTime? selectedDate;
  final LatLng? tappedCoordinate;
  final LatLng? hoverCoordinate;
  final Offset? hoverScreenPosition;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    if (mode == WeatherOverlayMode.none) return const SizedBox.shrink();
    final camera = MapCamera.of(context);
    return WeatherReadoutOverlay(
      mode: mode,
      camera: camera,
      rainForecastMode: rainForecastMode,
      selectedDate: selectedDate,
      tappedCoordinate: tappedCoordinate,
      hoverCoordinate: hoverCoordinate,
      hoverScreenPosition: hoverScreenPosition,
      onDismiss: onDismiss,
    );
  }
}

