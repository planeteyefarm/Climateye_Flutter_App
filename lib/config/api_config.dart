import 'package:flutter/foundation.dart';

/// Endpoint definitions for the ClimateEye backend (see handover §3).
class ApiConfig {
  static const String productionBaseUrl =
      'https://climateye-apis.up.railway.app/api';

  /// Web debug builds go through the dev-server proxy in web_dev_config.yaml
  /// (the backend sends no Access-Control-Allow-Origin header).
  static const String baseUrl =
      kIsWeb && kDebugMode ? '/api' : productionBaseUrl;

  static const String aqi = '/aqi';
  static const String weather = '/weather';
  static const String aqiHourly = '/aqi/hourly';
  static const String aqiHourlyRange = '/aqi/hourly/range';
  static const String weatherHourly = '/weather/hourly';
  static const String weatherMonthly = '/weather/monthly';
  static const String weatherRainForecast = '/weather/rain-forecast';
  static const String aqiAnalyze = '/aqi/analyze';
  static const String methane = '/methane';
  static const String methanePlumes = '/methane/plumes';
  static const String methaneTiles = '/methane/tiles';
  static const String buildings = '/buildings';

  /// Forward place search (map search bar).
  static const String geocoding = 'https://geocoding-api.open-meteo.com/v1/search';

  /// Browser-friendly reverse geocode (city + state from lat/lng).
  static const String reverseGeocode =
      'https://api.bigdatacloud.net/data/reverse-geocode-client';

  /// OSM Nominatim reverse geocode (fallback when BigDataCloud fails).
  static const String nominatimReverse =
      'https://nominatim.openstreetmap.org/reverse';

  static const Duration timeout = Duration(seconds: 60);
}

/// Map tile templates (handover §6.1 + post-login light OSM default).
class TileUrls {
  /// Free OpenStreetMap raster — natural light style (post-login default).
  /// Attribution: © OpenStreetMap contributors
  static const String osm =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Free OpenTopoMap — optional terrain layer (not the home default).
  static const String openTopo =
      'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png';

  /// Free Carto Dark Matter — optional alternative (not the home default).
  static const String cartoDark =
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';

  static const String lightMap =
      'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';
  static const String satellite =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
  static const String labels =
      'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}';

  /// Light blue-grey canvas behind OSM tiles (matches Design 1/5).
  static const int mapBackgroundArgb = 0xFFE8EEF4;

  /// Teal accent for AOI / home controls.
  static const int aoiAccentArgb = 0xFF14B8A6;
}
