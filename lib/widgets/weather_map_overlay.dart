import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'rain_field_overlay.dart';
import 'temperature_field_overlay.dart';
import 'weather_mode_bar.dart';
import 'weather_readout_overlay.dart';
import 'wind_field_overlay.dart';

class WeatherFieldPoint {
  const WeatherFieldPoint({
    required this.location,
    required this.temperature,
    this.precipitation = 0.0,
    this.windSpeed = 0.0,
    this.windDirection = 0.0,
  });

  final LatLng location;
  final double temperature;
  final double precipitation;
  final double windSpeed;
  final double windDirection;
}

class WeatherMapOverlayHelper {
  // Windy temperature ramp stops
  static const List<MapEntry<double, Color>> tempStops = [
    MapEntry(-20, Color.fromARGB(255, 18, 40, 150)),
    MapEntry(-10, Color.fromARGB(255, 36, 100, 210)),
    MapEntry(0, Color.fromARGB(255, 48, 170, 230)),
    MapEntry(5, Color.fromARGB(255, 40, 200, 195)),
    MapEntry(10, Color.fromARGB(255, 55, 205, 95)),
    MapEntry(15, Color.fromARGB(255, 150, 220, 45)),
    MapEntry(20, Color.fromARGB(255, 235, 225, 40)),
    MapEntry(24, Color.fromARGB(255, 245, 185, 30)),
    MapEntry(28, Color.fromARGB(255, 240, 130, 28)),
    MapEntry(32, Color.fromARGB(255, 230, 80, 28)),
    MapEntry(36, Color.fromARGB(255, 200, 40, 32)),
    MapEntry(40, Color.fromARGB(255, 145, 28, 38)),
  ];

  static Color colorForTemperature(double temperature, {int alpha = 175}) {
    final value = temperature.clamp(-20.0, 40.0);
    int index = 1;
    while (index < tempStops.length && tempStops[index].key < value) {
      index++;
    }
    final startEntry = tempStops[index - 1];
    final endEntry = tempStops[index < tempStops.length ? index : tempStops.length - 1];
    final t = endEntry.key == startEntry.key
        ? 0.0
        : (value - startEntry.key) / (endEntry.key - startEntry.key);
    final blend = t * t * (3 - 2 * t);
    final s = startEntry.value;
    final e = endEntry.value;
    final r = ((s.r + (e.r - s.r) * blend) * 255.0).round().clamp(0, 255);
    final g = ((s.g + (e.g - s.g) * blend) * 255.0).round().clamp(0, 255);
    final b = ((s.b + (e.b - s.b) * blend) * 255.0).round().clamp(0, 255);
    return Color.fromARGB(alpha, r, g, b);
  }

  static Color colorForRain(double mm, {int alpha = 180}) {
    if (mm <= 0.1) return const Color.fromARGB(0, 0, 0, 0);
    if (mm < 1.5) return Color.fromARGB(alpha, 20, 90, 130);
    if (mm < 3.0) return Color.fromARGB(alpha, 48, 170, 190);
    if (mm < 7.0) return Color.fromARGB(alpha, 40, 168, 120);
    if (mm < 10.0) return Color.fromARGB(alpha, 72, 196, 64);
    if (mm < 20.0) return Color.fromARGB(alpha, 200, 210, 48);
    if (mm < 30.0) return Color.fromARGB(alpha, 236, 160, 36);
    return Color.fromARGB(alpha, 196, 48, 160);
  }

  static Color colorForWind(double speedKmH) {
    if (speedKmH < 10) return const Color(0xFF7A2E9E);
    if (speedKmH < 20) return const Color(0xFF3A4ACC);
    if (speedKmH < 35) return const Color(0xFF20BAD6);
    if (speedKmH < 55) return const Color(0xFF36C460);
    if (speedKmH < 70) return const Color(0xFFE6D630);
    return const Color(0xFFEC8420);
  }
}

/// Builds map overlay layers corresponding to the selected WeatherOverlayMode.
class WeatherMapOverlay {
  static List<Widget> buildLayers({
    required WeatherOverlayMode mode,
    required List<WeatherFieldPoint> points,
    required double zoom,
    DateTime? selectedDate,
    LatLng? initialCenter,
    double? initialTemperature,
    double? initialPrecipitation,
    double? initialWindSpeed,
    double? initialWindDirection,
    bool rainForecastMode = true,
    LatLng? tappedCoordinate,
    LatLng? hoverCoordinate,
    Offset? hoverScreenPosition,
    VoidCallback? onDismissReadout,
  }) {
    if (mode == WeatherOverlayMode.none) {
      return const [];
    }

    final layers = <Widget>[];

    if (mode == WeatherOverlayMode.temp) {
      // Continuous full-viewport temperature gradient matching Website
      layers.add(
        TemperatureFieldOverlay(
          selectedDate: selectedDate,
          initialCenter: initialCenter,
          initialTemperature: initialTemperature,
        ),
      );
    } else if (mode == WeatherOverlayMode.rain) {
      // Continuous full-viewport rain accumulation raster matching Website
      layers.add(
        RainFieldOverlay(
          forecastMode: rainForecastMode,
          selectedDate: selectedDate,
          initialCenter: initialCenter,
          initialPrecipitation: initialPrecipitation,
        ),
      );
    } else if (mode == WeatherOverlayMode.wind) {
      // Animated particle streamlines over speed heatmap matching Website
      layers.add(
        WindFieldOverlay(
          selectedDate: selectedDate,
          initialCenter: initialCenter,
          initialWindSpeed: initialWindSpeed,
          initialWindDirection: initialWindDirection,
        ),
      );
    }

    // Weather readout overlay matching Website .regional-wind-tip
    if (tappedCoordinate != null ||
        (hoverCoordinate != null && hoverScreenPosition != null)) {
      layers.add(
        WeatherReadoutMapLayer(
          mode: mode,
          rainForecastMode: rainForecastMode,
          selectedDate: selectedDate,
          tappedCoordinate: tappedCoordinate,
          hoverCoordinate: hoverCoordinate,
          hoverScreenPosition: hoverScreenPosition,
          onDismiss: onDismissReadout,
        ),
      );
    }

    return layers;
  }
}

